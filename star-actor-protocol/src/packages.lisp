(defpackage :staractorprotocol
  (:use :cl)
  (:nicknames :star-actor-protocol)
  (:export
   #:star-actor-protocol-error
   #:invalid-star-service-uri-error
   #:star-service-uri
   #:star-service-uri-p
   #:star-service-uri-domain
   #:star-service-uri-address
   #:star-service-uri-actor-name
   #:make-star-service-uri
   #:parse-star-service-uri
   #:star-service-uri-string
   #:star-service-uri-target-p
   #:ensure-star-service-uri
   #:canonical-star-service-uri-for-actor))
