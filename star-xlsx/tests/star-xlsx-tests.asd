(defsystem "star-xlsx-tests"
  :description "Unit tests for star-xlsx"
  :author "lost-rob0t"
  :license "GPL-3.0"
  :depends-on ("star-xlsx" "fiveam")
  :components
  ((:file "star-xlsx-tests"))
  :perform (test-op (op c)
             (symbol-call :fiveam '#:run! 'starxlsx-tests)))
