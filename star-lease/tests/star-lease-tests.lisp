(defpackage :starlease-tests
  (:use :cl)
  (:import-from :starlease
                #:star-lease-error
                #:make-heartbeat-lease
                #:heartbeat-lease-note-seen
                #:heartbeat-lease-last-seen-at
                #:heartbeat-lease-expired-p)
  (:export #:run-tests))

(in-package :starlease-tests)

(defun check (truth control &rest arguments)
  (unless truth
    (error (apply #'format nil control arguments))))

(defun signals-p (condition-type thunk)
  (handler-case
      (progn
        (funcall thunk)
        nil)
    (error (condition)
      (typep condition condition-type))))

(defun test-timeout-boundary-and-renewal ()
  (let* ((clock (list 0))
         (lease
           (make-heartbeat-lease
            :timeout-ms 1000
            :clock (lambda () (car clock)))))
    (check (eq :node (heartbeat-lease-note-seen lease :node))
           "Heartbeat lease did not return the noted key.")
    (check (= 0 (heartbeat-lease-last-seen-at lease :node))
           "Heartbeat lease did not preserve the observation time.")
    (setf (car clock) 999)
    (check (not (heartbeat-lease-expired-p lease :node))
           "Heartbeat lease expired before the timeout boundary.")
    (setf (car clock) 1000)
    (check (heartbeat-lease-expired-p lease :node)
           "Heartbeat lease did not expire at the timeout boundary.")
    (setf (car clock) 1200)
    (heartbeat-lease-note-seen lease :node)
    (check (not (heartbeat-lease-expired-p lease :node))
           "Heartbeat renewal did not reset expiry.")))

(defun test-keys-expire-independently ()
  (let* ((clock (list 0))
         (lease
           (make-heartbeat-lease
            :timeout-ms 1000
            :clock (lambda () (car clock)))))
    (heartbeat-lease-note-seen lease "node-a")
    (setf (car clock) 500)
    (heartbeat-lease-note-seen lease "node-b")
    (setf (car clock) 1000)
    (check (heartbeat-lease-expired-p lease "node-a")
           "Stale heartbeat key remained live.")
    (check (not (heartbeat-lease-expired-p lease "node-b"))
           "Fresh heartbeat key expired with another key.")
    (check (not (heartbeat-lease-expired-p lease "never-seen"))
           "Unseen heartbeat key was treated as expired.")))

(defun test-configuration-and-clock-validation ()
  (check
   (signals-p 'star-lease-error
              (lambda () (make-heartbeat-lease :timeout-ms 0)))
   "Zero heartbeat timeout was accepted.")
  (check
   (signals-p 'star-lease-error
              (lambda () (make-heartbeat-lease :clock :not-a-function)))
   "Non-function heartbeat clock was accepted.")
  (let ((lease (make-heartbeat-lease :clock (lambda () -1))))
    (check
     (signals-p 'star-lease-error
                (lambda () (heartbeat-lease-note-seen lease :node)))
     "Negative heartbeat clock result was accepted.")))

(defun test-final-system-is-prototype-independent ()
  (check
   (null (find-package "STAR-LANG.CORE-SURFACE.PROTOTYPE"))
   "star-lease loaded the prototype package transitively."))

(defun run-tests ()
  (test-timeout-boundary-and-renewal)
  (test-keys-expire-independently)
  (test-configuration-and-clock-validation)
  (test-final-system-is-prototype-independent)
  (format t "~&star-lease tests passed~%")
  t)
