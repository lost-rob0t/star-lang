(defpackage :starsentocompat
  (:use :cl)
  (:nicknames :star-sento-compat)
  (:export
   #:star-sento-compat-error
   #:unsupported-sento-operation-error
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
   #:runtime-shutdown))