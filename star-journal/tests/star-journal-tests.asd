(defsystem "star-journal-tests"
  :description "Unit tests for star-journal"
  :author "lost-rob0t"
  :license "AGPL-3.0-only"
  :depends-on ("star-journal" "fiveam")
  :components
  ((:file "star-journal-tests"))
  :perform (test-op (op c)
             (symbol-call :fiveam '#:run! 'starjournal-tests)))
