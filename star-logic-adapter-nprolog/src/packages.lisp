(defpackage :starlogicadapternprolog
  (:use :cl)
  (:nicknames :star-logic-adapter-nprolog)
  (:import-from :starlogicprotocol
                #:+logic-backend-n-prolog+
                #:make-logic-backend-descriptor
                #:logic-backend-descriptor-of
                #:open-logic-session
                #:close-logic-session
                #:logic-backend-health)
  (:import-from :starprocessport
                #:launch-process
                #:process-stdin
                #:process-stdout
                #:process-stderr
                #:process-alive-p
                #:process-reaped-p
                #:process-exit-code
                #:wait-process
                #:kill-process
                #:dispose-process)
  (:export
   #:+nprolog-adapter-version+
   #:+nprolog-engine-upstream+
   #:+star-logic-bridge-package-id+
   #:+star-logic-bridge-protocol+
   #:nprolog-adapter-error
   #:nprolog-executable-unavailable-error
   #:nprolog-bridge-unavailable-error
   #:nprolog-worker-launch-error
   #:nprolog-worker-exited-during-startup-error
   #:nprolog-malformed-startup-data-error
   #:nprolog-backend-identity-mismatch-error
   #:nprolog-package-mismatch-error
   #:nprolog-handshake-error
   #:nprolog-bridge-port-error
   #:nprolog-bridge-wire-error
   #:nprolog-bridge-handshake-error
   #:nprolog-request-too-large-error
   #:nprolog-canary-failure-error
   #:nprolog-shutdown-failure-error
   #:nprolog-backend
   #:nprolog-backend-p
   #:make-nprolog-backend))
(in-package :starlogicadapternprolog)
