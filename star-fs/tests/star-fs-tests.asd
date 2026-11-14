(defsystem "star-fs-tests"
  :description "Tests for provider-neutral StarFS map/reduce"
  :author "lost-rob0t"
  :license "AGPL-3.0-only"
  :depends-on ("star-fs" "fiveam")
  :serial t
  :components
  ((:file "star-fs-tests"))
  :perform
  (test-op (operation component)
    (declare (ignore operation component))
    (uiop:symbol-call :starfs-tests :run-tests)))
