(defsystem "star-capability-tests"
  :description "Unit tests for star-capability"
  :author "lost-rob0t"
  :license "GPL-3.0"
  :depends-on ("star-capability" "fiveam")
  :components
  ((:file "star-capability-tests"))
  :perform (test-op (op c)
             (symbol-call :fiveam '#:run! 'starcapability-tests)))
