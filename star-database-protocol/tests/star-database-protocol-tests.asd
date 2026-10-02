(defsystem "star-database-protocol-tests"
  :description "Conformance tests for StarLang database actor contracts"
  :author "lost-rob0t"
  :license "AGPL-3.0-only"
  :depends-on ("star-database-protocol" "starlang-compiler")
  :serial t
  :components
  ((:file "star-database-protocol-tests"))
  :perform
  (test-op (operation component)
    (declare (ignore operation component))
    (uiop:symbol-call :stardatabaseprotocol-tests :run-tests)))
