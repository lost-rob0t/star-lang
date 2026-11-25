(defsystem "star-logic-adapter-nprolog-integration-tests"
  :description "Real Nix-pinned N-Prolog worker integration tests"
  :author "lost-rob0t"
  :license "AGPL-3.0-only"
  :depends-on ("star-logic-adapter-nprolog" "star-process-port" "fiveam")
  :components
  ((:file "integration-tests"))
  :perform
  (test-op (operation component)
    (declare (ignore operation component))
    (uiop:symbol-call :starlogicadapternprolog-integration-tests :run-tests)))
