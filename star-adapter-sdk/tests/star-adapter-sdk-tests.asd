(defsystem "star-adapter-sdk-tests"
  :description "Unit tests for star-adapter-sdk"
  :author "lost-rob0t"
  :license "AGPL-3.0-only"
  :depends-on ("star-adapter-sdk")
  :serial t
  :components
  ((:file "transport-port-tests"))
  :perform
  (test-op (operation component)
    (declare (ignore operation component))
    (uiop:symbol-call :staradaptersdk-tests :run-tests)))
