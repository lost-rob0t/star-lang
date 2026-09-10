(defsystem "star-ipx-tests"
  :description "Actor-semantic tests for star-ipx"
  :author "lost-rob0t"
  :license "AGPL-3.0-only"
  :depends-on ("star-ipx")
  :serial t
  :components
  ((:file "star-ipx-tests"))
  :perform
  (test-op (operation component)
    (declare (ignore operation component))
    (uiop:symbol-call :staripx-tests :run-tests)))
