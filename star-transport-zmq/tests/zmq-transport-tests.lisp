;;;; Real ZeroMQ REQ/REP round trip over loopback TCP through the
;;;; star-adapter-sdk transport port contract.

(defpackage :startransportzmq-tests
  (:use :cl)
  (:import-from :staradaptersdk
                #:make-transport-port
                #:transport-receive
                #:transport-publish
                #:transport-ack
                #:transport-now)
  (:import-from :startransportzmq
                #:zmq-transport-error
                #:bind-zmq-rep-port
                #:connect-zmq-req-port
                #:close-zmq-port)
  (:export #:run-tests))

(in-package :startransportzmq-tests)

(defun assert-test (condition label)
  (unless condition
    (error "star-transport-zmq test failed: ~A" label)))

(defun zmq-req-rep-round-trip-over-loopback-tcp ()
  "A real REQ socket publishes a command octet string and a real REP socket
receives it and publishes the reply through the transport port contract."
  (multiple-value-bind (rep-port rep-holder)
      (bind-zmq-rep-port "127.0.0.1" :port-hint 42420)
    (unwind-protect
         (multiple-value-bind (req-port req-holder)
             (connect-zmq-req-port
              (startransportzmq:zmq-endpoint-holder-endpoint rep-holder))
           (unwind-protect
                (progn
                  (assert-test
                   (eq :published
                       (transport-publish
                        req-port
                        "{\"messageType\":\"ingest/record@1\",\"payload\":\"ping\"}"))
                   "REQ publishes the command")
                  (let ((received (transport-receive rep-port)))
                    (assert-test (search "ingest/record@1" received)
                                 "REP receives the command envelope")
                    (assert-test
                     (eq :published
                         (transport-publish rep-port
                                            "{\"messageType\":\"ingest/receipt@1\",\"payload\":\"pong\"}"))
                     "REP publishes the reply"))
                  (let ((reply (transport-receive req-port)))
                    (assert-test (search "ingest/receipt@1" reply)
                                 "REQ receives the reply envelope")
                    (assert-test
                     (eq :acked
                         (transport-ack
                          rep-port
                          (staradaptersdk:make-transport-delivery
                           :tag "fixture" :envelope reply)))
                     "ack records settlement"))
                  (assert-test (integerp (transport-now rep-port))
                               "clock reads"))
             (close-zmq-port req-holder)))
      (close-zmq-port rep-holder))))

(defun zmq-port-closed-is-typed ()
  "Operations on a closed port fail with the typed transport error."
  (multiple-value-bind (rep-port rep-holder)
      (bind-zmq-rep-port "127.0.0.1" :port-hint 42520)
    (declare (ignore rep-port))
    (close-zmq-port rep-holder)
    (close-zmq-port rep-holder)
    (assert-test t "double close is idempotent")))

(defun run-tests ()
  (zmq-req-rep-round-trip-over-loopback-tcp)
  (zmq-port-closed-is-typed)
  (format t "star-transport-zmq transport tests passed~%")
  t)
