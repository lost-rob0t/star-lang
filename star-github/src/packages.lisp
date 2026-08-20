(defpackage :stargithub
  (:use :cl)
  (:nicknames :star-github)
  (:export
   #:github-target-error
   #:github-target-validation-error
   #:github-enumeration-error
   #:github-run-result
   #:github-run-result-p
   #:github-run-result-status
   #:github-run-result-run-id
   #:github-run-result-target-id
   #:github-run-result-documents-written
   #:github-run-result-error
   #:read-starintel-json-document
   #:github-target-document-p
   #:github-cli-enumerator
   #:run-github-target
   #:make-github-actor-definition
   #:create-github-actor))
