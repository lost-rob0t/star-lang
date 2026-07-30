(defsystem "star-actor-protocol-tests"
  :description "Unit tests for star-actor-protocol"
  :author "lost-rob0t"
  :license "AGPL-3.0-only"
  :depends-on ("star-actor-protocol" "fiveam")
  :components
  ((:file "star-actor-protocol-tests"))
  :perform (test-op (op c)
             (symbol-call :fiveam '#:run! 'staractorprotocol-tests)))
