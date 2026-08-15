(in-package :staractorprotocol)

(defun make-wire-envelope
    (&key message-type message-id actor dataset reply-to payload)
  (unless (and (stringp message-type)
               (stringp message-id)
               (stringp actor))
    (fail-invalid-wire-envelope
     "Wire envelope requires string message-type, message-id, and actor."))
  (list :star-version 1
        :message-type message-type
        :message-id message-id
        :actor actor
        :dataset dataset
        :reply-to reply-to
        :payload payload))

(defun portable-map-entry (map key)
  (cond
    ((and (listp map)
          (every #'consp map))
     (assoc key map :test #'string=))
    ((listp map)
     (let ((keyword (intern (string-upcase key) :keyword)))
       (loop for tail on map by #'cddr
             when (eq (first tail) keyword)
               do (return (cons key (second tail)))
             finally (return nil))))
    (t nil)))

(defun portable-wire-identifier-string (value)
  (cond
    ((stringp value) value)
    ((symbolp value) (string-downcase (symbol-name value)))
    (t
     (fail-invalid-wire-envelope
      "Wire identifier must be a string or symbol, received ~S."
      value))))

(defun portable-field-key-string (key)
  (if (stringp key)
      key
      (let ((normalized (portable-wire-identifier-string key)))
        (if (not (or (find #\- normalized)
                     (find #\_ normalized)))
            normalized
            (with-output-to-string (stream)
              (loop with uppercase-next = nil
                    for character across normalized
                    do (cond
                         ((or (char= character #\-)
                              (char= character #\_))
                          (setf uppercase-next t))
                         (uppercase-next
                          (write-char (char-upcase character) stream)
                          (setf uppercase-next nil))
                         (t
                          (write-char character stream)))))))))

(defun portable-keyword-plist-p (value)
  (and (listp value)
       (evenp (length value))
       (loop for tail on value by #'cddr
             always (keywordp (first tail)))))

(defun portable-string-alist-p (value)
  (and (listp value)
       value
       (every (lambda (entry)
                (and (consp entry)
                     (stringp (car entry))))
              value)))

(defun portable-payload-entry (payload field-name)
  (cond
    ((portable-string-alist-p payload)
     (assoc field-name payload :test #'string=))
    ((portable-keyword-plist-p payload)
     (loop for (key value) on payload by #'cddr
           when (string= (portable-field-key-string key) field-name)
             return (cons field-name value)))
    (t nil)))

(defun portable-payload-field-names (payload)
  (cond
    ((portable-string-alist-p payload)
     (mapcar #'car payload))
    ((portable-keyword-plist-p payload)
     (loop for tail on payload by #'cddr
           collect (portable-field-key-string (first tail))))
    ((null payload)
     '())
    (t nil)))

(defun portable-manifest-message-contract (manifest message-type)
  (find message-type
        (getf manifest :messages)
        :key (lambda (message) (getf message :name))
        :test #'string=))

(defun portable-manifest-type-contract (manifest qualified-name)
  (find qualified-name
        (getf manifest :types)
        :key (lambda (contract) (getf contract :name))
        :test #'string=))

(defun portable-manifest-document-fields (manifest contract)
  (let ((parent-name (getf contract :extends)))
    (append
     (when parent-name
       (let ((parent
               (portable-manifest-type-contract manifest parent-name)))
         (unless (and parent
                      (eq (getf parent :kind) :document))
           (fail-invalid-wire-envelope
            "Cannot resolve document parent ~A while validating wire data."
            parent-name))
         (portable-manifest-document-fields manifest parent)))
     (copy-tree (getf contract :fields)))))

(defun portable-decimal-wire-string-p (value)
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

(defun portable-decimal-fraction-digits (value)
  (let ((dot (position #\. value)))
    (if dot
        (- (length value) dot 1)
        0)))

(defun validate-portable-manifest-json-value (value)
  (cond
    ((eq value t) t)
    ((null value) t)
    ((stringp value) t)
    ((integerp value) t)
    ((keywordp value) t)
    ((symbolp value) t)
    ((portable-keyword-plist-p value)
     (loop for (key item) on value by #'cddr
           do (declare (ignore key))
              (validate-portable-manifest-json-value item))
     t)
    ((portable-string-alist-p value)
     (dolist (entry value t)
       (validate-portable-manifest-json-value (cdr entry))))
    ((listp value)
     (dolist (item value t)
       (validate-portable-manifest-json-value item)))
    (t
     (fail-invalid-wire-envelope
      "Cannot convert ~S to canonical JSON."
      value))))

(defun validate-portable-generic-wire-value (value)
  (cond
    ((eq value t) t)
    ((null value) t)
    ((stringp value) t)
    ((integerp value) t)
    ((symbolp value) t)
    ((portable-string-alist-p value)
     (dolist (entry value t)
       (validate-portable-generic-wire-value (cdr entry))))
    ((listp value)
     (dolist (item value t)
       (validate-portable-generic-wire-value item)))
    (t
     (fail-invalid-wire-envelope
      "Unsupported wire value ~S."
      value))))

(defun validate-portable-wire-map (value context)
  (cond
    ((null value) t)
    ((portable-string-alist-p value)
     (dolist (entry value t)
       (validate-portable-generic-wire-value (cdr entry))))
    ((portable-keyword-plist-p value)
     (loop for (key item) on value by #'cddr
           do (declare (ignore key))
              (validate-portable-manifest-json-value item))
     t)
    (t
     (fail-invalid-wire-envelope
      "~A requires an object/map value."
      context))))

(defun validate-portable-wire-reference (value context)
  (let ((schema (portable-payload-entry value "schema"))
        (id (portable-payload-entry value "id")))
    (unless (and schema
                 (stringp (cdr schema))
                 id
                 (stringp (cdr id)))
      (fail-invalid-wire-envelope
       "~A requires reference fields schema and id as strings."
       context))
    (validate-portable-wire-map value context)))

(defun validate-portable-wire-enum (contract value context)
  (let ((normalized
          (cond
            ((stringp value) value)
            ((symbolp value)
             (portable-wire-identifier-string value))
            (t nil))))
    (unless (and normalized
                 (member normalized
                         (getf contract :values)
                         :test #'string=))
      (fail-invalid-wire-envelope
       "~A requires one of ~S, received ~S."
       context
       (getf contract :values)
       value))
    t))

(defun validate-portable-scalar-constraints (contract value context)
  (let ((minimum (getf contract :minimum))
        (maximum (getf contract :maximum))
        (scale (getf contract :scale)))
    (when (and minimum
               (numberp value)
               (< value minimum))
      (fail-invalid-wire-envelope
       "~A is below scalar minimum ~A."
       context
       minimum))
    (when (and maximum
               (numberp value)
               (> value maximum))
      (fail-invalid-wire-envelope
       "~A exceeds scalar maximum ~A."
       context
       maximum))
    (when scale
      (unless (and (portable-decimal-wire-string-p value)
                   (<= (portable-decimal-fraction-digits value) scale))
        (fail-invalid-wire-envelope
         "~A requires a decimal string with at most ~D fractional digits."
         context
         scale))))
  t)

(defun validate-portable-wire-fields (manifest fields value context)
  (unless (or (portable-string-alist-p value)
              (portable-keyword-plist-p value)
              (null value))
    (fail-invalid-wire-envelope
     "~A requires an object payload."
     context))
  (let ((known
          (mapcar (lambda (field)
                    (getf field :name))
                  fields)))
    (dolist (name (portable-payload-field-names value))
      (unless (member name known :test #'string=)
        (fail-invalid-wire-envelope
         "~A contains unknown field ~A."
         context
         name)))
    (dolist (field fields)
      (let* ((name (getf field :name))
             (entry (portable-payload-entry value name)))
        (cond
          (entry
           (validate-portable-wire-value
            manifest
            (getf field :type)
            (cdr entry)
            (format nil "~A field ~A" context name)))
          ((getf field :required)
           (fail-invalid-wire-envelope
            "~A is missing required field ~A."
            context
            name))))))
  t)

(defun validate-portable-wire-value
    (manifest type value &optional (context "wire value"))
  (cond
    ((and (listp type)
          (eq (first type) :list)
          (= (length type) 2))
     (unless (listp value)
       (fail-invalid-wire-envelope
        "~A requires a list."
        context))
     (dolist (item value t)
       (validate-portable-wire-value
        manifest
        (second type)
        item
        context)))
    ((and (listp type)
          (eq (first type) :optional)
          (= (length type) 2))
     (if (null value)
         t
         (validate-portable-wire-value
          manifest
          (second type)
          value
          context)))
    ((not (stringp type))
     (fail-invalid-wire-envelope
      "~A has invalid type contract ~S."
      context
      type))
    ((string= type "any")
     (validate-portable-generic-wire-value value))
    ((member type
             '("string" "symbol" "iso-date" "iso-datetime")
             :test #'string=)
     (unless (or (stringp value)
                 (and (string= type "symbol")
                      (symbolp value)))
       (fail-invalid-wire-envelope
        "~A requires ~A."
        context
        type))
     t)
    ((string= type "integer")
     (unless (integerp value)
       (fail-invalid-wire-envelope
        "~A requires an integer."
        context))
     t)
    ((string= type "boolean")
     (unless (or (eq value t)
                 (null value))
       (fail-invalid-wire-envelope
        "~A requires a boolean."
        context))
     t)
    ((string= type "decimal")
     (unless (portable-decimal-wire-string-p value)
       (fail-invalid-wire-envelope
        "~A requires a decimal string to preserve wire precision."
        context))
     t)
    ((string= type "map")
     (validate-portable-wire-map value context))
    ((string= type "reference")
     (validate-portable-wire-reference value context))
    (t
     (let ((contract
             (portable-manifest-type-contract manifest type)))
       (unless contract
         (fail-invalid-wire-envelope
          "~A references unknown type ~A."
          context
          type))
       (case (getf contract :kind)
         (:scalar
          (validate-portable-wire-value
           manifest
           (getf contract :base)
           value
           context)
          (validate-portable-scalar-constraints
           contract value context))
         (:enum
          (validate-portable-wire-enum contract value context))
         (:document
          (validate-portable-wire-fields
           manifest
           (portable-manifest-document-fields manifest contract)
           value
           context))
         (otherwise
          (fail-invalid-wire-envelope
           "~A cannot use type kind ~A."
           context
           (getf contract :kind))))))))

(defun validate-portable-message-payload (manifest message-type payload)
  (let ((contract
          (portable-manifest-message-contract manifest message-type)))
    (unless contract
      (fail-invalid-wire-envelope
       "Unknown lifecycle message type ~A."
       message-type))
    (validate-portable-wire-fields
     manifest
     (getf contract :fields)
     payload
     (format nil "Message ~A" message-type))))

(defun validate-lifecycle-envelope-against-manifest
    (manifest envelope &key (validate-payload t))
  (validate-lifecycle-envelope
   envelope
   :validate-payload validate-payload
   :payload-validator
   (and validate-payload
        (lambda (data-envelope)
          (unless manifest
            (fail-invalid-wire-envelope
             "Data lifecycle envelopes require a portable manifest."))
          (validate-portable-message-payload
           manifest
           (getf data-envelope :message-type)
           (getf data-envelope :payload)))))
  t)

(defun validate-wire-envelope (manifest envelope)
  (unless (= (getf envelope :star-version) 1)
    (fail-invalid-wire-envelope "Unsupported Star wire version."))
  (let* ((message-type (getf envelope :message-type))
         (contract
           (portable-manifest-message-contract manifest message-type))
         (payload (getf envelope :payload)))
    (unless contract
      (fail-invalid-wire-envelope
       "Unknown message type ~A."
       message-type))
    (dolist (field (getf contract :fields))
      (when (and (getf field :required)
                 (null (portable-map-entry payload (getf field :name))))
        (fail-invalid-wire-envelope
         "Message ~A is missing required field ~A."
         message-type
         (getf field :name))))
    t))

(defun portable-manifest-actor-contract (manifest actor-target)
  (let ((actors (getf manifest :actors)))
    (if (star-service-uri-target-p actor-target)
        (let ((canonical
                (star-service-uri-string
                 (ensure-star-service-uri actor-target))))
          (find-if
           (lambda (actor)
             (let ((service-uri (getf actor :service-uri)))
               (and service-uri
                    (string= canonical service-uri))))
           actors))
        (find actor-target
              actors
              :key (lambda (actor) (getf actor :name))
              :test #'string=))))

(defun portable-actor-accepts-message-p (actor-contract message-type)
  (not
   (null
    (member message-type
            (getf actor-contract :accepts)
            :test #'string=))))
