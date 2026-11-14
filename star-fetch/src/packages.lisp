(defpackage :starfetch
  (:use :cl)
  (:nicknames :star-fetch)
  (:export
   #:fetch-error
   #:fetch-request
   #:fetch-request-p
   #:fetch-request-request-id
   #:fetch-request-url
   #:fetch-request-method
   #:fetch-request-headers
   #:fetch-request-body
   #:fetch-request-connect-timeout
   #:fetch-request-read-timeout
   #:fetch-request-max-redirects
   #:fetch-request-cache-mode
   #:fetch-request-ttl-seconds
   #:fetch-request-provenance
   #:make-fetch-request
   #:fetch-result
   #:fetch-result-p
   #:fetch-result-request-id
   #:fetch-result-requested-url
   #:fetch-result-final-url
   #:fetch-result-status
   #:fetch-result-headers
   #:fetch-result-body
   #:fetch-result-fetched-at
   #:fetch-result-transport
   #:fetch-result-cache-status
   #:fetch-result-provenance
   #:fetch-actor-system
   #:fetch-actor-system-p
   #:fetch-actor-system-coordinator
   #:fetch-actor-system-cache
   #:fetch-actor-system-worker
   #:create-fetch-actor-system
   #:invoke-fetch))
