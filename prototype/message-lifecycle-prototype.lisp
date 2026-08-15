(in-package #:star-lang.core-surface.prototype)

(export '(canonical-lifecycle-envelope-json
          delivery-outcome
          idempotency-scope-key
          make-ack-envelope
          make-cancel-envelope
          make-command-envelope
          make-error-envelope
          make-event-envelope
          make-reply-envelope
          terminal-lifecycle-envelope-p
          validate-lifecycle-envelope))

(eval-when (:compile-toplevel :load-toplevel :execute)
  (require :asdf))

(eval-when (:compile-toplevel :load-toplevel :execute)
  (unless (find-package "STARACTORPROTOCOL")
    (funcall
     (find-symbol "LOAD-ASD" "ASDF")
     (merge-pathnames
      "../star-actor-protocol/star-actor-protocol.asd"
      *load-truename*))
    (funcall (find-symbol "LOAD-SYSTEM" "ASDF") :star-actor-protocol))
  (unless (find-package "STARCANONICALJSON")
    (funcall
     (find-symbol "LOAD-ASD" "ASDF")
     (merge-pathnames
      "../star-canonical-json/star-canonical-json.asd"
      *load-truename*))
    (funcall (find-symbol "LOAD-SYSTEM" "ASDF") :star-canonical-json)))

;; These generic helpers predate the lifecycle split and remain in use by
;; unrelated prototype remoting code. They are not lifecycle implementations.
(defun required-nonempty-string (value context)
  (unless (and (stringp value) (> (length value) 0))
    (fail 'invalid-envelope-error
          "~A requires a non-empty string."
          context))
  value)

(defun positive-integer (value context)
  (unless (and (integerp value) (> value 0))
    (fail 'invalid-envelope-error
          "~A requires a positive integer."
          context))
  value)

(defun call-final-lifecycle (thunk)
  (handler-case
      (funcall thunk)
    (staractorprotocol:invalid-wire-envelope-error (condition)
      (fail 'invalid-envelope-error "~A" condition))))

(defun make-command-envelope (&rest arguments)
  (call-final-lifecycle
   (lambda ()
     (apply #'staractorprotocol:make-command-envelope arguments))))

(defun make-event-envelope (&rest arguments)
  (call-final-lifecycle
   (lambda ()
     (apply #'staractorprotocol:make-event-envelope arguments))))

(defun make-reply-envelope (source &rest arguments)
  (call-final-lifecycle
   (lambda ()
     (apply #'staractorprotocol:make-reply-envelope source arguments))))

(defun make-ack-envelope (source &rest arguments)
  (call-final-lifecycle
   (lambda ()
     (apply #'staractorprotocol:make-ack-envelope source arguments))))

(defun make-error-envelope (source &rest arguments)
  (call-final-lifecycle
   (lambda ()
     (apply #'staractorprotocol:make-error-envelope source arguments))))

(defun make-cancel-envelope (source &rest arguments)
  (call-final-lifecycle
   (lambda ()
     (apply #'staractorprotocol:make-cancel-envelope source arguments))))

(defun validate-lifecycle-envelope
    (manifest envelope &key (validate-payload t))
  (call-final-lifecycle
   (lambda ()
     (staractorprotocol:validate-lifecycle-envelope-against-manifest
      manifest envelope :validate-payload validate-payload)))
  t)

(defun canonical-lifecycle-envelope-json (manifest envelope)
  (handler-case
      (starcanonicaljson:canonical-lifecycle-envelope-json
       manifest envelope)
    (staractorprotocol:invalid-wire-envelope-error (condition)
      (fail 'invalid-envelope-error "~A" condition))
    (starcanonicaljson:invalid-canonical-json-error (condition)
      (fail 'invalid-envelope-error "~A" condition))))

(defun delivery-outcome (envelope)
  (call-final-lifecycle
   (lambda ()
     (staractorprotocol:delivery-outcome envelope))))

(defun terminal-lifecycle-envelope-p (envelope)
  (call-final-lifecycle
   (lambda ()
     (staractorprotocol:terminal-lifecycle-envelope-p envelope))))

(defun idempotency-scope-key (envelope)
  (call-final-lifecycle
   (lambda ()
     (staractorprotocol:idempotency-scope-key envelope))))
