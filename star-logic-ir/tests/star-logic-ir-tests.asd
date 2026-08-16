(defsystem "star-logic-ir-tests"
  :description "Engine-free conformance tests for normalized logic IR and materialization"
  :author "lost-rob0t"
  :license "AGPL-3.0-only"
  :depends-on ("star-logic-ir" "star-logic-testing")
  :serial t
  :components
  ((:file "helpers")
   (:file "conformance"))
  :perform
  (test-op (operation component)
    (declare (ignore operation component))
    (uiop:symbol-call :starlogicir-tests :run-tests)))
