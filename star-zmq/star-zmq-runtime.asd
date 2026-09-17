(asdf:defsystem "star-zmq-runtime"
  :description "Lower compiled external StarLang actors to managed local ZMQ peers"
  :version "0.1.0"
  :license "AGPL-3.0-only"
  :depends-on ("star-zmq-actors" "starlang-runtime" "starlang-compiler")
  :serial t
  :components ((:file "src/runtime-adapter"))
  :in-order-to ((asdf:test-op (asdf:test-op "star-zmq-runtime/tests"))))

(asdf:defsystem "star-zmq-runtime/tests"
  :depends-on ("star-zmq-runtime")
  :serial t
  :components ((:file "tests/runtime-e2e"))
  :perform (asdf:test-op (op system)
             (declare (ignore op system))
             (uiop:symbol-call :star-zmq-runtime-tests :run-tests)))
