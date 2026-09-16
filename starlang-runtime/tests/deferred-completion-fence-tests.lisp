(in-package :starlangruntime-wire-tests)

(defun deferred-success-result (value)
  (complete-dispatch
   :message-type "test/result@1"
   :payload (list (cons "value" value))))

(defun assert-deferred-identity-conflict (dispatcher command mutator context)
  (let ((conflict (copy-tree command)))
    (funcall mutator conflict)
    (check
     (signals-p
      'wire-dispatcher-idempotency-conflict-error
      (lambda ()
        (finish-deferred-dispatch
         dispatcher conflict (deferred-success-result "wrong-command"))))
     "Deferred completion accepted changed ~A identity."
     context)
    (check (eq :in-progress (deferred-dispatch-status dispatcher command))
           "Rejected ~A completion changed the active record."
           context)
    (check (null (drain-dispatcher-emitted dispatcher))
           "Rejected ~A completion emitted outcomes."
           context)))

(defun test-deferred-completion-fences-semantic-command-identity ()
  (let* ((dispatcher (make-deterministic-dispatcher (dispatcher-manifest)))
         (command (dispatcher-command)))
    (register-dispatch-actor
     dispatcher "worker"
     (lambda (runtime envelope)
       (declare (ignore runtime envelope))
       (defer-dispatch)))
    (submit-dispatch-envelope dispatcher command)
    (check (eq :deferred (run-dispatcher-next dispatcher))
           "Fixture did not enter deferred execution.")
    (drain-dispatcher-emitted dispatcher)
    (assert-deferred-identity-conflict
     dispatcher command
     (lambda (conflict)
       (setf (cdr (assoc "target" (getf conflict :payload) :test #'string=))
             "changed.example.org"))
     "payload")
    (assert-deferred-identity-conflict
     dispatcher command
     (lambda (conflict)
       (setf (getf conflict :sender) "other-caller"))
     "sender")
    (assert-deferred-identity-conflict
     dispatcher command
     (lambda (conflict)
       (setf (getf conflict :correlation-id) "other-correlation"))
     "correlation")
    (assert-deferred-identity-conflict
     dispatcher command
     (lambda (conflict)
       (setf (getf conflict :deadline) "2099-01-01T00:00:00Z"))
     "deadline")
    (check
     (eq :completed
         (finish-deferred-dispatch
          dispatcher command (deferred-success-result "right-command")))
     "Original deferred command did not complete after rejected conflicts.")
    (check (equal '(:reply :ack) (emitted-kinds dispatcher))
           "Valid deferred completion emitted the wrong outcomes.")))

(defun test-deferred-completion-fences-active-delivery-attempt ()
  (let* ((dispatcher (make-deterministic-dispatcher (dispatcher-manifest)))
         (attempt-1
           (dispatcher-command
            :message-id "deferred-attempt-1"
            :idempotency-key "deferred-attempt-key")))
    (register-dispatch-actor
     dispatcher "worker"
     (lambda (runtime envelope)
       (declare (ignore runtime envelope))
       (defer-dispatch)))
    (submit-dispatch-envelope dispatcher attempt-1)
    (check (eq :deferred (run-dispatcher-next dispatcher))
           "Attempt 1 did not defer.")
    (drain-dispatcher-emitted dispatcher)
    (check
     (eq :retry
         (finish-deferred-dispatch
          dispatcher attempt-1
          (retry-dispatch :retry-after-ms 1 :reason "retry")))
     "Attempt 1 did not settle into retry.")
    (drain-dispatcher-emitted dispatcher)
    (let ((attempt-2
            (redeliver-command
             dispatcher attempt-1 :message-id "deferred-attempt-2")))
      (submit-dispatch-envelope dispatcher attempt-2)
      (check (eq :deferred (run-dispatcher-next dispatcher))
             "Attempt 2 did not become the active deferred delivery.")
      (drain-dispatcher-emitted dispatcher)
      (let ((stale-outcome
              (handler-case
                  (finish-deferred-dispatch
                   dispatcher attempt-1
                   (deferred-success-result "stale-attempt"))
                (wire-dispatcher-error () :rejected))))
        (check (not (eq stale-outcome :completed))
               "Stale attempt 1 completed active attempt 2."))
      (check (eq :in-progress
                 (deferred-dispatch-status dispatcher attempt-2))
             "Stale attempt changed the active attempt-2 record.")
      (check (null (drain-dispatcher-emitted dispatcher))
             "Stale attempt emitted reply/completion outcomes.")
      (let ((wrong-attempt (copy-tree attempt-2)))
        (setf (getf wrong-attempt :attempt) 1)
        (let ((stale-outcome
                (handler-case
                    (finish-deferred-dispatch
                     dispatcher wrong-attempt
                     (deferred-success-result "reused-attempt"))
                  (wire-dispatcher-error () :rejected))))
          (check (not (eq stale-outcome :completed))
                 "Reused/non-monotonic attempt metadata settled attempt 2."))
        (check (eq :in-progress
                   (deferred-dispatch-status dispatcher attempt-2))
               "Rejected attempt metadata changed the active record.")
        (check (null (drain-dispatcher-emitted dispatcher))
               "Rejected attempt metadata emitted outcomes."))
      (check
       (eq :completed
           (finish-deferred-dispatch
            dispatcher attempt-2
            (deferred-success-result "active-attempt")))
       "Active attempt 2 did not settle.")
      (check (equal '(:reply :ack) (emitted-kinds dispatcher))
             "Active attempt 2 emitted the wrong outcomes.")
      (check (eq :terminal (deferred-dispatch-status dispatcher attempt-2))
             "Active attempt 2 did not become terminal.")
      (check
       (eq :late-terminal
           (finish-deferred-dispatch
            dispatcher attempt-1
            (deferred-success-result "late-after-terminal")))
       "Late stale completion did not remain terminal metadata.")
      (check (null (drain-dispatcher-emitted dispatcher))
             "Late terminal duplicate emitted new outcomes."))))

(defun run-deferred-completion-fence-tests ()
  (test-deferred-completion-fences-semantic-command-identity)
  (test-deferred-completion-fences-active-delivery-attempt)
  (format t "~&starlang-runtime deferred completion fence tests passed~%")
  t)
