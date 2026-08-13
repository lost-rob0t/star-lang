(defpackage :starlangruntime-tests
  (:use :cl)
  (:import-from :starlangruntime
                #:actor-definition-error
                #:actor-already-registered-error
                #:actor-stopped-error
                #:actor-external-dispatch-required-error
                #:actor-instance-data
                #:actor-instance-generation
                #:actor-instance-invocation-count
                #:create-native-actor
                #:create-external-actor
                #:invoke-actor
                #:make-external-actor-definition
                #:make-runtime
                #:resolve-actor
                #:restart-actor
                #:runtime-actor-count
                #:stop-actor
                #:unregister-actor)
  (:export #:run-tests))

(in-package :starlangruntime-tests)

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

(defun integer-contract-p (contract value)
  (and (eq contract :integer)
       (integerp value)))

(defun run-tests ()
  (let* ((runtime (make-runtime))
         (counter
           (create-native-actor
            runtime
            "counter"
            (lambda (message state actor-runtime)
              (declare (ignore actor-runtime))
              (values (+ message state) (1+ state)))
            :accepts :integer
            :produces :integer
            :input-validator #'integer-contract-p
            :output-validator #'integer-contract-p
            :initial-state 0)))
    (check (= 1 (runtime-actor-count runtime))
           "Expected one registered actor.")
    (check (eq counter (resolve-actor runtime "counter"))
           "Actor name did not resolve to the created actor.")
    (check (eq counter
               (resolve-actor runtime "star://local:localhost:counter"))
           "Canonical local STAR URI did not resolve to the created actor.")
    (check (= 10 (invoke-actor runtime "counter" 10))
           "Counter actor returned the wrong first result.")
    (check (= 1 (actor-instance-data counter))
           "Counter actor did not persist its private state.")
    (check (= 11 (invoke-actor runtime "counter" 10))
           "Counter actor returned the wrong stateful result.")
    (check (= 2 (actor-instance-invocation-count counter))
           "Counter invocation count did not advance.")

    (stop-actor runtime "counter")
    (check (signals-p 'actor-stopped-error
                      (lambda () (invoke-actor runtime "counter" 1)))
           "Stopped actor invocation did not fail deterministically.")
    (restart-actor runtime "counter")
    (check (= 1 (actor-instance-generation counter))
           "Actor restart did not advance its generation.")
    (check (= 3 (invoke-actor runtime "counter" 1))
           "Restarted actor lost or corrupted its state.")

    (let ((user-hunt
            (create-external-actor
             runtime
             "user-hunt"
             "star://quasar:localhost:user-hunt"))
          (nmap
            (create-external-actor
             runtime
             "nmap"
             "star://bbp:localhost:nmap")))
      (check (eq user-hunt
                 (resolve-actor runtime "star://quasar:localhost:user-hunt"))
             "Quasar user-hunt service URI did not resolve.")
      (check (eq nmap
                 (resolve-actor runtime "star://bbp:localhost:nmap"))
             "BBP nmap service URI did not resolve independently.")
      (check (not (eq user-hunt nmap))
             "Independent external STAR services collapsed to one actor.")
      (check (signals-p 'actor-external-dispatch-required-error
                        (lambda ()
                          (invoke-actor runtime
                                        "star://quasar:localhost:user-hunt"
                                        :fixture)))
             "External actor invocation did not require a transport dispatcher."))

    (check
     (signals-p
      'actor-definition-error
      (lambda ()
        (make-external-actor-definition
         "other-name"
         "star://quasar:localhost:user-hunt")))
     "Actor name/service URI mismatch was not rejected.")

    (check
     (signals-p
      'actor-already-registered-error
      (lambda ()
        (create-native-actor
         runtime
         "counter"
         (lambda (message state actor-runtime)
           (declare (ignore state actor-runtime))
           message))))
     "Duplicate actor registration was not rejected.")

    (unregister-actor runtime "star://bbp:localhost:nmap")
    (check (= 2 (runtime-actor-count runtime))
           "Actor unregister did not remove both name and URI indexes."))

  (format t "~&starlang-runtime tests passed~%")
  t)
