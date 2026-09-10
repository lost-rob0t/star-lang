(defpackage :starlogicadapterswi
  (:use :cl)
  (:nicknames :star-logic-adapter-swi)
  (:import-from :starlogicprotocol
                #:+logic-backend-swi-prolog+
                #:make-logic-backend-descriptor
                #:logic-backend-descriptor-of
                #:open-logic-session
                #:close-logic-session
                #:logic-backend-health)
  (:import-from :starprocessport
                #:launch-process
                #:process-stdout
                #:process-stderr
                #:process-alive-p
                #:process-reaped-p
                #:process-exit-code
                #:wait-process
                #:dispose-process)
  (:export
   #:+swi-adapter-version+
   #:swi-adapter-error
   #:swi-executable-unavailable-error
   #:swi-worker-launch-error
   #:swi-worker-exited-during-startup-error
   #:swi-malformed-startup-data-error
   #:swi-socket-connection-error
   #:swi-authentication-error
   #:swi-unsupported-mqi-protocol-error
   #:swi-backend-identity-mismatch-error
   #:swi-bootstrap-package-mismatch-error
   #:swi-bootstrap-handshake-error
   #:swi-mqi-malformed-frame-error
   #:swi-mqi-malformed-response-error
   #:swi-unexpected-eof-error
   #:swi-shutdown-failure-error
   #:swi-worker-crash-error
   #:swi-backend
   #:swi-backend-p
   #:make-swi-backend))
