(defsystem "star-lease-tests"
  :description "Unit tests for star-lease"
  :author "lost-rob0t"
  :license "AGPL-3.0-only"
  :depends-on ("star-lease")
  :serial t
  :components
  ((:file "star-lease-tests"))
  :perform
  (test-op (operation component)
    (declare (ignore operation component))
    (uiop:symbol-call :starlease-tests :run-tests)))
