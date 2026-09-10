(defsystem "star-process-port-tests"
  :description "Unit tests for star-process-port"
  :author "lost-rob0t"
  :license "AGPL-3.0-only"
  :depends-on ("star-process-port" "fiveam")
  :components
  ((:file "star-process-port-tests"))
  :perform
  (test-op (operation component)
    (declare (ignore operation component))
    (uiop:symbol-call :starprocessport-tests :run-tests)))
