(in-package #:star-lang.core-surface.prototype)

(export '(canonical-envelope-json
          canonical-manifest-json
          validate-wire-value))

;; Standalone prototype scripts load this file directly, so resolve final
;; protocol and serializer dependencies before package-qualified calls are read.
(eval-when (:compile-toplevel :load-toplevel :execute)
  (require :asdf))

(eval-when (:compile-toplevel :load-toplevel :execute)
  (unless (find-package "STARACTORPROTOCOL")
    (funcall (find-symbol "LOAD-ASD" "ASDF")
             (merge-pathnames "../star-actor-protocol/star-actor-protocol.asd"
                              *load-truename*))
    (funcall (find-symbol "LOAD-SYSTEM" "ASDF") :star-actor-protocol))
  (unless (find-package "STARCANONICALJSON")
    (funcall (find-symbol "LOAD-ASD" "ASDF")
             (merge-pathnames "../star-canonical-json/star-canonical-json.asd"
                              *load-truename*))
    (funcall (find-symbol "LOAD-SYSTEM" "ASDF") :star-canonical-json)))

;; Compatibility only: representation and serialization are final-owned.
(define-symbol-macro +json-true+ starcanonicaljson:+json-true+)
(define-symbol-macro +json-false+ starcanonicaljson:+json-false+)
(define-symbol-macro +json-null+ starcanonicaljson:+json-null+)

(defun %make-json-object (entries)
  (starcanonicaljson:make-json-object entries))

(defun %make-json-array (values)
  (starcanonicaljson:make-json-array values))

(defun canonical-json-string (value)
  (handler-case
      (starcanonicaljson:canonical-json-string value)
    (starcanonicaljson:invalid-canonical-json-error (condition)
      (fail 'invalid-envelope-error "~A" condition))))

(defun call-final-payload-validation (thunk)
  (handler-case
      (funcall thunk)
    (staractorprotocol:invalid-wire-envelope-error (condition)
      (fail 'invalid-envelope-error "~A" condition))))

(defun json-symbol-value (value)
  (substitute #\- #\_ (string-downcase (symbol-name value))))

(defun json-array-key-p (key)
  (member key
          '(:imports :types :predicates :messages :actors :fields :values
            :accepts :produces :capabilities)
          :test #'eq))

(defun manifest-json-object (plist)
  (let ((entries '()))
    (loop for (key value) on plist by #'cddr
          do (unless (and (null value)
                          (not (eq key :required))
                          (not (json-array-key-p key)))
               (push (cons (staractorprotocol:portable-field-key-string key)
                           (manifest-json-value value key))
                     entries)))
    (%make-json-object entries)))

(defun manifest-json-value (value &optional key)
  (cond
    ((eq key :required) (if value +json-true+ +json-false+))
    ((json-array-key-p key)
     (%make-json-array
      (mapcar (lambda (item) (manifest-json-value item)) (or value '()))))
    ((eq value t) +json-true+)
    ((null value) +json-null+)
    ((stringp value) value)
    ((integerp value) value)
    ((keywordp value) (json-symbol-value value))
    ((symbolp value) (identifier-string value))
    ((staractorprotocol:portable-keyword-plist-p value)
     (manifest-json-object value))
    ((staractorprotocol:portable-string-alist-p value)
     (%make-json-object
      (mapcar (lambda (entry)
                (cons (car entry) (manifest-json-value (cdr entry))))
              value)))
    ((listp value) (%make-json-array (mapcar #'manifest-json-value value)))
    (t
     (fail 'invalid-envelope-error
           "Cannot convert ~S to canonical JSON." value))))

(defun canonical-manifest-json (manifest)
  (canonical-json-string (manifest-json-object manifest)))

(defun manifest-type-contract (manifest qualified-name)
  (staractorprotocol:portable-manifest-type-contract manifest qualified-name))

(defun payload-entry (payload field-name)
  (staractorprotocol:portable-payload-entry payload field-name))

(defun generic-wire-json-value (value)
  (cond
    ((eq value t) +json-true+)
    ((null value) +json-null+)
    ((stringp value) value)
    ((integerp value) value)
    ((symbolp value)
     (staractorprotocol:portable-wire-identifier-string value))
    ((staractorprotocol:portable-string-alist-p value)
     (%make-json-object
      (mapcar (lambda (entry)
                (cons (car entry) (generic-wire-json-value (cdr entry))))
              value)))
    ((listp value) (%make-json-array (mapcar #'generic-wire-json-value value)))
    (t
     (fail 'invalid-envelope-error "Unsupported wire value ~S." value))))

(defun wire-map-value (value context)
  (declare (ignore context))
  (cond
    ((null value) (%make-json-object '()))
    ((staractorprotocol:portable-string-alist-p value)
     (%make-json-object
      (mapcar (lambda (entry)
                (cons (car entry) (generic-wire-json-value (cdr entry))))
              value)))
    ((staractorprotocol:portable-keyword-plist-p value)
     (manifest-json-object value))
    (t
     (error "Validated wire map reached an unsupported encoder shape: ~S."
            value))))

(defun wire-reference-value (value context)
  (wire-map-value value context))

(defun wire-enum-value (value)
  (if (stringp value)
      value
      (staractorprotocol:portable-wire-identifier-string value)))

(defun manifest-document-fields (manifest contract)
  (call-final-payload-validation
   (lambda ()
     (staractorprotocol:portable-manifest-document-fields
      manifest contract))))

(defun wire-fields-object (manifest fields value context)
  (call-final-payload-validation
   (lambda ()
     (staractorprotocol:validate-portable-wire-fields
      manifest fields value context)))
  (let ((entries '()))
    (dolist (field fields)
      (let* ((name (getf field :name))
             (entry (payload-entry value name)))
        (when entry
          (push
           (cons name
                 (wire-json-value-for-type
                  manifest
                  (getf field :type)
                  (cdr entry)
                  (format nil "~A field ~A" context name)))
           entries))))
    (%make-json-object entries)))

(defun wire-json-value-for-type (manifest type value context)
  (call-final-payload-validation
   (lambda ()
     (staractorprotocol:validate-portable-wire-value
      manifest type value context)))
  (cond
    ((and (listp type) (eq (first type) :list) (= (length type) 2))
     (%make-json-array
      (mapcar (lambda (item)
                (wire-json-value-for-type manifest (second type) item context))
              value)))
    ((and (listp type) (eq (first type) :optional) (= (length type) 2))
     (if (null value)
         +json-null+
         (wire-json-value-for-type manifest (second type) value context)))
    ((string= type "any") (generic-wire-json-value value))
    ((member type '("string" "symbol" "iso-date" "iso-datetime") :test #'string=)
     (if (symbolp value)
         (staractorprotocol:portable-wire-identifier-string value)
         value))
    ((string= type "integer") value)
    ((string= type "boolean") (if value +json-true+ +json-false+))
    ((string= type "decimal") value)
    ((string= type "map") (wire-map-value value context))
    ((string= type "reference") (wire-reference-value value context))
    (t
     (let ((contract (manifest-type-contract manifest type)))
       (case (getf contract :kind)
         (:scalar
          (wire-json-value-for-type
           manifest (getf contract :base) value context))
         (:enum
          (wire-enum-value value))
         (:document
          (wire-fields-object
           manifest (manifest-document-fields manifest contract) value context))
         (otherwise
          (error "Validated wire type reached an unsupported encoder kind: ~S."
                 (getf contract :kind))))))))

(defun validate-wire-value (manifest type value &optional (context "wire value"))
  (call-final-payload-validation
   (lambda ()
     (staractorprotocol:validate-portable-wire-value
      manifest type value context)))
  t)

(defun envelope-json-object (manifest envelope)
  (call-final-payload-validation
   (lambda ()
     (staractorprotocol:validate-wire-envelope manifest envelope)))
  (let* ((message-type (getf envelope :message-type))
         (contract
           (staractorprotocol:portable-manifest-message-contract
            manifest message-type)))
    (let ((entries
            (list (cons "starVersion" 1)
                  (cons "messageType" message-type)
                  (cons "messageId" (getf envelope :message-id))
                  (cons "actor" (getf envelope :actor))
                  (cons "payload"
                        (wire-fields-object
                         manifest (getf contract :fields) (getf envelope :payload)
                         (format nil "Message ~A" message-type))))))
      (when (getf envelope :dataset)
        (push (cons "dataset" (getf envelope :dataset)) entries))
      (when (getf envelope :reply-to)
        (push (cons "replyTo" (getf envelope :reply-to)) entries))
      (%make-json-object entries))))

(defun canonical-envelope-json (manifest envelope)
  (canonical-json-string (envelope-json-object manifest envelope)))
