(defsystem "star-http-port-tests"
  :description "Unit tests for star-http-port"
  :author "lost-rob0t"
  :license "AGPL-3.0-only"
  :depends-on ("star-http-port")
  :serial t
  :components
  ((:file "star-http-port-tests"))
  :perform
  (test-op (operation component)
    (declare (ignore operation component))
    (uiop:symbol-call :starhttpport-tests :run-tests)))
