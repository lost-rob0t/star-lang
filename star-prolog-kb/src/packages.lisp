(defpackage :starprologkb
  (:use :cl)
  (:nicknames :star-prolog-kb)
  (:export
   ;; Conditions.
   #:star-prolog-kb-error
   #:star-prolog-kb-error-message
   #:prolog-kb-grammar-error
   #:prolog-kb-schema-error
   #:tek9-unavailable-error

   ;; StarLang grammar IR.
   #:prolog-kb-program
   #:prolog-kb-program-p
   #:prolog-kb-program-name
   #:prolog-kb-program-version
   #:prolog-kb-program-runtime
   #:prolog-kb-program-persistence
   #:prolog-kb-program-protocol
   #:prolog-kb-program-schema
   #:prolog-kb-program-indexes
   #:prolog-kb-program-prolog-blocks
   #:prolog-kb-program-source-map
   #:kb-schema-ref
   #:kb-schema-ref-p
   #:kb-schema-ref-alias
   #:kb-schema-ref-source
   #:kb-schema-ref-version
   #:kb-schema-ref-digest
   #:kb-index-spec
   #:kb-index-spec-p
   #:kb-index-spec-name
   #:kb-index-spec-source
   #:kb-index-spec-selectors
   #:kb-index-spec-kind
   #:kb-index-spec-unique-p
   #:kb-index-spec-multi-valued-p
   #:kb-index-spec-automatic-p
   #:prolog-source-block
   #:prolog-source-block-p
   #:prolog-source-block-name
   #:prolog-source-block-source
   #:prolog-source-block-kind
   #:prolog-source-block-text
   #:prolog-source-block-span
   #:compile-prolog-kb
   #:compile-prolog-kb-source
   #:load-prolog-kb-file

   ;; Schema/index planning.
   #:document-declarations
   #:effective-document-fields
   #:make-auto-index-specs
   #:resolve-index-spec
   #:resolve-index-specs
   #:required-tek9-max-dbs
   #:field-index-name

   ;; Tek9-backed KB lifecycle and data access.
   #:starintel-kb
   #:starintel-kb-p
   #:starintel-kb-program
   #:starintel-kb-spec-ir
   #:starintel-kb-database
   #:starintel-kb-indexes
   #:starintel-kb-graph-name
   #:open-starintel-kb
   #:close-starintel-kb
   #:put-starintel-document
   #:put-starintel-documents
   #:fetch-starintel-document
   #:delete-starintel-document
   #:query-field
   #:query-index
   #:define-index
   #:list-indexes

   ;; Prolog materialization.
   #:write-prolog-snapshot
   #:prolog-snapshot-string))