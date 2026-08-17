(defpackage :starsentocompat-integration-tests
  (:use :cl :fiveam)
  (:import-from :starsentocompat
                #:make-sento-runtime-port
                #:runtime-spawn
                #:runtime-tell
                #:sento-make-actor-system
                #:sento-stop
                #:sento-shutdown)
  (:import-from :starhttpport
                #:http-port-error
                #:http-request
                #:http-request-url
                #:http-request-headers
                #:http-response
                #:http-response-body
                #:http-response-status
                #:http-response-headers
                #:http-response-final-url
                #:make-http-client
                #:make-http-request
                #:make-http-response
                #:perform-http-request
                #:make-dexador-http-client)
  (:export #:run-integration-tests
           #:run-live-smoke-tests))

(in-package :starsentocompat-integration-tests)
