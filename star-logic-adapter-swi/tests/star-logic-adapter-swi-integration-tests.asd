(defsystem "star-logic-adapter-swi-integration-tests"
  :description "Real SWI-Prolog MQI integration tests"
  :author "lost-rob0t"
  :license "AGPL-3.0-only"
  :depends-on ("star-logic-adapter-swi" "fiveam")
  :components
  ((:file "integration-tests"))
  :perform
  (test-op (operation component)
    (declare (ignore operation component))
    (uiop:symbol-call :starlogicadapterswi-integration-tests :run-tests)))
