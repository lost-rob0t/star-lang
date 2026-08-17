(defpackage :starsentocompat-integration-tests
  (:use :cl :fiveam)
  (:import-from :bordeaux-threads
                #:join-thread
                #:make-thread)
  (:import-from :starsentocompat
                #:make-sento-runtime-port
                #:runtime-ask
                #:runtime-resolve
                #:runtime-shutdown
                #:runtime-spawn
                #:runtime-stop
                #:runtime-tell
                #:sento-actor-live-p
                #:sento-all-actors
                #:sento-ask-failure-error
                #:sento-future-complete-p
                #:sento-future-result
                #:sento-make-actor-system
                #:sento-reply
                #:sento-shutdown
                #:star-sento-compat-error))
