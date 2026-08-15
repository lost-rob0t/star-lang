(in-package #:star-lang.core-surface.prototype)

(export '(command-idempotency-identity
          dispatcher-idempotency-conflict-error))

(defun command-idempotency-identity (command)
  (starlangruntime:command-idempotency-identity command))
