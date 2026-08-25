(defpackage :starprocessport
  (:use :cl)
  (:nicknames :star-process-port)
  (:export
   #:process-port-error
   #:invalid-process-command-error
   #:process-launch-error
   #:process-disposal-error
   #:managed-process
   #:managed-process-p
   #:launch-process
   #:process-stdin
   #:process-stdout
   #:process-stderr
   #:process-alive-p
   #:process-reaped-p
   #:process-exit-code
   #:wait-process
   #:terminate-process
   #:kill-process
   #:dispose-process))
