;;;; Common Lisp, Emacs Lisp, Prolog, and binding dispatch.

(in-package #:star-lang.compiler.core)

(defun common-lisp-type-expression (type)
  (cond
    ((and (listp type) (eq (first type) :list) (= (length type) 2)) 'list)
    ((and (listp type) (eq (first type) :optional) (= (length type) 2))
     (common-lisp-type-expression (second type)))
    ((not (stringp type))
     (fail 'invalid-type-error "Cannot generate Common Lisp type for ~S." type))
    ((member type '("string" "symbol" "iso-date" "iso-datetime" "decimal")
             :test #'string=) 'string)
    ((string= type "integer") 'integer)
    ((string= type "float") 'double-float)
    ((string= type "boolean") 'boolean)
    ((string= type "map") 'hash-table)
    ((string= type "any") 't)
    ((string= type "reference") 'star-reference)
    (t (intern (string-upcase (binding-kebab-name type)) :keyword))))

(defun write-common-lisp-struct (stream name fields)
  (let ((lisp-name (binding-kebab-name name)))
    (format stream "(defstruct ~A~%" lisp-name)
    (dolist (field fields)
      (format stream "  (~A nil))~%"
              (binding-kebab-name (getf field :name))))
    (format stream ")~%")
    (format stream "(defparameter +~A-wire-fields+~%  '(~%"
            lisp-name)
    (dolist (field fields)
      (format stream "    (~A . ~A)~%"
              (binding-source-string (getf field :name))
              (binding-kebab-name (getf field :name))))
    (format stream "  ))~%~%")))

(defun generate-common-lisp-bindings (manifest)
  (with-output-to-string (stream)
    (binding-write-lisp-header stream :common-lisp)
    (format stream "(defstruct star-reference schema id)~%~%")
    (dolist (contract (getf manifest :types))
      (case (getf contract :kind)
        (:scalar
         (format stream "(deftype ~A () '~A)~%~%"
                 (binding-kebab-name (getf contract :name))
                 (string-downcase
                  (symbol-name
                   (common-lisp-type-expression (getf contract :base))))))
        (:enum
         (format stream "(deftype ~A () '(member~{ ~A~}))~%~%"
                 (binding-kebab-name (getf contract :name))
                 (mapcar #'binding-source-string (getf contract :values))))
        (:document
         (write-common-lisp-struct
          stream
          (getf contract :name)
          (binding-document-fields manifest contract)))))
    (dolist (message (binding-message-contracts manifest))
      (write-common-lisp-struct stream
                                (getf message :name)
                                (getf message :fields)))))

(defun write-emacs-lisp-struct (stream name fields)
  (let ((el-name (format nil "starintel-~A" (binding-kebab-name name))))
    (format stream "(cl-defstruct (~A (:constructor ~A-create))~%" el-name el-name)
    (dolist (field fields)
      (format stream "  ~A~%" (binding-kebab-name (getf field :name))))
    (format stream ")~%")
    (format stream "(defconst ~A-wire-fields~%  '(~%" el-name)
    (dolist (field fields)
      (format stream "    (~A . ~A)~%"
              (binding-source-string (getf field :name))
              (binding-kebab-name (getf field :name))))
    (format stream "  ))~%~%")))

(defun generate-emacs-lisp-bindings (manifest)
  (with-output-to-string (stream)
    (format stream ";;; Generated from StarLang portable manifest. DO NOT EDIT. -*- lexical-binding: t; -*-~%~%")
    (format stream "(require 'cl-lib)~%~%")
    (format stream "(cl-defstruct (starintel-reference (:constructor starintel-reference-create)) schema id)~%~%")
    (dolist (contract (getf manifest :types))
      (case (getf contract :kind)
        (:scalar
         (format stream "(defconst starintel-~A-type ~A)~%~%"
                 (binding-kebab-name (getf contract :name))
                 (binding-source-string (getf contract :base))))
        (:enum
         (format stream "(defconst starintel-~A-values '~S)~%~%"
                 (binding-kebab-name (getf contract :name))
                 (getf contract :values)))
        (:document
         (write-emacs-lisp-struct
          stream
          (getf contract :name)
          (binding-document-fields manifest contract)))))
    (dolist (message (binding-message-contracts manifest))
      (write-emacs-lisp-struct stream
                               (getf message :name)
                               (getf message :fields)))
    (format stream "(provide 'starintel-bindings)~%")))

(defun prolog-type-term (type)
  (cond
    ((and (listp type) (eq (first type) :list) (= (length type) 2))
     (format nil "list(~A)" (prolog-type-term (second type))))
    ((and (listp type) (eq (first type) :optional) (= (length type) 2))
     (format nil "optional(~A)" (prolog-type-term (second type))))
    ((stringp type) (binding-prolog-atom type))
    (t (binding-prolog-atom (princ-to-string type)))))

(defun write-prolog-fields (stream owner fields)
  (dolist (field fields)
    (format stream "star_field(~A, ~A, ~A, ~A).~%"
            (binding-prolog-atom owner)
            (binding-prolog-atom (getf field :name))
            (prolog-type-term (getf field :type))
            (if (binding-field-required-p field) "required" "optional"))))

(defun generate-prolog-bindings (manifest)
  (with-output-to-string (stream)
    (binding-write-prolog-header stream)
    (format stream "star_reference_type(star_reference).~%")
    (dolist (contract (getf manifest :types))
      (case (getf contract :kind)
        (:scalar
         (format stream "star_scalar(~A, ~A).~%"
                 (binding-prolog-atom (getf contract :name))
                 (binding-prolog-atom (getf contract :base))))
        (:enum
         (format stream "star_enum(~A).~%"
                 (binding-prolog-atom (getf contract :name)))
         (dolist (value (getf contract :values))
           (format stream "star_enum_value(~A, ~A).~%"
                   (binding-prolog-atom (getf contract :name))
                   (binding-prolog-atom value))))
        (:document
         (format stream "star_document(~A).~%"
                 (binding-prolog-atom (getf contract :name)))
         (when (getf contract :extends)
           (format stream "star_extends(~A, ~A).~%"
                   (binding-prolog-atom (getf contract :name))
                   (binding-prolog-atom (getf contract :extends))))
         (write-prolog-fields stream
                              (getf contract :name)
                              (binding-document-fields manifest contract)))))
    (dolist (message (binding-message-contracts manifest))
      (format stream "star_message(~A).~%"
              (binding-prolog-atom (getf message :name)))
      (write-prolog-fields stream
                           (getf message :name)
                           (getf message :fields)))))

(defun generate-bindings (manifest language)
  (ecase language
    (:common-lisp (generate-common-lisp-bindings manifest))
    (:kotlin (generate-kotlin-bindings manifest))
    (:java (generate-java-bindings manifest))
    (:python (generate-python-bindings manifest))
    (:typescript (generate-typescript-bindings manifest))
    (:nim (generate-nim-bindings manifest))
    (:go (generate-go-bindings manifest))
    (:rust (generate-rust-bindings manifest))
    (:emacs-lisp (generate-emacs-lisp-bindings manifest))
    (:prolog (generate-prolog-bindings manifest))))

(defun generate-all-bindings (manifest)
  (mapcar (lambda (language)
            (cons language (generate-bindings manifest language)))
          +portable-binding-languages+))
