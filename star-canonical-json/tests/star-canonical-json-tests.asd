(defsystem "star-canonical-json-tests"
  :description "Unit tests for star-canonical-json"
  :author "lost-rob0t"
  :license "GPL-3.0"
  :depends-on ("star-canonical-json" "fiveam")
  :components
  ((:file "star-canonical-json-tests"))
  :perform (test-op (op c)
             (symbol-call :fiveam '#:run! 'starcanonicaljson-tests)))
