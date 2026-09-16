(defsystem "star-journal-tests"
  :description "Unit tests for star-journal"
  :author "lost-rob0t"
  :license "AGPL-3.0-only"
  :depends-on ("star-journal")
  :serial t
  :components
  ((:file "star-journal-tests")
   (:file "journal-boundary-tests")
   (:file "file-replay-watchdog-tests"))
  :perform
  (test-op (operation component)
    (declare (ignore operation component))
    (uiop:symbol-call :starjournal-tests :run-tests)
    (uiop:symbol-call :starjournal-boundary-tests :run-tests)
    (uiop:symbol-call :starjournal-file-replay-watchdog-tests :run-tests)))
