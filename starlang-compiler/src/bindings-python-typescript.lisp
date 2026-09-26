;;;; Python and TypeScript portable binding generation.

(in-package #:star-lang.compiler.core)

(defun python-type-expression (type)
  (cond
    ((and (listp type) (eq (first type) :list) (= (length type) 2))
     (format nil "list[~A]" (python-type-expression (second type))))
    ((and (listp type) (eq (first type) :optional) (= (length type) 2))
     (format nil "~A | None" (python-type-expression (second type))))
    ((not (stringp type))
     (fail 'invalid-type-error "Cannot generate Python type for ~S." type))
    ((string= type "any") "Any")
    ((member type '("string" "symbol" "iso-date" "iso-datetime" "decimal")
             :test #'string=)
     "str")
    ((string= type "float") "float")
    ((string= type "integer") "int")
    ((string= type "boolean") "bool")
    ((string= type "map") "dict[str, Any]")
    ((string= type "reference") "StarReference")
    (t (binding-pascal-name type))))

(defun typescript-type-expression (type)
  (cond
    ((and (listp type) (eq (first type) :list) (= (length type) 2))
     (format nil "Array<~A>" (typescript-type-expression (second type))))
    ((and (listp type) (eq (first type) :optional) (= (length type) 2))
     (format nil "~A | null" (typescript-type-expression (second type))))
    ((not (stringp type))
     (fail 'invalid-type-error "Cannot generate TypeScript type for ~S." type))
    ((string= type "any") "unknown")
    ((member type '("string" "symbol" "iso-date" "iso-datetime" "decimal")
             :test #'string=)
     "string")
    ((member type '("integer" "float") :test #'string=) "number")
    ((string= type "boolean") "boolean")
    ((string= type "map") "Record<string, unknown>")
    ((string= type "reference") "StarReference")
    (t (binding-pascal-name type))))

(defun write-python-typed-dict (stream name fields)
  (format stream "~A = TypedDict(~A, {~%"
          name (binding-source-string name))
  (dolist (field fields)
    (format stream "    ~A: ~A[~A],~%"
            (binding-source-string (getf field :name))
            (if (binding-field-required-p field) "Required" "NotRequired")
            (python-type-expression (getf field :type))))
  (format stream "})~%~%"))

(defun write-python-string-list (stream values)
  (write-char #\[ stream)
  (loop for value in values
        for first-p = t then nil
        do (unless first-p (write-string ", " stream))
           (write-string (binding-source-string value) stream))
  (write-char #\] stream))

(defun write-python-actor-contracts (stream actors)
  (format stream "ACTOR_CONTRACTS: dict[str, dict[str, object]] = {~%")
  (dolist (actor actors)
    (format stream "    ~A: {~%" (binding-source-string (getf actor :name)))
    (format stream "        \"runtime\": ~A,~%"
            (binding-source-string
             (staractorprotocol:portable-wire-identifier-string
              (getf actor :runtime))))
    (when (getf actor :protocol)
      (format stream "        \"protocol\": ~A,~%"
              (binding-source-string (getf actor :protocol))))
    (when (getf actor :endpoint)
      (format stream "        \"endpoint\": ~A,~%"
              (binding-source-string (getf actor :endpoint))))
    (write-string "        \"accepts\": " stream)
    (write-python-string-list stream (getf actor :accepts))
    (format stream ",~%        \"produces\": ")
    (write-python-string-list stream (getf actor :produces))
    (format stream ",~%    },~%"))
  (format stream "}~%"))

(defun generate-python-bindings (manifest)
  (with-output-to-string (stream)
    (format stream "# Generated from StarLang portable manifest. DO NOT EDIT.~%")
    (format stream "from __future__ import annotations~%~%")
    (format stream "from typing import Any, Literal, NotRequired, Required, TypedDict~%~%")
    (format stream "class StarReference(TypedDict):~%    schema: str~%    id: str~%~%")
    (dolist (contract (getf manifest :types))
      (case (getf contract :kind)
        (:scalar
         (format stream "~A = ~A~%~%"
                 (binding-pascal-name (getf contract :name))
                 (python-type-expression (getf contract :base))))
        (:enum
         (format stream "~A = Literal[~{~A~^, ~}]~%~%"
                 (binding-pascal-name (getf contract :name))
                 (mapcar #'binding-source-string (getf contract :values))))
        (:document
         (write-python-typed-dict
          stream
          (binding-pascal-name (getf contract :name))
          (binding-document-fields manifest contract)))))
    (dolist (message (binding-message-contracts manifest))
      (write-python-typed-dict
       stream
       (binding-pascal-name (getf message :name))
       (getf message :fields)))
    (write-python-actor-contracts stream (getf manifest :actors))))

(defun write-typescript-interface (stream name fields &optional extends)
  (format stream "export interface ~A~@[ extends ~A~] {~%" name extends)
  (dolist (field fields)
    (format stream "  ~A~:[?~;~]: ~A;~%"
            (binding-source-string (getf field :name))
            (binding-field-required-p field)
            (typescript-type-expression (getf field :type))))
  (format stream "}~%~%"))

(defun write-typescript-string-array (stream values)
  (write-char #\[ stream)
  (loop for value in values
        for first-p = t then nil
        do (unless first-p (write-string ", " stream))
           (write-string (binding-source-string value) stream))
  (write-char #\] stream))

(defun write-typescript-actor-contracts (stream actors)
  (format stream "export const actorContracts = {~%")
  (dolist (actor actors)
    (format stream "  ~A: {~%" (binding-source-string (getf actor :name)))
    (format stream "    runtime: ~A,~%"
            (binding-source-string
             (staractorprotocol:portable-wire-identifier-string
              (getf actor :runtime))))
    (when (getf actor :protocol)
      (format stream "    protocol: ~A,~%"
              (binding-source-string (getf actor :protocol))))
    (when (getf actor :endpoint)
      (format stream "    endpoint: ~A,~%"
              (binding-source-string (getf actor :endpoint))))
    (write-string "    accepts: " stream)
    (write-typescript-string-array stream (getf actor :accepts))
    (format stream ",~%    produces: ")
    (write-typescript-string-array stream (getf actor :produces))
    (format stream ",~%  },~%"))
  (format stream "} as const;~%"))

(defun generate-typescript-bindings (manifest)
  (with-output-to-string (stream)
    (format stream "// Generated from StarLang portable manifest. DO NOT EDIT.~%~%")
    (format stream "export interface StarReference {~%  schema: string;~%  id: string;~%}~%~%")
    (dolist (contract (getf manifest :types))
      (case (getf contract :kind)
        (:scalar
         (format stream "export type ~A = ~A;~%~%"
                 (binding-pascal-name (getf contract :name))
                 (typescript-type-expression (getf contract :base))))
        (:enum
         (format stream "export type ~A = ~{~A~^ | ~};~%~%"
                 (binding-pascal-name (getf contract :name))
                 (mapcar #'binding-source-string (getf contract :values))))
        (:document
         (write-typescript-interface
          stream
          (binding-pascal-name (getf contract :name))
          (getf contract :fields)
          (and (getf contract :extends)
               (binding-pascal-name (getf contract :extends)))))))
    (dolist (message (binding-message-contracts manifest))
      (write-typescript-interface
       stream
       (binding-pascal-name (getf message :name))
       (getf message :fields)))
    (write-typescript-actor-contracts stream (getf manifest :actors))))
