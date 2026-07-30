(defsystem "star-adapter-sdk-tests"
  :description "Unit tests for star-adapter-sdk"
  :author "lost-rob0t"
  :license "AGPL-3.0-only"
  :depends-on ("star-adapter-sdk" "fiveam")
  :components
  ((:file "star-adapter-sdk-tests"))
  :perform (test-op (op c)
             (symbol-call :fiveam '#:run! 'staradaptersdk-tests)))
