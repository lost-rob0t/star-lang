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
  "Wait without a busy loop; NIL means no readable message within the budget."
  (bounded-integer timeout-ms 0 60000)
  (let ((handle (owned-handle socket)))
    (cffi:with-foreign-object (item '(:struct poll-item))
      (setf (cffi:foreign-slot-value item '(:struct poll-item) 'socket) handle
            (cffi:foreign-slot-value item '(:struct poll-item) 'fd) 0
            (cffi:foreign-slot-value item '(:struct poll-item) 'events) 1
            (cffi:foreign-slot-value item '(:struct poll-item) 'revents) 0)
      (checked (%poll item 1 timeout-ms) :poll)
      (logbitp 0 (cffi:foreign-slot-value item '(:struct poll-item) 'revents)))))
