(defsystem "starlang-compiler-tests"
  :description "Unit tests for starlang-compiler"
  :author "lost-rob0t"
  :license "AGPL-3.0-only"
  :depends-on ("starlang-compiler" "star-canonical-json" "star-logic-testing" "fiveam")
  :serial t
  :components
  ((:file "starlang-compiler-tests")
   (:file "actor-compiler-tests"))
  :perform
  (test-op (op c)
    (declare (ignore op c))
    (uiop:symbol-call :starlangcompiler-tests :run-tests)
    (uiop:symbol-call :starlang-actor-compiler-tests :run-tests)))
