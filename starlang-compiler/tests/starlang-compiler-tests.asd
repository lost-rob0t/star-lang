(defsystem "starlang-compiler-tests"
  :description "Unit tests for starlang-compiler"
  :author "lost-rob0t"
  :license "AGPL-3.0-only"
  :depends-on ("starlang-compiler" "star-canonical-json" "star-logic-testing" "fiveam")
  :serial t
  :components
  ((:file "starlang-compiler-tests")
   (:file "actor-compiler-tests")
   (:file "actor-option-key-tests")
   (:file "actor-capabilities-tests")
   (:file "field-marker-tests")
   (:file "macro-expander-tests")
   (:file "lifecycle-tests")
   (:file "kotlin-backend-tests"))
  :perform
  (test-op (op c)
    (declare (ignore op c))
    (uiop:symbol-call :starlangcompiler-tests :run-tests)
    (uiop:symbol-call :starlang-actor-compiler-tests :run-tests)
    (uiop:symbol-call :starlang-actor-option-key-tests :run-tests)
    (uiop:symbol-call :starlang-actor-capabilities-tests :run-tests)
    (uiop:symbol-call :starlang-field-marker-tests :run-tests)
    (uiop:symbol-call :starlang-macro-expander-tests :run-tests)
    (uiop:symbol-call :starlang-lifecycle-tests :run-tests)
    (uiop:symbol-call :starlang-kotlin-backend-tests :run-tests)))
