(in-package :starlogicadapterswi)

(defparameter +max-mqi-startup-line-chars+ 4096)

(defstruct (swi-worker (:constructor %make-swi-worker))
  process
  socket
  stream
  endpoint
  password
  mqi-major
  mqi-minor
  communication-thread-id
  goal-thread-id
  (state :starting))

(defvar *last-owned-process* nil)
(defvar *authentication-password-transform* #'identity)

(defun %monotonic-deadline (seconds)
  (+ (get-internal-real-time)
     (ceiling (* seconds internal-time-units-per-second))))

(defun %read-startup-line (process
                           &key
                             (timeout 10.0d0)
                             (max-chars +max-mqi-startup-line-chars+))
  "Read one bounded pre-authentication line from SWI's startup stdout."
  (unless (and (integerp max-chars) (plusp max-chars))
    (%swi-fail 'swi-malformed-startup-data-error
               "MQI startup line bound must be a positive integer."))
  (let ((deadline (%monotonic-deadline timeout))
        (stream (process-stdout process))
        (buffer (make-string-output-stream))
        (length 0))
    (loop
      (let ((char (read-char-no-hang stream nil :eof)))
        (cond
          ((eq char :eof)
           (%swi-fail 'swi-worker-exited-during-startup-error
                      "SWI MQI closed stdout before startup data completed."))
          ((characterp char)
           (cond
             ((char= char #\Newline)
              (return (get-output-stream-string buffer)))
             ((char= char #\Return))
             (t
              (incf length)
              (when (> length max-chars)
                (%swi-fail 'swi-malformed-startup-data-error
                           "SWI MQI startup line exceeds the configured bound."))
              (write-char char buffer))))
          ((not (process-alive-p process))
           (%swi-fail 'swi-worker-exited-during-startup-error
                      "SWI worker exited while emitting MQI startup data."))
          ((>= (get-internal-real-time) deadline)
           (%swi-fail 'swi-malformed-startup-data-error
                      "Timed out waiting for SWI MQI startup data."))
          (t
           (sleep 0.01d0)))))))

(defun %parse-startup-values (port-line password-line)
  (let ((port (handler-case
                  (parse-integer (%trim-whitespace port-line) :junk-allowed nil)
                (error () nil))))
    (unless (and port (<= 1 port 65535))
      (%swi-fail 'swi-malformed-startup-data-error
                 "SWI MQI emitted an invalid loopback TCP port."))
    (unless (and (stringp password-line) (plusp (length password-line)))
      (%swi-fail 'swi-malformed-startup-data-error
                 "SWI MQI emitted an empty generated password."))
    (values port password-line)))

(defun %connect-loopback (process port &key (timeout 5.0d0))
  (let ((deadline (%monotonic-deadline timeout))
        (last-error nil))
    (loop
      (unless (process-alive-p process)
        (%swi-fail-diagnostic
         'swi-worker-exited-during-startup-error
         (%bounded-diagnostic last-error)
         "SWI worker exited before its MQI endpoint accepted a connection."))
      (handler-case
          (return
            (usocket:socket-connect
             "127.0.0.1" port
             :element-type '(unsigned-byte 8)
             :timeout 1))
        (error (cause)
          (setf last-error cause)))
      (when (>= (get-internal-real-time) deadline)
        (%swi-fail-diagnostic
         'swi-socket-connection-error
         (%bounded-diagnostic last-error)
         "Could not connect to SWI MQI loopback endpoint."))
      (sleep 0.01d0))))

(defun %integerish (value condition-type field)
  (cond
    ((integerp value) value)
    ((stringp value)
     (handler-case (parse-integer value :junk-allowed nil)
       (error ()
         (%swi-fail condition-type "~A is not an integer: ~S" field value))))
    (t
     (%swi-fail condition-type "~A is not an integer: ~S" field value))))

(defun %validate-mqi-version (major minor)
  (let ((major (%integerish major 'swi-unsupported-mqi-protocol-error
                            "MQI major version"))
        (minor (%integerish minor 'swi-unsupported-mqi-protocol-error
                            "MQI minor version")))
    (unless (and (= major +supported-mqi-major+)
                 (>= minor +supported-mqi-minor+))
      (%swi-fail 'swi-unsupported-mqi-protocol-error
                 "Unsupported SWI MQI protocol ~D.~D; adapter supports ~D.~D compatibility."
                 major minor +supported-mqi-major+ +supported-mqi-minor+))
    (values major minor)))

(defun %send-private-message (worker message)
  (unless (and (eq (swi-worker-state worker) :ready)
               (swi-worker-stream worker))
    (%swi-fail 'swi-worker-crash-error
               "SWI worker is not in a usable state."))
  (handler-case
      (progn
        (%write-octets (swi-worker-stream worker) (%encode-mqi-frame message))
        (%parse-mqi-json-response
         (%stream-byte-source (swi-worker-stream worker))))
    (swi-adapter-error (cause)
      (error cause))
    (error (cause)
      (%swi-fail-diagnostic
       'swi-socket-connection-error
       (%bounded-diagnostic cause)
       "MQI request/response transport failed."))))

(defun %authenticate-worker (worker password)
  (handler-case
      (progn
        (let ((wire-password
                (funcall *authentication-password-transform* password)))
          (%write-octets (swi-worker-stream worker)
                         (%encode-mqi-frame wire-password)))
        (multiple-value-bind (major minor comm-thread goal-thread)
            (%extract-authentication-metadata
             (%parse-mqi-json-response
              (%stream-byte-source (swi-worker-stream worker))))
          (multiple-value-bind (major minor) (%validate-mqi-version major minor)
            (setf (swi-worker-mqi-major worker) major
                  (swi-worker-mqi-minor worker) minor
                  (swi-worker-communication-thread-id worker) comm-thread
                  (swi-worker-goal-thread-id worker) goal-thread
                  ;; Do not retain the generated secret after authentication.
                  (swi-worker-password worker) nil
                  (swi-worker-state worker) :ready))))
    (swi-adapter-error (cause)
      (error cause))
    (error (cause)
      (%swi-fail-diagnostic
       'swi-authentication-error
       (%bounded-diagnostic cause)
       "SWI MQI authentication transport failed."))))

(defun %verify-bootstrap (worker bootstrap-path version-triplet)
  (let ((identity-response
          (%send-private-message
           worker (%bootstrap-load-and-identity-message bootstrap-path))))
    (unless (%simple-true-response-p identity-response)
      (%swi-fail 'swi-bootstrap-handshake-error
                 "Trusted SWI bootstrap identity handshake failed.")))
  (destructuring-bind (major minor patch) version-triplet
    (let ((version-response
            (%send-private-message
             worker (%bootstrap-version-message major minor patch))))
      (unless (%simple-true-response-p version-response)
        (%swi-fail 'swi-backend-identity-mismatch-error
                   "Launched SWI worker version does not match its backend descriptor.")))))

(defun %dispose-worker (worker)
  (when worker
    (setf (swi-worker-state worker) :disposing)
    (when (swi-worker-socket worker)
      (ignore-errors (usocket:socket-close (swi-worker-socket worker)))
      (setf (swi-worker-socket worker) nil
            (swi-worker-stream worker) nil))
    (when (swi-worker-process worker)
      (ignore-errors (dispose-process (swi-worker-process worker))))
    (setf (swi-worker-password worker) nil
          (swi-worker-state worker) :closed))
  worker)

(defun %open-swi-worker (executable version-triplet bootstrap-path)
  (let ((worker nil)
        (succeeded nil))
    (unwind-protect
         (handler-case
             (let* ((process (launch-process
                              executable
                              '("mqi"
                                "--write_connection_values=true"
                                "--pending_connections=1")))
                    (port-line nil)
                    (password-line nil))
               (setf *last-owned-process* process
                     worker (%make-swi-worker :process process))
               (setf port-line (%read-startup-line process)
                     password-line (%read-startup-line process))
               (multiple-value-bind (port password)
                   (%parse-startup-values port-line password-line)
                 (setf (swi-worker-endpoint worker)
                       (list :host "127.0.0.1" :port port)
                       (swi-worker-password worker) password
                       (swi-worker-socket worker)
                       (%connect-loopback process port)
                       (swi-worker-stream worker)
                       (usocket:socket-stream (swi-worker-socket worker)))
                 (%authenticate-worker worker password)
                 (%verify-bootstrap worker bootstrap-path version-triplet)
                 (setf succeeded t)
                 worker))
           (starprocessport:process-launch-error (cause)
             (%swi-fail-diagnostic
              'swi-worker-launch-error
              (%bounded-diagnostic cause)
              "Failed to launch exact SWI MQI worker.")))
      (unless succeeded
        (%dispose-worker worker)))))

(defun %orderly-shutdown-worker (worker)
  (let ((failure nil))
    (unwind-protect
         (handler-case
             (progn
               (unless (process-alive-p (swi-worker-process worker))
                 (%swi-fail 'swi-worker-crash-error
                            "SWI worker exited before orderly shutdown."))
               (let ((response (%send-private-message worker "quit")))
                 (unless (%simple-true-response-p response)
                   (%swi-fail 'swi-shutdown-failure-error
                              "SWI MQI did not acknowledge orderly quit.")))
               (when (swi-worker-socket worker)
                 (usocket:socket-close (swi-worker-socket worker))
                 (setf (swi-worker-socket worker) nil
                       (swi-worker-stream worker) nil))
               (multiple-value-bind (exit status)
                   (wait-process (swi-worker-process worker) :timeout 5.0d0)
                 (unless (and (eq status :exited)
                              (integerp exit)
                              (zerop exit))
                   (%swi-fail 'swi-shutdown-failure-error
                              "SWI worker did not exit cleanly after MQI quit.")))
               (setf (swi-worker-state worker) :closed))
           (error (cause)
             (setf failure cause)))
      (unless (and (swi-worker-process worker)
                   (process-reaped-p (swi-worker-process worker)))
        (%dispose-worker worker))
      (setf (swi-worker-password worker) nil))
    (when failure
      (if (typep failure 'swi-adapter-error)
          (error failure)
          (%swi-fail-diagnostic
           'swi-shutdown-failure-error
           (%bounded-diagnostic failure)
           "SWI worker shutdown failed.")))
    t))
