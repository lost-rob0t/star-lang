(defsystem "star-supervisor-tests"
  :description "Unit tests for star-supervisor"
  :author "lost-rob0t"
  :license "GPL-3.0"
  :depends-on ("star-supervisor" "fiveam")
  :components
  ((:file "star-supervisor-tests"))
  :perform (test-op (op c)
             (symbol-call :fiveam '#:run! 'starsupervisor-tests)))
