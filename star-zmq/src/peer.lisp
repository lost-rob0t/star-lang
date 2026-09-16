(in-package :star-zmq-actors)

(define-condition peer-error (error) ()
  (:report (lambda (condition stream)
             (declare (ignore condition))
             (write-string "External actor session failed; no command was replayed." stream))))
(define-condition peer-timeout-error (peer-error) ())
(define-condition peer-protocol-error (peer-error) ())
(define-condition peer-exited-error (peer-error) ())

(defstruct (peer (:constructor %make-peer))
  owner socket process identity actor manifest generation
  (state :starting) drainers
  (drain-lock (bordeaux-threads:make-lock "star-zmq process drains"))
  (drain-failed-p nil) (closing-p nil))

(defun require-peer-owner (peer)
  (check-type peer peer)
  (unless (eq (peer-owner peer) (bordeaux-threads:current-thread))
    (error 'star-zmq:socket-owner-error)))

(defun peer-live-p (peer)
  (require-peer-owner peer)
  (and (eq (peer-state peer) :ready)
       (star-zmq:socket-open-p (peer-socket peer))
       (starprocessport:process-alive-p (peer-process peer))))

(defun start-drainer (peer stream)
  ;; Pipes are drained even when no requests are in flight. Retain no child
  ;; output here; logging policy belongs to the host, not the transport.
  (bordeaux-threads:make-thread
   (lambda ()
     (handler-case
         (let ((buffer (make-array 4096 :element-type '(unsigned-byte 8))))
           (loop while (plusp (read-sequence buffer stream))))
       (error ()
         (bordeaux-threads:with-lock-held ((peer-drain-lock peer))
           (unless (peer-closing-p peer)
             (setf (peer-drain-failed-p peer) t))))))
   :name "star-zmq child output drain"))

(defun finish-drainers (peer)
  ;; A descendant could inherit stdout/stderr. As in star-process-port's
  ;; bounded collector, that must not keep a reaped root's drainers alive.
  (let ((deadline (+ (get-internal-real-time) internal-time-units-per-second)))
    (dolist (thread (peer-drainers peer))
      (loop while (and (bordeaux-threads:thread-alive-p thread)
                       (< (get-internal-real-time) deadline)) do (sleep 0.01d0))
      (when (bordeaux-threads:thread-alive-p thread)
        (bordeaux-threads:destroy-thread thread))
      (bordeaux-threads:join-thread thread)))
  (setf (peer-drainers peer) nil))

(defun close-peer (peer)
  "Close an owner-thread session. OS termination/reaping stays in star-process-port."
  (require-peer-owner peer)
  (unless (eq (peer-state peer) :closed)
    (bordeaux-threads:with-lock-held ((peer-drain-lock peer))
      (setf (peer-closing-p peer) t))
    (setf (peer-state peer) :closing)
    (unwind-protect
         (when (and (peer-socket peer) (star-zmq:socket-open-p (peer-socket peer)))
           (star-zmq:close-socket (peer-socket peer)))
      (unwind-protect
           (when (peer-process peer)
             (starprocessport:dispose-process (peer-process peer) :terminate-timeout 0.5d0))
        (finish-drainers peer)))
    (setf (peer-state peer) :closed))
  t)

(defun request-deadline (timeout-ms)
  (unless (and (integerp timeout-ms) (<= 1 timeout-ms 60000))
    (error 'peer-protocol-error))
  (+ (get-internal-real-time)
     (ceiling (* timeout-ms internal-time-units-per-second) 1000)))

(defun remaining-ms (deadline)
  (max 0 (ceiling (* 1000 (- deadline (get-internal-real-time)))
                  internal-time-units-per-second)))

(defun await-envelope (peer deadline)
  (loop
    for remaining = (remaining-ms deadline)
    do (when (zerop remaining) (error 'peer-timeout-error))
       (bordeaux-threads:with-lock-held ((peer-drain-lock peer))
         (when (peer-drain-failed-p peer) (error 'peer-exited-error)))
       ;; Poll before testing liveness: an orderly child can exit immediately
       ;; after sending its last reply. Do not discard an already queued reply.
       (let* ((live (starprocessport:process-alive-p (peer-process peer)))
              (readable (star-zmq:poll-readable (peer-socket peer) (min remaining 100))))
         (when readable
           (star-zmq:set-socket-timeout (peer-socket peer) (max 1 (min 100 (remaining-ms deadline))))
           (let ((frames (star-zmq:receive-frames (peer-socket peer))))
             (unless (equalp (first frames) (peer-identity peer))
               (error 'peer-protocol-error))
             (return (decode-envelope (peer-manifest peer) (second frames)))))
         (unless live (error 'peer-exited-error)))))

(defun open-peer (context executable endpoint identity actor manifest
                  &key (generation 0) (timeout-ms 5000))
  "Launch a local version-1 example actor and require a generation-bound readiness event.

CONTEXT is host-owned. GENERATION is supplied by the existing supervisor; this
port defines no restart/replay policy. IPC directory ownership is the caller's
responsibility. A routing identity is not authentication. Only local endpoints
accepted by star-zmq are allowed. The returned session is single-owner."
  (let ((deadline (request-deadline timeout-ms)))
    (unless (and (integerp generation) (<= 0 generation 2147483647)
                 (stringp actor) (plusp (length actor))
                 (stringp identity) (plusp (length identity)))
      (error 'peer-protocol-error))
    (let* ((route (format nil "~A/~D" identity generation))
           (bytes (babel:string-to-octets route :encoding :utf-8))
           (peer (%make-peer :owner (bordeaux-threads:current-thread)
                             :identity bytes :actor actor :manifest manifest
                             :generation generation)))
      (unless (and (<= 1 (length bytes) 255) (not (find (code-char 0) route)))
        (error 'peer-protocol-error))
      (handler-case
          (progn
            (setf (peer-socket peer) (star-zmq:open-socket context :router :timeout-ms (min 100 timeout-ms)))
            (star-zmq:bind-endpoint (peer-socket peer) endpoint)
            (setf (peer-process peer)
                  (starprocessport:launch-process executable
                   (list endpoint route actor (write-to-string generation))
                   :generation generation :element-type '(unsigned-byte 8)))
            (push (start-drainer peer (starprocessport:process-stdout (peer-process peer))) (peer-drainers peer))
            (push (start-drainer peer (starprocessport:process-stderr (peer-process peer))) (peer-drainers peer))
            (let ((ready (await-envelope peer deadline)))
              (unless (and (eq (getf ready :kind) :event)
                           (string= (getf ready :message-type) "star.zmq/ready@1")
                           (string= (getf ready :actor) actor)
                           (equal (getf ready :sender) actor)
                           (eql (cdr (assoc "generation" (getf ready :payload) :test #'string=)) generation))
                (error 'peer-protocol-error)))
            (setf (peer-state peer) :ready)
            peer)
        (error (condition)
          (close-peer peer)
          (error condition))))))

(defun peer-request (peer envelope &key (timeout-ms 5000))
  "Send one command and await its correlated reply. Never retry automatically.

Timeout, peer exit, malformed replies and stale routes close the session. A
failed request can have an UNKNOWN execution outcome; the existing journal and
idempotency authority, not this port, decides whether another attempt is safe."
  (require-peer-owner peer)
  (unless (eq (peer-state peer) :ready) (error 'peer-exited-error))
  (let* ((deadline (request-deadline timeout-ms))
         (bytes (encode-envelope (peer-manifest peer) envelope))
         (reply-to (getf envelope :reply-to)))
    ;; Reject caller errors before any effect. This synchronous external-effect
    ;; port does not implement event delivery or nested actor ask semantics.
    (unless (and (eq (getf envelope :kind) :command)
                 (string= (getf envelope :actor) (peer-actor peer))
                 (stringp reply-to) (plusp (length reply-to)))
      (error 'peer-protocol-error))
    (handler-case
        (progn
          (star-zmq:set-socket-timeout (peer-socket peer) (max 1 (min 100 (remaining-ms deadline))))
          (star-zmq:send-frames (peer-socket peer) (list (peer-identity peer) bytes))
          (let ((reply (await-envelope peer deadline)))
            (unless (and (member (getf reply :kind) '(:reply :error))
                         (equal (getf reply :actor) reply-to)
                         (equal (getf reply :sender) (peer-actor peer))
                         (equal (getf reply :correlation-id) (getf envelope :correlation-id))
                         (equal (getf reply :causation-id) (getf envelope :message-id))
                         (equal (getf reply :dataset) (getf envelope :dataset))
                         (or (eq (getf reply :kind) :error)
                             (equal (getf reply :message-type) (getf envelope :message-type))))
              (error 'peer-protocol-error))
            reply))
      (error (condition)
        (close-peer peer)
        (error condition)))))
