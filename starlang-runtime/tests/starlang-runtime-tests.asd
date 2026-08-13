(defsystem "starlang-runtime-tests"
  :description "Unit tests for starlang-runtime"
  :author "lost-rob0t"
  :license "AGPL-3.0-only"
  :depends-on ("starlang-runtime")
  :serial t
  :components
  ((:file "starlang-runtime-tests"))
  :perform
  (test-op (operation component)
    (declare (ignore operation component))
    (uiop:symbol-call :starlangruntime-tests :run-tests)))
