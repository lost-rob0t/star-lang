(in-package :starcanonicaljson)

(defun starlang-json-symbol-value (value)
  (substitute #\- #\_ (string-downcase (symbol-name value))))

(defun starlang-json-array-key-p (key)
  (member key
          '(:imports :types :predicates :messages :actors :fields :values
            :accepts :produces :capabilities)
          :test #'eq))

(defun starlang-manifest-json-object (plist)
  (let ((entries '()))
    (loop for (key value) on plist by #'cddr
          do (unless (and (null value)
                          (not (eq key :required))
                          (not (starlang-json-array-key-p key)))
               (push
                (cons
                 (staractorprotocol:portable-field-key-string key)
                 (starlang-manifest-json-value value key))
                entries)))
    (make-json-object entries)))

(defun starlang-manifest-json-value (value &optional key)
  (cond
    ((eq key :required)
     (if value +json-true+ +json-false+))
    ((starlang-json-array-key-p key)
     (make-json-array
      (mapcar
       (lambda (item)
         (starlang-manifest-json-value item))
       (or value '()))))
    ((eq value t) +json-true+)
    ((null value) +json-null+)
    ((stringp value) value)
    ((integerp value) value)
    ((keywordp value) (starlang-json-symbol-value value))
    ((symbolp value)
     (staractorprotocol:portable-wire-identifier-string value))
    ((staractorprotocol:portable-keyword-plist-p value)
     (starlang-manifest-json-object value))
    ((staractorprotocol:portable-string-alist-p value)
     (make-json-object
      (mapcar
       (lambda (entry)
         (cons (car entry)
               (starlang-manifest-json-value (cdr entry))))
       value)))
    ((listp value)
     (make-json-array
      (mapcar #'starlang-manifest-json-value value)))
    (t
     (fail-canonical-json
      "Cannot convert ~S to canonical JSON."
      value))))

(defun canonical-manifest-json (manifest)
  (canonical-json-string
   (starlang-manifest-json-object manifest)))

(defun starlang-generic-wire-json-value (value)
  (cond
    ((eq value t) +json-true+)
    ((null value) +json-null+)
    ((stringp value) value)
    ((integerp value) value)
    ((symbolp value)
     (staractorprotocol:portable-wire-identifier-string value))
    ((staractorprotocol:portable-string-alist-p value)
     (make-json-object
      (mapcar
       (lambda (entry)
         (cons (car entry)
               (starlang-generic-wire-json-value (cdr entry))))
       value)))
    ((listp value)
     (make-json-array
      (mapcar #'starlang-generic-wire-json-value value)))
    (t
     (fail-canonical-json
      "Unsupported wire value ~S."
      value))))

(defun starlang-wire-map-json-value (value)
  (cond
    ((null value)
     (make-json-object '()))
    ((staractorprotocol:portable-string-alist-p value)
     (make-json-object
      (mapcar
       (lambda (entry)
         (cons (car entry)
               (starlang-generic-wire-json-value (cdr entry))))
       value)))
    ((staractorprotocol:portable-keyword-plist-p value)
     (starlang-manifest-json-object value))
    (t
     (fail-canonical-json
      "Validated wire map reached an unsupported encoder shape: ~S."
      value))))

(defun starlang-wire-fields-json-object (manifest fields value context)
  (staractorprotocol:validate-portable-wire-fields
   manifest fields value context)
  (let ((entries '()))
    (dolist (field fields)
      (let* ((name (getf field :name))
             (entry
               (staractorprotocol:portable-payload-entry value name)))
        (when entry
          (push
           (cons
            name
            (starlang-wire-json-value-for-type
             manifest
             (getf field :type)
             (cdr entry)
             (format nil "~A field ~A" context name)))
           entries))))
    (make-json-object entries)))

(defun starlang-wire-json-value-for-type (manifest type value context)
  (staractorprotocol:validate-portable-wire-value
   manifest type value context)
  (cond
    ((and (listp type)
          (eq (first type) :list)
          (= (length type) 2))
     (make-json-array
      (mapcar
       (lambda (item)
         (starlang-wire-json-value-for-type
          manifest (second type) item context))
       value)))
    ((and (listp type)
          (eq (first type) :optional)
          (= (length type) 2))
     (if (null value)
         +json-null+
         (starlang-wire-json-value-for-type
          manifest (second type) value context)))
    ((string= type "any")
     (starlang-generic-wire-json-value value))
    ((member type
             '("string" "symbol" "iso-date" "iso-datetime")
             :test #'string=)
     (if (symbolp value)
         (staractorprotocol:portable-wire-identifier-string value)
         value))
    ((string= type "integer") value)
    ((string= type "boolean")
     (if value +json-true+ +json-false+))
    ((string= type "decimal") value)
    ((string= type "map")
     (starlang-wire-map-json-value value))
    ((string= type "reference")
     (starlang-wire-map-json-value value))
    (t
     (let ((contract
             (staractorprotocol:portable-manifest-type-contract
              manifest type)))
       (case (getf contract :kind)
         (:scalar
          (starlang-wire-json-value-for-type
           manifest (getf contract :base) value context))
         (:enum
          (if (stringp value)
              value
              (staractorprotocol:portable-wire-identifier-string value)))
         (:document
          (starlang-wire-fields-json-object
           manifest
           (staractorprotocol:portable-manifest-document-fields
            manifest contract)
           value
           context))
         (otherwise
          (fail-canonical-json
           "Validated wire type reached an unsupported encoder kind: ~S."
           (getf contract :kind))))))))

(defun canonical-envelope-json (manifest envelope)
  (staractorprotocol:validate-wire-envelope manifest envelope)
  (let* ((message-type (getf envelope :message-type))
         (contract
           (staractorprotocol:portable-manifest-message-contract
            manifest message-type))
         (entries
           (list
            (cons "starVersion" 1)
            (cons "messageType" message-type)
            (cons "messageId" (getf envelope :message-id))
            (cons "actor" (getf envelope :actor))
            (cons
             "payload"
             (starlang-wire-fields-json-object
              manifest
              (getf contract :fields)
              (getf envelope :payload)
              (format nil "Message ~A" message-type))))))
    (when (getf envelope :dataset)
      (push (cons "dataset" (getf envelope :dataset)) entries))
    (when (getf envelope :reply-to)
      (push (cons "replyTo" (getf envelope :reply-to)) entries))
    (canonical-json-string (make-json-object entries))))

(defun lifecycle-common-json-entries (envelope)
  (let ((entries
          (list
           (cons "starVersion" staractorprotocol:+lifecycle-wire-version+)
           (cons "kind"
                 (staractorprotocol:portable-wire-identifier-string
                  (getf envelope :kind)))
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

(defun lifecycle-control-payload-json (envelope)
  (let ((payload (getf envelope :payload)))
    (ecase (getf envelope :kind)
      (:ack
       (make-json-object
        (remove
         nil
         (list
          (cons
           "status"
           (staractorprotocol:portable-wire-identifier-string
            (getf payload :status)))
          (cons "forMessageId" (getf payload :for-message-id))
          (and (getf payload :reason)
               (cons "reason" (getf payload :reason)))
          (and (getf payload :retry-after-ms)
               (cons "retryAfterMs" (getf payload :retry-after-ms)))))))
      (:error
       (make-json-object
        (remove
         nil
         (list
          (cons "forMessageId" (getf payload :for-message-id))
          (cons "code" (getf payload :code))
          (cons "message" (getf payload :message))
          (cons
           "retryable"
           (if (getf payload :retryable)
               +json-true+
               +json-false+))
          (and (getf payload :details)
               (cons
                "details"
                (starlang-generic-wire-json-value
                 (getf payload :details))))))))
      (:cancel
       (make-json-object
        (remove
         nil
         (list
          (cons "targetMessageId" (getf payload :target-message-id))
          (cons
           "targetCorrelationId"
           (getf payload :target-correlation-id))
          (and (getf payload :reason)
               (cons "reason" (getf payload :reason))))))))))

(defun canonical-lifecycle-envelope-json (manifest envelope)
  (staractorprotocol:validate-lifecycle-envelope-against-manifest
   manifest envelope)
  (let* ((kind (getf envelope :kind))
         (payload-json
           (if (member kind '(:command :event :reply) :test #'eq)
               (let ((contract
                       (staractorprotocol:portable-manifest-message-contract
                        manifest
                        (getf envelope :message-type))))
                 (starlang-wire-fields-json-object
                  manifest
                  (getf contract :fields)
                  (getf envelope :payload)
                  (format nil
                          "Message ~A"
                          (getf envelope :message-type))))
               (lifecycle-control-payload-json envelope)))
         (entries (lifecycle-common-json-entries envelope)))
    (push (cons "payload" payload-json) entries)
    (canonical-json-string (make-json-object entries))))
