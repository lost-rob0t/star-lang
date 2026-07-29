(defsystem "star-lease-tests"
  :description "Unit tests for star-lease"
  :author "lost-rob0t"
  :license "GPL-3.0"
  :depends-on ("star-lease" "fiveam")
  :components
  ((:file "star-lease-tests"))
  :perform (test-op (op c)
             (symbol-call :fiveam '#:run! 'starlease-tests)))
