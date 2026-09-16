(defpackage :starsupervisor-tests
  (:use :cl :fiveam)
  (:import-from :staractorprotocol
                #:star-actor-reference-generation)
  (:import-from :starlangruntime
                #:actor-running-p
                #:actor-stale-reference-error
                #:ask
                #:make-native-actor-definition
                #:make-runtime
                #:resolve-actor
                #:runtime-status
                #:stop-actor
                #:tell)
  (:export))
(in-package :starsupervisor-tests)

(def-suite starsupervisor-tests
  :description "Final one-for-one supervision semantics through the real runtime.")

(in-suite starsupervisor-tests)

(defun supervisor-symbol (name)
  (multiple-value-bind (symbol status)
      (find-symbol name :starsupervisor)
    (unless (and symbol (eq status :external) (fboundp symbol))
      (error "Missing exported star-supervisor function ~A." name))
    symbol))

(defun supervisor-call (name &rest arguments)
  (apply (symbol-function (supervisor-symbol name)) arguments))

(defun snapshot-value (snapshot key)
  (getf snapshot key :missing))

(defun make-test-definition (name restart-policy &key (handler nil))
  (make-native-actor-definition
   name
   (or handler
       (lambda (message state runtime)
         (declare (ignore runtime))
         (case message
           (:crash (error "fixture crash"))
           (:state (values state state))
           (otherwise (values message state)))))
   :service-uri (format nil "star://test:local:~A" name)
   :restart-policy restart-policy
   :initial-state (list :count 0)))

(defun make-runtime-supervisor-fixture (specs &rest options)
  (let ((runtime (make-runtime)))
    (values runtime
            (apply #'supervisor-call
                   "MAKE-RUNTIME-SUPERVISOR"
                   "root" runtime specs options))))

(defun child-reference (supervisor child-id)
  (supervisor-call "SUPERVISOR-CHILD-REFERENCE" supervisor child-id))

(defun child-snapshot (supervisor child-id)
  (supervisor-call "SUPERVISOR-CHILD-SNAPSHOT" supervisor child-id))

(defun start-supervisor (supervisor)
  (supervisor-call "START-SUPERVISOR" supervisor))

(defun step-supervisor (supervisor)
  (supervisor-call "SUPERVISOR-STEP" supervisor))

(defun runtime-child-spec (id definition)
  (supervisor-call "MAKE-RUNTIME-CHILD-SPEC" id definition))

(defun condition-name (condition)
  (let ((name (class-name (class-of condition))))
    (if (symbolp name) (symbol-name name) (princ-to-string name))))

(test permanent-failure-restarts-one-child-and-fences-stale-reference
  (let* ((primary-definition (make-test-definition "primary" :permanent))
         (sibling-definition (make-test-definition "sibling" :permanent))
         (primary-spec (runtime-child-spec "primary" primary-definition))
         (sibling-spec (runtime-child-spec "sibling" sibling-definition)))
    (multiple-value-bind (runtime supervisor)
        (make-runtime-supervisor-fixture (list primary-spec sibling-spec))
      (start-supervisor supervisor)
      (let ((old-primary (child-reference supervisor "primary"))
            (old-sibling (child-reference supervisor "sibling")))
        (is (eq :accepted (starlangruntime:delivery-result-status
                           (tell runtime old-primary :crash))))
        (step-supervisor supervisor)
        (let ((new-primary (child-reference supervisor "primary"))
              (new-sibling (child-reference supervisor "sibling")))
          (is (= 1 (star-actor-reference-generation new-primary)))
          (is (= (star-actor-reference-generation old-sibling)
                 (star-actor-reference-generation new-sibling)))
          (signals actor-stale-reference-error
            (resolve-actor runtime old-primary))
          (is (eq :ping (ask runtime new-sibling :ping))))))))

(test transient-restarts-only-on-failure-and-temporary-never-restarts
  (let* ((transient-spec
           (runtime-child-spec
            "transient" (make-test-definition "transient" :transient)))
         (temporary-spec
           (runtime-child-spec
            "temporary" (make-test-definition "temporary" :temporary))))
    (multiple-value-bind (runtime supervisor)
        (make-runtime-supervisor-fixture (list transient-spec temporary-spec))
      (start-supervisor supervisor)
      (let ((transient (child-reference supervisor "transient"))
            (temporary (child-reference supervisor "temporary")))
        (tell runtime transient :crash)
        (tell runtime temporary :crash)
        (step-supervisor supervisor)
        (is (= 1 (star-actor-reference-generation
                  (child-reference supervisor "transient"))))
        (is (eq :stopped
                (snapshot-value (child-snapshot supervisor "temporary") :status)))
        (let ((after-failure (child-reference supervisor "transient")))
          (stop-actor runtime after-failure)
          (step-supervisor supervisor)
          (is (= 1 (star-actor-reference-generation
                    (child-reference supervisor "transient"))))
          (is (eq :stopped
                  (snapshot-value (child-snapshot supervisor "transient")
                                  :status))))))))

(test restart-intensity-is-bounded-and-terminally-classified
  (let ((now 100))
    (let ((spec (runtime-child-spec
                 "worker" (make-test-definition "worker" :permanent))))
      (multiple-value-bind (runtime supervisor)
          (make-runtime-supervisor-fixture
           (list spec)
           :max-restarts 2
           :restart-window 10
           :clock (lambda () now))
        (start-supervisor supervisor)
        (dotimes (index 2)
          (declare (ignorable index))
          (tell runtime (child-reference supervisor "worker") :crash)
          (step-supervisor supervisor))
        (tell runtime (child-reference supervisor "worker") :crash)
        (let ((caught nil))
          (handler-case
              (step-supervisor supervisor)
            (error (condition)
              (setf caught condition)))
          (is (not (null caught)))
          (is (string= "RESTART-BUDGET-EXHAUSTED-ERROR"
                       (condition-name caught))))
        (is (eq :failed
                (snapshot-value
                 (supervisor-call "SUPERVISOR-SNAPSHOT" supervisor)
                 :status)))
        (is (eq :failed
                (snapshot-value (child-snapshot supervisor "worker")
                                :status)))))))

(test drain-suppresses-permanent-restart-and-shutdown-is-terminal
  (let ((spec (runtime-child-spec
               "worker" (make-test-definition "worker" :permanent))))
    (multiple-value-bind (runtime supervisor)
        (make-runtime-supervisor-fixture (list spec))
      (start-supervisor supervisor)
      (let ((before (child-reference supervisor "worker")))
        (supervisor-call "DRAIN-SUPERVISOR" supervisor)
        (step-supervisor supervisor)
        (is (= (star-actor-reference-generation before)
               (star-actor-reference-generation
                (child-reference supervisor "worker"))))
        (is (not (actor-running-p (resolve-actor runtime before))))
        (is (eq :stopped
                (snapshot-value
                 (supervisor-call "SUPERVISOR-SNAPSHOT" supervisor)
                 :status))))
      (supervisor-call "SHUTDOWN-SUPERVISOR" supervisor)
      (is (eq :stopped (runtime-status runtime))))))

(test snapshots-expose-only-supervision-state
  (let ((spec (runtime-child-spec
               "worker" (make-test-definition "worker" :permanent))))
    (multiple-value-bind (runtime supervisor)
        (make-runtime-supervisor-fixture (list spec))
      (declare (ignore runtime))
      (start-supervisor supervisor)
      (let ((snapshot (supervisor-call "SUPERVISOR-SNAPSHOT" supervisor))
            (child (child-snapshot supervisor "worker")))
        (is (string= "root" (snapshot-value snapshot :id)))
        (is (eq :running (snapshot-value snapshot :status)))
        (is (string= "worker" (snapshot-value child :id)))
        (is (eq :permanent (snapshot-value child :restart-class)))
        (is (= 0 (snapshot-value child :generation)))
        (is (eq :running (snapshot-value child :status)))
        (is (eq :missing (snapshot-value child :business-state)))))))
