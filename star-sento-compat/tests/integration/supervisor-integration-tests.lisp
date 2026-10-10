(in-package :starsentocompat-integration-tests)

(in-suite starsentocompat-integration-tests)

(defun supervisor-integration-symbol (name)
  (multiple-value-bind (symbol status)
      (find-symbol name :starsupervisor)
    (unless (and symbol (eq status :external) (fboundp symbol))
      (error "Missing exported star-supervisor function ~A." name))
    symbol))

(defun supervisor-integration-call (name &rest arguments)
  (apply (symbol-function (supervisor-integration-symbol name)) arguments))

(defun supervisor-child-generation (supervisor child-id)
  (getf
   (supervisor-integration-call
    "SUPERVISOR-CHILD-SNAPSHOT" supervisor child-id)
   :generation))

(test real-sento-supervisor-fences-stale-exit-and-preserves-shared-system
  (with-real-actor-system (system)
    (let* ((port (make-sento-runtime-port))
           (unrelated (spawn-echo port system))
           (name (unique-actor-name "supervised"))
           (spec
             (supervisor-integration-call
              "MAKE-SENTO-CHILD-SPEC"
              "worker" name
              (lambda (message)
                (when (eq message :ping)
                  (sento-reply :pong)))
              :restart-class :permanent))
           (supervisor
             (supervisor-integration-call
              "MAKE-SENTO-SUPERVISOR"
              "root" port system (list spec)
              :max-restarts 3
              :restart-window 10
              :clock (lambda () 0))))
      (supervisor-integration-call "START-SUPERVISOR" supervisor)
      (let ((old-actor
              (supervisor-integration-call
               "SUPERVISOR-CHILD-BACKEND-REF" supervisor "worker")))
        (is (sento-actor-live-p system old-actor))
        (is (= 0 (supervisor-child-generation supervisor "worker")))
        (is (eq :restarted
                (supervisor-integration-call
                 "SUPERVISOR-HANDLE-CHILD-EXIT"
                 supervisor "worker" :normal
                 :observed-generation 0)))
        (let ((new-actor
                (supervisor-integration-call
                 "SUPERVISOR-CHILD-BACKEND-REF" supervisor "worker")))
          (is (not (eq old-actor new-actor)))
          (is (not (sento-actor-live-p system old-actor)))
          (is (sento-actor-live-p system new-actor))
          (is (= 1 (supervisor-child-generation supervisor "worker")))
          (is (eq :stale
                  (supervisor-integration-call
                   "SUPERVISOR-HANDLE-CHILD-EXIT"
                   supervisor "worker" :normal
                   :observed-generation 0)))
          (is (eq new-actor
                  (supervisor-integration-call
                   "SUPERVISOR-CHILD-BACKEND-REF" supervisor "worker")))
          (is (= 1 (supervisor-child-generation supervisor "worker")))
          (is (eq :pong
                  (ask-result port new-actor :ping
                              :operation "supervised sento child")))
          (is (eq :outside
                  (ask-result port unrelated :outside
                              :operation "unrelated sento actor before supervisor shutdown")))
          (supervisor-integration-call "SHUTDOWN-SUPERVISOR" supervisor)
          (is (not (sento-actor-live-p system new-actor)))
          (is (sento-actor-live-p system unrelated))
          (is (eq :outside
                  (ask-result port unrelated :outside
                              :operation "unrelated sento actor after supervisor shutdown"))))))))

(test real-sento-budget-exhaustion-stops-every-owned-child
  (with-real-actor-system (system)
    (let* ((port (make-sento-runtime-port))
           (primary-spec
             (supervisor-integration-call
              "MAKE-SENTO-CHILD-SPEC"
              "primary" (unique-actor-name "budget-primary") #'identity
              :restart-class :permanent))
           (sibling-spec
             (supervisor-integration-call
              "MAKE-SENTO-CHILD-SPEC"
              "sibling" (unique-actor-name "budget-sibling") #'identity
              :restart-class :permanent))
           (supervisor
             (supervisor-integration-call
              "MAKE-SENTO-SUPERVISOR"
              "budget-root" port system (list primary-spec sibling-spec)
              :max-restarts 0
              :restart-window 10
              :clock (lambda () 0))))
      (supervisor-integration-call "START-SUPERVISOR" supervisor)
      (let ((primary
              (supervisor-integration-call
               "SUPERVISOR-CHILD-BACKEND-REF" supervisor "primary"))
            (sibling
              (supervisor-integration-call
               "SUPERVISOR-CHILD-BACKEND-REF" supervisor "sibling")))
        (signals error
          (supervisor-integration-call
           "SUPERVISOR-HANDLE-CHILD-EXIT"
           supervisor "primary" :failure
           :observed-generation 0))
        (is (not (sento-actor-live-p system primary)))
        (is (not (sento-actor-live-p system sibling)))
        (is (eq :stopped
                (getf
                 (supervisor-integration-call
                  "SUPERVISOR-CHILD-SNAPSHOT" supervisor "sibling")
                 :status)))))))
