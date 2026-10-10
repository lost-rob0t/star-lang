(defsystem "star-prolog-kb-tests"
  :description "Grammar, schema-index, and optional Tek9 integration tests"
  :author "lost-rob0t"
  :license "AGPL-3.0-only"
  :depends-on ("star-prolog-kb")
  :serial t
  :components ((:file "tests"))
  :perform
  (test-op (operation component)
    (declare (ignore operation component))
    (uiop:symbol-call :starprologkb-tests :run-tests)))