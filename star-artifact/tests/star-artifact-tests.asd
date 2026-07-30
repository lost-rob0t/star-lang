(defsystem "star-artifact-tests"
  :description "Unit tests for star-artifact"
  :author "lost-rob0t"
  :license "AGPL-3.0-only"
  :depends-on ("star-artifact" "fiveam")
  :components
  ((:file "star-artifact-tests"))
  :perform (test-op (op c)
             (symbol-call :fiveam '#:run! 'starartifact-tests)))
