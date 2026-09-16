(defsystem "star-process-port-tests"
  :description "Contract tests for star-process-port lifecycle behavior"
  :author "lost-rob0t"
  :license "AGPL-3.0-only"
  :depends-on ("star-process-port" "bordeaux-threads" "fiveam")
  :components
  ((:file "star-process-port-tests"))
  :perform
  (test-op (operation component)
    (declare (ignore operation component))
    (uiop:symbol-call :starprocessport-tests :run-tests)))
