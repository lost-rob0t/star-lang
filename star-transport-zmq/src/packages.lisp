;;;; ZeroMQ REQ/REP transport ports (concrete transport adapter).

(in-package :cl-user)

(defpackage :startransportzmq
  (:use :cl)
  (:nicknames :star-transport-zmq)
  (:export
   #:zmq-transport-error
   #:zmq-endpoint-holder
   #:zmq-endpoint-holder-p
   #:zmq-endpoint-holder-endpoint
   #:zmq-endpoint-holder-kind
   #:zmq-endpoint-holder-open-p
   #:bind-zmq-rep-port
   #:connect-zmq-req-port
   #:close-zmq-port))
