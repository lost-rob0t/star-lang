(defpackage :starjournal
  (:use :cl)
  (:nicknames :star-journal)
  (:export
   #:star-journal-error
   #:runtime-journal-port
   #:runtime-journal-port-p
   #:make-runtime-journal-port
   #:runtime-journal-append
   #:runtime-journal-replay
   #:make-memory-runtime-journal-port
   #:make-file-runtime-journal-port))
