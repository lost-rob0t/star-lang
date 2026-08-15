(defsystem "star-canonical-json-tests"
  :description "Unit tests for star-canonical-json"
  :author "lost-rob0t"
  :license "AGPL-3.0-only"
  :depends-on ("star-canonical-json")
  :serial t
  :components
  ((:file "star-canonical-json-tests")
   (:file "starlang-wire-json-tests"))
  :perform
  (test-op (operation component)
    (declare (ignore operation component))
    (uiop:symbol-call :starcanonicaljson-tests :run-tests)
    (uiop:symbol-call :starcanonicaljson-wire-tests :run-tests)))
