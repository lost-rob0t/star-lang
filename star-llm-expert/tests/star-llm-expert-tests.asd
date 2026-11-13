(defsystem "star-llm-expert-tests"
  :description "Unit tests for star-llm-expert"
  :author "lost-rob0t"
  :license "AGPL-3.0-only"
  :version "0.1.0"
  :depends-on ("star-llm-expert" "star-canonical-json" "fiveam")
  :serial t
  :components
  ((:file "star-llm-expert-tests"))
  :perform (test-op (op c)
             (symbol-call :star-llm-expert-tests '#:run-tests)))
