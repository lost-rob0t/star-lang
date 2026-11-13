(defsystem "star-llm-expert"
  :description "Provider-neutral LLM expert-system primitives: validated expert graphs, policy-checked provider selection, structured output schemas, capability grants, budgets, deterministic verification and fallback routing"
  :author "lost-rob0t"
  :license "AGPL-3.0-only"
  :version "0.1.0"
  :depends-on ("star-canonical-json" "ironclad" "babel" "uiop")
  :serial t
  :components
  ((:module "src"
    :components
    ((:file "packages")
     (:file "expert")
     (:file "json"))))
  :in-order-to ((test-op (test-op "star-llm-expert-tests"))))
