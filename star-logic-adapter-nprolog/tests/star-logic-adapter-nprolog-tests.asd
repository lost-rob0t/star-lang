(defsystem "star-logic-adapter-nprolog-tests"
  :description "Pure and fake-boundary tests for star-logic-adapter-nprolog"
  :author "lost-rob0t"
  :license "AGPL-3.0-only"
  :depends-on ("star-logic-adapter-nprolog" "star-process-port" "fiveam")
  :serial t
  :components
  ((:file "backend-tests"))
  :perform
  (test-op (operation component)
    (declare (ignore operation component))
    (uiop:symbol-call :starlogicadapternprolog-tests :run-tests)))
