(defsystem "star-logic-protocol-tests"
  :description "Unit tests for star-logic-protocol and the engine-free fake backend"
  :author "lost-rob0t"
  :license "AGPL-3.0-only"
  :depends-on ("star-logic-protocol" "star-logic-testing")
  :serial t
  :components
  ((:file "star-logic-protocol-tests"))
  :perform
  (test-op (operation component)
    (declare (ignore operation component))
    (uiop:symbol-call :starlogicprotocol-tests :run-tests)))
