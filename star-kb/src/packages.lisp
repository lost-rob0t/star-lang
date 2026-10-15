(defpackage :starkb
  (:use :cl)
  (:nicknames :star-kb)
  (:export
   ;; Conditions.
   #:kb-error
   #:kb-error-message
   #:kb-contract-error
   #:kb-backend-error
   #:kb-backend-error-operation
   #:kb-backend-error-backend

   ;; Portable records.
   #:make-kb-entry
   #:make-kb-relation
   #:kb-entry-p
   #:kb-relation-p
   #:kb-record-id
   #:kb-record-namespace
   #:kb-record-dataset
   #:kb-entry-kind
   #:kb-entry-fields
   #:kb-record-metadata
   #:kb-record-provenance
   #:kb-relation-source
   #:kb-relation-predicate
   #:kb-relation-target
   #:kb-field-value

   ;; Store port.
   #:kb-store
   #:kb-store-p
   #:kb-store-name
   #:make-kb-store
   #:kb-put-entry
   #:kb-fetch-entry
   #:kb-delete-entry
   #:kb-find-entries-by-kind
   #:kb-find-entries-by-dataset
   #:kb-find-entries-by-field
   #:kb-put-relation
   #:kb-fetch-relation
   #:kb-delete-relation
   #:kb-find-relations-by-predicate
   #:kb-neighbors
   #:kb-close

   ;; Reference backend.
   #:make-memory-kb-store))
