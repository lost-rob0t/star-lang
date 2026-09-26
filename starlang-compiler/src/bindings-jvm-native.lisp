;;;; Kotlin, Java, Nim, Go, and Rust portable binding generation.

(in-package #:star-lang.compiler.core)

(defun kotlin-type-expression (type)
  (cond
    ((and (listp type) (eq (first type) :list) (= (length type) 2))
     (format nil "List<~A>" (kotlin-type-expression (second type))))
    ((and (listp type) (eq (first type) :optional) (= (length type) 2))
     (format nil "~A?" (kotlin-type-expression (second type))))
    ((not (stringp type))
     (fail 'invalid-type-error "Cannot generate Kotlin type for ~S." type))
    ((member type '("string" "symbol" "iso-date" "iso-datetime" "decimal")
             :test #'string=) "String")
    ((string= type "integer") "Long")
    ((string= type "float") "Double")
    ((string= type "boolean") "Boolean")
    ((string= type "map") "Map<String, Any?>")
    ((string= type "any") "Any?")
    ((string= type "reference") "StarReference")
    (t (binding-pascal-name type))))

(defun write-kotlin-record (stream name fields)
  (format stream "data class ~A(~%" name)
  (loop for field in fields
        for tail on fields
        for required = (binding-field-required-p field)
        for type = (kotlin-type-expression (getf field :type))
        do (format stream "    val ~A: ~A~A~A~%"
                   (format nil "`~A`" (getf field :name))
                   type
                   (if required "" "?")
                   (if required
                       (if (rest tail) "," "")
                       (format nil " = null~A" (if (rest tail) "," "")))))
  (format stream ")~%~%"))

(defun generate-kotlin-bindings (manifest)
  (with-output-to-string (stream)
    (format stream "// Generated from StarLang portable manifest. DO NOT EDIT.~%~%")
    (format stream "data class StarReference(val schema: String, val id: String)~%~%")
    (dolist (contract (getf manifest :types))
      (case (getf contract :kind)
        (:scalar
         (format stream "typealias ~A = ~A~%~%"
                 (binding-pascal-name (getf contract :name))
                 (kotlin-type-expression (getf contract :base))))
        (:enum
         (format stream "enum class ~A(val wireValue: String) {~%"
                 (binding-pascal-name (getf contract :name)))
         (loop for value in (getf contract :values)
               for tail on (getf contract :values)
               do (format stream "    ~A(~A)~A~%"
                          (binding-pascal-name value)
                          (binding-source-string value)
                          (if (rest tail) "," ";")))
         (format stream "}~%~%"))
        (:document
         (write-kotlin-record
          stream
          (binding-pascal-name (getf contract :name))
          (binding-document-fields manifest contract)))))
    (dolist (message (binding-message-contracts manifest))
      (write-kotlin-record stream
                           (binding-pascal-name (getf message :name))
                           (getf message :fields)))))

(defparameter +java-reserved-words+
  '("abstract" "assert" "boolean" "break" "byte" "case" "catch" "char"
    "class" "const" "continue" "default" "do" "double" "else" "enum"
    "extends" "final" "finally" "float" "for" "goto" "if" "implements"
    "import" "instanceof" "int" "interface" "long" "native" "new" "package"
    "private" "protected" "public" "return" "short" "static" "strictfp"
    "super" "switch" "synchronized" "this" "throw" "throws" "transient"
    "try" "void" "volatile" "while" "record" "sealed" "permits" "var"
    "yield"))

(defun java-field-name (name)
  (if (member name +java-reserved-words+ :test #'string=)
      (format nil "field~A" (binding-pascal-name name))
      name))

(defun java-type-expression (type)
  (cond
    ((and (listp type) (eq (first type) :list) (= (length type) 2))
     (format nil "List<~A>" (java-type-expression (second type))))
    ((and (listp type) (eq (first type) :optional) (= (length type) 2))
     (java-type-expression (second type)))
    ((not (stringp type))
     (fail 'invalid-type-error "Cannot generate Java type for ~S." type))
    ((member type '("string" "symbol" "iso-date" "iso-datetime" "decimal")
             :test #'string=) "String")
    ((string= type "integer") "Long")
    ((string= type "float") "Double")
    ((string= type "boolean") "Boolean")
    ((string= type "map") "Map<String, Object>")
    ((string= type "any") "Object")
    ((string= type "reference") "StarReference")
    (t (binding-pascal-name type))))

(defun write-java-record (stream name fields)
  (format stream "    public record ~A(~%" name)
  (loop for field in fields
        for tail on fields
        do (format stream "        ~A ~A~A~%"
                   (java-type-expression (getf field :type))
                   (java-field-name (getf field :name))
                   (if (rest tail) "," "")))
  (format stream "    ) {}~%~%"))

(defun generate-java-bindings (manifest)
  (with-output-to-string (stream)
    (format stream "// Generated from StarLang portable manifest. DO NOT EDIT.~%")
    (format stream "import java.util.List;~%import java.util.Map;~%~%")
    (format stream "public final class StarIntelBindings {~%")
    (format stream "    private StarIntelBindings() {}~%~%")
    (format stream "    public record StarReference(String schema, String id) {}~%~%")
    (dolist (contract (getf manifest :types))
      (case (getf contract :kind)
        (:scalar
         (format stream "    public record ~A(~A value) {}~%~%"
                 (binding-pascal-name (getf contract :name))
                 (java-type-expression (getf contract :base))))
        (:enum
         (format stream "    public enum ~A {~%"
                 (binding-pascal-name (getf contract :name)))
         (loop for value in (getf contract :values)
               for tail on (getf contract :values)
               do (format stream "        ~A(~A)~A~%"
                          (binding-upper-snake-name value)
                          (binding-source-string value)
                          (if (rest tail) "," ";")))
         (format stream "        public final String wireValue;~%")
         (format stream "        ~A(String wireValue) { this.wireValue = wireValue; }~%"
                 (binding-pascal-name (getf contract :name)))
         (format stream "    }~%~%"))
        (:document
         (write-java-record stream
                            (binding-pascal-name (getf contract :name))
                            (binding-document-fields manifest contract)))))
    (dolist (message (binding-message-contracts manifest))
      (write-java-record stream
                         (binding-pascal-name (getf message :name))
                         (getf message :fields)))
    (format stream "}~%")))

(defun nim-type-expression (type)
  (cond
    ((and (listp type) (eq (first type) :list) (= (length type) 2))
     (format nil "seq[~A]" (nim-type-expression (second type))))
    ((and (listp type) (eq (first type) :optional) (= (length type) 2))
     (format nil "Option[~A]" (nim-type-expression (second type))))
    ((not (stringp type))
     (fail 'invalid-type-error "Cannot generate Nim type for ~S." type))
    ((member type '("string" "symbol" "iso-date" "iso-datetime" "decimal")
             :test #'string=) "string")
    ((string= type "integer") "int64")
    ((string= type "float") "float64")
    ((string= type "boolean") "bool")
    ((member type '("map" "any") :test #'string=) "JsonNode")
    ((string= type "reference") "StarReference")
    (t (binding-pascal-name type))))

(defun write-nim-object (stream name fields)
  (format stream "  ~A* = object~%" name)
  (if fields
      (dolist (field fields)
        (format stream "    `~A`*: ~A~A~%"
                (getf field :name)
                (if (binding-field-required-p field) "" "Option[")
                (if (binding-field-required-p field)
                    (nim-type-expression (getf field :type))
                    (format nil "~A]" (nim-type-expression (getf field :type))))))
      (format stream "    discard~%"))
  (terpri stream))

(defun generate-nim-bindings (manifest)
  (with-output-to-string (stream)
    (format stream "## Generated from StarLang portable manifest. DO NOT EDIT.~%")
    (format stream "import std/[json, options]~%~%")
    (format stream "type~%  StarReference* = object~%    schema*: string~%    id*: string~%~%")
    (dolist (contract (getf manifest :types))
      (case (getf contract :kind)
        (:scalar
         (format stream "  ~A* = distinct ~A~%"
                 (binding-pascal-name (getf contract :name))
                 (nim-type-expression (getf contract :base))))
        (:enum
         (format stream "  ~A* = distinct string~%"
                 (binding-pascal-name (getf contract :name))))
        (:document
         (write-nim-object stream
                           (binding-pascal-name (getf contract :name))
                           (binding-document-fields manifest contract)))))
    (terpri stream)
    (dolist (contract (binding-contracts manifest :enum))
      (dolist (value (getf contract :values))
        (format stream "const ~A~A* = ~A(~A)~%"
                (binding-pascal-name (getf contract :name))
                (binding-pascal-name value)
                (binding-pascal-name (getf contract :name))
                (binding-source-string value))))
    (terpri stream)
    (dolist (message (binding-message-contracts manifest))
      (format stream "type~%")
      (write-nim-object stream
                        (binding-pascal-name (getf message :name))
                        (getf message :fields)))))

(defun go-type-expression (type)
  (cond
    ((and (listp type) (eq (first type) :list) (= (length type) 2))
     (format nil "[]~A" (go-type-expression (second type))))
    ((and (listp type) (eq (first type) :optional) (= (length type) 2))
     (go-type-expression (second type)))
    ((not (stringp type))
     (fail 'invalid-type-error "Cannot generate Go type for ~S." type))
    ((member type '("string" "symbol" "iso-date" "iso-datetime" "decimal")
             :test #'string=) "string")
    ((string= type "integer") "int64")
    ((string= type "float") "float64")
    ((string= type "boolean") "bool")
    ((member type '("map" "any") :test #'string=) "map[string]any")
    ((string= type "reference") "StarReference")
    (t (binding-pascal-name type))))

(defun write-go-struct (stream name fields)
  (format stream "type ~A struct {~%" name)
  (dolist (field fields)
    (format stream "    ~A ~A `json:\"~A~A\"`~%"
            (binding-pascal-name (getf field :name))
            (if (binding-field-required-p field)
                (go-type-expression (getf field :type))
                (format nil "*~A" (go-type-expression (getf field :type))))
            (getf field :name)
            (if (binding-field-required-p field) "" ",omitempty")))
  (format stream "}~%~%"))

(defun generate-go-bindings (manifest)
  (with-output-to-string (stream)
    (format stream "// Code generated from StarLang portable manifest. DO NOT EDIT.~%")
    (format stream "package starintel~%~%")
    (format stream "type StarReference struct {~%    Schema string `json:\"schema\"`~%    ID string `json:\"id\"`~%}~%~%")
    (dolist (contract (getf manifest :types))
      (case (getf contract :kind)
        (:scalar
         (format stream "type ~A ~A~%~%"
                 (binding-pascal-name (getf contract :name))
                 (go-type-expression (getf contract :base))))
        (:enum
         (format stream "type ~A string~%~%const (~%"
                 (binding-pascal-name (getf contract :name)))
         (dolist (value (getf contract :values))
           (format stream "    ~A~A ~A = ~A~%"
                   (binding-pascal-name (getf contract :name))
                   (binding-pascal-name value)
                   (binding-pascal-name (getf contract :name))
                   (binding-source-string value)))
         (format stream ")~%~%"))
        (:document
         (write-go-struct stream
                          (binding-pascal-name (getf contract :name))
                          (binding-document-fields manifest contract)))))
    (dolist (message (binding-message-contracts manifest))
      (write-go-struct stream
                       (binding-pascal-name (getf message :name))
                       (getf message :fields)))))

(defparameter +rust-reserved-words+
  '("as" "break" "const" "continue" "crate" "else" "enum" "extern" "false"
    "fn" "for" "if" "impl" "in" "let" "loop" "match" "mod" "move" "mut"
    "pub" "ref" "return" "self" "Self" "static" "struct" "super" "trait"
    "true" "type" "unsafe" "use" "where" "while" "async" "await" "dyn"))

(defun rust-field-name (name)
  (let ((snake (binding-snake-name name)))
    (if (member snake +rust-reserved-words+ :test #'string=)
        (format nil "field_~A" snake)
        snake)))

(defun rust-type-expression (type)
  (cond
    ((and (listp type) (eq (first type) :list) (= (length type) 2))
     (format nil "Vec<~A>" (rust-type-expression (second type))))
    ((and (listp type) (eq (first type) :optional) (= (length type) 2))
     (format nil "Option<~A>" (rust-type-expression (second type))))
    ((not (stringp type))
     (fail 'invalid-type-error "Cannot generate Rust type for ~S." type))
    ((member type '("string" "symbol" "iso-date" "iso-datetime" "decimal")
             :test #'string=) "String")
    ((string= type "integer") "i64")
    ((string= type "float") "f64")
    ((string= type "boolean") "bool")
    ((string= type "map") "BTreeMap<String, serde_json::Value>")
    ((string= type "any") "serde_json::Value")
    ((string= type "reference") "StarReference")
    (t (binding-pascal-name type))))

(defun write-rust-struct (stream name fields)
  (format stream "#[derive(Clone, Debug, Serialize, Deserialize)]~%pub struct ~A {~%" name)
  (dolist (field fields)
    (let* ((required (binding-field-required-p field))
           (wire-name (getf field :name))
           (field-name (rust-field-name wire-name))
           (type (rust-type-expression (getf field :type))))
      (format stream "    #[serde(rename = ~A~A)]~%"
              (binding-source-string wire-name)
              (if required "" ", skip_serializing_if = \"Option::is_none\""))
      (format stream "    pub ~A: ~A,~%"
              field-name
              (if required type (format nil "Option<~A>" type)))))
  (format stream "}~%~%"))

(defun generate-rust-bindings (manifest)
  (with-output-to-string (stream)
    (format stream "// Generated from StarLang portable manifest. DO NOT EDIT.~%")
    (format stream "use serde::{Deserialize, Serialize};~%use std::collections::BTreeMap;~%~%")
    (format stream "#[derive(Clone, Debug, Serialize, Deserialize)]~%")
    (format stream "pub struct StarReference { pub schema: String, pub id: String }~%~%")
    (dolist (contract (getf manifest :types))
      (case (getf contract :kind)
        (:scalar
         (format stream "pub type ~A = ~A;~%~%"
                 (binding-pascal-name (getf contract :name))
                 (rust-type-expression (getf contract :base))))
        (:enum
         (format stream "#[derive(Clone, Debug, Serialize, Deserialize)]~%pub enum ~A {~%"
                 (binding-pascal-name (getf contract :name)))
         (dolist (value (getf contract :values))
           (format stream "    #[serde(rename = ~A)] ~A,~%"
                   (binding-source-string value)
                   (binding-pascal-name value)))
         (format stream "}~%~%"))
        (:document
         (write-rust-struct stream
                            (binding-pascal-name (getf contract :name))
                            (binding-document-fields manifest contract)))))
    (dolist (message (binding-message-contracts manifest))
      (write-rust-struct stream
                         (binding-pascal-name (getf message :name))
                         (getf message :fields)))))
