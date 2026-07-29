(defsystem "starlang-runtime-tests"
  :description "Unit tests for starlang-runtime"
  :author "lost-rob0t"
  :license "GPL-3.0"
  :depends-on ("starlang-runtime" "fiveam")
  :components
  ((:file "starlang-runtime-tests"))
  :perform (test-op (op c)
             (symbol-call :fiveam '#:run! 'starlangruntime-tests)))
