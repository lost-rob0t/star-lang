(defpackage :starsentocompat
  (:use :cl)
  (:nicknames :star-sento-compat)
  (:export
   #:star-sento-compat-error
   #:unsupported-sento-operation-error
   #:sento-backend-unavailable-error
   #:runtime-port
   #:runtime-port-p
   #:make-runtime-port
   #:runtime-spawn
   #:runtime-tell
   #:runtime-ask
   #:runtime-stop
   #:runtime-watch
   #:runtime-unwatch
   #:runtime-link
   #:runtime-resolve
   #:runtime-mailbox-metrics
   #:runtime-shutdown
   #:sento-backend-available-p
   #:sento-remoting-backend-available-p
   #:sento-make-actor-system
   #:sento-enable-remoting
   #:sento-actor-of
   #:sento-make-remote-ref
   #:sento-tell
   #:sento-stop
   #:sento-disable-remoting
   #:sento-remoting-port
   #:sento-shutdown
   #:make-sento-runtime-port))
