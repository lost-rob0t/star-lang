(in-package :staractorprotocol)

(define-condition invalid-wire-envelope-error
    (star-actor-protocol-error)
  ())

(defun fail-invalid-wire-envelope (control &rest arguments)
  (error 'invalid-wire-envelope-error
         :message (apply #'format nil control arguments)))

(defconstant +lifecycle-wire-version+ 1)
(defconstant +ack-message-type+ "star.protocol/ack@1")
(defconstant +error-message-type+ "star.protocol/error@1")
(defconstant +cancel-message-type+ "star.protocol/cancel@1")

(defparameter *lifecycle-kinds*
  '(:command :event :reply :ack :error :cancel))

(defparameter *ack-statuses*
  '(:accepted :completed :rejected :retry))

(defun proper-plist-p (value)
  (loop with rest = value
        do (cond
             ((null rest) (return t))
             ((and (consp rest) (consp (cdr rest)))
              (setf rest (cddr rest)))
             (t (return nil)))))

(defun ensure-lifecycle-plist (value context)
  (unless (proper-plist-p value)
    (fail-invalid-wire-envelope
     "~A must be a property list."
     context))
  value)

(defun lifecycle-plist-has-key-p (plist key)
  (loop for (candidate value) on plist by #'cddr
        do (declare (ignore value))
        when (eq candidate key)
          do (return t)
        finally (return nil)))

(defun lifecycle-required-option (plist key context)
  (unless (lifecycle-plist-has-key-p plist key)
    (fail-invalid-wire-envelope
     "~A requires ~A."
     context key))
  (getf plist key))

(defun lifecycle-required-nonempty-string (value context)
  (unless (and (stringp value) (> (length value) 0))
    (fail-invalid-wire-envelope
     "~A requires a non-empty string."
     context))
  value)

(defun lifecycle-positive-integer (value context)
  (unless (and (integerp value) (> value 0))
    (fail-invalid-wire-envelope
     "~A requires a positive integer."
     context))
  value)

(defun lifecycle-name-string (value)
  (cond
    ((stringp value) value)
    ((symbolp value) (symbol-name value))
    (t nil)))

(defun normalize-lifecycle-kind (value)
  (let* ((name (lifecycle-name-string value))
         (kind (and name
                    (intern (string-upcase name) :keyword))))
    (unless (member kind *lifecycle-kinds* :test #'eq)
      (fail-invalid-wire-envelope
       "Lifecycle kind must be one of ~S."
       *lifecycle-kinds*))
    kind))

(defun normalize-ack-status (value)
  (let* ((name (lifecycle-name-string value))
         (status (and name
                      (intern (string-upcase name) :keyword))))
    (unless (member status *ack-statuses* :test #'eq)
      (fail-invalid-wire-envelope
       "Acknowledgement status must be one of ~S."
       *ack-statuses*))
    status))

(defun lifecycle-base
    (&key kind message-id message-type actor sender
          correlation-id causation-id attempt idempotency-key
          dataset reply-to sent-at deadline payload)
  (list :star-version +lifecycle-wire-version+
        :kind (normalize-lifecycle-kind kind)
        :message-id
        (lifecycle-required-nonempty-string message-id "messageId")
        :message-type
        (lifecycle-required-nonempty-string message-type "message-type")
        :actor
        (lifecycle-required-nonempty-string actor "actor")
        :sender sender
        :correlation-id
        (lifecycle-required-nonempty-string correlation-id "correlationId")
        :causation-id causation-id
        :attempt (lifecycle-positive-integer attempt "attempt")
        :idempotency-key idempotency-key
        :dataset dataset
        :reply-to reply-to
        :sent-at sent-at
        :deadline deadline
        :payload payload))

(defun make-command-envelope
    (&key message-id message-type actor sender payload
          idempotency-key correlation-id causation-id
          dataset reply-to sent-at deadline (attempt 1))
  (lifecycle-base
   :kind :command
   :message-id message-id
   :message-type message-type
   :actor actor
   :sender sender
   :correlation-id (or correlation-id message-id)
   :causation-id causation-id
   :attempt attempt
   :idempotency-key
   (lifecycle-required-nonempty-string
    idempotency-key
    "command idempotency-key")
   :dataset dataset
   :reply-to reply-to
   :sent-at sent-at
   :deadline deadline
   :payload payload))

(defun make-event-envelope
    (&key message-id message-type actor sender payload
          correlation-id causation-id dataset sent-at (attempt 1))
  (lifecycle-base
   :kind :event
   :message-id message-id
   :message-type message-type
   :actor actor
   :sender sender
   :correlation-id (or correlation-id message-id)
   :causation-id causation-id
   :attempt attempt
   :dataset dataset
   :sent-at sent-at
   :payload payload))

(defun lifecycle-message-id (envelope)
  (lifecycle-required-nonempty-string
   (getf envelope :message-id)
   "messageId"))

(defun lifecycle-correlation-id (envelope)
  (lifecycle-required-nonempty-string
   (getf envelope :correlation-id)
   "correlationId"))

(defun lifecycle-causation-id (envelope)
  (getf envelope :causation-id))

(defun source-correlation-id (source)
  (or (getf source :correlation-id)
      (getf source :message-id)))

(defun make-reply-envelope
    (source
     &key message-id message-type actor sender payload
          dataset sent-at deadline)
  (validate-lifecycle-envelope source :validate-payload nil)
  (lifecycle-base
   :kind :reply
   :message-id message-id
   :message-type message-type
   :actor actor
   :sender sender
   :correlation-id (source-correlation-id source)
   :causation-id (getf source :message-id)
   :attempt 1
   :dataset (or dataset (getf source :dataset))
   :sent-at sent-at
   :deadline deadline
   :payload payload))

(defun make-ack-envelope
    (source
     &key message-id actor sender status reason retry-after-ms sent-at)
  (validate-lifecycle-envelope source :validate-payload nil)
  (let ((normalized-status (normalize-ack-status status)))
    (when (eq normalized-status :retry)
      (lifecycle-positive-integer retry-after-ms "retry-after-ms"))
    (when (and retry-after-ms
               (not (eq normalized-status :retry)))
      (fail-invalid-wire-envelope
       "retry-after-ms is valid only for retry acknowledgements."))
    (lifecycle-base
     :kind :ack
     :message-id message-id
     :message-type +ack-message-type+
     :actor actor
     :sender sender
     :correlation-id (source-correlation-id source)
     :causation-id (getf source :message-id)
     :attempt 1
     :dataset (getf source :dataset)
     :sent-at sent-at
     :payload
     (list :status normalized-status
           :for-message-id (getf source :message-id)
           :reason reason
           :retry-after-ms retry-after-ms))))

(defun make-error-envelope
    (source
     &key message-id actor sender code message
          retryable details sent-at)
  (validate-lifecycle-envelope source :validate-payload nil)
  (lifecycle-base
   :kind :error
   :message-id message-id
   :message-type +error-message-type+
   :actor actor
   :sender sender
   :correlation-id (source-correlation-id source)
   :causation-id (getf source :message-id)
   :attempt 1
   :dataset (getf source :dataset)
   :sent-at sent-at
   :payload
   (list :for-message-id (getf source :message-id)
         :code
         (lifecycle-required-nonempty-string code "error code")
         :message
         (lifecycle-required-nonempty-string message "error message")
         :retryable (not (null retryable))
         :details details)))

(defun make-cancel-envelope
    (source
     &key message-id actor sender reason sent-at)
  (validate-lifecycle-envelope source :validate-payload nil)
  (lifecycle-base
   :kind :cancel
   :message-id message-id
   :message-type +cancel-message-type+
   :actor actor
   :sender sender
   :correlation-id (source-correlation-id source)
   :causation-id (getf source :message-id)
   :attempt 1
   :dataset (getf source :dataset)
   :sent-at sent-at
   :payload
   (list :target-message-id (getf source :message-id)
         :target-correlation-id (source-correlation-id source)
         :reason reason)))

(defun validate-referenced-message-id
    (payload-key envelope payload context)
  (let ((reference
          (lifecycle-required-nonempty-string
           (lifecycle-required-option payload payload-key context)
           (format nil "~A ~A" context payload-key))))
    (unless (string= reference (getf envelope :causation-id))
      (fail-invalid-wire-envelope
       "~A ~A must match envelope causationId."
       context payload-key))
    reference))

(defun validate-control-payload (envelope)
  (let ((kind (getf envelope :kind))
        (payload (getf envelope :payload)))
    (ensure-lifecycle-plist payload "lifecycle control payload")
    (ecase kind
      (:ack
       (let ((status
               (normalize-ack-status
                (lifecycle-required-option
                 payload :status "ack payload")))
             (retry-after-ms (getf payload :retry-after-ms)))
         (setf (getf payload :status) status)
         (validate-referenced-message-id
          :for-message-id envelope payload "ack payload")
         (when (eq status :retry)
           (lifecycle-positive-integer
            retry-after-ms
            "ack retry-after-ms"))
         (when (and retry-after-ms
                    (not (eq status :retry)))
           (fail-invalid-wire-envelope
            "Only retry acknowledgements may carry retry-after-ms."))))
      (:error
       (validate-referenced-message-id
        :for-message-id envelope payload "error payload")
       (lifecycle-required-nonempty-string
        (lifecycle-required-option payload :code "error payload")
        "error code")
       (lifecycle-required-nonempty-string
        (lifecycle-required-option payload :message "error payload")
        "error message")
       (unless (lifecycle-plist-has-key-p payload :retryable)
         (fail-invalid-wire-envelope
          "error payload requires explicit retryable boolean."))
       (unless (member (getf payload :retryable) '(t nil) :test #'eq)
         (fail-invalid-wire-envelope
          "error retryable must be boolean.")))
      (:cancel
       (validate-referenced-message-id
        :target-message-id envelope payload "cancel payload")
       (let ((target-correlation-id
               (lifecycle-required-nonempty-string
                (lifecycle-required-option
                 payload :target-correlation-id "cancel payload")
                "cancel target-correlation-id")))
         (unless (string= target-correlation-id
                          (getf envelope :correlation-id))
           (fail-invalid-wire-envelope
            "cancel payload target-correlation-id must match envelope correlationId."))))))
  t)

(defun data-lifecycle-kind-p (kind)
  (member kind '(:command :event :reply) :test #'eq))

(defun validate-lifecycle-envelope
    (envelope &key (validate-payload t) payload-validator)
  (ensure-lifecycle-plist envelope "lifecycle envelope")
  (unless (eql (getf envelope :star-version)
               +lifecycle-wire-version+)
    (fail-invalid-wire-envelope
     "Unsupported lifecycle wire version."))
  (let ((kind (normalize-lifecycle-kind (getf envelope :kind))))
    (setf (getf envelope :kind) kind)
    (lifecycle-required-nonempty-string
     (getf envelope :message-id)
     "messageId")
    (lifecycle-required-nonempty-string
     (getf envelope :message-type)
     "message-type")
    (lifecycle-required-nonempty-string
     (getf envelope :actor)
     "actor")
    (lifecycle-required-nonempty-string
     (getf envelope :correlation-id)
     "correlationId")
    (lifecycle-positive-integer
     (getf envelope :attempt)
     "attempt")
    (when (member kind '(:reply :ack :error :cancel) :test #'eq)
      (lifecycle-required-nonempty-string
       (getf envelope :causation-id)
       "causationId"))
    (when (eq kind :command)
      (lifecycle-required-nonempty-string
       (getf envelope :idempotency-key)
       "command idempotency-key"))
    (when (and (getf envelope :deadline)
               (not (stringp (getf envelope :deadline))))
      (fail-invalid-wire-envelope
       "deadline must be an ISO datetime string."))
    (when validate-payload
      (if (data-lifecycle-kind-p kind)
          (when payload-validator
            (funcall payload-validator envelope))
          (validate-control-payload envelope))))
  t)

(defun delivery-outcome (envelope)
  (case (normalize-lifecycle-kind (getf envelope :kind))
    (:ack
     (case (normalize-ack-status
            (getf (getf envelope :payload) :status))
       (:accepted :accepted)
       (:completed :completed)
       (:rejected :rejected)
       (:retry :retry)))
    (:error
     (if (getf (getf envelope :payload) :retryable)
         :retry
         :failed))
    (:cancel :cancel-requested)
    (otherwise :pending)))

(defun terminal-lifecycle-envelope-p (envelope)
  (not
   (null
    (member (delivery-outcome envelope)
            '(:completed :rejected :failed)
            :test #'eq))))

(defun idempotency-scope-key (envelope)
  (unless (eq (normalize-lifecycle-kind (getf envelope :kind))
              :command)
    (fail-invalid-wire-envelope
     "Idempotency scope keys are defined for command envelopes."))
  (list
   (getf envelope :actor)
   (getf envelope :message-type)
   (lifecycle-required-nonempty-string
    (getf envelope :idempotency-key)
    "command idempotency-key")))

(defun cancel-target-message-id (envelope)
  (unless (eq (normalize-lifecycle-kind (getf envelope :kind))
              :cancel)
    (fail-invalid-wire-envelope
     "Cancellation target identity is defined for cancel envelopes."))
  (lifecycle-required-nonempty-string
   (getf (getf envelope :payload) :target-message-id)
   "cancel target-message-id"))

(defun cancel-target-correlation-id (envelope)
  (unless (eq (normalize-lifecycle-kind (getf envelope :kind))
              :cancel)
    (fail-invalid-wire-envelope
     "Cancellation correlation identity is defined for cancel envelopes."))
  (lifecycle-required-nonempty-string
   (getf (getf envelope :payload) :target-correlation-id)
   "cancel target-correlation-id"))
