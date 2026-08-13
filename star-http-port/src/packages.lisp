(defpackage :starhttpport
  (:use :cl)
  (:nicknames :star-http-port)
  (:export
   #:http-port-error
   #:http-backend-unavailable-error
   #:http-request-error
   #:http-request
   #:http-request-p
   #:http-request-url
   #:http-request-method
   #:http-request-headers
   #:http-request-body
   #:http-request-connect-timeout
   #:http-request-read-timeout
   #:http-request-max-redirects
   #:make-http-request
   #:http-response
   #:http-response-p
   #:http-response-body
   #:http-response-status
   #:http-response-headers
   #:http-response-final-url
   #:make-http-response
   #:http-response-success-p
   #:http-client
   #:http-client-p
   #:http-client-name
   #:make-http-client
   #:perform-http-request
   #:http-get
   #:make-dexador-http-client))
