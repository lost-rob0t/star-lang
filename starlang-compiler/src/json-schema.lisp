;;;; Deterministic JSON Schema 2020-12 generation from a portable manifest.

(in-package #:star-lang.compiler.core)

(defun schema-object (&rest entries)
  (starcanonicaljson:make-json-object entries))

(defun schema-array (values)
  (starcanonicaljson:make-json-array values))

(defun schema-ref (qualified-name)
  (schema-object
   (cons "$ref"
         (format nil "#/$defs/~A" (binding-pascal-name qualified-name)))))

(defun schema-reference-definition ()
  (schema-object
   (cons "type" "object")
   (cons "properties"
         (schema-object
          (cons "schema" (schema-object (cons "type" "string")))
          (cons "id" (schema-object (cons "type" "string")))))
   (cons "required" (schema-array '("schema" "id")))
   (cons "additionalProperties" starcanonicaljson:+json-false+)))

(defun schema-builtin-type (type)
  (cond
    ((string= type "any") (schema-object))
    ((member type '("string" "symbol") :test #'string=)
     (schema-object (cons "type" "string")))
    ((string= type "iso-date")
     (schema-object (cons "type" "string") (cons "format" "date")))
    ((string= type "iso-datetime")
     (schema-object (cons "type" "string") (cons "format" "date-time")))
    ((string= type "decimal")
     (schema-object
      (cons "type" "string")
      (cons "pattern" "^[+-]?[0-9]+(?:\\.[0-9]+)?$")))
    ((string= type "integer") (schema-object (cons "type" "integer")))
    ((string= type "float") (schema-object (cons "type" "number")))
    ((string= type "boolean") (schema-object (cons "type" "boolean")))
    ((string= type "map")
     (schema-object (cons "type" "object")
                    (cons "additionalProperties" starcanonicaljson:+json-true+)))
    ((string= type "reference")
     (schema-object (cons "$ref" "#/$defs/StarReference")))
    (t nil)))

(defun schema-type (type)
  (cond
    ((and (listp type) (eq (first type) :list) (= (length type) 2))
     (schema-object
      (cons "type" "array")
      (cons "items" (schema-type (second type)))))
    ((and (listp type) (eq (first type) :optional) (= (length type) 2))
     (schema-object
      (cons "anyOf"
            (schema-array
             (list (schema-type (second type))
                   (schema-object (cons "type" "null")))))))
    ((not (stringp type))
     (fail 'invalid-type-error "Cannot generate JSON Schema type for ~S." type))
    (t (or (schema-builtin-type type) (schema-ref type)))))

(defun schema-default-value (type value)
  (cond
    ((string= type "boolean")
     (if value starcanonicaljson:+json-true+ starcanonicaljson:+json-false+))
    ((null value) starcanonicaljson:+json-null+)
    (t value)))

(defun schema-field (field)
  (let* ((type (getf field :type))
         (base (schema-type type)))
    (if (loop for tail on field by #'cddr thereis (eq (first tail) :default))
        (schema-object
         (cons "allOf" (schema-array (list base)))
         (cons "default" (schema-default-value type (getf field :default))))
        base)))

(defun schema-scalar-definition (contract)
  (let* ((base (getf contract :base))
         (entries
           (copy-list
            (starcanonicaljson:json-object-entries
             (schema-type base)))))
    (when (getf contract :pattern)
      (push (cons "pattern" (getf contract :pattern)) entries))
    (when (getf contract :format)
      (push (cons "format" (getf contract :format)) entries))
    (when (and (member base '("integer" "float") :test #'string=)
               (getf contract :minimum))
      (push (cons "minimum" (getf contract :minimum)) entries))
    (when (and (member base '("integer" "float") :test #'string=)
               (getf contract :maximum))
      (push (cons "maximum" (getf contract :maximum)) entries))
    (starcanonicaljson:make-json-object entries)))

(defun schema-enum-definition (contract)
  (schema-object
   (cons "type" "string")
   (cons "enum" (schema-array (copy-list (getf contract :values))))))

(defun schema-document-definition (manifest contract)
  (let* ((fields (binding-document-fields manifest contract))
         (properties
           (mapcar (lambda (field)
                     (cons (getf field :name) (schema-field field)))
                   fields))
         (required
           (loop for field in fields
                 when (binding-field-required-p field)
                   collect (getf field :name))))
    (schema-object
     (cons "type" "object")
     (cons "properties" (starcanonicaljson:make-json-object properties))
     (cons "required" (schema-array required))
     (cons "additionalProperties" starcanonicaljson:+json-false+))))

(defun schema-definition (manifest contract)
  (case (getf contract :kind)
    (:scalar (schema-scalar-definition contract))
    (:enum (schema-enum-definition contract))
    (:document (schema-document-definition manifest contract))
    (otherwise
     (fail 'invalid-type-error
           "Cannot generate JSON Schema definition for ~S."
           (getf contract :kind)))))

(defun generate-json-schema (manifest)
  "Return deterministic JSON Schema 2020-12 text for MANIFEST."
  (let* ((library (getf manifest :library))
         (name (getf library :name))
         (version (getf library :version))
         (definitions
           (cons
            (cons "StarReference" (schema-reference-definition))
            (mapcar
             (lambda (contract)
               (cons (binding-pascal-name (getf contract :name))
                     (schema-definition manifest contract)))
             (getf manifest :types))))
         (root
           (schema-object
            (cons "$schema" "https://json-schema.org/draft/2020-12/schema")
            (cons "$id" (format nil "https://schemas.starintel.actor/~A/~A/schema.json"
                                name version))
            (cons "title" (format nil "~A ~A" name version))
            (cons "$defs" (starcanonicaljson:make-json-object definitions)))))
    (starcanonicaljson:canonical-json-string root)))
