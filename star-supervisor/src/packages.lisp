(defpackage :starsupervisor
  (:use :cl)
  (:nicknames :star-supervisor)
  (:export
   #:supervisor-error #:invalid-supervisor-spec #:supervisor-clock-error
   #:supervisor-stopped-error
   #:supervisor-spec #:make-supervisor-spec
   #:supervisor #:start-supervisor #:with-supervisor
   #:supervisor-status #:supervisor-runtime
   #:supervisor-tell #:supervisor-step #:run-supervisor
   #:child-reference #:stop-child
   #:stop-supervisor #:drain-supervisor
   #:next-restart-at #:supervisor-snapshot))
