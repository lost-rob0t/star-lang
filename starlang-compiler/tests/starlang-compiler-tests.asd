(defsystem "starlang-compiler-tests"
  :description "Unit tests for starlang-compiler"
  :author "lost-rob0t"
  :license "GPL-3.0"
  :depends-on ("starlang-compiler" "fiveam")
  :components
  ((:file "starlang-compiler-tests"))
  :perform (test-op (op c)
             (symbol-call :fiveam '#:run! 'starlangcompiler-tests)))
