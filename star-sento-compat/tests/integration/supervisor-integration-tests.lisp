(in-package :starsentocompat-integration-tests)

(defun supervisor-integration-symbol (name)
  (multiple-value-bind (symbol status)
      (find-symbol name :starsupervisor)
    (unless (and symbol (eq status :external) (fboundp symbol))
      (error "Missing exported star-supervisor function ~A." name))
    symbol))

(defun supervisor-integration-call (name &rest arguments)
  (apply (symbol-function (supervisor-integration-symbol name)) arguments))

(test real-sento-supervisor-replaces-one-child-and-shuts-down-cleanly
  (with-real-actor-system (system)
    (let* ((port (make-sento-runtime-port))
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
        (supervisor-integration-call
         "SUPERVISOR-HANDLE-CHILD-EXIT" supervisor "worker" :normal)
        (let ((new-actor
                (supervisor-integration-call
                 "SUPERVISOR-CHILD-BACKEND-REF" supervisor "worker")))
          (is (not (eq old-actor new-actor)))
          (is (not (sento-actor-live-p system old-actor)))
          (is (sento-actor-live-p system new-actor))
          (is (eql 1
                   (getf
                    (supervisor-integration-call
                     "SUPERVISOR-CHILD-SNAPSHOT" supervisor "worker")
                    :generation)))
          (is (eq :pong
                  (ask-result port new-actor :ping
                              :operation "supervised sento child")))))
      (supervisor-integration-call "SHUTDOWN-SUPERVISOR" supervisor)
      (is (null (sento-all-actors system)))
      (setf system nil))))
