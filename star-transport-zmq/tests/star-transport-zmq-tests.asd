(defsystem "star-transport-zmq-tests"
  :description "Tests for star-transport-zmq: real REQ/REP plus the
two-process ingest fixture over ZMQ TCP"
  :author "lost-rob0t"
  :license "AGPL-3.0-only"
  :depends-on ("star-transport-zmq" "starlang-compiler" "starlang-runtime"
               "star-canonical-json" "star-process-port")
  :serial t
  :components
  ((:file "zmq-transport-tests")
   (:file "ingest-fixture-tests"))
  :perform
  (test-op (operation component)
    (declare (ignore operation component))
    (uiop:symbol-call :startransportzmq-tests :run-tests)
    (uiop:symbol-call :startransportzmq-ingest-tests :run-tests)))
