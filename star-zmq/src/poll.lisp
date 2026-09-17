(in-package :star-zmq)

(export '(poll-readable socket-open-p set-socket-timeout))

;; zmq_pollitem_t uses SOCKET (uintptr_t) on Windows, int elsewhere.
(cffi:defcstruct poll-item
  (socket :pointer)
  (fd #+(or win32 windows) :uintptr #-(or win32 windows) :int)
  (events :short)
  (revents :short))
(cffi:defcfun ("zmq_poll" %poll) :int
  (items :pointer) (count :int) (timeout :long))

(defun socket-open-p (socket)
  (check-type socket transport-socket)
  (not (null (transport-socket-handle socket))))

(defun set-socket-timeout (socket timeout-ms)
  "Set both I/O budgets on the owner thread. Never enable infinite I/O."
  (bounded-integer timeout-ms 1 60000)
  (set-integer-option socket 27 timeout-ms)
  (set-integer-option socket 28 timeout-ms)
  timeout-ms)

(defun poll-readable (socket timeout-ms)
  "Wait up to TIMEOUT-MS. NIL also permits an interrupted/spurious wakeup.
The caller owns an absolute deadline; this function never resets or retries it."
  (bounded-integer timeout-ms 0 60000)
  (let ((handle (owned-handle socket)))
    (cffi:with-foreign-object (item '(:struct poll-item))
      (setf (cffi:foreign-slot-value item '(:struct poll-item) 'socket) handle
            (cffi:foreign-slot-value item '(:struct poll-item) 'fd) 0
            (cffi:foreign-slot-value item '(:struct poll-item) 'events) 1
            (cffi:foreign-slot-value item '(:struct poll-item) 'revents) 0)
      (handler-case
          (checked (%poll item 1 timeout-ms) :poll)
        (zmq-error (condition)
          ;; SIGCHLD can interrupt native poll when a managed child exits.
          ;; Surface liveness to the owner loop rather than losing the session
          ;; to an unrelated transport error. All other native failures remain.
          (if (= 4 (zmq-error-code condition))
              (return-from poll-readable nil)
              (error condition))))
      (logbitp 0 (cffi:foreign-slot-value item '(:struct poll-item) 'revents)))))
