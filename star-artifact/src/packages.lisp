(defpackage :starartifact
  (:use :cl)
  (:nicknames :star-artifact)
  (:export
   #:json-file-error
   #:invalid-json-file-record-error
   #:json-file-write-error
   #:json-file-write
   #:json-file-write-p
   #:json-file-write-collection
   #:json-file-write-id
   #:json-file-write-document
   #:make-json-file-write
   #:json-file-result
   #:json-file-result-p
   #:json-file-result-status
   #:json-file-result-collection
   #:json-file-result-id
   #:json-file-result-path
   #:write-json-file-record
   #:make-json-file-writer-actor-definition
   #:create-json-file-writer-actor))
