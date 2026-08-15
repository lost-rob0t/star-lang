(in-package #:star-lang.core-surface.prototype)

(export '(advance-dispatcher-clock
          complete-dispatch
          defer-dispatch
          deterministic-dispatcher-emitted
          deterministic-dispatcher-handler-count
          deterministic-dispatcher-now
          deterministic-dispatcher-queue
          drain-dispatcher-emitted
          fail-dispatch
          make-deterministic-dispatcher
          redeliver-command
          register-dispatch-actor
          retry-dispatch
          run-dispatcher
          run-dispatcher-next
          submit-dispatch-envelope))

(eval-when (:compile-toplevel :load-toplevel :execute)
  (require :asdf))

(eval-when (:compile-toplevel :load-toplevel :execute)
  (unless (find-package "STARLANGRUNTIME")
    (funcall
     (find-symbol "LOAD-ASD" "ASDF")
     (merge-pathnames
      "../starlang-runtime/starlang-runtime.asd"
      *load-truename*))
    (funcall (find-symbol "LOAD-SYSTEM" "ASDF") :starlang-runtime)))

;; Compatibility condition retained for prototype callers.  The semantic
;; idempotency check itself is final-owned by starlang-runtime.
(define-condition dispatcher-idempotency-conflict-error
    (invalid-envelope-error) ())

(defun call-final-dispatcher (thunk)
  (handler-case
      (funcall thunk)
    (starlangruntime:wire-dispatcher-idempotency-conflict-error (condition)
      (fail 'dispatcher-idempotency-conflict-error "~A" condition))
    (starlangruntime:wire-dispatcher-invalid-actor-error (condition)
      (fail 'invalid-actor-error "~A" condition))
    (starlangruntime:wire-dispatcher-error (condition)
      (fail 'invalid-envelope-error "~A" condition))))

(deftype deterministic-dispatcher ()
  'starlangruntime:deterministic-dispatcher)

(defun deterministic-dispatcher-p (value)
  (starlangruntime:deterministic-dispatcher-p value))

(defun deterministic-dispatcher-manifest (dispatcher)
  (starlangruntime:deterministic-dispatcher-manifest dispatcher))

(defun deterministic-dispatcher-queue (dispatcher)
  (starlangruntime:deterministic-dispatcher-queue dispatcher))

(defun (setf deterministic-dispatcher-queue) (value dispatcher)
  (setf (starlangruntime:deterministic-dispatcher-queue dispatcher) value))

(defun deterministic-dispatcher-emitted (dispatcher)
  (starlangruntime:deterministic-dispatcher-emitted dispatcher))

(defun (setf deterministic-dispatcher-emitted) (value dispatcher)
  (setf (starlangruntime:deterministic-dispatcher-emitted dispatcher) value))

(defun deterministic-dispatcher-idempotency (dispatcher)
  (starlangruntime:deterministic-dispatcher-idempotency dispatcher))

(defun (setf deterministic-dispatcher-idempotency) (value dispatcher)
  (setf (starlangruntime:deterministic-dispatcher-idempotency dispatcher) value))

(defun deterministic-dispatcher-handler-count (dispatcher)
  (starlangruntime:deterministic-dispatcher-handler-count dispatcher))

(defun (setf deterministic-dispatcher-handler-count) (value dispatcher)
  (setf (starlangruntime:deterministic-dispatcher-handler-count dispatcher) value))

(defun deterministic-dispatcher-sequence (dispatcher)
  (starlangruntime:deterministic-dispatcher-sequence dispatcher))

(defun (setf deterministic-dispatcher-sequence) (value dispatcher)
  (setf (starlangruntime:deterministic-dispatcher-sequence dispatcher) value))

(defun deterministic-dispatcher-now (dispatcher)
  (starlangruntime:deterministic-dispatcher-now dispatcher))

(defun (setf deterministic-dispatcher-now) (value dispatcher)
  (setf (starlangruntime:deterministic-dispatcher-now dispatcher) value))

(defun make-deterministic-dispatcher (manifest &key
                                               (now "1970-01-01T00:00:00Z"))
  (call-final-dispatcher
   (lambda ()
     (starlangruntime:make-deterministic-dispatcher manifest :now now))))

(defun advance-dispatcher-clock (dispatcher now)
  (call-final-dispatcher
   (lambda ()
     (starlangruntime:advance-dispatcher-clock dispatcher now))))

(defun dispatcher-next-message-id (dispatcher prefix)
  (call-final-dispatcher
   (lambda ()
     (starlangruntime:dispatcher-next-message-id dispatcher prefix))))

(defun register-dispatch-actor (dispatcher actor-name handler)
  (call-final-dispatcher
   (lambda ()
     (starlangruntime:register-dispatch-actor
      dispatcher actor-name handler))))

(defun complete-dispatch (&key message-type payload)
  (starlangruntime:complete-dispatch
   :message-type message-type
   :payload payload))

(defun retry-dispatch (&key retry-after-ms reason)
  (call-final-dispatcher
   (lambda ()
     (starlangruntime:retry-dispatch
      :retry-after-ms retry-after-ms
      :reason reason))))

(defun fail-dispatch (&key code message retryable details)
  (call-final-dispatcher
   (lambda ()
     (starlangruntime:fail-dispatch
      :code code
      :message message
      :retryable retryable
      :details details))))

(defun defer-dispatch ()
  (starlangruntime:defer-dispatch))

(defun dispatcher-emit (dispatcher envelope)
  (call-final-dispatcher
   (lambda ()
     (starlangruntime:dispatcher-emit dispatcher envelope))))

(defun drain-dispatcher-emitted (dispatcher)
  (call-final-dispatcher
   (lambda ()
     (starlangruntime:drain-dispatcher-emitted dispatcher))))

(defun command-idempotency-record (dispatcher command)
  (starlangruntime:command-idempotency-record dispatcher command))

(defun set-command-idempotency-record (dispatcher command record)
  (starlangruntime:set-command-idempotency-record
   dispatcher command record))

(defun process-command (dispatcher command)
  (call-final-dispatcher
   (lambda ()
     (starlangruntime:process-command dispatcher command))))

(defun submit-dispatch-envelope (dispatcher envelope)
  (call-final-dispatcher
   (lambda ()
     (starlangruntime:submit-dispatch-envelope dispatcher envelope))))

(defun run-dispatcher-next (dispatcher)
  (call-final-dispatcher
   (lambda ()
     (starlangruntime:run-dispatcher-next dispatcher))))

(defun run-dispatcher (dispatcher)
  (call-final-dispatcher
   (lambda ()
     (starlangruntime:run-dispatcher dispatcher))))

(defun redeliver-command (dispatcher command &key message-id)
  (call-final-dispatcher
   (lambda ()
     (starlangruntime:redeliver-command
      dispatcher command :message-id message-id))))
