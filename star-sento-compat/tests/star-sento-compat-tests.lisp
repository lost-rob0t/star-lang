(defpackage :starsentocompat-tests
  (:use :cl :fiveam)
  (:import-from :starsentocompat
                #:star-sento-compat-error
                #:unsupported-sento-operation-error
                #:sento-backend-unavailable-error
                #:runtime-port-p
                #:make-runtime-port
                #:make-sento-runtime-port
                #:runtime-spawn
                #:runtime-tell
                #:runtime-ask
                #:runtime-stop
                #:runtime-shutdown)
  (:export))

(in-package :starsentocompat-tests)

(def-suite starsentocompat-tests
  :description "Narrow Sento/cl-gserver compatibility boundary.")

(in-suite starsentocompat-tests)

(test required-operations-are-validated
  (signals star-sento-compat-error
    (make-runtime-port
     :spawn nil
     :tell (lambda (&rest values) (declare (ignore values)))
     :stop (lambda (&rest values) (declare (ignore values)))
     :shutdown (lambda (&rest values) (declare (ignore values))))))

(test runtime-port-forwards-proven-operations
  (let ((calls '()))
    (let ((port
            (make-runtime-port
             :spawn
             (lambda (context name receive options)
               (declare (ignore receive))
               (push (list :spawn context name options) calls)
               :actor-ref)
             :tell
             (lambda (actor message sender)
               (push (list :tell actor message sender) calls)
               :sent)
             :stop
             (lambda (context actor &key wait)
               (push (list :stop context actor wait) calls)
               :stopped)
             :shutdown
             (lambda (context &key wait)
               (push (list :shutdown context wait) calls)
               :shutdown))))
      (is (eq :actor-ref
              (runtime-spawn port :system "counter" #'identity
                             :dispatcher :cpu)))
      (is (eq :sent (runtime-tell port :actor-ref :message :sender)))
      (is (eq :stopped (runtime-stop port :system :actor-ref :wait t)))
      (is (eq :shutdown (runtime-shutdown port :system :wait t)))
      (is (equal '(:shutdown :stop :tell :spawn)
                 (mapcar #'first calls)))
      (is (equal '(:dispatcher :cpu)
                 (fourth (fourth calls)))))))

(test optional-operation-is-typed-unsupported
  (let ((port
          (make-runtime-port
           :spawn (lambda (&rest values) (declare (ignore values)))
           :tell (lambda (&rest values) (declare (ignore values)))
           :stop (lambda (&rest values) (declare (ignore values)))
           :shutdown (lambda (&rest values) (declare (ignore values))))))
    (signals unsupported-sento-operation-error
      (runtime-ask port :actor :message :timeout 1))))

(test ask-wiring-is-classified-as-port-evidence-only
  (let ((calls nil)
        (port
          (make-runtime-port
           :spawn (lambda (&rest values) (declare (ignore values)))
           :tell (lambda (&rest values) (declare (ignore values)))
           :ask (lambda (actor message timeout sender)
                  (setf calls (list actor message timeout sender))
                  :future)
           :stop (lambda (&rest values) (declare (ignore values)))
           :shutdown (lambda (&rest values) (declare (ignore values))))))
    (is (eq :future
            (runtime-ask port :actor :message :timeout 2 :sender nil)))
    (is (equal '(:actor :message 2 nil) calls))))

(test concrete-sento-port-does-not-create-a-hard-system-dependency
  (is (runtime-port-p (make-sento-runtime-port)))
  (signals sento-backend-unavailable-error
    (starsentocompat::sento-operation
     "STARLANG.TEST.MISSING-SENTO-PACKAGE"
     "NO-SUCH-OPERATION")))
