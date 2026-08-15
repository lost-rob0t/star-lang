(in-package :starlease)

(define-condition star-lease-error (error)
  ((message :initarg :message :reader star-lease-error-message))
  (:report
   (lambda (condition stream)
     (write-string (star-lease-error-message condition) stream))))

(defun fail-lease (control &rest arguments)
  (error 'star-lease-error
         :message (apply #'format nil control arguments)))

(defun monotonic-milliseconds ()
  (floor (* 1000
            (/ (get-internal-real-time)
               internal-time-units-per-second))))

(defstruct (heartbeat-lease
            (:constructor %make-heartbeat-lease))
  clock-fn
  timeout-ms
  (last-seen (make-hash-table :test #'equal)))

(defun make-heartbeat-lease (&key (timeout-ms 15000) clock)
  (unless (and (integerp timeout-ms) (> timeout-ms 0))
    (fail-lease "Heartbeat lease timeout must be a positive integer."))
  (when clock
    (unless (functionp clock)
      (fail-lease "Heartbeat lease clock must be a function.")))
  (%make-heartbeat-lease
   :clock-fn (or clock #'monotonic-milliseconds)
   :timeout-ms timeout-ms))

(defun heartbeat-lease-now (lease)
  (unless (heartbeat-lease-p lease)
    (fail-lease "Expected a heartbeat lease, received ~S." lease))
  (let ((now (funcall (heartbeat-lease-clock-fn lease))))
    (unless (and (integerp now) (>= now 0))
      (fail-lease
       "Heartbeat lease clock must return a nonnegative integer, received ~S."
       now))
    now))

(defun heartbeat-lease-note-seen (lease key)
  (unless (heartbeat-lease-p lease)
    (fail-lease "Expected a heartbeat lease, received ~S." lease))
  (setf (gethash key (heartbeat-lease-last-seen lease))
        (heartbeat-lease-now lease))
  key)

(defun heartbeat-lease-last-seen-at (lease key)
  (unless (heartbeat-lease-p lease)
    (fail-lease "Expected a heartbeat lease, received ~S." lease))
  (gethash key (heartbeat-lease-last-seen lease)))

(defun heartbeat-lease-expired-p
    (lease key &optional (now (heartbeat-lease-now lease)))
  (unless (and (integerp now) (>= now 0))
    (fail-lease
     "Heartbeat lease expiry time must be a nonnegative integer, received ~S."
     now))
  (multiple-value-bind (last-seen present-p)
      (heartbeat-lease-last-seen-at lease key)
    (and present-p
         (>= (- now last-seen)
             (heartbeat-lease-timeout-ms lease)))))
