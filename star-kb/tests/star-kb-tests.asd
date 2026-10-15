(defsystem "star-kb-tests"
  :description "Contract tests for star-kb"
  :author "lost-rob0t"
  :license "AGPL-3.0-only"
  :depends-on ("star-kb")
  :serial t
  :components
  ((:file "star-kb-tests"))
  :perform
  (test-op (operation component)
    (declare (ignore operation component))
    (uiop:symbol-call :starkb-tests :run-tests)))
