(defpackage :starlangruntime-state-isolation-tests
  (:use :cl)
  (:import-from :starlangruntime
                #:actor-contract-error
                #:actor-stale-completion-error
                #:actor-instance-data
                #:actor-instance-invocation-count
                #:create-native-actor
                #:dispatch-next
                #:dispatch-result-condition
                #:dispatch-result-status
                #:make-runtime
                #:restart-actor
                #:shutdown-runtime
                #:tell
                #:ask)
  (:export #:run-tests))

(in-package :starlangruntime-state-isolation-tests)

(defun check (truth control &rest arguments)
  (unless truth
    (error (apply #'format nil control arguments))))

(defun integer-contract-p (contract value)
  (and (eq contract :integer)
       (integerp value)))

(defun nested-state (text)
  (list (vector (copy-seq text))))

(defun nested-text (state)
  (aref (car state) 0))

(defun mutate-nested-text (state character)
  (setf (char (nested-text state) 0) character)
  state)

(defun over-depth-state ()
  (loop with value = :leaf
        repeat 65
        do (setf value (vector value))
        finally (return value)))

(defun test-handler-error-cannot-mutate-committed-state ()
  (let ((runtime (make-runtime)))
    (unwind-protect
         (let ((actor
                 (create-native-actor
                  runtime
                  "state-error-isolation"
                  (lambda (message state owner)
                    (declare (ignore message owner))
                    (mutate-nested-text state #\X)
                    (error "synthetic transition failure"))
                  :initial-state (nested-state "seed"))))
           (tell runtime actor :go)
           (let ((result (dispatch-next runtime actor)))
             (check (eq :failed (dispatch-result-status result))
                    "Mutating handler failure did not fail dispatch.")
             (check (string= "seed" (nested-text (actor-instance-data actor)))
                    "Handler failure leaked nested mutation into committed state.")
             (check (zerop (actor-instance-invocation-count actor))
                    "Failed mutating transition advanced invocation count.")))
      (shutdown-runtime runtime))))

(defun test-output-rejection-cannot-mutate-committed-state ()
  (let ((runtime (make-runtime)))
    (unwind-protect
         (let ((actor
                 (create-native-actor
                  runtime
                  "state-contract-isolation"
                  (lambda (message state owner)
                    (declare (ignore message owner))
                    (mutate-nested-text state #\X)
                    (values "invalid-output" state))
                  :produces :integer
                  :output-validator #'integer-contract-p
                  :initial-state (nested-state "seed"))))
           (tell runtime actor :go)
           (let ((result (dispatch-next runtime actor)))
             (check (eq :failed (dispatch-result-status result))
                    "Rejected output did not fail dispatch.")
             (check (typep (dispatch-result-condition result)
                           'actor-contract-error)
                    "Rejected output did not preserve actor-contract-error.")
             (check (string= "seed" (nested-text (actor-instance-data actor)))
                    "Rejected output leaked nested mutation into committed state.")
             (check (zerop (actor-instance-invocation-count actor))
                    "Rejected output advanced invocation count.")))
      (shutdown-runtime runtime))))

(defun test-omitted-next-state-does-not-commit-working-mutation ()
  (let ((runtime (make-runtime)))
    (unwind-protect
         (let ((actor
                 (create-native-actor
                  runtime
                  "state-omitted-commit"
                  (lambda (message state owner)
                    (declare (ignore message owner))
                    (mutate-nested-text state #\X)
                    :ok)
                  :initial-state (nested-state "seed"))))
           (tell runtime actor :go)
           (let ((result (dispatch-next runtime actor)))
             (check (eq :completed (dispatch-result-status result))
                    "One-value transition unexpectedly failed.")
             (check (string= "seed" (nested-text (actor-instance-data actor)))
                    "One-value transition implicitly committed working-state mutation.")
             (check (= 1 (actor-instance-invocation-count actor))
                    "Successful one-value transition did not count exactly once.")))
      (shutdown-runtime runtime))))

(defun test-committed-next-state-does-not-retain-handler-alias ()
  (let ((runtime (make-runtime))
        (retained nil))
    (unwind-protect
         (let ((actor
                 (create-native-actor
                  runtime
                  "state-alias-isolation"
                  (lambda (message state owner)
                    (declare (ignore message state owner))
                    (let ((next (nested-state "owned")))
                      (setf retained next)
                      (values :ok next)))
                  :initial-state (nested-state "seed"))))
           (tell runtime actor :go)
           (let ((result (dispatch-next runtime actor)))
             (check (eq :completed (dispatch-result-status result))
                    "Valid next-state transition did not complete."))
           (mutate-nested-text retained #\X)
           (check (string= "owned" (nested-text (actor-instance-data actor)))
                  "Retained handler alias retroactively mutated committed state."))
      (shutdown-runtime runtime))))

(defun test-cyclic-next-state-is-typed-rejection ()
  (let ((runtime (make-runtime)))
    (unwind-protect
         (let ((actor
                 (create-native-actor
                  runtime
                  "state-cycle-rejection"
                  (lambda (message state owner)
                    (declare (ignore message state owner))
                    (let ((cycle (list :cycle)))
                      (setf (cdr cycle) cycle)
                      (values :ok cycle)))
                  :initial-state (nested-state "seed"))))
           (tell runtime actor :go)
           (let ((result (dispatch-next runtime actor)))
             (check (eq :failed (dispatch-result-status result))
                    "Cyclic next-state was committed instead of rejected.")
             (check (typep (dispatch-result-condition result)
                           'actor-contract-error)
                    "Cyclic next-state rejection was not actor-contract-error.")
             (check (string= "seed" (nested-text (actor-instance-data actor)))
                    "Cyclic next-state rejection changed committed state.")
             (check (zerop (actor-instance-invocation-count actor))
                    "Cyclic next-state rejection advanced invocation count.")))
      (shutdown-runtime runtime))))

(defun test-unsupported-host-next-state-is-typed-rejection ()
  (let ((runtime (make-runtime)))
    (unwind-protect
         (let ((actor
                 (create-native-actor
                  runtime
                  "state-host-rejection"
                  (lambda (message state owner)
                    (declare (ignore message state owner))
                    (values :ok #'identity))
                  :initial-state (nested-state "seed"))))
           (tell runtime actor :go)
           (let ((result (dispatch-next runtime actor)))
             (check (eq :failed (dispatch-result-status result))
                    "Unsupported host next-state was committed instead of rejected.")
             (check (typep (dispatch-result-condition result)
                           'actor-contract-error)
                    "Unsupported host next-state rejection was not actor-contract-error.")
             (check (string= "seed" (nested-text (actor-instance-data actor)))
                    "Unsupported host next-state rejection changed committed state.")
             (check (zerop (actor-instance-invocation-count actor))
                    "Unsupported host next-state rejection advanced invocation count.")))
      (shutdown-runtime runtime))))

(defun test-resource-bound-next-state-is-typed-rejection ()
  (let ((runtime (make-runtime)))
    (unwind-protect
         (let ((actor
                 (create-native-actor
                  runtime
                  "state-resource-rejection"
                  (lambda (message state owner)
                    (declare (ignore message state owner))
                    (values :ok (over-depth-state)))
                  :initial-state (nested-state "seed"))))
           (tell runtime actor :go)
           (let ((result (dispatch-next runtime actor)))
             (check (eq :failed (dispatch-result-status result))
                    "Over-depth next-state was committed instead of rejected.")
             (check (typep (dispatch-result-condition result)
                           'actor-contract-error)
                    "Over-depth next-state rejection was not actor-contract-error.")
             (check (string= "seed" (nested-text (actor-instance-data actor)))
                    "Over-depth next-state rejection changed committed state.")
             (check (zerop (actor-instance-invocation-count actor))
                    "Over-depth next-state rejection advanced invocation count.")))
      (shutdown-runtime runtime))))

(defun test-restart-fencing-also-isolates-working-state ()
  (let ((runtime (make-runtime)))
    (unwind-protect
         (progn
           (create-native-actor
            runtime
            "state-isolation-restarter"
            (lambda (message state owner)
              (declare (ignore state))
              (ecase message
                (:restart
                 (restart-actor owner "state-isolation-worker")
                 :restarted))))
           (let ((actor
                   (create-native-actor
                    runtime
                    "state-isolation-worker"
                    (lambda (message state owner)
                      (declare (ignore message))
                      (mutate-nested-text state #\X)
                      (ask owner "state-isolation-restarter" :restart)
                      (values :late state))
                    :initial-state (nested-state "seed"))))
             (tell runtime actor :go)
             (let ((result (dispatch-next runtime actor)))
               (check (eq :failed (dispatch-result-status result))
                      "Restarted old-generation completion was not rejected.")
               (check (typep (dispatch-result-condition result)
                             'actor-stale-completion-error)
                      "Restarted old-generation completion was not typed stale.")
               (check (string= "seed" (nested-text (actor-instance-data actor)))
                      "Old-generation working mutation leaked across restart fencing.")
               (check (zerop (actor-instance-invocation-count actor))
                      "Stale mutating completion advanced invocation count."))))
      (shutdown-runtime runtime))))

(defun run-tests ()
  (test-handler-error-cannot-mutate-committed-state)
  (test-output-rejection-cannot-mutate-committed-state)
  (test-omitted-next-state-does-not-commit-working-mutation)
  (test-committed-next-state-does-not-retain-handler-alias)
  (test-cyclic-next-state-is-typed-rejection)
  (test-unsupported-host-next-state-is-typed-rejection)
  (test-resource-bound-next-state-is-typed-rejection)
  (test-restart-fencing-also-isolates-working-state)
  (format t "~&starlang-runtime state-isolation tests passed~%")
  t)
