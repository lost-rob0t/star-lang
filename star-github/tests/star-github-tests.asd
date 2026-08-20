(defsystem "star-github-tests"
  :description "Unit tests for the StarLang GitHub target actor"
  :author "lost-rob0t"
  :license "AGPL-3.0-only"
  :depends-on ("star-github")
  :serial t
  :components
  ((:file "star-github-tests"))
  :perform
  (test-op (operation component)
    (declare (ignore operation component))
    (uiop:symbol-call :stargithub-tests :run-tests)))
