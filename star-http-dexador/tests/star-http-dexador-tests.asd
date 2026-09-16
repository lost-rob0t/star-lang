(defsystem "star-http-dexador-tests"
  :description "Real-loopback regression tests for the synchronous Dexador HTTP backend"
  :author "lost-rob0t"
  :license "AGPL-3.0-only"
  :depends-on ("star-http-port"
               "dexador"
               "usocket"
               "bordeaux-threads"
               "babel")
  :serial t
  :components
  ((:file "star-http-dexador-tests"))
  :perform
  (test-op (operation component)
    (declare (ignore operation component))
    (uiop:symbol-call :starhttpdexador-tests :run-tests)))
