(defsystem "star-process-port-tests"
  :description "Unit tests for star-process-port"
  :author "lost-rob0t"
  :license "GPL-3.0"
  :depends-on ("star-process-port" "fiveam")
  :components
  ((:file "star-process-port-tests"))
  :perform (test-op (op c)
             (symbol-call :fiveam '#:run! 'starprocessport-tests)))
