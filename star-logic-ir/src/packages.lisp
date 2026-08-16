(defpackage :starlogicir
  (:use :cl)
  (:nicknames :star-logic-ir)
  (:import-from :starlogicprotocol
                #:+logic-backend-lisa+
                #:+logic-backend-swi-prolog+
                #:+logic-backend-n-prolog+
                #:make-logic-selection-request
                #:select-logic-backend
                #:logic-backend-descriptor-of
                #:logic-backend-descriptor-id
                #:logic-backend-descriptor-version
                #:logic-backend-descriptor-build-id
                #:logic-selection-evidence-requested
                #:logic-selection-evidence-semantic-profile
                #:logic-selection-evidence-required-capabilities
                #:logic-selection-evidence-required-hard-limits
                #:logic-selection-evidence-required-isolation
                #:logic-selection-evidence-candidates
                #:logic-selection-evidence-selected
                #:logic-selection-evidence-policy
                #:logic-selection-candidate-backend-id
                #:logic-selection-candidate-status
                #:logic-selection-candidate-reason)
  (:import-from :starcanonicaljson
                #:make-json-object
                #:make-json-array
                #:+json-true+
                #:+json-null+
                #:canonical-json-string)
  (:export
   ;; Conditions.
   #:logic-ir-error
   #:logic-ir-error-message
   #:invalid-logic-backend-policy-error
   #:invalid-logic-operation-error
   #:invalid-logic-package-identity-error
   #:invalid-logic-value-error
   #:logic-materialized-backend-change-error

   ;; Closed policy/operation vocabularies.
   #:+logic-backend-auto+
   #:+logic-operation-kinds+
   #:logic-backend-policy-p
   #:logic-operation-kind-p

   ;; Digest-locked package and mapping identity.
   #:logic-package-identity
   #:logic-package-identity-p
   #:make-logic-package-identity
   #:logic-package-identity-package-id
   #:logic-package-identity-package-version
   #:logic-package-identity-package-digest
   #:logic-package-identity-mapping-id
   #:logic-package-identity-mapping-digest

   ;; Normalized compiler-owned operation request.
   #:logic-call
   #:logic-call-p
   #:make-logic-call
   #:logic-call-operation-id
   #:logic-call-named-operation-id
   #:logic-call-operation-kind
   #:logic-call-semantic-profile
   #:logic-call-backend-policy
   #:logic-call-bindings
   #:logic-call-answer-policy
   #:logic-call-proof-policy
   #:logic-call-required-capabilities
   #:logic-call-required-hard-limits
   #:logic-call-required-isolation
   #:logic-call-package-identity
   #:logic-call-budget
   #:logic-call-source-span

   ;; Materialization boundary.
   #:logic-materialization-request
   #:logic-materialization-request-p
   #:logic-call-materialization-request
   #:logic-materialization-request-backend-policy
   #:logic-materialization-request-semantic-profile
   #:logic-materialization-request-required-capabilities
   #:logic-materialization-request-required-hard-limits
   #:logic-materialization-request-required-isolation
   #:logic-materialization-request-package-identity
   #:logic-materialization-request-proof-policy
   #:materialized-logic-call
   #:materialized-logic-call-p
   #:materialize-logic-call
   #:materialized-logic-call-logic-call
   #:materialized-logic-call-backend-id
   #:materialized-logic-call-backend-version
   #:materialized-logic-call-backend-build-id
   #:materialized-logic-call-selection-evidence
   #:materialized-logic-call-package-identity
   #:ensure-materialized-backend-compatible

   ;; Canonical replay/public serialization.
   #:logic-call-json-object
   #:logic-selection-evidence-json-object
   #:materialized-logic-call-json-object
   #:logic-call-canonical-json
   #:materialized-logic-call-canonical-json))
