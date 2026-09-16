(defpackage :starlangruntime-stale-completion-tests
  (:use :cl)
  (:import-from :starlangruntime
                #:actor-stale-completion-error
                #:actor-instance-data
                #:actor-instance-generation
                #:actor-instance-invocation-count
                #:actor-instance-last-error
                #:dispatch-result-condition
                #:dispatch-result-status
                #:make-runtime
                #:create-native-actor
                #:register-actor
                #:tell
                #:ask
                #:dispatch-next
                #:restart-actor
                #:stop-actor
                #:unregister-actor
                #:shutdown-runtime
                #:runtime-actor-count
                #:runtime-status)
  (:export #:run-tests))

(in-package :starlangruntime-stale-completion-tests)

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

(defun stale-dispatch-p (result)
  (and (eq :failed (dispatch-result-status result))
       (typep (dispatch-result-condition result)
              'actor-stale-completion-error)))

(defun test-restart-fences-handler-error-diagnostics ()
  (let ((runtime (make-runtime)))
    (unwind-protect
         (progn
           (create-native-actor
            runtime
            "error-restarter"
            (lambda (message state owner)
              (declare (ignore state))
              (ecase message
                (:restart
                 (restart-actor owner "error-worker")
                 :restarted))))
           (let ((actor
                   (create-native-actor
                    runtime
                    "error-worker"
                    (lambda (message state owner)
                      (declare (ignore state))
                      (ecase message
                        (:go
                         (ask owner "error-restarter" :restart)
                         (error "late old-generation failure"))))
                    :initial-state 11)))
             (tell runtime actor :go)
             (let ((result (dispatch-next runtime actor)))
               (check (stale-dispatch-p result)
                      "Handler failure after restart was not typed as stale completion.")
               (check (= 1 (actor-instance-generation actor))
                      "Handler-error fixture did not restart the actor.")
               (check (= 11 (actor-instance-data actor))
                      "Handler failure after restart changed replacement state.")
               (check (zerop (actor-instance-invocation-count actor))
                      "Handler failure after restart changed replacement success count.")
               (check (null (actor-instance-last-error actor))
                      "Old-generation handler failure overwrote replacement diagnostics."))))
      (shutdown-runtime runtime))))

(defun test-restart-during-output-validation-fences-diagnostics ()
  (let ((runtime (make-runtime))
        (restart-on-validation-p t))
    (unwind-protect
         (let ((actor
                 (create-native-actor
                  runtime
                  "validator-worker"
                  (lambda (message state owner)
                    (declare (ignore message owner))
                    (values 42 (1+ state)))
                  :produces :integer
                  :output-validator
                  (lambda (contract value)
                    (declare (ignore contract value))
                    (when restart-on-validation-p
                      (setf restart-on-validation-p nil)
                      (restart-actor runtime "validator-worker"))
                    nil)
                  :initial-state 3)))
           (tell runtime actor :go)
           (let ((result (dispatch-next runtime actor)))
             (check (stale-dispatch-p result)
                    "Output validation after restart did not report stale completion.")
             (check (= 1 (actor-instance-generation actor))
                    "Output-validator fixture did not restart the actor.")
             (check (= 3 (actor-instance-data actor))
                    "Old-generation output validation changed replacement state.")
             (check (zerop (actor-instance-invocation-count actor))
                    "Old-generation output validation changed replacement success count.")
             (check (null (actor-instance-last-error actor))
                    "Old-generation output validation overwrote replacement diagnostics.")))
      (shutdown-runtime runtime))))

(defun test-stop-fences-inflight-completion ()
  (let ((runtime (make-runtime)))
    (unwind-protect
         (let ((actor
                 (create-native-actor
                  runtime
                  "stop-worker"
                  (lambda (message state owner)
                    (declare (ignore message state))
                    (stop-actor owner "stop-worker")
                    (values :late 99))
                  :initial-state 5)))
           (tell runtime actor :go)
           (let ((result (dispatch-next runtime actor)))
             (check (stale-dispatch-p result)
                    "Stopped actor published its in-flight completion.")
             (check (= 5 (actor-instance-data actor))
                    "Stopped actor committed in-flight state.")
             (check (zerop (actor-instance-invocation-count actor))
                    "Stopped actor counted an in-flight success.")
             (check (null (actor-instance-last-error actor))
                    "Stopped actor accepted old-dispatch diagnostics.")))
      (shutdown-runtime runtime))))

(defun test-unregister-fences-inflight-completion ()
  (let ((runtime (make-runtime)))
    (unwind-protect
         (let ((actor
                 (create-native-actor
                  runtime
                  "unregistered-worker"
                  (lambda (message state owner)
                    (declare (ignore message state))
                    (unregister-actor owner "unregistered-worker")
                    (values :late 99))
                  :initial-state 13)))
           (tell runtime actor :go)
           (let ((result (dispatch-next runtime actor)))
             (check (stale-dispatch-p result)
                    "Unregistered actor published its in-flight completion.")
             (check (= 13 (actor-instance-data actor))
                    "Unregistered actor committed in-flight state.")
             (check (zerop (actor-instance-invocation-count actor))
                    "Unregistered actor counted an in-flight success.")
             (check (null (actor-instance-last-error actor))
                    "Unregistered actor accepted old-dispatch diagnostics.")
             (check (zerop (runtime-actor-count runtime))
                    "Unregister fixture left the actor registered.")))
      (shutdown-runtime runtime))))

(defun test-reregister-same-instance-does-not-resurrect-completion-ownership ()
  (let ((runtime (make-runtime))
        (actor nil))
    (unwind-protect
         (progn
           (setf actor
                 (create-native-actor
                  runtime
                  "reregister-worker"
                  (lambda (message state owner)
                    (declare (ignore state))
                    (ecase message
                      (:go
                       (unregister-actor owner actor)
                       (register-actor owner actor)
                       (values :late 99))
                      (:fresh
                       (values :fresh 31))))
                  :initial-state 29))
           (tell runtime actor :go)
           (let ((result (dispatch-next runtime actor)))
             (check (stale-dispatch-p result)
                    "Unregister/re-register of the same instance resurrected old completion ownership.")
             (check (= 29 (actor-instance-data actor))
                    "Old dispatch committed state after unregister/re-register ABA.")
             (check (zerop (actor-instance-invocation-count actor))
                    "Old dispatch counted success after unregister/re-register ABA.")
             (check (null (actor-instance-last-error actor))
                    "Old dispatch overwrote diagnostics after unregister/re-register ABA.")
             (check (= 1 (runtime-actor-count runtime))
                    "Re-register fixture did not restore the same actor registration."))
           (tell runtime actor :fresh)
           (let ((fresh-result (dispatch-next runtime actor)))
             (check (eq :completed (dispatch-result-status fresh-result))
                    "Fresh delivery after re-registration did not complete normally.")
             (check (= 31 (actor-instance-data actor))
                    "Fresh delivery after re-registration did not commit state.")
             (check (= 1 (actor-instance-invocation-count actor))
                    "Fresh delivery after re-registration did not commit exactly once.")))
      (shutdown-runtime runtime))))

(defun test-shutdown-fences-inflight-completion ()
  (let ((runtime (make-runtime)))
    (unwind-protect
         (let ((actor
                 (create-native-actor
                  runtime
                  "shutdown-worker"
                  (lambda (message state owner)
                    (declare (ignore message state))
                    (shutdown-runtime owner)
                    (values :late 99))
                  :initial-state 17)))
           (tell runtime actor :go)
           (let ((result (dispatch-next runtime actor)))
             (check (stale-dispatch-p result)
                    "Shut-down runtime published an in-flight completion.")
             (check (eq :stopped (runtime-status runtime))
                    "Shutdown fixture did not stop the runtime.")
             (check (= 17 (actor-instance-data actor))
                    "Shut-down actor committed in-flight state.")
             (check (zerop (actor-instance-invocation-count actor))
                    "Shut-down actor counted an in-flight success.")
             (check (null (actor-instance-last-error actor))
                    "Shut-down actor accepted old-dispatch diagnostics.")))
      (shutdown-runtime runtime))))

(defun test-stale-ask-does-not-publish-success ()
  (let ((runtime (make-runtime)))
    (unwind-protect
         (progn
           (create-native-actor
            runtime
            "ask-restarter"
            (lambda (message state owner)
              (declare (ignore state))
              (ecase message
                (:restart
                 (restart-actor owner "ask-worker")
                 :restarted))))
           (create-native-actor
            runtime
            "ask-worker"
            (lambda (message state owner)
              (declare (ignore state))
              (ecase message
                (:go
                 (ask owner "ask-restarter" :restart)
                 (values :late-success 99))))
            :initial-state 23)
           (check
            (signals-p 'actor-stale-completion-error
                       (lambda () (ask runtime "ask-worker" :go)))
            "ASK published a successful reply from a stale dispatch."))
      (shutdown-runtime runtime))))

(defun run-tests ()
  (test-restart-fences-handler-error-diagnostics)
  (test-restart-during-output-validation-fences-diagnostics)
  (test-stop-fences-inflight-completion)
  (test-unregister-fences-inflight-completion)
  (test-reregister-same-instance-does-not-resurrect-completion-ownership)
  (test-shutdown-fences-inflight-completion)
  (test-stale-ask-does-not-publish-success)
  (format t "~&starlang-runtime stale completion tests passed~%")
  t)
