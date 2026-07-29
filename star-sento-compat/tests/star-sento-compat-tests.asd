(defsystem "star-sento-compat-tests"
  :description "Unit tests for star-sento-compat"
  :author "lost-rob0t"
  :license "GPL-3.0"
  :depends-on ("star-sento-compat" "fiveam")
  :components
  ((:file "star-sento-compat-tests"))
  :perform (test-op (op c)
             (symbol-call :fiveam '#:run! 'starsentocompat-tests)))
