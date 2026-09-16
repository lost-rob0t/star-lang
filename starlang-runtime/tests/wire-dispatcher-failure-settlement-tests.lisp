(defpackage :starlangruntime-wire-failure-tests
  (:use :cl)
  (:import-from :starlangruntime
                #:make-deterministic-dispatcher
                #:register-dispatch-actor
                #:submit-dispatch-envelope
                #:run-dispatcher-next
                #:deferred-dispatch-status)
  (:export #:run-tests))

(in-package :starlangruntime-wire-failure-tests)

(defun test-handler-error-does-not-leave-active-record ()
  (let* ((dispatcher
           (make-deterministic-dispatcher
            (starlangruntime-wire-tests::dispatcher-manifest)))
         (command (starlangruntime-wire-tests::dispatcher-command))
         (calls 0))
    (register-dispatch-actor
     dispatcher "worker"
     (lambda (runtime envelope)
       (declare (ignore runtime envelope))
       (incf calls)
       (error "synthetic handler failure")))
    (submit-dispatch-envelope dispatcher command)
    (handler-case
        (run-dispatcher-next dispatcher)
      (error () nil))
    (starlangruntime-wire-tests::check
     (= 1 calls)
     "Failure-settlement fixture did not reach the handler.")
    (starlangruntime-wire-tests::check
     (member (deferred-dispatch-status dispatcher command)
             '(:terminal :retry))
     "An exited handler left an in-progress idempotency record.")))

(defun run-tests ()
  (test-handler-error-does-not-leave-active-record)
  (format t "~&starlang-runtime wire failure-settlement tests passed~%")
  t)
