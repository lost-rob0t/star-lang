;;;; Tests for the star-llm-expert primitives (issue #138).
(defpackage :star-llm-expert-tests
  (:use :cl :fiveam)
  (:import-from :starllmexpert
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
                #:make-llm-model-requirement
                #:llm-model-requirement-p
                #:llm-model-requirement-providers
                #:llm-model-requirement-min-context-tokens
                #:llm-model-requirement-required-capabilities
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
                #:make-llm-prompt-template
                #:llm-prompt-template-p
                #:llm-prompt-template-id
                #:llm-prompt-template-version
                #:llm-prompt-template-body
                #:render-llm-prompt
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
                #:make-llm-tool
                #:llm-tool-p
                #:llm-tool-id
                #:llm-tool-input-schema
                #:make-llm-tool-request
                #:llm-tool-request-p
                #:llm-tool-request-tool
                #:llm-tool-request-arguments
                #:validate-llm-tool-request
                #:authorize-llm-tool-request
                #:make-llm-expert-rule
                #:llm-expert-rule-p
                #:make-llm-budget
                #:llm-budget-p
                #:llm-budget-max-model-calls
                #:llm-budget-max-tool-invocations
                #:llm-budget-max-total-tokens
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
                #:llm-expert-json-object
                #:llm-expert-json-string
                #:make-llm-verifier-table
                #:register-llm-verifier
                #:run-llm-verifier)
  (:import-from :starcanonicaljson
                #:canonical-json-string
                #:json-object-p
                #:write-canonical-json)
  (:export #:run-tests))

(in-package :star-llm-expert-tests)

(defun check (truth control &rest arguments)
  (unless truth
    (error (apply #'format nil control arguments))))

(defun signals-p (condition-type thunk)
  (handler-case
      (progn
        (funcall thunk)
        nil)
    (error (condition)
      (typep condition condition-type))))

(def-suite star-llm-expert-suite
  :description "star-llm-expert primitive suite")

(in-suite star-llm-expert-suite)

;;; ---------------------------------------------------------------------
;;; Model requirements: typed, validated, provider-opaque data.

(test model-requirement-normalizes-and-sorts
  (let ((requirement (make-llm-model-requirement
                      :providers '("beta" "alpha" "beta")
                      :min-context-tokens 4096
                      :required-capabilities '("json-schema" "chat"))))
    (check (llm-model-requirement-p requirement) "requirement type")
    (check (equal (llm-model-requirement-providers requirement)
                  '("alpha" "beta"))
           "providers sorted/deduped: ~S"
           (llm-model-requirement-providers requirement))
    (check (equal (llm-model-requirement-required-capabilities requirement)
                  '("chat" "json-schema"))
           "capabilities sorted: ~S"
           (llm-model-requirement-required-capabilities requirement))
    (check (eql (llm-model-requirement-min-context-tokens requirement) 4096)
           "context floor")))

(test model-requirement-rejects-invalid
  (check (signals-p 'invalid-llm-model-requirement-error
                    (lambda ()
                      (make-llm-model-requirement
                       :providers '() :min-context-tokens 1)))
         "empty providers rejected")
  (check (signals-p 'invalid-llm-model-requirement-error
                    (lambda ()
                      (make-llm-model-requirement
                       :providers '("alpha") :min-context-tokens 0)))
         "zero context rejected")
  (check (signals-p 'invalid-llm-model-requirement-error
                    (lambda ()
                      (make-llm-model-requirement
                       :providers '("alpha" "") :min-context-tokens 1)))
         "empty provider id rejected"))

;;; ---------------------------------------------------------------------
;;; Provider descriptors and policy-validated selection.

(test provider-descriptor-validates
  (let ((descriptor (make-llm-provider-descriptor
                     :provider "alpha" :model "alpha-large"
                     :context-tokens 8192
                     :capabilities '("chat" "json-schema"))))
    (check (llm-provider-descriptor-p descriptor) "descriptor type")
    (check (equal (llm-provider-descriptor-provider descriptor) "alpha")
           "provider id")
    (check (equal (llm-provider-descriptor-capabilities descriptor)
                  '("chat" "json-schema"))
           "capabilities"))
  (check (signals-p 'invalid-llm-provider-descriptor-error
                    (lambda ()
                      (make-llm-provider-descriptor
                       :provider "alpha" :model "m"
                       :context-tokens -1)))
         "negative context rejected"))

(test provider-registry-register-find-list
  (let ((registry (make-llm-provider-registry)))
    (register-llm-provider
     registry
     (make-llm-provider-descriptor :provider "beta" :model "beta-small"
                                   :context-tokens 2048
                                   :capabilities '("chat")))
    (register-llm-provider
     registry
     (make-llm-provider-descriptor :provider "alpha" :model "alpha-large"
                                   :context-tokens 8192
                                   :capabilities '("chat" "json-schema")))
    (check (llm-provider-descriptor-p (find-llm-provider registry "alpha"))
           "find alpha")
    (check (equal (mapcar #'llm-provider-descriptor-provider
                          (list-llm-providers registry))
                  '("alpha" "beta"))
           "deterministic listing")
    (check (signals-p 'duplicate-llm-provider-error
                      (lambda ()
                        (register-llm-provider
                         registry
                         (make-llm-provider-descriptor
                          :provider "alpha" :model "dup"
                          :context-tokens 1))))
           "duplicate rejected without replace")))

(test provider-selection-validates-requirement-as-data
  (let ((registry (make-llm-provider-registry)))
    (register-llm-provider
     registry
     (make-llm-provider-descriptor :provider "alpha" :model "alpha-large"
                                   :context-tokens 8192
                                   :capabilities '("chat" "json-schema")))
    ;; Requirement naming an unregistered provider must fail policy.
    (check (signals-p 'llm-provider-selection-error
                      (lambda ()
                        (select-llm-provider
                         registry
                         (make-llm-model-requirement
                          :providers '("omega") :min-context-tokens 1))))
           "unknown provider id rejected")
    ;; Capability shortfall must fail policy.
    (check (signals-p 'llm-provider-selection-error
                      (lambda ()
                        (select-llm-provider
                         registry
                         (make-llm-model-requirement
                          :providers '("alpha") :min-context-tokens 1
                          :required-capabilities '("vision")))))
           "capability shortfall rejected")
    ;; Context shortfall must fail policy.
    (check (signals-p 'llm-provider-selection-error
                      (lambda ()
                        (select-llm-provider
                         registry
                         (make-llm-model-requirement
                          :providers '("alpha") :min-context-tokens 99999))))
           "context shortfall rejected")
    ;; Satisfied requirement selects deterministically with evidence.
    (let ((selection (select-llm-provider
                      registry
                      (make-llm-model-requirement
                       :providers '("alpha") :min-context-tokens 4096
                       :required-capabilities '("chat")))))
      (check (llm-selection-p selection) "selection type")
      (check (string= (llm-selection-provider selection) "alpha")
             "selected provider")
      (check (string= (llm-selection-model selection) "alpha-large")
             "selected model")
      (check (every #'consp (llm-selection-candidates selection))
             "candidate evidence present"))))

;;; ---------------------------------------------------------------------
;;; Prompt templates: deterministic substitution, fail closed.

(test prompt-template-renders-placeholders
  (let ((template (make-llm-prompt-template
                   :id "triage" :version 3
                   :body "Classify ticket: {{ticketBody}} for {{tenant}}.")))
    (check (llm-prompt-template-p template) "template type")
    (check (= (llm-prompt-template-version template) 3) "version")
    (check (string=
            (render-llm-prompt
             template '(("ticketBody" . "printer on fire")
                        ("tenant" . "acme")))
            "Classify ticket: printer on fire for acme.")
           "rendered prompt")))

(test prompt-template-fails-closed
  (let ((template (make-llm-prompt-template
                   :id "triage" :version 1 :body "Hello {{name}}")))
    (check (signals-p 'invalid-llm-prompt-template-error
                      (lambda ()
                        (make-llm-prompt-template
                         :id "bad" :version 1 :body "")))
           "empty body rejected")
    (check (signals-p 'llm-prompt-render-error
                      (lambda () (render-llm-prompt template nil)))
           "missing binding rejected")
    (check (signals-p 'llm-prompt-render-error
                      (lambda ()
                        (render-llm-prompt
                         (make-llm-prompt-template
                          :id "x" :version 1 :body "ok {{missing}}")
                         '(("other" . "1")))))
           "unknown placeholder rejected")))

;;; ---------------------------------------------------------------------
;;; Structured response schemas: output validates before expert state.

(test schema-field-and-schema-validation
  (let ((field (make-llm-schema-field :name "priority" :type "enum"
                                      :values '("low" "normal" "urgent"))))
    (check (llm-schema-field-p field) "field type")
    (check (equal (llm-schema-field-values field)
                  '("low" "normal" "urgent")) "enum values"))
  (check (signals-p 'invalid-llm-response-schema-error
                    (lambda () (make-llm-schema-field :name "" :type "string")))
         "bad field name rejected")
  (check (signals-p 'invalid-llm-response-schema-error
                    (lambda () (make-llm-schema-field :name "x" :type "float32")))
         "unknown field type rejected"))

(defun triage-schema ()
  (make-llm-response-schema
   :fields (list
            (make-llm-schema-field :name "priority" :type "enum"
                                   :values '("low" "normal" "urgent"))
            (make-llm-schema-field :name "category" :type "string")
            (make-llm-schema-field :name "confidence" :type "integer")
            (make-llm-schema-field :name "tags" :type "string-array"))
   :required '("priority" "category")))

(test structured-output-validation-accepts-and-normalizes
  (let ((record (validate-llm-structured-output
                 (triage-schema)
                 '(("priority" . "urgent")
                   ("category" . "hardware")
                   ("confidence" . 90)))))
    (check (equal (cdr (assoc "priority" record :test #'string=)) "urgent")
           "enum accepted")
    (check (equal (cdr (assoc "category" record :test #'string=)) "hardware")
           "string accepted")
    (check (eql (cdr (assoc "confidence" record :test #'string=)) 90)
           "integer accepted")
    (check (null (assoc "tags" record :test #'string=))
           "optional absent field omitted")))

(test structured-output-validation-rejects
  (check (signals-p 'invalid-llm-structured-output-error
                    (lambda ()
                      (validate-llm-structured-output
                       (triage-schema) '(("priority" . "urgent")))))
         "missing required rejected")
  (check (signals-p 'invalid-llm-structured-output-error
                    (lambda ()
                      (validate-llm-structured-output
                       (triage-schema)
                       '(("priority" . "catastrophic")
                         ("category" . "x")))))
         "invalid enum rejected")
  (check (signals-p 'invalid-llm-structured-output-error
                    (lambda ()
                      (validate-llm-structured-output
                       (triage-schema)
                       '(("priority" . "low")
                         ("category" . 42)))))
         "wrong scalar type rejected")
  (check (signals-p 'invalid-llm-structured-output-error
                    (lambda ()
                      (validate-llm-structured-output
                       (triage-schema)
                        '(("priority" . "low")
                          ("category" . "x")
                          ("granted" . "root")))))
         "undeclared field rejected"))

;;; ---------------------------------------------------------------------
;;; Tools and capability grants: model text never grants capabilities.

(test tool-definitions-validate
  (let ((tool (make-llm-tool
               :id "lookupAccount"
               :description "Look up an account record"
               :input-schema (make-llm-response-schema
                              :fields (list (make-llm-schema-field
                                             :name "accountId"
                                             :type "string"))
                              :required '("accountId")))))
    (check (llm-tool-p tool) "tool type")
    (check (string= (llm-tool-id tool) "lookupAccount") "tool id")
    (check (llm-response-schema-p (llm-tool-input-schema tool)) "input schema"))
  (check (signals-p 'invalid-llm-tool-error
                    (lambda ()
                      (make-llm-tool :id "snake_case" :input-schema
                                     (make-llm-response-schema :fields nil))))
         "non-camelCase tool id rejected"))

(test tool-request-validation
  (let* ((tool (make-llm-tool
                :id "lookupAccount"
                :input-schema (make-llm-response-schema
                               :fields (list (make-llm-schema-field
                                              :name "accountId" :type "string"))
                               :required '("accountId"))))
         (expert (make-llm-expert
                  :id "triage" :version 1
                  :route (list (make-llm-model-requirement
                                :providers '("alpha") :min-context-tokens 1))
                  :template (make-llm-prompt-template
                             :id "t" :version 1 :body "go")
                  :response-schema (triage-schema)
                  :tools (list tool)
                  :grants '("lookupAccount")
                  :rules nil
                  :budget (make-llm-budget :max-model-calls 3
                                           :max-tool-invocations 2
                                           :max-total-tokens 10000))))
    ;; Well-formed, declared, granted request passes.
    (let ((request (make-llm-tool-request
                    :tool "lookupAccount"
                    :arguments '(("accountId" . "a-17")))))
      (check (validate-llm-tool-request expert request) "valid request")
      (check (authorize-llm-tool-request expert request) "authorized request"))
    ;; Unknown tool id is untrusted.
    (check (signals-p 'untrusted-llm-tool-request-error
                      (lambda ()
                        (validate-llm-tool-request
                         expert
                         (make-llm-tool-request
                          :tool "dropAllTables"
                          :arguments '(("accountId" . "a"))))))
           "undeclared tool rejected as untrusted")
    ;; Declared tool with malformed arguments is invalid.
    (check (signals-p 'invalid-llm-tool-request-error
                      (lambda ()
                        (validate-llm-tool-request
                         expert
                         (make-llm-tool-request
                          :tool "lookupAccount"
                          :arguments '(("accountId" . 99))))))
           "malformed arguments rejected")
    ;; Declared tool that is NOT granted must fail authorization even though
    ;; the model requested it.
    (let* ((ungranted-tool (make-llm-tool
                            :id "sendEmail"
                            :input-schema (make-llm-response-schema
                                           :fields nil)))
           (expert-closed
             (make-llm-expert
              :id "triage" :version 1
              :route (list (make-llm-model-requirement
                            :providers '("alpha") :min-context-tokens 1))
              :template (make-llm-prompt-template :id "t" :version 1 :body "go")
              :response-schema (triage-schema)
              :tools (list tool ungranted-tool)
              :grants '("lookupAccount")
              :rules nil
              :budget (make-llm-budget :max-model-calls 3
                                       :max-tool-invocations 2
                                       :max-total-tokens 10000)))
           (request (make-llm-tool-request
                     :tool "sendEmail" :arguments nil)))
      (check (validate-llm-tool-request expert-closed request)
             "declared tool shape valid")
      (check (null (authorize-llm-tool-request expert-closed request))
             "ungranted tool fails authorization"))))

;;; ---------------------------------------------------------------------
;;; Expert rules and budgets.

(test expert-rules-validate
  (let ((rule (make-llm-expert-rule
               :id "escalate" :condition-fact "priority"
               :condition-op "eq" :condition-value "urgent"
               :action-kind "set-fact"
               :action-fact "escalate" :action-value "true")))
    (check (llm-expert-rule-p rule) "rule type"))
  (check (signals-p 'invalid-llm-expert-rule-error
                    (lambda ()
                      (make-llm-expert-rule
                       :id "bad" :condition-fact "x" :condition-op "regex"
                       :action-kind "set-fact" :action-fact "y")))
         "unknown condition op rejected")
  (check (signals-p 'invalid-llm-expert-rule-error
                    (lambda ()
                      (make-llm-expert-rule
                       :id "bad" :condition-fact "x" :condition-op "eq"
                       :action-kind "execute-shell")))
         "unknown action kind rejected"))

(test budgets-validate
  (check (llm-budget-p (make-llm-budget :max-model-calls 3
                                        :max-tool-invocations 1
                                        :max-total-tokens 100))
         "budget type")
  (check (signals-p 'invalid-llm-budget-error
                    (lambda ()
                      (make-llm-budget :max-model-calls 0
                                       :max-tool-invocations 1
                                       :max-total-tokens 100)))
         "zero model calls rejected"))

;;; ---------------------------------------------------------------------
;;; Expert graph compilation: validate, freeze, digest.

(defun reference-expert (&key (grants '("lookupAccount")))
  (make-llm-expert
   :id "ticketTriage" :version 2
   :route (list
           (make-llm-model-requirement
            :providers '("alpha") :min-context-tokens 4096
            :required-capabilities '("chat" "json-schema"))
           (make-llm-model-requirement
            :providers '("beta") :min-context-tokens 2048
            :required-capabilities '("chat")))
   :template (make-llm-prompt-template
              :id "triage-prompt" :version 4
              :body "Classify: {{ticketBody}}")
   :response-schema (triage-schema)
   :tools (list (make-llm-tool
                 :id "lookupAccount"
                 :input-schema (make-llm-response-schema
                                :fields (list (make-llm-schema-field
                                               :name "accountId" :type "string"))
                                :required '("accountId"))))
   :grants grants
   :rules (list (make-llm-expert-rule
                 :id "escalate" :condition-fact "priority"
                 :condition-op "eq" :condition-value "urgent"
                 :action-kind "set-fact"
                 :action-fact "escalate" :action-value "true"))
   :verifiers '("confidence-floor")
   :budget (make-llm-budget :max-model-calls 3
                            :max-tool-invocations 2
                            :max-total-tokens 20000)))

(defun verifier-table ()
  (let ((table (make-llm-verifier-table)))
    (register-llm-verifier
     table "confidence-floor"
     (lambda (facts)
       (let ((confidence (cdr (assoc "confidence" facts :test #'string=))))
         (and (integerp confidence) (>= confidence 50)))))
    table))

(test compile-llm-expert-freezes-with-deterministic-digest
  (let ((compiled (compile-llm-expert (reference-expert)
                                      :verifier-table (verifier-table))))
    (check (compiled-llm-expert-p compiled) "compiled type")
    (check (llm-expert-p (compiled-llm-expert-graph compiled))
           "compiled carries graph")
    (check (and (stringp (compiled-llm-expert-digest compiled))
                 (= (length (compiled-llm-expert-digest compiled))
                    (+ 7 64))
                 (string= (compiled-llm-expert-digest compiled)
                          "sha256:" :end1 7))
           "digest shape: ~S" (compiled-llm-expert-digest compiled))
    (check (string= (compiled-llm-expert-digest compiled)
                    (compiled-llm-expert-digest
                     (compile-llm-expert (reference-expert)
                                         :verifier-table (verifier-table))))
           "digest deterministic")))

(test compile-llm-expert-rejects-broken-graphs
  (check (signals-p 'invalid-llm-expert-error
                    (lambda ()
                      (compile-llm-expert
                       (make-llm-expert
                        :id "x" :version 1
                        :route nil
                        :template (make-llm-prompt-template
                                   :id "t" :version 1 :body "go")
                        :response-schema (triage-schema)
                        :tools nil :grants nil :rules nil :verifiers nil
                        :budget (make-llm-budget :max-model-calls 1
                                                 :max-tool-invocations 1
                                                 :max-total-tokens 1)))))
         "empty route rejected")
  (check (signals-p 'invalid-llm-expert-error
                    (lambda ()
                      (compile-llm-expert
                       (make-llm-expert
                        :id "x" :version 1
                        :route (list (make-llm-model-requirement
                                      :providers '("alpha")
                                      :min-context-tokens 1))
                        :template (make-llm-prompt-template
                                   :id "t" :version 1 :body "go")
                        :response-schema (triage-schema)
                        :tools nil
                        :grants '("phantomTool")
                        :rules nil :verifiers nil
                        :budget (make-llm-budget :max-model-calls 1
                                                 :max-tool-invocations 1
                                                 :max-total-tokens 1)))))
         "grant for undeclared tool rejected")
  (check (signals-p 'llm-verifier-not-found-error
                    (lambda ()
                      (compile-llm-expert (reference-expert)
                                          :verifier-table
                                          (make-llm-verifier-table))))
         "unresolved verifier rejected"))

;;; ---------------------------------------------------------------------
;;; Serialization: versioned, runtime-neutral, canonical camelCase JSON.

(test expert-serializes-to-canonical-camelcase-json
  (let* ((compiled (compile-llm-expert (reference-expert)
                                       :verifier-table (verifier-table)))
         (object (llm-expert-json-object compiled)))
    (check (json-object-p object) "json object type")
    (let ((json (llm-expert-json-string compiled)))
      (check (search "\"schema\":\"star.llm.expert/1\"" json)
             "schema version present: ~S" json)
      (check (search "{{ticketBody}}" json)
             "camelCase placeholder preserved")
      (check (not (search "ticket_body" json)) "no snake_case keys")
      (check (string= json
                      (llm-expert-json-string
                       (compile-llm-expert (reference-expert)
                                           :verifier-table
                                           (verifier-table))))
             "serialization byte-deterministic"))))

;;; ---------------------------------------------------------------------
;;; Verifier predicates.

(test verifier-table-run
  (let ((table (verifier-table)))
    (check (run-llm-verifier table "confidence-floor"
                             '(("confidence" . 90)))
           "passing verifier")
    (check (not (run-llm-verifier table "confidence-floor"
                                  '(("confidence" . 10))))
           "failing verifier")
    (check (signals-p 'llm-verifier-not-found-error
                      (lambda () (run-llm-verifier table "nope" nil)))
           "unknown verifier signalled")))

(defun run-tests ()
  ;; fiveam's run! returns T only when every check passed; surface failures
  ;; through the process exit code so ASDF/Nix/CI gates cannot pass silently.
  (unless (run! 'star-llm-expert-suite)
    (error "star-llm-expert tests failed.")))
