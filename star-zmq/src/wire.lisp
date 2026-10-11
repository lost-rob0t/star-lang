;; Compatibility namespace. The canonical codec is shared with Rabbit/local ports.
(defpackage :star-zmq-actors
  (:use :cl)
  (:import-from :star-actor-wire #:wire-error #:encode-envelope #:decode-envelope)
  (:export #:wire-error #:encode-envelope #:decode-envelope
           #:peer-error #:peer-timeout-error #:peer-protocol-error #:peer-exited-error
           #:open-peer #:close-peer #:peer-request #:peer-live-p #:peer-generation))
