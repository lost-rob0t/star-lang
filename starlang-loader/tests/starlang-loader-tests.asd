(defsystem "starlang-loader-tests"
  :description "Final StarLang loader tests"
  :author "lost-rob0t"
  :license "AGPL-3.0-only"
  :depends-on ("starlang-loader" "fiveam")
  :serial t
  :components ((:file "loader-tests"))
  :perform
  (test-op (op c)
    (declare (ignore op c))
    (uiop:symbol-call :starlang-loader-tests :run-tests)))
