(defpackage :starcanonicaljson
  (:use :cl)
  (:nicknames :star-canonical-json)
  (:export
   #:star-canonical-json-error
   #:invalid-canonical-json-error
   #:json-object
   #:json-object-p
   #:make-json-object
   #:json-object-entries
   #:json-array
   #:json-array-p
   #:make-json-array
   #:json-array-values
   #:+json-true+
   #:+json-false+
   #:+json-null+
   #:write-canonical-json
   #:canonical-json-string))
