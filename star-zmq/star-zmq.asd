(asdf:defsystem "star-zmq"
  :description "Bounded local libzmq transport; not an actor runtime or federation service"
  :version "0.1.0"
  :license "AGPL-3.0-only"
  :depends-on ("cffi" "bordeaux-threads")
  :serial t
  :components ((:file "src/transport"))
  :in-order-to ((asdf:test-op (asdf:test-op "star-zmq/tests"))))

(asdf:defsystem "star-zmq/tests"
  :depends-on ("star-zmq")
  :serial t
  :components ((:file "tests/native"))
  :perform (asdf:test-op (op system)
             (declare (ignore op system))
             (uiop:symbol-call :star-zmq-tests :run-tests)))
