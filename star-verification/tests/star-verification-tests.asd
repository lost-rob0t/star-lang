(defsystem "star-verification-tests"
  :description "Unit tests for star-verification"
  :author "lost-rob0t"
  :license "AGPL-3.0-only"
  :depends-on ("star-verification")
  :serial t
  :components
  ((:file "star-verification-tests")
   (:file "scope-tests"))
  :perform
  (test-op (operation component)
    (declare (ignore operation component))
    (uiop:symbol-call :starverification-tests :run-tests)
    (uiop:symbol-call :starverification-tests :run-scope-tests)))
