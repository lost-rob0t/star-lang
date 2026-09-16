(defpackage :starhttpdexador
  (:use :cl)
  (:nicknames :star-http-dexador)
  (:import-from :cl+ssl
                #:ssl-error-initialize
                #:ssl-error-verify)
  (:import-from :dexador
                #:http-request-failed
                #:request
                #:request-uri
                #:response-body
                #:response-headers
                #:response-status)
  (:import-from :fast-http.error
                #:fast-http-error)
  (:import-from :starhttpport
                #:http-request-body
                #:http-request-connect-timeout
                #:http-request-headers
                #:http-request-max-redirects
                #:http-request-method
                #:http-request-read-timeout
                #:http-request-url
                #:http-transport-error
                #:make-http-client
                #:make-http-response)
  (:import-from :usocket
                #:socket-error
                #:timeout-error)
  (:export #:make-dexador-http-client))
