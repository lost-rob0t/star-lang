(defsystem "star-fetch-tests"
  :description "Contract tests for bounded generic fetch/cache actors"
  :author "lost-rob0t"
  :license "AGPL-3.0-only"
  :depends-on ("star-fetch")
  :serial t
  :components
  ((:file "star-fetch-tests"))
  :perform
  (test-op (operation component)
    (declare (ignore operation component))
    (uiop:symbol-call :starfetch-tests :run-tests)))
