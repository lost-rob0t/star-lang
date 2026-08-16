(defpackage :starlogicprotocol
  (:use :cl)
  (:nicknames :star-logic-protocol)
  (:export
   ;; Stable backend identities.
   #:+logic-backend-lisa+
   #:+logic-backend-swi-prolog+
   #:+logic-backend-n-prolog+

   ;; Portable operation states.
   #:+logic-operation-pending+
   #:+logic-operation-running+
   #:+logic-operation-completed+
   #:+logic-operation-no-answer+
   #:+logic-operation-cancelled+
   #:+logic-operation-failed+

   ;; Conditions.
   #:star-logic-error
   #:invalid-logic-backend-descriptor-error
   #:duplicate-logic-backend-error
   #:logic-backend-not-found-error
   #:logic-backend-incompatible-error
   #:logic-backend-selection-error
   #:unsupported-logic-operation-error
   #:logic-session-error

   ;; Backend descriptors.
   #:logic-backend-descriptor
   #:logic-backend-descriptor-p
   #:make-logic-backend-descriptor
   #:logic-backend-descriptor-id
   #:logic-backend-descriptor-version
   #:logic-backend-descriptor-build-id
   #:logic-backend-descriptor-semantic-profiles
   #:logic-backend-descriptor-capabilities
   #:logic-backend-descriptor-isolation-classes
   #:logic-backend-descriptor-hard-limits
   #:logic-backend-descriptor-cooperative-limits
   #:logic-backend-descriptor-metadata

   ;; Registry.
   #:logic-backend-registry
   #:logic-backend-registry-p
   #:make-logic-backend-registry
   #:register-logic-backend
   #:unregister-logic-backend
   #:find-logic-backend
   #:list-logic-backends

   ;; Selection.
   #:logic-selection-request
   #:logic-selection-request-p
   #:make-logic-selection-request
   #:logic-selection-request-backend-policy
   #:logic-selection-request-semantic-profile
   #:logic-selection-request-required-capabilities
   #:logic-selection-request-required-hard-limits
   #:logic-selection-request-required-isolation
   #:logic-selection-candidate
   #:logic-selection-candidate-p
   #:logic-selection-candidate-backend-id
   #:logic-selection-candidate-status
   #:logic-selection-candidate-reason
   #:logic-selection-evidence
   #:logic-selection-evidence-p
   #:logic-selection-evidence-requested
   #:logic-selection-evidence-semantic-profile
   #:logic-selection-evidence-required-capabilities
   #:logic-selection-evidence-required-hard-limits
   #:logic-selection-evidence-required-isolation
   #:logic-selection-evidence-candidates
   #:logic-selection-evidence-selected
   #:logic-selection-evidence-policy
   #:select-logic-backend

   ;; Adapter protocol.
   #:logic-backend-descriptor-of
   #:open-logic-session
   #:close-logic-session
   #:apply-logic-fact-delta
   #:invoke-logic-operation
   #:next-logic-result
   #:cancel-logic-operation
   #:logic-operation-status
   #:logic-backend-health))
