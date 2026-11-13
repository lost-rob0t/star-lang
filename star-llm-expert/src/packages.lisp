;;;; Package definition for the provider-neutral LLM expert-system
;;;; primitives (issue #138).  Everything here is deterministic data except
;;;; the single completion port consumed by the engine.
(defpackage :starllmexpert
  (:use :cl)
  (:nicknames :star-llm-expert)
  (:import-from :starcanonicaljson
                #:make-json-object
                #:make-json-array
                #:json-object-p
                #:canonical-json-string
                #:+json-true+
                #:+json-false+
                #:+json-null+)
  (:export
   ;; conditions
   #:star-llm-expert-error
   #:invalid-llm-model-requirement-error
   #:invalid-llm-provider-descriptor-error
   #:duplicate-llm-provider-error
   #:llm-provider-selection-error
   #:invalid-llm-prompt-template-error
   #:llm-prompt-render-error
   #:invalid-llm-response-schema-error
   #:invalid-llm-structured-output-error
   #:invalid-llm-tool-error
   #:invalid-llm-tool-request-error
   #:untrusted-llm-tool-request-error
   #:invalid-llm-expert-rule-error
   #:invalid-llm-budget-error
   #:invalid-llm-expert-error
   #:llm-verifier-not-found-error
   #:llm-budget-exhausted-error
   ;; model requirements
   #:make-llm-model-requirement
   #:llm-model-requirement-p
   #:llm-model-requirement-providers
   #:llm-model-requirement-min-context-tokens
   #:llm-model-requirement-required-capabilities
   ;; provider descriptors, registry, policy selection
   #:make-llm-provider-descriptor
   #:llm-provider-descriptor-p
   #:llm-provider-descriptor-provider
   #:llm-provider-descriptor-model
   #:llm-provider-descriptor-context-tokens
   #:llm-provider-descriptor-capabilities
   #:make-llm-provider-registry
   #:register-llm-provider
   #:find-llm-provider
   #:list-llm-providers
   #:select-llm-provider
   #:llm-selection-p
   #:llm-selection-provider
   #:llm-selection-model
   #:llm-selection-candidates
   ;; prompt templates
   #:make-llm-prompt-template
   #:llm-prompt-template-p
   #:llm-prompt-template-id
   #:llm-prompt-template-version
   #:llm-prompt-template-body
   #:render-llm-prompt
   ;; structured response schemas
   #:make-llm-schema-field
   #:llm-schema-field-p
   #:llm-schema-field-name
   #:llm-schema-field-type
   #:llm-schema-field-values
   #:make-llm-response-schema
   #:llm-response-schema-p
   #:llm-response-schema-fields
   #:llm-response-schema-required
   #:validate-llm-structured-output
   ;; tools and capability grants
   #:make-llm-tool
   #:llm-tool-p
   #:llm-tool-id
   #:llm-tool-description
   #:llm-tool-input-schema
   #:make-llm-tool-request
   #:llm-tool-request-p
   #:llm-tool-request-tool
   #:llm-tool-request-arguments
   #:validate-llm-tool-request
   #:authorize-llm-tool-request
   ;; expert rules
   #:make-llm-expert-rule
   #:llm-expert-rule-p
   #:llm-expert-rule-id
   #:llm-expert-rule-condition-fact
   #:llm-expert-rule-condition-op
   #:llm-expert-rule-condition-value
   #:llm-expert-rule-action-kind
   #:llm-expert-rule-action-fact
   #:llm-expert-rule-action-value
   ;; budgets
   #:make-llm-budget
   #:llm-budget-p
   #:llm-budget-max-model-calls
   #:llm-budget-max-tool-invocations
   #:llm-budget-max-total-tokens
   ;; expert graph and compilation
   #:make-llm-expert
   #:llm-expert-p
   #:llm-expert-id
   #:llm-expert-version
   #:llm-expert-route
   #:llm-expert-template
   #:llm-expert-response-schema
   #:llm-expert-tools
   #:llm-expert-grants
   #:llm-expert-rules
   #:llm-expert-verifiers
   #:llm-expert-budget
   #:compile-llm-expert
   #:compiled-llm-expert-p
   #:compiled-llm-expert-graph
   #:compiled-llm-expert-digest
   ;; serialization
   #:llm-expert-json-object
   #:llm-expert-json-string
   ;; verifier predicates
   #:make-llm-verifier-table
   #:register-llm-verifier
   #:run-llm-verifier
   ;; engine
   #:llm-completion-port
   #:llm-complete
   #:make-llm-completion-request
   #:llm-completion-request-p
   #:llm-completion-request-prompt
   #:llm-completion-request-schema
   #:llm-completion-request-tools
   #:llm-completion-request-provider
   #:make-llm-completion
   #:llm-completion-p
   #:llm-completion-structured
   #:llm-completion-tool-request
   #:llm-completion-usage-tokens-in
   #:llm-completion-usage-tokens-out
   #:run-llm-expert
   #:llm-run-result-p
   #:llm-run-result-status
   #:llm-run-result-facts
   #:llm-run-result-usage
   #:llm-run-result-provenance
   #:llm-run-result-trace
   #:llm-usage-p
   #:llm-usage-model-calls
   #:llm-usage-tool-invocations
   #:llm-usage-tokens-in
   #:llm-usage-tokens-out
   #:llm-provenance-p
   #:llm-provenance-graph-digest
   #:llm-provenance-template-id
   #:llm-provenance-template-version
   #:llm-provenance-provider
   #:llm-provenance-model
   #:llm-provenance-response-digest
   #:llm-trace-event-p
   #:llm-trace-event-ordinal
   #:llm-trace-event-stage
   #:llm-trace-event-provider
   #:llm-trace-event-model
   #:llm-trace-event-detail))
