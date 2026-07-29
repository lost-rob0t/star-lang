(defsystem "star-mailbox-tests"
  :description "Unit tests for star-mailbox"
  :author "lost-rob0t"
  :license "GPL-3.0"
  :depends-on ("star-mailbox" "fiveam")
  :components
  ((:file "star-mailbox-tests"))
  :perform (test-op (op c)
             (symbol-call :fiveam '#:run! 'starmailbox-tests)))
