(defsystem "star-transport-zmq"
  :description "Concrete ZeroMQ REQ/REP transport port for StarLang actors"
  :author "lost-rob0t"
  :license "AGPL-3.0-only"
  :version "0.1.0"
  :depends-on ("star-actor-protocol" "star-adapter-sdk" "babel" "pzmq")
  :serial t
  :components
  ((:module "src"
    :components
    ((:file "packages")
     (:file "zmq-transport"))))
  :in-order-to ((test-op (test-op "star-transport-zmq-tests"))))
