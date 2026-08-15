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

;; Standalone prototype scripts historically load this file directly.
;; Load the final owner before the reader reaches package-qualified calls below.
(eval-when (:compile-toplevel :load-toplevel :execute)
  (require :asdf))

(eval-when (:compile-toplevel :load-toplevel :execute)
  (unless (find-package "STARACTORPROTOCOL")
    (funcall
     (find-symbol "LOAD-ASD" "ASDF")
     (merge-pathnames
      "../star-actor-protocol/star-actor-protocol.asd"
      *load-truename*))
    (funcall
     (find-symbol "LOAD-SYSTEM" "ASDF")
     :star-actor-protocol)))

;; These two generic helpers predate the lifecycle split and are still used by
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
      manifest
      envelope
      :validate-payload validate-payload)))
  t)

(defun lifecycle-common-json-entries (envelope)
  (let ((entries
          (list
           (cons "starVersion" staractorprotocol:+lifecycle-wire-version+)
           (cons "kind" (identifier-string (getf envelope :kind)))
           (cons "messageId" (getf envelope :message-id))
           (cons "messageType" (getf envelope :message-type))
           (cons "actor" (getf envelope :actor))
           (cons "correlationId" (getf envelope :correlation-id))
           (cons "attempt" (getf envelope :attempt)))))
    (dolist (mapping
             '((:sender . "sender")
               (:causation-id . "causationId")
               (:idempotency-key . "idempotencyKey")
               (:dataset . "dataset")
               (:reply-to . "replyTo")
               (:sent-at . "sentAt")
               (:deadline . "deadline")))
      (let ((value (getf envelope (car mapping))))
        (when value
          (push (cons (cdr mapping) value) entries))))
    entries))

(defun control-payload-json (envelope)
  (let ((payload (getf envelope :payload)))
    (ecase (getf envelope :kind)
      (:ack
       (%make-json-object
        (remove nil
                (list
                 (cons "status"
                       (identifier-string (getf payload :status)))
                 (cons "forMessageId"
                       (getf payload :for-message-id))
                 (and (getf payload :reason)
                      (cons "reason" (getf payload :reason)))
                 (and (getf payload :retry-after-ms)
                      (cons "retryAfterMs"
                            (getf payload :retry-after-ms)))))))
      (:error
       (%make-json-object
        (remove nil
                (list
                 (cons "forMessageId"
                       (getf payload :for-message-id))
                 (cons "code" (getf payload :code))
                 (cons "message" (getf payload :message))
                 (cons "retryable"
                       (if (getf payload :retryable)
                           +json-true+
                           +json-false+))
                 (and (getf payload :details)
                      (cons
                       "details"
                       (generic-wire-json-value
                        (getf payload :details))))))))
      (:cancel
       (%make-json-object
        (remove nil
                (list
                 (cons "targetMessageId"
                       (getf payload :target-message-id))
                 (cons "targetCorrelationId"
                       (getf payload :target-correlation-id))
                 (and (getf payload :reason)
                      (cons "reason" (getf payload :reason))))))))))

(defun canonical-lifecycle-envelope-json (manifest envelope)
  (validate-lifecycle-envelope manifest envelope)
  (let* ((kind (getf envelope :kind))
         (payload-json
           (if (member kind '(:command :event :reply) :test #'eq)
               (let ((contract
                       (message-contract
                        manifest
                        (getf envelope :message-type))))
                 (wire-fields-object
                  manifest
                  (getf contract :fields)
                  (getf envelope :payload)
                  (format nil
                          "Message ~A"
                          (getf envelope :message-type))))
               (control-payload-json envelope)))
         (entries (lifecycle-common-json-entries envelope)))
    (push (cons "payload" payload-json) entries)
    (canonical-json-string (%make-json-object entries))))

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
