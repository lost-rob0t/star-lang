(defsystem "starlang-runtime-tests"
  :description "Unit tests for starlang-runtime"
  :author "lost-rob0t"
  :license "AGPL-3.0-only"
  :depends-on ("starlang-runtime")
  :serial t
  :components
  ((:file "starlang-runtime-tests")
   (:file "stale-completion-tests")
   (:file "wire-dispatcher-tests")
   (:file "deferred-completion-fence-tests")
   (:file "wire-dispatcher-failure-settlement-tests"))
  :perform
  (test-op (operation component)
    (declare (ignore operation component))
    (uiop:symbol-call :starlangruntime-tests :run-tests)
    (uiop:symbol-call :starlangruntime-stale-completion-tests :run-tests)
    (uiop:symbol-call :starlangruntime-wire-tests :run-tests)
    (uiop:symbol-call :starlangruntime-wire-tests :run-deferred-completion-fence-tests)
    (uiop:symbol-call :starlangruntime-wire-failure-tests :run-tests)))
