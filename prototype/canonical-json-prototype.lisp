(in-package #:star-lang.core-surface.prototype)

(export '(canonical-envelope-json
          canonical-manifest-json
          validate-wire-value))

;; Standalone prototype scripts historically load this file directly. Load the
;; final serializer before the reader reaches package-qualified calls below.
(eval-when (:compile-toplevel :load-toplevel :execute)
  (require :asdf))

(eval-when (:compile-toplevel :load-toplevel :execute)
  (unless (find-package "STARCANONICALJSON")
    (funcall
     (find-symbol "LOAD-ASD" "ASDF")
     (merge-pathnames
      "../star-canonical-json/star-canonical-json.asd"
      *load-truename*))
    (funcall
     (find-symbol "LOAD-SYSTEM" "ASDF")
     :star-canonical-json)))

;; Compatibility aliases only. JSON node representation, sentinels, escaping,
;; key ordering, and serialization are authoritative in star-canonical-json.
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

(defun keyword-plist-p (value)
  (and (listp value)
       (evenp (length value))
       (loop for tail on value by #'cddr
             always (keywordp (first tail)))))

(defun string-alist-p (value)
  (and (listp value)
       value
       (every (lambda (entry)
                (and (consp entry) (stringp (car entry))))
              value)))

(defun json-key-name (key)
  (let ((name (string-downcase
               (etypecase key
                 (keyword (symbol-name key))
                 (symbol (symbol-name key))
                 (string key)))))
    (with-output-to-string (stream)
      (loop with uppercase-next = nil
            for character across name
            do (cond
                 ((or (char= character #\-) (char= character #\_))
                  (setf uppercase-next t))
                 (uppercase-next
                  (write-char (char-upcase character) stream)
                  (setf uppercase-next nil))
                 (t
                  (write-char character stream)))))))

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
               (push (cons (json-key-name key)
                           (manifest-json-value value key))
                     entries)))
    (%make-json-object entries)))

(defun manifest-json-value (value &optional key)
  (cond
    ((eq key :required)
     (if value +json-true+ +json-false+))
    ((json-array-key-p key)
     (%make-json-array
      (mapcar (lambda (item)
                (manifest-json-value item))
              (or value '()))))
    ((eq value t)
     +json-true+)
    ((null value)
     +json-null+)
    ((stringp value)
     value)
    ((integerp value)
     value)
    ((keywordp value)
     (json-symbol-value value))
    ((symbolp value)
     (identifier-string value))
    ((keyword-plist-p value)
     (manifest-json-object value))
    ((string-alist-p value)
     (%make-json-object
      (mapcar (lambda (entry)
                (cons (car entry)
                      (manifest-json-value (cdr entry))))
              value)))
    ((listp value)
     (%make-json-array
      (mapcar #'manifest-json-value value)))
    (t
     (fail 'invalid-envelope-error
           "Cannot convert ~S to canonical JSON."
           value))))

(defun canonical-manifest-json (manifest)
  (canonical-json-string (manifest-json-object manifest)))

(defun manifest-type-contract (manifest qualified-name)
  (find qualified-name (getf manifest :types)
        :key (lambda (contract) (getf contract :name))
        :test #'string=))

(defun payload-entry (payload field-name)
  (cond
    ((string-alist-p payload)
     (assoc field-name payload :test #'string=))
    ((keyword-plist-p payload)
     (loop for (key value) on payload by #'cddr
           when (string= (field-key-string key) field-name)
             return (cons field-name value)))
    (t nil)))

(defun payload-field-names (payload)
  (cond
    ((string-alist-p payload)
     (mapcar #'car payload))
    ((keyword-plist-p payload)
     (loop for tail on payload by #'cddr
           collect (field-key-string (first tail))))
    ((null payload)
     '())
    (t nil)))

(defun generic-wire-json-value (value)
  (cond
    ((eq value t)
     +json-true+)
    ((null value)
     +json-null+)
    ((stringp value)
     value)
    ((integerp value)
     value)
    ((symbolp value)
     (identifier-string value))
    ((string-alist-p value)
     (%make-json-object
      (mapcar (lambda (entry)
                (cons (car entry)
                      (generic-wire-json-value (cdr entry))))
              value)))
    ((listp value)
     (%make-json-array
      (mapcar #'generic-wire-json-value value)))
    (t
     (fail 'invalid-envelope-error
           "Unsupported wire value ~S."
           value))))

(defun wire-map-value (value context)
  (cond
    ((null value)
     (%make-json-object '()))
    ((string-alist-p value)
     (%make-json-object
      (mapcar (lambda (entry)
                (cons (car entry)
                      (generic-wire-json-value (cdr entry))))
              value)))
    ((keyword-plist-p value)
     (manifest-json-object value))
    (t
     (fail 'invalid-envelope-error
           "~A requires an object/map value."
           context))))

(defun wire-reference-value (value context)
  (let ((schema (payload-entry value "schema"))
        (id (payload-entry value "id")))
    (unless (and schema
                 (stringp (cdr schema))
                 id
                 (stringp (cdr id)))
      (fail 'invalid-envelope-error
            "~A requires reference fields schema and id as strings."
            context))
    (wire-map-value value context)))

(defun wire-enum-value (contract value context)
  (let ((normalized
          (cond
            ((stringp value)
             value)
            ((symbolp value)
             (identifier-string value))
            (t nil))))
    (unless (and normalized
                 (member normalized
                         (getf contract :values)
                         :test #'string=))
      (fail 'invalid-envelope-error
            "~A requires one of ~S, received ~S."
            context
            (getf contract :values)
            value))
    normalized))

(defun manifest-document-fields (manifest contract)
  (let ((parent-name (getf contract :extends)))
    (append
     (when parent-name
       (let ((parent (manifest-type-contract manifest parent-name)))
         (unless (and parent
                      (eq (getf parent :kind) :document))
           (fail 'invalid-envelope-error
                 "Cannot resolve document parent ~A while validating wire data."
                 parent-name))
         (manifest-document-fields manifest parent)))
     (copy-tree (getf contract :fields)))))

(defun decimal-wire-string-p (value)
  (and (stringp value)
       (> (length value) 0)
       (let* ((start
                (if (member (char value 0) '(#\+ #\-))
                    1
                    0))
              (dot (position #\. value :start start)))
         (and (< start (length value))
              (or (null dot)
                  (> dot start))
              (every #'digit-char-p
                     (if dot
                         (subseq value start dot)
                         (subseq value start)))
              (or (null dot)
                  (and (< dot (1- (length value)))
                       (every #'digit-char-p
                              (subseq value (1+ dot)))))))))

(defun decimal-fraction-digits (value)
  (let ((dot (position #\. value)))
    (if dot
        (- (length value) dot 1)
        0)))

(defun validate-scalar-constraints (contract value context)
  (let ((minimum (getf contract :minimum))
        (maximum (getf contract :maximum))
        (scale (getf contract :scale)))
    (when (and minimum
               (numberp value)
               (< value minimum))
      (fail 'invalid-envelope-error
            "~A is below scalar minimum ~A."
            context
            minimum))
    (when (and maximum
               (numberp value)
               (> value maximum))
      (fail 'invalid-envelope-error
            "~A exceeds scalar maximum ~A."
            context
            maximum))
    (when scale
      (unless (and (decimal-wire-string-p value)
                   (<= (decimal-fraction-digits value) scale))
        (fail 'invalid-envelope-error
              "~A requires a decimal string with at most ~D fractional digits."
              context
              scale))))
  value)

(defun wire-fields-object (manifest fields value context)
  (unless (or (string-alist-p value)
              (keyword-plist-p value)
              (null value))
    (fail 'invalid-envelope-error
          "~A requires an object payload."
          context))
  (let ((known (mapcar (lambda (field)
                         (getf field :name))
                       fields))
        (entries '()))
    (dolist (name (payload-field-names value))
      (unless (member name known :test #'string=)
        (fail 'invalid-envelope-error
              "~A contains unknown field ~A."
              context
              name)))
    (dolist (field fields)
      (let* ((name (getf field :name))
             (entry (payload-entry value name)))
        (cond
          (entry
           (push
            (cons name
                  (wire-json-value-for-type
                   manifest
                   (getf field :type)
                   (cdr entry)
                   (format nil "~A field ~A" context name)))
            entries))
          ((getf field :required)
           (fail 'invalid-envelope-error
                 "~A is missing required field ~A."
                 context
                 name)))))
    (%make-json-object entries)))

(defun wire-json-value-for-type (manifest type value context)
  (cond
    ((and (listp type)
          (eq (first type) :list)
          (= (length type) 2))
     (unless (listp value)
       (fail 'invalid-envelope-error
             "~A requires a list."
             context))
     (%make-json-array
      (mapcar (lambda (item)
                (wire-json-value-for-type
                 manifest
                 (second type)
                 item
                 context))
              value)))
    ((and (listp type)
          (eq (first type) :optional)
          (= (length type) 2))
     (if (null value)
         +json-null+
         (wire-json-value-for-type
          manifest
          (second type)
          value
          context)))
    ((not (stringp type))
     (fail 'invalid-envelope-error
           "~A has invalid type contract ~S."
           context
           type))
    ((string= type "any")
     (generic-wire-json-value value))
    ((member type
             '("string" "symbol" "iso-date" "iso-datetime")
             :test #'string=)
     (unless (or (stringp value)
                 (and (string= type "symbol")
                      (symbolp value)))
       (fail 'invalid-envelope-error
             "~A requires ~A."
             context
             type))
     (if (symbolp value)
         (identifier-string value)
         value))
    ((string= type "integer")
     (unless (integerp value)
       (fail 'invalid-envelope-error
             "~A requires an integer."
             context))
     value)
    ((string= type "boolean")
     (unless (or (eq value t)
                 (null value))
       (fail 'invalid-envelope-error
             "~A requires a boolean."
             context))
     (if value
         +json-true+
         +json-false+))
    ((string= type "decimal")
     (unless (decimal-wire-string-p value)
       (fail 'invalid-envelope-error
             "~A requires a decimal string to preserve wire precision."
             context))
     value)
    ((string= type "map")
     (wire-map-value value context))
    ((string= type "reference")
     (wire-reference-value value context))
    (t
     (let ((contract (manifest-type-contract manifest type)))
       (unless contract
         (fail 'invalid-envelope-error
               "~A references unknown type ~A."
               context
               type))
       (case (getf contract :kind)
         (:scalar
          (let ((encoded
                  (wire-json-value-for-type
                   manifest
                   (getf contract :base)
                   value
                   context)))
            (validate-scalar-constraints contract value context)
            encoded))
         (:enum
          (wire-enum-value contract value context))
         (:document
          (wire-fields-object
           manifest
           (manifest-document-fields manifest contract)
           value
           context))
         (otherwise
          (fail 'invalid-envelope-error
                "~A cannot use type kind ~A."
                context
                (getf contract :kind))))))))

(defun validate-wire-value (manifest type value &optional (context "wire value"))
  (wire-json-value-for-type manifest type value context)
  t)

(defun envelope-json-object (manifest envelope)
  (unless (= (getf envelope :star-version) 1)
    (fail 'invalid-envelope-error
          "Unsupported Star wire version."))
  (let* ((message-type (getf envelope :message-type))
         (contract (message-contract manifest message-type)))
    (unless contract
      (fail 'invalid-envelope-error
            "Unknown message type ~A."
            message-type))
    (let ((entries
            (list
             (cons "starVersion" 1)
             (cons "messageType" message-type)
             (cons "messageId" (getf envelope :message-id))
             (cons "actor" (getf envelope :actor))
             (cons
              "payload"
              (wire-fields-object
               manifest
               (getf contract :fields)
               (getf envelope :payload)
               (format nil "Message ~A" message-type))))))
      (when (getf envelope :dataset)
        (push (cons "dataset" (getf envelope :dataset)) entries))
      (when (getf envelope :reply-to)
        (push (cons "replyTo" (getf envelope :reply-to)) entries))
      (%make-json-object entries))))

(defun canonical-envelope-json (manifest envelope)
  (canonical-json-string
   (envelope-json-object manifest envelope)))
