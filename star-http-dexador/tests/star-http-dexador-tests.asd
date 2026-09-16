(defsystem "star-http-dexador-tests"
  :description "Real-loopback regression tests for the synchronous Dexador HTTP backend"
  :author "lost-rob0t"
  :license "AGPL-3.0-only"
  :depends-on ("star-http-dexador"
               "usocket"
               "bordeaux-threads"
               "babel")
  :serial t
  :components
  ((:file "star-http-dexador-tests")
   (:file "star-http-dexador-ownership-tests")
   (:file "star-http-dexador-red-runner"))
  :perform
  (test-op (operation component)
    (declare (ignore operation component))
    (uiop:symbol-call :starhttpdexador-tests :run-tests)
    (uiop:symbol-call :starhttpdexador-tests :run-ownership-red-tests)))
