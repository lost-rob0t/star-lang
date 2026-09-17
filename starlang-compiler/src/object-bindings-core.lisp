(in-package :starlangcompiler)

(defparameter +object-binding-targets+
  '(:common-lisp :python :typescript :nim :java :kotlin :go :rust :elisp :prolog))

(defparameter +binding-built-in-types+
  '("any" "string" "symbol" "iso-date" "iso-datetime" "decimal"
    "integer" "boolean" "map" "reference"))

(defvar *binding-name-table* nil)

(defun binding-target (value)
  (let ((target
          (etypecase value
            (keyword value)
            (symbol (intern (string-upcase (symbol-name value)) :keyword))
            (string (intern (string-upcase value) :keyword)))))
    (unless (member target +object-binding-targets+ :test #'eq)
      (error "Unsupported Star object binding target ~S. Supported targets: ~{~S~^, ~}."
             value +object-binding-targets+))
    target))

(defun binding-local-name (qualified-name)
  (let ((position (position #\/ qualified-name :from-end t)))
    (if position
        (subseq qualified-name (1+ position))
        qualified-name)))

(defun binding-identifier-words (value &key (local-only t))
  (let ((words '())
        (current (make-string-output-stream))
        (source (if local-only (binding-local-name value) value)))
    (labels ((finish-word ()
               (let ((word (get-output-stream-string current)))
                 (unless (string= word "")
                   (push word words)))
               (setf current (make-string-output-stream))))
      (loop for character across source
            do (if (alphanumericp character)
                   (write-char character current)
                   (finish-word)))
      (finish-word))
    (nreverse words)))

(defun binding-pascal-name (value &key (local-only t))
  (with-output-to-string (stream)
    (dolist (word (binding-identifier-words value :local-only local-only))
      (when (> (length word) 0)
        (write-char (char-upcase (char word 0)) stream)
        (loop for character across (subseq word 1)
              do (write-char (char-downcase character) stream))))))

(defun binding-snake-name (value &key (local-only t))
  (format nil "~{~A~^_~}"
          (mapcar #'string-downcase
                  (binding-identifier-words value :local-only local-only))))

(defun binding-kebab-name (value &key (local-only t))
  (format nil "~{~A~^-~}"
          (mapcar #'string-downcase
                  (binding-identifier-words value :local-only local-only))))

(defun binding-upper-snake-name (value &key (local-only t))
  (string-upcase (binding-snake-name value :local-only local-only)))

(defun binding-string (value)
  (with-output-to-string (stream)
    (write-char #\" stream)
    (loop for character across value
          do (case character
               (#\" (write-string "\\\"" stream))
               (#\\ (write-string "\\\\" stream))
               (#\Newline (write-string "\\n" stream))
               (#\Return (write-string "\\r" stream))
               (#\Tab (write-string "\\t" stream))
               (otherwise
                (if (< (char-code character) 32)
                    (format stream "\\u~4,'0X" (char-code character))
                    (write-char character stream)))))
    (write-char #\" stream)))

(defun binding-prolog-atom (value)
  (with-output-to-string (stream)
    (write-char #\' stream)
    (loop for character across value
          do (if (char= character #\')
                 (write-string "''" stream)
                 (write-char character stream)))
    (write-char #\' stream)))

(defun binding-type-leaves (type)
  (cond
    ((stringp type) (list type))
    ((and (listp type)
          (= (length type) 2)
          (member (first type) '(:list :optional) :test #'eq))
     (binding-type-leaves (second type)))
    (t
     (error "Invalid Star binding type expression ~S." type))))

(defun binding-local-contract-names (manifest)
  (append (mapcar (lambda (contract) (getf contract :name))
                  (getf manifest :types))
          (mapcar (lambda (message) (getf message :name))
                  (getf manifest :messages))))

(defun binding-referenced-contract-names (manifest)
  (let ((references '()))
    (dolist (contract (getf manifest :types))
      (when (eq (getf contract :kind) :document)
        (when (getf contract :extends)
          (push (getf contract :extends) references))
        (dolist (field (getf contract :fields))
          (setf references
                (nconc (binding-type-leaves (getf field :type)) references)))))
    (dolist (message (getf manifest :messages))
      (dolist (field (getf message :fields))
        (setf references
              (nconc (binding-type-leaves (getf field :type)) references))))
    (dolist (predicate (getf manifest :predicates))
      (push (getf predicate :source) references)
      (push (getf predicate :destination) references))
    (dolist (actor (getf manifest :actors))
      (setf references (nconc (copy-list (getf actor :accepts)) references))
      (setf references (nconc (copy-list (getf actor :produces)) references)))
    (remove-duplicates references :test #'string=)))

(defun binding-external-contract-names (manifest)
  (let ((local (binding-local-contract-names manifest)))
    (sort
     (remove-if
      (lambda (name)
        (or (member name +binding-built-in-types+ :test #'string=)
            (member name local :test #'string=)))
      (binding-referenced-contract-names manifest))
     #'string<)))

(defun binding-object-names (manifest)
  (remove-duplicates
   (append (binding-local-contract-names manifest)
           (binding-external-contract-names manifest))
   :test #'string=))

(defun binding-name-style (target value &key (local-only t))
  (case target
    ((:common-lisp :elisp)
     (binding-kebab-name value :local-only local-only))
    (:prolog
     (binding-snake-name value :local-only local-only))
    (otherwise
     (binding-pascal-name value :local-only local-only))))

(defun binding-make-name-table (manifest target)
  "Build stable identifiers. Keep a compact local name while it is unique;
fall back to the fully qualified contract name when two objects would collide."
  (let* ((names (sort (copy-list (binding-object-names manifest)) #'string<))
         (short-counts (make-hash-table :test #'equal))
         (used (make-hash-table :test #'equal))
         (table (make-hash-table :test #'equal)))
    (dolist (name names)
      (incf (gethash (binding-name-style target name) short-counts 0)))
    (dolist (name names table)
      (let* ((short (binding-name-style target name))
             (base (if (= 1 (gethash short short-counts 0))
                       short
                       (binding-name-style target name :local-only nil)))
             (candidate base)
             (ordinal 2))
        (loop while (gethash candidate used)
              do (setf candidate (format nil "~A~D" base ordinal))
                 (incf ordinal))
        (setf (gethash candidate used) t
              (gethash name table) candidate)))))

(defun binding-name (target contract-name)
  (or (and *binding-name-table*
           (gethash contract-name *binding-name-table*))
      (binding-name-style target contract-name)))

(defun binding-document-fields (manifest contract)
  "Flatten only ancestors present in MANIFEST. An external parent remains an
opaque generated stub because its fields are not locally authoritative."
  (labels ((walk (item)
             (let* ((parent-name (getf item :extends))
                    (parent (and parent-name
                                 (staractorprotocol:portable-manifest-type-contract
                                  manifest parent-name))))
               (append (if (and parent (eq (getf parent :kind) :document))
                           (walk parent)
                           '())
                       (copy-tree (getf item :fields))))))
    (walk contract)))

(defun binding-prefix-p (prefix value)
  (and (<= (length prefix) (length value))
       (string= prefix value :end2 (length prefix))))

(defun binding-suffix-p (suffix value)
  (and (<= (length suffix) (length value))
       (string= suffix value :start2 (- (length value) (length suffix)))))

(defun binding-optional-type (target type-string)
  (case target
    (:nim
     (if (binding-prefix-p "Option[" type-string)
         type-string
         (format nil "Option[~A]" type-string)))
    (:kotlin
     (if (binding-suffix-p "?" type-string)
         type-string
         (format nil "~A?" type-string)))
    (:go
     (if (binding-prefix-p "*" type-string)
         type-string
         (format nil "*~A" type-string)))
    (:rust
     (if (binding-prefix-p "Option<" type-string)
         type-string
         (format nil "Option<~A>" type-string)))
    (otherwise type-string)))

(defun binding-type-expression (target type)
  (labels ((recur (inner) (binding-type-expression target inner)))
    (cond
      ((and (listp type) (eq (first type) :list) (= (length type) 2))
       (case target
         (:common-lisp (format nil "(list ~A)" (recur (second type))))
         (:python (format nil "list[~A]" (recur (second type))))
         (:typescript (format nil "Array<~A>" (recur (second type))))
         (:nim (format nil "seq[~A]" (recur (second type))))
         (:java (format nil "List<~A>" (recur (second type))))
         (:kotlin (format nil "List<~A>" (recur (second type))))
         (:go (format nil "[]~A" (recur (second type))))
         (:rust (format nil "Vec<~A>" (recur (second type))))
         (:elisp "list")
         (:prolog (format nil "list(~A)" (recur (second type))))))
      ((and (listp type) (eq (first type) :optional) (= (length type) 2))
       (case target
         (:common-lisp (format nil "(or null ~A)" (recur (second type))))
         (:python (format nil "~A | None" (recur (second type))))
         (:typescript (format nil "~A | null" (recur (second type))))
         (:nim (binding-optional-type :nim (recur (second type))))
         (:java (recur (second type)))
         (:kotlin (binding-optional-type :kotlin (recur (second type))))
         (:go (binding-optional-type :go (recur (second type))))
         (:rust (binding-optional-type :rust (recur (second type))))
         (:elisp (recur (second type)))
         (:prolog (format nil "optional(~A)" (recur (second type))))))
      ((not (stringp type))
       (error "Invalid Star binding type expression ~S." type))
      (t
       (case target
         (:common-lisp
          (cond
            ((string= type "any") "t")
            ((member type '("string" "symbol" "iso-date" "iso-datetime" "decimal")
                     :test #'string=) "string")
            ((string= type "integer") "integer")
            ((string= type "boolean") "boolean")
            ((string= type "map") "list")
            ((string= type "reference") "star-reference")
            (t (binding-name :common-lisp type))))
         (:python
          (cond
            ((string= type "any") "Any")
            ((member type '("string" "symbol" "iso-date" "iso-datetime" "decimal")
                     :test #'string=) "str")
            ((string= type "integer") "int")
            ((string= type "boolean") "bool")
            ((string= type "map") "dict[str, Any]")
            ((string= type "reference") "StarReference")
            (t (binding-name :python type))))
         (:typescript
          (cond
            ((string= type "any") "unknown")
            ((member type '("string" "symbol" "iso-date" "iso-datetime" "decimal")
                     :test #'string=) "string")
            ((string= type "integer") "number")
            ((string= type "boolean") "boolean")
            ((string= type "map") "Record<string, unknown>")
            ((string= type "reference") "StarReference")
            (t (binding-name :typescript type))))
         (:nim
          (cond
            ((string= type "any") "JsonNode")
            ((member type '("string" "symbol" "iso-date" "iso-datetime" "decimal")
                     :test #'string=) "string")
            ((string= type "integer") "int64")
            ((string= type "boolean") "bool")
            ((string= type "map") "Table[string, JsonNode]")
            ((string= type "reference") "StarReference")
            (t (binding-name :nim type))))
         (:java
          (cond
            ((string= type "any") "Object")
            ((member type '("string" "symbol" "iso-date" "iso-datetime" "decimal")
                     :test #'string=) "String")
            ((string= type "integer") "Long")
            ((string= type "boolean") "Boolean")
            ((string= type "map") "Map<String, Object>")
            ((string= type "reference") "StarReference")
            (t (binding-name :java type))))
         (:kotlin
          (cond
            ((string= type "any") "Any")
            ((member type '("string" "symbol" "iso-date" "iso-datetime" "decimal")
                     :test #'string=) "String")
            ((string= type "integer") "Long")
            ((string= type "boolean") "Boolean")
            ((string= type "map") "Map<String, Any?>")
            ((string= type "reference") "StarReference")
            (t (binding-name :kotlin type))))
         (:go
          (cond
            ((string= type "any") "any")
            ((member type '("string" "symbol" "iso-date" "iso-datetime" "decimal")
                     :test #'string=) "string")
            ((string= type "integer") "int64")
            ((string= type "boolean") "bool")
            ((string= type "map") "map[string]any")
            ((string= type "reference") "StarReference")
            (t (binding-name :go type))))
         (:rust
          (cond
            ((string= type "any") "serde_json::Value")
            ((member type '("string" "symbol" "iso-date" "iso-datetime" "decimal")
                     :test #'string=) "String")
            ((string= type "integer") "i64")
            ((string= type "boolean") "bool")
            ((string= type "map") "std::collections::BTreeMap<String, serde_json::Value>")
            ((string= type "reference") "StarReference")
            (t (binding-name :rust type))))
         (:elisp
          (cond
            ((string= type "integer") "integer")
            ((string= type "boolean") "boolean")
            ((string= type "map") "alist")
            ((string= type "reference") "star-reference")
            ((string= type "any") "t")
            ((member type '("string" "symbol" "iso-date" "iso-datetime" "decimal")
                     :test #'string=) "string")
            (t (binding-name :elisp type))))
         (:prolog
          (if (member type +binding-built-in-types+ :test #'string=)
              (string-downcase type)
              (binding-prolog-atom type))))))))

(defun binding-field-type (target field)
  (let ((type (binding-type-expression target (getf field :type))))
    (if (getf field :required)
        type
        (binding-optional-type target type))))

(defun binding-write-string-list (stream values &key (prefix "[") (suffix "]"))
  (write-string prefix stream)
  (loop for value in values
        for first = t then nil
        do (unless first (write-string ", " stream))
           (write-string (binding-string value) stream))
  (write-string suffix stream))

(defun binding-write-nullable-string (stream value null-token)
  (if value
      (write-string (binding-string value) stream)
      (write-string null-token stream)))
