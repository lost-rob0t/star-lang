(defpackage :starlangruntime-tests
  (:use :cl)
  (:import-from :starlangruntime
                #:actor-runtime-error
                #:actor-definition-error
                #:actor-already-registered-error
                #:actor-stopped-error
                #:actor-stale-reference-error
                #:actor-ask-timeout-error
                #:actor-external-dispatch-required-error
                #:actor-contract-error
                #:actor-instance-data
                #:actor-instance-generation
                #:actor-instance-invocation-count
                #:actor-instance-last-error
                #:actor-reference
                #:actor-mailbox-depth
                #:delivery-result-status
                #:dispatch-result-status
                #:make-native-actor-definition
                #:create-native-actor
                #:create-external-actor
                #:spawn
                #:tell
                #:ask
                #:dispatch-next
                #:run-until-idle
                #:invoke-actor
                #:make-external-actor-definition
                #:make-runtime
                #:runtime-status
                #:resolve-actor
                #:restart-actor
                #:shutdown-runtime
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

(defun test-mailbox-tell-ordering ()
  (let ((runtime (make-runtime))
        (seen '()))
    (let ((actor
            (create-native-actor
             runtime
             "ordered"
             (lambda (message state actor-runtime)
               (declare (ignore actor-runtime))
               (push message seen)
               (values message state))
             :mailbox-capacity 2)))
      (check (eq :accepted
                 (delivery-result-status (tell runtime actor :first)))
             "First tell was not accepted.")
      (check (eq :accepted
                 (delivery-result-status (tell runtime actor :second)))
             "Second tell was not accepted.")
      (check (null seen)
             "Tell executed the handler synchronously instead of enqueueing.")
      (check (= 2 (actor-mailbox-depth actor))
             "Mailbox depth did not reflect queued tells.")
      (check (eq :mailbox-full
                 (delivery-result-status (tell runtime actor :third)))
             "Bounded mailbox did not return typed mailbox-full delivery.")
      (check (eq :completed (dispatch-result-status (dispatch-next runtime actor)))
             "First queued tell did not dispatch.")
      (check (eq :completed (dispatch-result-status (dispatch-next runtime actor)))
             "Second queued tell did not dispatch.")
      (check (equal '(:first :second) (reverse seen))
             "Tell dispatch did not preserve FIFO order."))))

(defun test-state-and-restart-generation ()
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
            :initial-state 0
            :mailbox-capacity 4)))
    (check (= 10 (ask runtime "counter" 10))
           "ASK returned the wrong first result.")
    (check (= 1 (actor-instance-data counter))
           "Actor did not commit its private state.")
    (check (= 11 (invoke-actor runtime "counter" 10))
           "Compatibility invoke-actor did not use stateful ASK semantics.")
    (check (= 2 (actor-instance-invocation-count counter))
           "Invocation count did not advance after mailbox execution.")
    (let ((stale-reference (actor-reference counter)))
      (stop-actor runtime counter)
      (check (eq :stopped
                 (delivery-result-status (tell runtime counter 1)))
             "Tell did not reject a stopped actor.")
      (check (signals-p 'actor-stopped-error
                        (lambda () (ask runtime counter 1)))
             "ASK did not reject a stopped actor.")
      (restart-actor runtime counter)
      (check (= 1 (actor-instance-generation counter))
             "Actor restart did not advance generation.")
      (check (= 3 (ask runtime counter 1))
             "Restart did not preserve explicitly retained committed state.")
      (check (signals-p 'actor-stale-reference-error
                        (lambda () (resolve-actor runtime stale-reference)))
             "Pre-restart ActorRef was not rejected as stale."))))

(defun test-failed-transition-does-not-commit ()
  (let* ((runtime (make-runtime))
         (actor
           (create-native-actor
            runtime
            "transactional"
            (lambda (message state actor-runtime)
              (declare (ignore actor-runtime))
              (if (eq message :boom)
                  (error "boom")
                  (values message (1+ state))))
            :initial-state 7)))
    (tell runtime actor :boom)
    (let ((result (dispatch-next runtime actor)))
      (check (eq :failed (dispatch-result-status result))
             "Handler failure did not become an async dispatch failure.")
      (check (= 7 (actor-instance-data actor))
             "Failed transition committed actor state.")
      (check (actor-instance-last-error actor)
             "Handler failure was not recorded on the actor."))))

(defun test-contract-failure-does-not-commit ()
  (let* ((runtime (make-runtime))
         (actor
           (create-native-actor
            runtime
            "contract-rollback"
            (lambda (message state actor-runtime)
              (declare (ignore message state actor-runtime))
              (values "invalid-output" 99))
            :produces :integer
            :output-validator #'integer-contract-p
            :initial-state 5)))
    (tell runtime actor :go)
    (let ((result (dispatch-next runtime actor)))
      (check (eq :failed (dispatch-result-status result))
             "Output contract failure did not fail dispatch.")
      (check (= 5 (actor-instance-data actor))
             "Output contract failure committed proposed actor state.")
      (check (typep (actor-instance-last-error actor) 'actor-contract-error)
             "Output contract failure did not preserve the typed condition."))))

(defun test-two-actor-ask-exchange ()
  (let ((runtime (make-runtime)))
    (create-native-actor
     runtime
     "double"
     (lambda (message state actor-runtime)
       (declare (ignore state actor-runtime))
       (* 2 message)))
    (create-native-actor
     runtime
     "plus-one-via-double"
     (lambda (message state actor-runtime)
       (declare (ignore state))
       (1+ (ask actor-runtime "double" message))))
    (check (= 9 (ask runtime "plus-one-via-double" 4))
           "Two actors did not exchange request/reply through mailbox machinery.")))

(defun test-no-reentrant-self-ask ()
  (let ((runtime (make-runtime)))
    (create-native-actor
     runtime
     "self-ask"
     (lambda (message state actor-runtime)
       (declare (ignore state))
       (ask actor-runtime "self-ask" message :timeout-steps 1)))
    (check
     (signals-p 'actor-ask-timeout-error
                (lambda () (ask runtime "self-ask" :loop)))
     "Busy actor was re-entered instead of timing out its self-ASK.")))

(defun test-spawn-and-shutdown ()
  (let* ((runtime (make-runtime))
         (definition
           (make-native-actor-definition
            "spawned"
            (lambda (message state actor-runtime)
              (declare (ignore state actor-runtime))
              message)
            :mailbox-capacity 2))
         (actor (spawn runtime definition)))
    (check (eq actor (resolve-actor runtime "spawned"))
           "SPAWN did not register the actor.")
    (tell runtime actor :queued)
    (check (= 1 (actor-mailbox-depth actor))
           "Spawned actor did not own its mailbox.")
    (check (eq :stopped (shutdown-runtime runtime))
           "Runtime shutdown did not return terminal status.")
    (check (eq :stopped (runtime-status runtime))
           "Runtime status did not become stopped.")
    (check (= 0 (actor-mailbox-depth actor))
           "Runtime shutdown did not discard queued work.")
    (check (eq :stopped
               (delivery-result-status (tell runtime actor :late)))
           "Shutdown actor accepted a late tell.")
    (check
     (signals-p
      'actor-runtime-error
      (lambda ()
        (spawn runtime
               (make-native-actor-definition
                "too-late"
                (lambda (message state actor-runtime)
                  (declare (ignore state actor-runtime))
                  message)))))
     "Shut-down runtime accepted a new actor spawn.")))

(defun test-runtime-registry-and-external-boundary ()
  (let ((runtime (make-runtime)))
    (let ((counter
            (create-native-actor
             runtime "counter"
             (lambda (message state actor-runtime)
               (declare (ignore state actor-runtime))
               message))))
      (check (eq counter (resolve-actor runtime "counter"))
             "Actor name did not resolve.")
      (check (eq counter
                 (resolve-actor runtime "star://local:localhost:counter"))
             "Canonical local STAR URI did not resolve."))
    (let ((user-hunt
            (create-external-actor
             runtime "user-hunt" "star://quasar:localhost:user-hunt"))
          (nmap
            (create-external-actor
             runtime "nmap" "star://bbp:localhost:nmap")))
      (check (eq user-hunt
                 (resolve-actor runtime "star://quasar:localhost:user-hunt"))
             "Quasar user-hunt service URI did not resolve.")
      (check (eq nmap
                 (resolve-actor runtime "star://bbp:localhost:nmap"))
             "BBP nmap service URI did not resolve independently.")
      (check (signals-p 'actor-external-dispatch-required-error
                        (lambda ()
                          (ask runtime
                               "star://quasar:localhost:user-hunt"
                               :fixture)))
             "External actor ASK bypassed the transport boundary."))
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
           "Actor unregister did not remove both name and URI indexes.")))

(defun test-run-until-idle ()
  (let ((runtime (make-runtime))
        (count 0))
    (create-native-actor
     runtime "drain"
     (lambda (message state actor-runtime)
       (declare (ignore message state actor-runtime))
       (incf count)))
    (dotimes (index 3)
      (tell runtime "drain" index))
    (check (= 3 (run-until-idle runtime))
           "Deterministic drain processed the wrong number of messages.")
    (check (= 3 count)
           "Deterministic drain did not execute every queued message.")))

(defun run-tests ()
  (test-mailbox-tell-ordering)
  (test-state-and-restart-generation)
  (test-failed-transition-does-not-commit)
  (test-contract-failure-does-not-commit)
  (test-two-actor-ask-exchange)
  (test-no-reentrant-self-ask)
  (test-spawn-and-shutdown)
  (test-runtime-registry-and-external-boundary)
  (test-run-until-idle)
  (format t "~&starlang-runtime tests passed~%")
  t)