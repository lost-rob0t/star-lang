(defsystem "star-kb-tek9-tests"
  :description "Real Tek9 integration tests for star-kb-tek9"
  :author "lost-rob0t"
  :license "AGPL-3.0-only"
  :depends-on ("star-kb-tek9")
  :serial t
  :components
  ((:file "star-kb-tek9-tests"))
  :perform
  (test-op (operation component)
    (declare (ignore operation component))
    (uiop:symbol-call :starkbtek9-tests :run-tests)))
