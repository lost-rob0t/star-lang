(asdf:defsystem "star-zmq-actors"
  :description "Local lifecycle-envelope codec and managed external actor sessions"
  :version "0.2.0"
  :license "AGPL-3.0-only"
  :depends-on ("star-zmq" "star-actor-protocol" "star-canonical-json"
               "star-process-port" "babel" "yason" "bordeaux-threads")
  :serial t
  :components ((:file "src/wire") (:file "src/peer"))
  :in-order-to ((asdf:test-op (asdf:test-op "star-zmq-actors/tests"))))

(asdf:defsystem "star-zmq-actors/tests"
  :depends-on ("star-zmq-actors")
  :serial t
  :components ((:file "tests/actors"))
  :perform (asdf:test-op (op system)
             (declare (ignore op system))
             (uiop:symbol-call :star-zmq-actor-tests :run-tests)))
