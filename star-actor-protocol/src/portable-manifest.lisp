(in-package :staractorprotocol)

(defconstant +portable-manifest-wire-version+ 1)
(defconstant +portable-manifest-max-types+ 4096)
(defconstant +portable-manifest-max-predicates+ 4096)
(defconstant +portable-manifest-max-messages+ 4096)
(defconstant +portable-manifest-max-actors+ 2048)
(defconstant +portable-manifest-max-fields+ 1024)
(defconstant +portable-manifest-max-capabilities+ 256)
(defconstant +portable-manifest-max-metadata-entries+ 128)
(defconstant +portable-manifest-max-name-bytes+ 512)
(defconstant +portable-manifest-min-metadata-integer+ -9223372036854775808)
(defconstant +portable-manifest-max-metadata-integer+ 9223372036854775807)

(defparameter +portable-manifest-built-in-types+
  '("any" "string" "symbol" "iso-date" "iso-datetime" "decimal"
    "integer" "boolean" "map" "reference"))

(defun manifest-fail (control &rest arguments)
  (apply #'fail-invalid-wire-envelope control arguments))

(defun manifest-keyword-plist-p (value)
  (and (listp value)
       (evenp (length value))
       (loop for tail on value by #'cddr
             always (keywordp (first tail)))))

(defun manifest-key-present-p (plist key)
  (loop for tail on plist by #'cddr
        thereis (eq (first tail) key)))

(defun manifest-assert-plist (value context)
  (unless (manifest-keyword-plist-p value)
    (manifest-fail "~A must be a keyword property list." context))
  (let ((seen '()))
    (loop for tail on value by #'cddr
          for key = (first tail)
          do (when (member key seen :test #'eq)
               (manifest-fail "~A contains duplicate key ~S." context key))
             (push key seen)))
  value)

(defun manifest-assert-closed-keys (value required optional context)
  (manifest-assert-plist value context)
  (dolist (key required)
    (unless (manifest-key-present-p value key)
      (manifest-fail "~A is missing required key ~S." context key)))
  (loop for tail on value by #'cddr
        for key = (first tail)
        unless (or (member key required :test #'eq)
                   (member key optional :test #'eq))
          do (manifest-fail "~A contains unsupported key ~S." context key))
  value)

(defun manifest-assert-string (value context &key (allow-empty nil))
  (unless (and (stringp value)
               (or allow-empty (> (length value) 0))
               (<= (length value) +portable-manifest-max-name-bytes+))
    (manifest-fail "~A must be a bounded string." context))
  value)

(defun manifest-digest-p (value)
  (and (stringp value)
       (> (length value) 7)
       (string= "sha256:" value :end2 7)))

(defun manifest-lower-camel-name-p (value)
  (and (stringp value)
       (> (length value) 0)
       (char<= #\a (char value 0) #\z)
       (loop for character across value
             always (or (char<= #\a character #\z)
                        (char<= #\A character #\Z)
                        (char<= #\0 character #\9)))))

(defun manifest-external-contract-name-p (value)
  "Return true for a qualified contract identifier that can be resolved by a
registry outside this manifest. Standalone actor manifests legitimately carry
such references without embedding the referenced library's type table."
  (and (stringp value)
       (> (length value) 3)
       (let ((slash (position #\/ value))
             (at (position #\@ value :from-end t)))
         (and slash at (> slash 0) (> at (1+ slash)) (< at (1- (length value)))))))

(defun manifest-assert-list-limit (value maximum context)
  (unless (listp value)
    (manifest-fail "~A must be a list." context))
  (when (> (length value) maximum)
    (manifest-fail "~A exceeds the limit of ~D entries." context maximum))
  value)

(defun manifest-assert-unique-strings (values context)
  (let ((seen (make-hash-table :test #'equal)))
    (dolist (value values)
      (manifest-assert-string value context)
      (when (gethash value seen)
        (manifest-fail "~A contains duplicate value ~S." context value))
      (setf (gethash value seen) t)))
  values)

(defun manifest-type-expression-p (type &optional (depth 0))
  (and (< depth 32)
       (or (and (stringp type) (> (length type) 0)
                (<= (length type) +portable-manifest-max-name-bytes+))
           (and (listp type)
                (= (length type) 2)
                (member (first type) '(:list :optional) :test #'eq)
                (manifest-type-expression-p (second type) (1+ depth))))))

(defun manifest-type-leaf (type)
  (if (stringp type)
      type
      (manifest-type-leaf (second type))))

(defun manifest-validate-field-shape (field context)
  (manifest-assert-closed-keys
   field '(:name :type :required) '(:default) context)
  (let ((name (getf field :name))
        (type (getf field :type))
        (required (getf field :required)))
    (unless (manifest-lower-camel-name-p name)
      (manifest-fail "~A field name ~S must use ASCII lower camelCase."
                     context name))
    (unless (manifest-type-expression-p type)
      (manifest-fail "~A field ~A has invalid type expression ~S."
                     context name type))
    (unless (or (eq required t) (null required))
      (manifest-fail "~A field ~A required flag must be boolean."
                     context name))
    (when (manifest-key-present-p field :default)
      (validate-portable-manifest-json-value (getf field :default))))
  field)

(defun manifest-validate-fields (fields context)
  (manifest-assert-list-limit fields +portable-manifest-max-fields+ context)
  (let ((seen (make-hash-table :test #'equal)))
    (dolist (field fields)
      (manifest-validate-field-shape field context)
      (let ((name (getf field :name)))
        (when (gethash name seen)
          (manifest-fail "~A contains duplicate field ~A." context name))
        (setf (gethash name seen) t))))
  fields)

(defun manifest-validate-scalar-constraints (contract name)
  (let ((pattern (getf contract :pattern))
        (format-name (getf contract :format))
        (minimum (getf contract :minimum))
        (maximum (getf contract :maximum))
        (scale (getf contract :scale)))
    (when pattern
      (manifest-assert-string pattern (format nil "scalar ~A pattern" name)))
    (when format-name
      (unless (or (stringp format-name) (symbolp format-name))
        (manifest-fail "Scalar ~A format must be a string/symbol." name)))
    (when minimum
      (unless (numberp minimum)
        (manifest-fail "Scalar ~A minimum must be numeric." name)))
    (when maximum
      (unless (numberp maximum)
        (manifest-fail "Scalar ~A maximum must be numeric." name)))
    (when (and minimum maximum (> minimum maximum))
      (manifest-fail "Scalar ~A minimum exceeds maximum." name))
    (when scale
      (unless (and (integerp scale) (>= scale 0))
        (manifest-fail "Scalar ~A scale must be a non-negative integer." name))))
  contract)

(defun manifest-validate-type-shape (contract)
  (manifest-assert-plist contract "portable type contract")
  (let ((kind (getf contract :kind))
        (name (getf contract :name)))
    (manifest-assert-string name "portable type name")
    (case kind
      (:scalar
       (manifest-assert-closed-keys
        contract
        '(:kind :name :base :pattern :format :minimum :maximum :scale)
        '()
        (format nil "scalar ~A" name))
       (manifest-assert-string (getf contract :base)
                               (format nil "scalar ~A base" name))
       (manifest-validate-scalar-constraints contract name))
      (:enum
       (manifest-assert-closed-keys
        contract '(:kind :name :values) '() (format nil "enum ~A" name))
       (let ((values (getf contract :values)))
         (manifest-assert-list-limit values +portable-manifest-max-fields+
                                     (format nil "enum ~A values" name))
         (unless values
           (manifest-fail "Enum ~A must contain at least one value." name))
         (manifest-assert-unique-strings values (format nil "enum ~A" name))))
      (:document
       (manifest-assert-closed-keys
        contract '(:kind :name :extends :persistence :fields) '()
        (format nil "document ~A" name))
       (let ((extends (getf contract :extends))
             (persistence (getf contract :persistence)))
         (when extends
           (manifest-assert-string extends (format nil "document ~A parent" name)))
         (unless (member persistence '(:persistent :transient) :test #'eq)
           (manifest-fail "Document ~A has invalid persistence ~S."
                          name persistence)))
       (manifest-validate-fields (getf contract :fields)
                                 (format nil "document ~A" name)))
      (otherwise
       (manifest-fail "Portable type ~A has unsupported kind ~S." name kind))))
  contract)

(defun manifest-validate-message-shape (message)
  (manifest-assert-closed-keys
   message '(:kind :name :fields) '() "portable message contract")
  (unless (eq (getf message :kind) :message)
    (manifest-fail "Portable message contract has invalid kind ~S."
                   (getf message :kind)))
  (manifest-assert-string (getf message :name) "portable message name")
  (manifest-validate-fields
   (getf message :fields)
   (format nil "message ~A" (getf message :name)))
  message)

(defun manifest-validate-predicate-shape (predicate)
  (manifest-assert-closed-keys
   predicate '(:kind :name :source :destination) '()
   "portable predicate contract")
  (unless (eq (getf predicate :kind) :predicate)
    (manifest-fail "Portable predicate contract has invalid kind ~S."
                   (getf predicate :kind)))
  (dolist (key '(:name :source :destination))
    (manifest-assert-string
     (getf predicate key)
     (format nil "portable predicate ~A" key)))
  predicate)

(defun manifest-validate-metadata (metadata actor-name)
  (manifest-assert-list-limit metadata +portable-manifest-max-metadata-entries+
                              (format nil "actor ~A metadata" actor-name))
  (let ((seen (make-hash-table :test #'equal)))
    (dolist (entry metadata)
      (unless (and (consp entry)
                   (stringp (car entry))
                   (or (stringp (cdr entry)) (integerp (cdr entry))))
        (manifest-fail
         "Actor ~A metadata entries must be string-keyed scalar pairs."
         actor-name))
      (unless (manifest-lower-camel-name-p (car entry))
        (manifest-fail "Actor ~A metadata key ~S must use lower camelCase."
                       actor-name (car entry)))
      (manifest-assert-string (car entry) (format nil "actor ~A metadata key" actor-name))
      (when (and (stringp (cdr entry))
                 (> (length (cdr entry)) +portable-manifest-max-name-bytes+))
        (manifest-fail "Actor ~A metadata string value is too large." actor-name))
      (when (and (integerp (cdr entry))
                 (or (< (cdr entry) +portable-manifest-min-metadata-integer+)
                     (> (cdr entry) +portable-manifest-max-metadata-integer+)))
        (manifest-fail "Actor ~A metadata integer is outside signed 64-bit range."
                       actor-name))
      (when (gethash (car entry) seen)
        (manifest-fail "Actor ~A metadata duplicates key ~A."
                       actor-name (car entry)))
      (setf (gethash (car entry) seen) t)))
  metadata)

(defun manifest-validate-actor-shape (actor)
  (manifest-assert-closed-keys
   actor
   '(:name :runtime :protocol :endpoint :accepts :produces :capabilities)
   '(:service-uri :metadata)
   "portable actor contract")
  (let ((name (getf actor :name))
        (runtime (getf actor :runtime))
        (protocol (getf actor :protocol))
        (endpoint (getf actor :endpoint)))
    (manifest-assert-string name "actor name")
    (unless (member runtime '(:native :external) :test #'eq)
      (manifest-fail "Actor ~A has invalid runtime ~S." name runtime))
    (ecase runtime
      (:native
       (when (or protocol endpoint)
         (manifest-fail "Native actor ~A must not carry protocol/endpoint." name)))
      (:external
       (manifest-assert-string protocol (format nil "actor ~A protocol" name))
       (manifest-assert-string endpoint (format nil "actor ~A endpoint" name))))
    (dolist (key '(:accepts :produces))
      (let ((values (getf actor key)))
        (manifest-assert-list-limit values +portable-manifest-max-fields+
                                    (format nil "actor ~A ~A" name key))
        (manifest-assert-unique-strings values
                                        (format nil "actor ~A ~A" name key))))
    (let ((capabilities (getf actor :capabilities)))
      (manifest-assert-list-limit capabilities +portable-manifest-max-capabilities+
                                  (format nil "actor ~A capabilities" name))
      (manifest-assert-unique-strings capabilities
                                      (format nil "actor ~A capabilities" name)))
    (let ((service-uri (getf actor :service-uri)))
      (when service-uri
        (manifest-assert-string service-uri (format nil "actor ~A service URI" name))
        (handler-case
            (let* ((parsed (ensure-star-service-uri service-uri))
                   (canonical (star-service-uri-string parsed)))
              (unless (string= canonical service-uri)
                (manifest-fail "Actor ~A service URI is not canonical." name))
              (unless (string= (star-service-uri-actor-name parsed) name)
                (manifest-fail
                 "Actor ~A service URI names different actor ~A."
                 name (star-service-uri-actor-name parsed))))
          (invalid-star-service-uri-error (condition)
            (manifest-fail "Actor ~A has invalid service URI: ~A" name condition)))))
    (when (manifest-key-present-p actor :metadata)
      (manifest-validate-metadata (getf actor :metadata) name)))
  actor)

(defun manifest-validate-import (import)
  (manifest-assert-closed-keys
   import '(:kind :name :version :digest) '() "manifest import")
  (unless (eq (getf import :kind) :import)
    (manifest-fail "Manifest import kind must be :IMPORT."))
  (manifest-assert-string (getf import :name) "manifest import name")
  (manifest-assert-string (getf import :version) "manifest import version")
  (unless (manifest-digest-p (getf import :digest))
    (manifest-fail "Manifest import digest must be sha256-prefixed."))
  import)

(defun manifest-validate-imports (imports)
  (let ((seen (make-hash-table :test #'equal)))
    (dolist (import imports)
      (manifest-validate-import import)
      (let ((name (getf import :name)))
        (when (gethash name seen)
          (manifest-fail "Manifest imports duplicate library ~A." name))
        (setf (gethash name seen) t))))
  imports)

(defun manifest-build-name-table (contracts context)
  (let ((table (make-hash-table :test #'equal)))
    (dolist (contract contracts table)
      (let ((name (getf contract :name)))
        (when (gethash name table)
          (manifest-fail "~A contains duplicate name ~A." context name))
        (setf (gethash name table) contract)))))

(defun manifest-validate-global-contract-names (types messages)
  (let ((seen (make-hash-table :test #'equal)))
    (dolist (contract types)
      (setf (gethash (getf contract :name) seen) :type))
    (dolist (message messages)
      (let ((name (getf message :name)))
        (when (gethash name seen)
          (manifest-fail
           "Portable contract name ~A is used by both a type and message."
           name))
        (setf (gethash name seen) :message))))
  t)

(defun manifest-assert-known-or-external-type (type type-table context)
  (let ((leaf (manifest-type-leaf type)))
    (unless (or (member leaf +portable-manifest-built-in-types+ :test #'string=)
                (gethash leaf type-table)
                (manifest-external-contract-name-p leaf))
      (manifest-fail "~A references unknown unqualified type ~A." context leaf)))
  type)

(defun manifest-validate-type-references (types type-table)
  (dolist (contract types)
    (let ((name (getf contract :name)))
      (case (getf contract :kind)
        (:scalar
         (unless (member (getf contract :base)
                         +portable-manifest-built-in-types+
                         :test #'string=)
           (manifest-fail "Scalar ~A base ~A is not a built-in wire type."
                          name (getf contract :base))))
        (:document
         (let ((parent-name (getf contract :extends)))
           (when parent-name
             (let ((parent (gethash parent-name type-table)))
               (unless (or (and parent (eq (getf parent :kind) :document))
                           (and (null parent)
                                (manifest-external-contract-name-p parent-name)))
                 (manifest-fail "Document ~A extends unknown/non-document ~A."
                                name parent-name)))))
         (dolist (field (getf contract :fields))
           (manifest-assert-known-or-external-type
            (getf field :type) type-table
            (format nil "document ~A field ~A" name (getf field :name))))))))
  types)

(defun manifest-validate-document-acyclic (types type-table)
  (let ((state (make-hash-table :test #'equal)))
    (labels ((visit (name)
               (case (gethash name state)
                 (:done t)
                 (:visiting
                  (manifest-fail "Document inheritance contains a cycle at ~A." name))
                 (otherwise
                  (setf (gethash name state) :visiting)
                  (let* ((contract (gethash name type-table))
                         (parent (and contract (getf contract :extends))))
                    (when (and parent (gethash parent type-table))
                      (visit parent)))
                  (setf (gethash name state) :done)))))
      (dolist (contract types)
        (when (eq (getf contract :kind) :document)
          (visit (getf contract :name))))))
  t)

(defun manifest-local-parent-field-names (contract type-table)
  (let ((names '())
        (parent-name (getf contract :extends)))
    (loop while parent-name
          for parent = (gethash parent-name type-table)
          while (and parent (eq (getf parent :kind) :document))
          do (dolist (field (getf parent :fields))
               (pushnew (getf field :name) names :test #'string=))
             (setf parent-name (getf parent :extends)))
    names))

(defun manifest-validate-inherited-fields (types type-table)
  (dolist (contract types)
    (when (eq (getf contract :kind) :document)
      (let ((inherited (manifest-local-parent-field-names contract type-table)))
        (dolist (field (getf contract :fields))
          (when (member (getf field :name) inherited :test #'string=)
            (manifest-fail
             "Document ~A redefines inherited field ~A."
             (getf contract :name) (getf field :name)))))))
  t)

(defun validate-portable-manifest (manifest)
  "Validate one complete runtime-neutral manifest and fail closed on ambiguity.

The validator enforces closed object shapes, bounded collections, duplicate-key
rejection, unique names/fields, local type integrity, safe qualified external
references, acyclic/additive local document inheritance, canonical actor-bound
service URIs, and bounded actor contracts. It never interns peer-controlled
strings."
  (manifest-assert-closed-keys
   manifest '(:wire-version :library :imports :types :predicates :messages :actors)
   '() "portable manifest")
  (unless (= (getf manifest :wire-version) +portable-manifest-wire-version+)
    (manifest-fail "Unsupported portable manifest wire version ~S."
                   (getf manifest :wire-version)))
  (let ((library (getf manifest :library)))
    (manifest-assert-closed-keys
     library '(:name :version :digest) '() "portable manifest library")
    (manifest-assert-string (getf library :name) "manifest library name")
    (manifest-assert-string (getf library :version) "manifest library version")
    (let ((digest (getf library :digest)))
      (when (and digest (not (manifest-digest-p digest)))
        (manifest-fail "Manifest library digest must be sha256-prefixed."))))
  (let ((imports (getf manifest :imports)))
    (manifest-assert-list-limit imports +portable-manifest-max-fields+
                                "manifest imports")
    (manifest-validate-imports imports))
  (let* ((types (manifest-assert-list-limit
                 (getf manifest :types) +portable-manifest-max-types+ "manifest types"))
         (predicates (manifest-assert-list-limit
                      (getf manifest :predicates) +portable-manifest-max-predicates+
                      "manifest predicates"))
         (messages (manifest-assert-list-limit
                    (getf manifest :messages) +portable-manifest-max-messages+
                    "manifest messages"))
         (actors (manifest-assert-list-limit
                  (getf manifest :actors) +portable-manifest-max-actors+
                  "manifest actors")))
    (mapc #'manifest-validate-type-shape types)
    (mapc #'manifest-validate-predicate-shape predicates)
    (mapc #'manifest-validate-message-shape messages)
    (mapc #'manifest-validate-actor-shape actors)
    (let* ((type-table (manifest-build-name-table types "manifest types"))
           (predicate-table (manifest-build-name-table predicates "manifest predicates"))
           (message-table (manifest-build-name-table messages "manifest messages"))
           (actor-table (manifest-build-name-table actors "manifest actors")))
      (declare (ignore predicate-table message-table actor-table))
      (manifest-validate-global-contract-names types messages)
      (manifest-validate-type-references types type-table)
      (manifest-validate-document-acyclic types type-table)
      (manifest-validate-inherited-fields types type-table)
      (dolist (predicate predicates)
        (dolist (key '(:source :destination))
          (let* ((endpoint (getf predicate key))
                 (contract (gethash endpoint type-table)))
            (unless (or (and contract (eq (getf contract :kind) :document))
                        (and (null contract)
                             (manifest-external-contract-name-p endpoint)))
              (manifest-fail "Predicate ~A ~A references unknown/non-document ~A."
                             (getf predicate :name) key endpoint)))))
      (dolist (message messages)
        (dolist (field (getf message :fields))
          (manifest-assert-known-or-external-type
           (getf field :type) type-table
           (format nil "message ~A field ~A"
                   (getf message :name) (getf field :name)))))))
  t)
