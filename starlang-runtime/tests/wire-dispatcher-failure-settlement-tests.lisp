(defpackage :starlangruntime-wire-failure-tests
  (:use :cl)
  (:import-from :starlangruntime
                #:make-deterministic-dispatcher
                #:register-dispatch-actor
                #:complete-dispatch
                #:retry-dispatch
                #:fail-dispatch
                #:defer-dispatch
                #:submit-dispatch-envelope
                #:run-dispatcher
                #:run-dispatcher-next
                #:drain-dispatcher-emitted
                #:redeliver-command
                #:deferred-dispatch-status)
  (:export #:run-tests))

(in-package :starlangruntime-wire-failure-tests)

(defun check (truth control &rest arguments)
  (apply #'starlangruntime-wire-tests::check truth control arguments))

(defun dispatcher-command (&rest arguments)
  (apply #'starlangruntime-wire-tests::dispatcher-command arguments))

(defun make-fixture-dispatcher ()
  (make-deterministic-dispatcher
   (starlangruntime-wire-tests::dispatcher-manifest)))

(defun emitted-kinds (outcomes)
  (mapcar (lambda (envelope) (getf envelope :kind)) outcomes))

(defun error-envelope-code (outcomes)
  (let ((error-envelope
          (find :error outcomes :key (lambda (envelope) (getf envelope :kind)))))
    (and error-envelope
         (getf (getf error-envelope :payload) :code))))

(defun check-terminal-handler-failure (handler label)
  (let* ((dispatcher (make-fixture-dispatcher))
         (command (dispatcher-command)))
    (register-dispatch-actor dispatcher "worker" handler)
    (submit-dispatch-envelope dispatcher command)
    (check (eq :failed (run-dispatcher-next dispatcher))
           "~A did not settle as a terminal failure."
           label)
    (check (eq :terminal (deferred-dispatch-status dispatcher command))
           "~A left an active idempotency record."
           label)
    (let ((outcomes (drain-dispatcher-emitted dispatcher)))
      (check (equal '(:ack :error) (emitted-kinds outcomes))
             "~A emitted the wrong lifecycle chain: ~S"
             label
             (emitted-kinds outcomes))
      (check (string= "star.native-handler-error"
                      (or (error-envelope-code outcomes) ""))
             "~A emitted the wrong terminal error code."
             label))))

(defun test-handler-error-does-not-leave-active-record ()
  (let ((calls 0))
    (check-terminal-handler-failure
     (lambda (runtime envelope)
       (declare (ignore runtime envelope))
       (incf calls)
       (error "synthetic handler failure"))
     "handler exception")
    (check (= 1 calls)
           "Failure-settlement fixture did not reach the handler exactly once.")))

(defun test-result-contract-errors-settle-terminally ()
  (check-terminal-handler-failure
   (lambda (runtime envelope)
     (declare (ignore runtime envelope))
     :not-a-property-list)
   "non-plist result")
  (check-terminal-handler-failure
   (lambda (runtime envelope)
     (declare (ignore runtime envelope))
     (list :outcome :unknown))
   "unknown result outcome")
  (check-terminal-handler-failure
   (lambda (runtime envelope)
     (declare (ignore runtime envelope))
     (complete-dispatch
      :message-type "test/unknown@1"
      :payload '(("value" . "not-produced"))))
   "invalid reply contract")
  (check-terminal-handler-failure
   (lambda (runtime envelope)
     (declare (ignore runtime envelope))
     (retry-dispatch :retry-after-ms 0 :reason "invalid retry"))
   "result construction error"))

(defun test-legitimate-defer-remains-active ()
  (let* ((dispatcher (make-fixture-dispatcher))
         (command (dispatcher-command)))
    (register-dispatch-actor
     dispatcher "worker"
     (lambda (runtime envelope)
       (declare (ignore runtime envelope))
       (defer-dispatch)))
    (submit-dispatch-envelope dispatcher command)
    (check (eq :deferred (run-dispatcher-next dispatcher))
           "Legitimate deferred work did not remain deferred.")
    (check (eq :in-progress (deferred-dispatch-status dispatcher command))
           "Legitimate deferred work was terminalized.")
    (check (equal '(:ack)
                  (emitted-kinds (drain-dispatcher-emitted dispatcher)))
           "Legitimate deferred work emitted a terminal outcome.")))

(defun test-explicit-retryable-failure-remains-retryable ()
  (let* ((dispatcher (make-fixture-dispatcher))
         (command
           (dispatcher-command
            :message-id "retryable-failure-1"
            :idempotency-key "retryable-failure-key")))
    (register-dispatch-actor
     dispatcher "worker"
     (lambda (runtime envelope)
       (declare (ignore runtime envelope))
       (fail-dispatch
        :code "test.retryable"
        :message "explicit retry policy"
        :retryable t)))
    (submit-dispatch-envelope dispatcher command)
    (check (eq :retry (run-dispatcher-next dispatcher))
           "Explicit retryable failure was converted to terminal failure.")
    (check (eq :retry (deferred-dispatch-status dispatcher command))
           "Explicit retryable failure lost retry state.")
    (let ((outcomes (drain-dispatcher-emitted dispatcher)))
      (check (equal '(:ack :error) (emitted-kinds outcomes))
             "Explicit retryable failure emitted the wrong lifecycle chain.")
      (check (string= "test.retryable"
                      (or (error-envelope-code outcomes) ""))
             "Explicit retryable failure changed its error code."))))

(defun test-terminal-state-is-not-overwritten-by-exception-settlement ()
  (let* ((dispatcher (make-fixture-dispatcher))
         (command
           (dispatcher-command
            :message-id "cancel-then-error-1"
            :idempotency-key "cancel-then-error-key")))
    (register-dispatch-actor
     dispatcher "worker"
     (lambda (runtime envelope)
       (submit-dispatch-envelope
        runtime
        (staractorprotocol:make-cancel-envelope
         envelope
         :message-id "cancel-during-handler"
         :actor "worker"
         :sender "caller"
         :reason "test"))
       (error "failure after terminal cancellation")))
    (submit-dispatch-envelope dispatcher command)
    (run-dispatcher-next dispatcher)
    (check (eq :terminal (deferred-dispatch-status dispatcher command))
           "Handler exception overwrote a pre-existing terminal record.")
    (let ((outcomes (drain-dispatcher-emitted dispatcher)))
      (check (equal '(:ack :error) (emitted-kinds outcomes))
             "Handler exception duplicated an already-terminal outcome: ~S"
             (emitted-kinds outcomes))
      (check (string= "star.cancelled"
                      (or (error-envelope-code outcomes) ""))
             "Handler exception replaced the existing cancellation outcome."))))

(defun test-failed-command-does-not-block-unrelated-queue-work ()
  (let* ((dispatcher (make-fixture-dispatcher))
         (bad
           (dispatcher-command
            :message-id "bad-command"
            :idempotency-key "bad-key"
            :target "bad.example.org"))
         (good
           (dispatcher-command
            :message-id "good-command"
            :idempotency-key "good-key"
            :target "good.example.org"))
         (calls 0))
    (register-dispatch-actor
     dispatcher "worker"
     (lambda (runtime envelope)
       (declare (ignore runtime))
       (incf calls)
       (if (string= "bad.example.org"
                    (cdr (assoc "target" (getf envelope :payload)
                                :test #'string=)))
           (error "synthetic first-command failure")
           (complete-dispatch
            :message-type "test/result@1"
            :payload '(("value" . "ok"))))))
    (submit-dispatch-envelope dispatcher bad)
    (submit-dispatch-envelope dispatcher good)
    (check (equal '(:failed :completed) (run-dispatcher dispatcher))
           "A failed command prevented unrelated queued work from completing.")
    (check (= 2 calls)
           "Unrelated queued work did not reach the handler after failure.")
    (check (eq :terminal (deferred-dispatch-status dispatcher bad))
           "Failed command did not become terminal.")
    (check (eq :terminal (deferred-dispatch-status dispatcher good))
           "Following successful command did not become terminal.")
    (check (equal '(:ack :error :ack :reply :ack)
                  (emitted-kinds (drain-dispatcher-emitted dispatcher)))
           "Failure plus following success emitted the wrong lifecycle chain.")))

(defun test-terminal-failure-redelivery-does-not-rerun-handler ()
  (let* ((dispatcher (make-fixture-dispatcher))
         (command
           (dispatcher-command
            :message-id "terminal-error-1"
            :idempotency-key "terminal-error-key"))
         (calls 0))
    (register-dispatch-actor
     dispatcher "worker"
     (lambda (runtime envelope)
       (declare (ignore runtime envelope))
       (incf calls)
       (error "terminal synthetic failure")))
    (submit-dispatch-envelope dispatcher command)
    (check (eq :failed (run-dispatcher-next dispatcher))
           "Initial handler failure did not settle terminally.")
    (drain-dispatcher-emitted dispatcher)
    (let ((redelivery
            (redeliver-command
             dispatcher command :message-id "terminal-error-2")))
      (submit-dispatch-envelope dispatcher redelivery)
      (check (eq :duplicate (run-dispatcher-next dispatcher))
             "Terminal handler failure was not replayed on redelivery.")
      (check (= 1 calls)
             "Terminal handler failure redelivery reran the handler.")
      (let ((outcomes (drain-dispatcher-emitted dispatcher)))
        (check (equal '(:error) (emitted-kinds outcomes))
               "Terminal handler failure replay emitted the wrong outcomes.")
        (check (string= "star.native-handler-error"
                        (or (error-envelope-code outcomes) ""))
               "Terminal handler failure replay changed its error code.")))))

(defun run-tests ()
  (test-handler-error-does-not-leave-active-record)
  (test-result-contract-errors-settle-terminally)
  (test-legitimate-defer-remains-active)
  (test-explicit-retryable-failure-remains-retryable)
  (test-terminal-state-is-not-overwritten-by-exception-settlement)
  (test-failed-command-does-not-block-unrelated-queue-work)
  (test-terminal-failure-redelivery-does-not-rerun-handler)
  (format t "~&starlang-runtime wire failure-settlement tests passed~%")
  t)
