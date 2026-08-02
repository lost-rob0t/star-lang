(require :asdf)

(unless (find-package "STAR-LANG.DOCUMENT-RUNTIME")
  (load (merge-pathnames "document-runtime.lisp" *load-truename*)))

(defpackage #:star-lang.relation-compatibility
  (:use #:cl)
  (:export
   #:legacy-relation-target-warning
   #:legacy-relation-target-warning-document-type
   #:relation-compatibility-installed-p))

(in-package #:star-lang.relation-compatibility)

(define-condition legacy-relation-target-warning (warning)
  ((document-type
    :initarg :document-type
    :reader legacy-relation-target-warning-document-type))
  (:report
   (lambda (condition stream)
     (format stream
             "Relation ~A uses deprecated field target; normalized it to destination."
             (legacy-relation-target-warning-document-type condition)))))

(defparameter *runtime-metadata-fields*
  '("id"
    "dataset"
    "dtype"
    "schema-version"
    "created-at"
    "date-added"
    "updated-at"
    "date-updated"))

(defvar *installed-p* nil)
(defvar *base-create-document* nil)
(defvar *base-decode-document* nil)

(defun relation-compatibility-installed-p ()
  *installed-p*)

(defun map-entry (values key)
  (assoc key values :test #'string=))

(defun map-has-key-p (values key)
  (not (null (map-entry values key))))

(defun map-value (values key)
  (cdr (map-entry values key)))

(defun map-remove (values key)
  (remove key values :key #'car :test #'string=))

(defun map-set (values key value)
  (acons key value (map-remove values key)))

(defun contract-has-field-p (contract name)
  (not
   (null
    (find name
          (star-lang.document-runtime:document-contract-fields contract)
          :key (lambda (field) (getf field :name))
          :test #'string=))))

(defun relation-contract-p (contract)
  (and (contract-has-field-p contract "source")
       (contract-has-field-p contract "predicate")
       (or (contract-has-field-p contract "destination")
           (contract-has-field-p contract "target"))))

(defun relation-endpoint-field (contract)
  (when (relation-contract-p contract)
    (let ((destination-p (contract-has-field-p contract "destination"))
          (target-p (contract-has-field-p contract "target")))
      (cond
        ((and destination-p target-p)
         (star-lang.document-runtime::fail-runtime
          'star-lang.document-runtime::invalid-document-error
          "Relation contract ~A declares both destination and target."
          (star-lang.document-runtime:document-contract-qualified-name contract)))
        (destination-p "destination")
        (target-p "target")
        (t nil)))))

(defun warn-about-legacy-target (contract)
  (warn 'legacy-relation-target-warning
        :document-type
        (star-lang.document-runtime:document-contract-qualified-name contract)))

(defun normalize-relation-values (contract input)
  (let* ((values (star-lang.document-runtime::normalize-input-map input))
         (endpoint (relation-endpoint-field contract)))
    (if (null endpoint)
        values
        (let* ((alternate
                 (if (string= endpoint "destination") "target" "destination"))
               (endpoint-p (map-has-key-p values endpoint))
               (alternate-p (map-has-key-p values alternate)))
          (when (and endpoint-p alternate-p
                     (not (equal (map-value values endpoint)
                                 (map-value values alternate))))
            (star-lang.document-runtime::fail-runtime
             'star-lang.document-runtime::invalid-document-error
             "Relation ~A received conflicting destination and target values."
             (star-lang.document-runtime:document-contract-qualified-name contract)))
          (cond
            ((and endpoint-p alternate-p)
             (when (string= alternate "target")
               (warn-about-legacy-target contract))
             (map-remove values alternate))
            (alternate-p
             (when (string= alternate "target")
               (warn-about-legacy-target contract))
             (map-set (map-remove values alternate)
                      endpoint
                      (map-value values alternate)))
            (t values))))))

(defun remove-undeclared-generated-metadata (contract document input-values)
  (let ((values
          (star-lang.document-runtime:document-instance-values document)))
    (dolist (field *runtime-metadata-fields*)
      (when (and (not (contract-has-field-p contract field))
                 (not (map-has-key-p input-values field)))
        (setf values (map-remove values field))))
    (setf (star-lang.document-runtime:document-instance-values document) values)
    document))

(defun compatible-create-document (graph document-type values
                                    &key dataset (validate t))
  (let* ((contract
           (star-lang.document-runtime:compile-document-contract
            graph document-type))
         (normalized-values
           (normalize-relation-values contract values))
         (document
           (funcall *base-create-document*
                    graph
                    document-type
                    normalized-values
                    :dataset dataset
                    :validate nil)))
    (remove-undeclared-generated-metadata
     contract document normalized-values)
    (when validate
      (star-lang.document-runtime:validate-document
       graph document contract))
    document))

(defun compatible-decode-document (graph document-type encoded
                                    &key dataset (key-style :camel) (couchdb t))
  (let ((contract
          (star-lang.document-runtime:compile-document-contract
           graph document-type)))
    (funcall *base-decode-document*
             graph
             document-type
             (normalize-relation-values contract encoded)
             :dataset dataset
             :key-style key-style
             :couchdb couchdb)))

(defun compatible-relate-documents (graph source destination
                                    &key
                                      (relation-type "relation")
                                      (predicate "related-to")
                                      note
                                      dataset)
  (unless (and (typep source 'star-lang.document-runtime:document-instance)
               (typep destination 'star-lang.document-runtime:document-instance))
    (star-lang.document-runtime::fail-runtime
     'star-lang.document-runtime::invalid-document-error
     "relate-documents requires document instances."))
  (star-lang.document-runtime:create-document
   graph
   relation-type
   (list
    (cons "source" (star-lang.document-runtime:document-value source "id"))
    (cons "destination"
          (star-lang.document-runtime:document-value destination "id"))
    (cons "predicate" predicate)
    (cons "note" (or note "")))
   :dataset
   (or dataset
       (star-lang.document-runtime:document-value source "dataset")
       (star-lang.document-runtime:document-value destination "dataset"))))

(defun install-relation-compatibility ()
  (unless *installed-p*
    (setf *base-create-document*
          (symbol-function 'star-lang.document-runtime:create-document)
          *base-decode-document*
          (symbol-function 'star-lang.document-runtime:decode-document)
          (symbol-function 'star-lang.document-runtime:create-document)
          #'compatible-create-document
          (symbol-function 'star-lang.document-runtime:decode-document)
          #'compatible-decode-document
          (symbol-function 'star-lang.document-runtime:relate-documents)
          #'compatible-relate-documents
          *installed-p* t))
  t)

(install-relation-compatibility)
