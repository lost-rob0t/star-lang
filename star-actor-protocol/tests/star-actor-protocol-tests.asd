(defsystem "star-actor-protocol-tests"
  :description "Unit tests for star-actor-protocol"
  :author "lost-rob0t"
  :license "GPL-3.0"
  :depends-on ("star-actor-protocol" "fiveam")
  :components
  ((:file "star-actor-protocol-tests"))
  :perform (test-op (op c)
             (symbol-call :fiveam '#:run! 'staractorprotocol-tests)))
