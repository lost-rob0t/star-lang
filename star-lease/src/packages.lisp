(defpackage :starlease
  (:use :cl)
  (:nicknames :star-lease)
  (:export
   #:star-lease-error
   #:heartbeat-lease
   #:heartbeat-lease-p
   #:make-heartbeat-lease
   #:heartbeat-lease-timeout-ms
   #:heartbeat-lease-note-seen
   #:heartbeat-lease-last-seen-at
   #:heartbeat-lease-expired-p))
