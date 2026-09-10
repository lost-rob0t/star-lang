(defsystem "star-logic-adapter-swi-tests"
  :description "Pure and fake-boundary tests for star-logic-adapter-swi"
  :author "lost-rob0t"
  :license "AGPL-3.0-only"
  :depends-on ("star-logic-adapter-swi" "fiveam")
  :serial t
  :components
  ((:file "codec-tests")
   (:file "worker-tests"))
  :perform
  (test-op (operation component)
    (declare (ignore operation component))
    (uiop:symbol-call :starlogicadapterswi-tests :run-tests)))
