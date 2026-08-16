(defsystem "starlang-compiler-tests"
  :description "Unit tests for starlang-compiler"
  :author "lost-rob0t"
  :license "AGPL-3.0-only"
  :depends-on ("starlang-compiler" "star-logic-testing" "fiveam")
  :components
  ((:file "starlang-compiler-tests"))
  :perform (test-op (op c)
             (declare (ignore op c))
             (symbol-call :fiveam '#:run! 'starlangcompiler-tests)))
