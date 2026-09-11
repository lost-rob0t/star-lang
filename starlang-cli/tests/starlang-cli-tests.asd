(defsystem "starlang-cli-tests"
  :description "Unit tests for starlang-cli"
  :author "lost-rob0t"
  :license "AGPL-3.0-only"
  :depends-on ("starlang-cli" "fiveam")
  :serial t
  :components
  ((:file "cli-tests"))
  :perform
  (test-op (op c)
    (declare (ignore op c))
    (uiop:symbol-call :star-lang.cli-tests :run-tests)))
