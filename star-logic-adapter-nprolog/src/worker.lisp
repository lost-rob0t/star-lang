(in-package :starlogicadapternprolog)

(defparameter +max-nprolog-startup-line-chars+ 4096)
(defparameter +max-nprolog-canary-chars+ 4096)
(defparameter +nprolog-bridge-connect-timeout+ 5.0d0)
(defparameter +nprolog-bridge-connect-attempts+ 2)
(defparameter +nprolog-canary-goal+ "true.")
(defparameter +nprolog-halt-goal+ "halt.")

;; The editable N-Prolog REPL is an ncurses line editor; only -r gives the
;; plain stdin/stdout REPL loop that a machine boundary can own. -c consults
;; the digest-pinned bridge file (./-prefixed names resolve relative to the
;; child's working directory, which the adapter pins to the bridge directory).
(defun %nprolog-launch-argv ()
  (list "-r" "-c" +star-logic-bridge-consult-name+))

(defstruct (nprolog-worker (:constructor %make-nprolog-worker))
  process
  socket
  stream
  (port nil)
  (state :starting))

(defvar *last-owned-process* nil)

(defun %monotonic-deadline (seconds)
  (+ (get-internal-real-time)
     (ceiling (* seconds internal-time-units-per-second))))

(defun %read-startup-banner (process
                             &key
                               (timeout 10.0d0)
                               (max-chars +max-nprolog-startup-line-chars+))
  "Read one bounded startup banner line from N-Prolog's stdout."
  (unless (and (integerp max-chars) (plusp max-chars))
    (%nprolog-fail 'nprolog-malformed-startup-data-error
                   "N-Prolog startup line bound must be a positive integer."))
  (let ((deadline (%monotonic-deadline timeout))
        (stream (process-stdout process))
        (buffer (make-string-output-stream))
        (length 0))
    (loop
      (let ((char (read-char-no-hang stream nil :eof)))
        (cond
          ((eq char :eof)
           (%nprolog-fail 'nprolog-worker-exited-during-startup-error
                          "N-Prolog closed stdout before startup data completed."))
          ((characterp char)
           (cond
             ((char= char #\Newline)
              (return (get-output-stream-string buffer)))
             ((char= char #\Return))
             (t
              (incf length)
              (when (> length max-chars)
                (%nprolog-fail 'nprolog-malformed-startup-data-error
                               "N-Prolog startup line exceeds the configured bound."))
              (write-char char buffer))))
          ((not (process-alive-p process))
           (%nprolog-fail 'nprolog-worker-exited-during-startup-error
                          "N-Prolog worker exited while emitting startup data."))
          ((>= (get-internal-real-time) deadline)
           (%nprolog-fail 'nprolog-malformed-startup-data-error
                          "Timed out waiting for N-Prolog startup data."))
          (t
           (sleep 0.01d0)))))))

;; Observed N-Prolog 5.20: the plain -r REPL still emits an ANSI reset (ESC[0m)
;; before verdict output, so machine-readable reads strip ANSI control
;; sequences before matching.
(defun %strip-ansi-escapes (string)
  (let ((result (make-string-output-stream))
        (index 0)
        (length (length string)))
    (loop while (< index length)
          do (let ((char (char string index)))
               (if (char= char #\Escape)
                   (let ((cursor (1+ index)))
                     (when (and (< cursor length) (char= (char string cursor) #\[))
                       (incf cursor))
                     (loop while (and (< cursor length)
                                      (let ((code (char-code (char string cursor))))
                                        (not (<= 64 code 126))))
                           do (incf cursor))
                     (setf index (min (1+ cursor) length)))
                   (progn
                     (write-char char result)
                     (incf index)))))
    (get-output-stream-string result)))

(defun %canary-line-confirmed-p (line)
  "The observed verdict form is a line ending in yes after the ?- prompt."
  (let ((trimmed (%trim-whitespace (%strip-ansi-escapes line))))
    (and (>= (length trimmed) 3)
         (string= trimmed "yes" :start1 (- (length trimmed) 3)))))

(defun %canary-confirmed-p (transcript)
  (some #'%canary-line-confirmed-p
        (uiop:split-string transcript :separator '(#\Newline))))

(defun %await-canary-confirmation (process
                                   &key
                                     (timeout 10.0d0)
                                     (max-chars +max-nprolog-canary-chars+))
  "Consume bounded worker output until the canary verdict is confirmed."
  (unless (and (integerp max-chars) (plusp max-chars))
    (%nprolog-fail 'nprolog-malformed-startup-data-error
                   "N-Prolog canary bound must be a positive integer."))
  (let ((deadline (%monotonic-deadline timeout))
        (stream (process-stdout process))
        (buffer (make-string-output-stream))
        (length 0)
        (confirmed nil))
    (loop
      (let ((char (read-char-no-hang stream nil :eof)))
        (cond
          (confirmed (return t))
          ((eq char :eof)
           (%nprolog-fail 'nprolog-worker-exited-during-startup-error
                          "N-Prolog worker closed stdout before the canary completed."))
          ((characterp char)
           (incf length)
           (when (> length max-chars)
             (%nprolog-fail 'nprolog-malformed-startup-data-error
                            "N-Prolog canary output exceeds the configured bound."))
           (write-char char buffer)
           (when (%canary-confirmed-p (get-output-stream-string buffer))
             (setf confirmed t)))
          ((not (process-alive-p process))
           (%nprolog-fail 'nprolog-worker-exited-during-startup-error
                          "N-Prolog worker exited during the canary exchange."))
          ((>= (get-internal-real-time) deadline)
           (%nprolog-fail-diagnostic
            'nprolog-canary-failure-error
            (%bounded-diagnostic (get-output-stream-string buffer))
            "Timed out waiting for the N-Prolog canary confirmation."))
          (t
           (sleep 0.01d0)))))))

(defun %require-startup-banner-match (banner expected-pair executable)
  (multiple-value-bind (major minor) (%parse-startup-banner banner)
    (unless (equal (list major minor) expected-pair)
      (%nprolog-fail 'nprolog-backend-identity-mismatch-error
                     "Launched N-Prolog worker banner ~S does not match backend version ~{~D.~2,'0D~} for ~A."
                     banner expected-pair executable)))
  t)

(defun %connect-bridge (worker port)
  "Connect to the bridge endpoint, retrying until the deadline.

create_server_socket/2 binds after engine init, so early connection-refused
errors are normal startup lag, not bind failures; only the deadline decides."
  (let ((deadline (%monotonic-deadline +nprolog-bridge-connect-timeout+))
        (process (nprolog-worker-process worker))
        (last-error nil))
    (loop
      (unless (process-alive-p process)
        (%nprolog-fail-diagnostic
         'nprolog-worker-exited-during-startup-error
         (%bounded-diagnostic last-error)
         "N-Prolog worker exited before its bridge endpoint accepted a connection."))
      (handler-case
          (return
            (usocket:socket-connect "127.0.0.1" port
                                    :element-type '(unsigned-byte 8)
                                    :timeout 1))
        (error (cause)
          (setf last-error cause)))
      (when (>= (get-internal-real-time) deadline)
        (%nprolog-fail-diagnostic
         'nprolog-bridge-port-error
         (%bounded-diagnostic last-error)
         "Could not connect to the N-Prolog bridge endpoint on port ~D." port))
      (sleep 0.01d0))))

(defun %start-bridge-endpoint (worker)
  "Open the bridge endpoint: probe a free port, drive the worker into
create_server_socket/2 with a bridge-start goal, connect, and handshake.
One retry with a fresh port covers the probe-to-bind race."
  (loop
    with attempts-left = +nprolog-bridge-connect-attempts+
    do
       (let ((port (%probe-free-loopback-port)))
         (let ((stdin (process-stdin (nprolog-worker-process worker))))
           (format stdin "star_logic_bridge_start(~D).~%" port)
           (finish-output stdin))
         (handler-case
             (let* ((socket (%connect-bridge worker port))
                    (stream (usocket:socket-stream socket)))
               (%bridge-handshake stream (nprolog-worker-process worker))
               (setf (nprolog-worker-socket worker) socket
                     (nprolog-worker-stream worker) stream
                     (nprolog-worker-port worker) port
                     (nprolog-worker-state worker) :bridge-ready)
               (return worker))
           (nprolog-bridge-port-error (cause)
             (decf attempts-left)
             (when (<= attempts-left 0)
               (error cause))
             ;; The bind likely lost the probe race; the goal has failed and
             ;; the worker is back at the REPL, ready for a fresh port.
             )))))

(defun %open-nprolog-worker (executable expected-pair bridge-file-path)
  (let ((process (ignore-errors
                  (launch-process executable (%nprolog-launch-argv)
                                  :directory (uiop:pathname-directory-pathname
                                              bridge-file-path)))))
    (unless process
      (%nprolog-fail 'nprolog-worker-launch-error
                     "Could not launch exact N-Prolog executable ~A." executable))
    (setf *last-owned-process* process)
    (let ((worker (%make-nprolog-worker :process process)))
      (handler-case
          (progn
            (%require-startup-banner-match
             (%read-startup-banner process) expected-pair executable)
            (let ((stdin (process-stdin process)))
              (format stdin "~A~%" +nprolog-canary-goal+)
              (finish-output stdin))
            (%await-canary-confirmation process)
            (%start-bridge-endpoint worker)
            worker)
        (nprolog-adapter-error (cause)
          (ignore-errors (kill-process process))
          (ignore-errors (dispose-process process))
          (error cause))))))

(defun %close-bridge-endpoint (worker)
  "Close the bridge from the adapter side and let the engine return to the
REPL. The wire quit must precede the halt goal so the bridge loop unblocks."
  (let ((stream (nprolog-worker-stream worker)))
    (when stream
      (handler-case
          (progn
            (%write-bridge-frame stream "quit")
            (sleep 0.05d0))
        (nprolog-adapter-error ()
          nil)))
    (let ((socket (nprolog-worker-socket worker)))
      (when socket
        (ignore-errors (usocket:socket-close socket))))
    (setf (nprolog-worker-socket worker) nil
          (nprolog-worker-stream worker) nil
          (nprolog-worker-port worker) nil))
  t)

(defun %orderly-shutdown-worker (worker)
  (let ((process (nprolog-worker-process worker)))
    (setf (nprolog-worker-state worker) :stopping)
    (%close-bridge-endpoint worker)
    (when (and process (process-alive-p process))
      (let ((stdin (process-stdin process)))
        (format stdin "~A~%" +nprolog-halt-goal+)
        (finish-output stdin))
      (multiple-value-bind (exit status)
          (wait-process process :timeout 10.0d0)
        (when (eq status :timeout)
          (ignore-errors (kill-process process))
          (ignore-errors (dispose-process process))
          (%nprolog-fail 'nprolog-shutdown-failure-error
                         "Timed out waiting for the N-Prolog worker to halt."))
        (unless (and (integerp exit) (zerop exit))
          (%nprolog-fail 'nprolog-shutdown-failure-error
                         "N-Prolog worker exited with status ~S during shutdown." exit))))
    (unless (and process (process-reaped-p process))
      (ignore-errors (dispose-process process)))
    t))
