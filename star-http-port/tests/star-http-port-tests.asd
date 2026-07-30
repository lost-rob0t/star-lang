(defsystem "star-http-port-tests"
  :description "Unit tests for star-http-port"
  :author "lost-rob0t"
  :license "AGPL-3.0-only"
  :depends-on ("star-http-port" "fiveam")
  :components
  ((:file "star-http-port-tests"))
  :perform (test-op (op c)
             (symbol-call :fiveam '#:run! 'starhttpport-tests)))
