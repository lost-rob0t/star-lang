(in-package #:star-lang.core-surface.prototype)

(export '(finish-deferred-dispatch
          deferred-dispatch-status))

(defun deferred-dispatch-status (dispatcher command)
  (call-final-dispatcher
   (lambda ()
     (starlangruntime:deferred-dispatch-status dispatcher command))))

(defun finish-deferred-dispatch (dispatcher command result)
  (call-final-dispatcher
   (lambda ()
     (starlangruntime:finish-deferred-dispatch
      dispatcher command result))))
