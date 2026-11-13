(in-package :starllmexpert)

;;;; Provider-neutral LLM expert-system primitives (issue #138).
;;;;
;;;; Every construct in this file is deterministic data with validated
;;;; constructors.  The only external-effect seam in the system is the
;;;; completion port in engine.lisp.  Capability grants live only in
;;;; compiled expert-graph data; model output can never mint them.

(defparameter +llm-expert-schema+ "star.llm.expert/1")

(define-condition star-llm-expert-error (error)
  ((message :initarg :message :reader star-llm-expert-error-message))
  (:report (lambda (condition stream)
             (write-string (star-llm-expert-error-message condition) stream))))

(define-condition invalid-llm-model-requirement-error (star-llm-expert-error) ())
(define-condition invalid-llm-provider-descriptor-error (star-llm-expert-error) ())
(define-condition duplicate-llm-provider-error (star-llm-expert-error) ())
(define-condition llm-provider-selection-error (star-llm-expert-error) ())
(define-condition invalid-llm-prompt-template-error (star-llm-expert-error) ())
(define-condition llm-prompt-render-error (star-llm-expert-error) ())
(define-condition invalid-llm-response-schema-error (star-llm-expert-error) ())
(define-condition invalid-llm-structured-output-error (star-llm-expert-error) ())
(define-condition invalid-llm-tool-error (star-llm-expert-error) ())
(define-condition invalid-llm-tool-request-error (star-llm-expert-error) ())
(define-condition untrusted-llm-tool-request-error (star-llm-expert-error) ())
(define-condition invalid-llm-expert-rule-error (star-llm-expert-error) ())
(define-condition invalid-llm-budget-error (star-llm-expert-error) ())
(define-condition invalid-llm-expert-error (star-llm-expert-error) ())
(define-condition llm-verifier-not-found-error (star-llm-expert-error) ())
(define-condition llm-budget-exhausted-error (star-llm-expert-error) ())

(defun %fail (condition-type control &rest arguments)
  (error condition-type :message (apply #'format nil control arguments)))

(defun %non-empty-string-p (value)
  (and (stringp value) (plusp (length value))))

(defun %require-non-empty-string (value field condition-type)
  (unless (%non-empty-string-p value)
    (%fail condition-type "~A must be a non-empty string, got ~S." field value))
  (copy-seq value))

(defun %require-positive-integer (value field condition-type)
  (unless (and (integerp value) (typep value '(integer 1 *)))
    (%fail condition-type "~A must be a positive integer, got ~S." field value))
  value)

(defun %proper-list-p (value)
  (or (null value)
      (and (consp value) (%proper-list-p (cdr value)))))

(defun %normalize-string-list (values field condition-type)
  (unless (and (%proper-list-p values)
               (every #'%non-empty-string-p values))
    (%fail condition-type "~A must be a list of non-empty strings, got ~S."
           field values))
  (sort (remove-duplicates (mapcar #'copy-seq values) :test #'string=)
        #'string<))

(defun %camel-case-p (value)
  ;; Lower camelCase: a lowercase ASCII first letter and alphanumeric
  ;; remainder; interior capitals are the camelCase humps themselves.
  (and (%non-empty-string-p value)
       (let ((chars (coerce value 'list)))
         (and (lower-case-p (first chars))
              (every #'alphanumericp chars)
              value))))

(defun %require-camel-case (value field condition-type)
  (unless (%camel-case-p value)
    (%fail condition-type
           "~A must be an ASCII lower camelCase identifier, got ~S."
           field value))
  (copy-seq value))

(defun %copy-portable-value (value field condition-type)
  ;; Portable expert-state values: strings, integers, booleans, and
  ;; lists/records built from them.  Everything else is rejected so the
  ;; expert state stays serializable and runtime-neutral.
  (cond
    ((stringp value) (copy-seq value))
    ((integerp value) value)
    ((eq value t) t)
    ((eq value nil) nil)
    ((and (%proper-list-p value) (every #'consp value))
     (mapcar (lambda (entry)
               (unless (%non-empty-string-p (car entry))
                 (%fail condition-type
                        "~A record keys must be non-empty strings, got ~S."
                        field (car entry)))
               (cons (copy-seq (car entry))
                     (%copy-portable-value (cdr entry) field condition-type)))
             value))
    ((and (%proper-list-p value))
     (mapcar (lambda (item)
               (%copy-portable-value item field condition-type))
             value))
    (t
     (%fail condition-type
            "~A must be a portable value (string, integer, boolean, list or record), got ~S."
            field value))))

;;;; ---------------------------------------------------------------------
;;;; Typed model/provider requirements.

(defstruct (llm-model-requirement
            (:constructor %make-llm-model-requirement))
  providers
  min-context-tokens
  required-capabilities)

(defun make-llm-model-requirement
    (&key providers min-context-tokens (required-capabilities '()))
  (let ((providers (%normalize-string-list
                    providers "requirement providers"
                    'invalid-llm-model-requirement-error)))
    (unless providers
      (%fail 'invalid-llm-model-requirement-error
             "A model requirement must name at least one provider id."))
    (%make-llm-model-requirement
     :providers providers
     :min-context-tokens (%require-positive-integer
                          min-context-tokens "minimum context tokens"
                          'invalid-llm-model-requirement-error)
     :required-capabilities
     (%normalize-string-list
      required-capabilities "required capabilities"
      'invalid-llm-model-requirement-error))))

;;;; ---------------------------------------------------------------------
;;;; Provider descriptors, registry, and policy-validated selection.
;;;;
;;;; Provider/model selection is DATA validated by runtime policy: the
;;;; requirement names acceptable provider ids; only descriptors registered
;;;; in the runtime registry can satisfy it.  No provider is hard-coded.

(defstruct (llm-provider-descriptor
            (:constructor %make-llm-provider-descriptor))
  provider
  model
  context-tokens
  capabilities)

(defun make-llm-provider-descriptor
    (&key provider model context-tokens (capabilities '()))
  (%make-llm-provider-descriptor
   :provider (%require-non-empty-string
              provider "provider id" 'invalid-llm-provider-descriptor-error)
   :model (%require-non-empty-string
           model "model id" 'invalid-llm-provider-descriptor-error)
   :context-tokens (%require-positive-integer
                    context-tokens "context tokens"
                    'invalid-llm-provider-descriptor-error)
   :capabilities (%normalize-string-list
                  capabilities "provider capabilities"
                  'invalid-llm-provider-descriptor-error)))

(defstruct (llm-provider-registry
            (:constructor %make-llm-provider-registry))
  (table (make-hash-table :test #'equal)))

(defun make-llm-provider-registry ()
  (%make-llm-provider-registry))

(defun register-llm-provider (registry descriptor &key replace)
  (check-type registry llm-provider-registry)
  (check-type descriptor llm-provider-descriptor)
  (let ((id (llm-provider-descriptor-provider descriptor))
        (table (llm-provider-registry-table registry)))
    (when (and (gethash id table) (not replace))
      (%fail 'duplicate-llm-provider-error
             "Provider ~S is already registered." id))
    (setf (gethash id table) descriptor)
    descriptor))

(defun find-llm-provider (registry provider-id)
  (check-type registry llm-provider-registry)
  (gethash provider-id (llm-provider-registry-table registry)))

(defun list-llm-providers (registry)
  (check-type registry llm-provider-registry)
  (let ((descriptors '()))
    (maphash (lambda (id descriptor)
               (declare (ignore id))
               (push descriptor descriptors))
             (llm-provider-registry-table registry))
    (sort descriptors #'string<
          :key #'llm-provider-descriptor-provider)))

(defstruct (llm-selection
            (:constructor %make-llm-selection))
  provider
  model
  candidates)

(defun %requirement-satisfies-policy-p (descriptor requirement)
  ;; Policy checks: the descriptor must be one of the acceptable provider
  ;; ids, cover every required capability, and meet the context floor.
  (and (member (llm-provider-descriptor-provider descriptor)
               (llm-model-requirement-providers requirement)
               :test #'string=)
       (>= (llm-provider-descriptor-context-tokens descriptor)
           (llm-model-requirement-min-context-tokens requirement))
       (subsetp (llm-model-requirement-required-capabilities requirement)
                (llm-provider-descriptor-capabilities descriptor)
                :test #'string=)))

(defun select-llm-provider (registry requirement)
  "Validate REQUIREMENT as data against the runtime provider policy in
REGISTRY and return the deterministic selection, scanning candidates in
sorted provider-id order.  Signals llm-provider-selection-error when no
registered descriptor satisfies the policy."
  (check-type registry llm-provider-registry)
  (check-type requirement llm-model-requirement)
  (let ((candidates '())
        (selected nil))
    (dolist (descriptor (list-llm-providers registry))
      (let ((status
              (if (%requirement-satisfies-policy-p descriptor requirement)
                  (progn
                    (unless selected (setf selected descriptor))
                    "selected")
                  "rejected")))
        (push (cons (llm-provider-descriptor-provider descriptor) status)
              candidates)))
    (unless selected
      (%fail 'llm-provider-selection-error
             "No registered provider satisfies requirement (providers ~S, min context ~D, capabilities ~S)."
             (llm-model-requirement-providers requirement)
             (llm-model-requirement-min-context-tokens requirement)
             (llm-model-requirement-required-capabilities requirement)))
    (%make-llm-selection
     :provider (llm-provider-descriptor-provider selected)
     :model (llm-provider-descriptor-model selected)
     :candidates (nreverse candidates))))

;;;; ---------------------------------------------------------------------
;;;; Prompt templates: deterministic substitution, fail closed.

(defstruct (llm-prompt-template
            (:constructor %make-llm-prompt-template))
  id
  version
  body)

(defun make-llm-prompt-template (&key id version body)
  (%make-llm-prompt-template
   :id (%require-non-empty-string
        id "template id" 'invalid-llm-prompt-template-error)
   :version (%require-positive-integer
             version "template version" 'invalid-llm-prompt-template-error)
   :body (%require-non-empty-string
          body "template body" 'invalid-llm-prompt-template-error)))

(defun %placeholder-name-p (value)
  (%camel-case-p value))

(defun render-llm-prompt (template bindings)
  "Substitute {{camelCase}} placeholders in TEMPLATE from BINDINGS (an
alist of string names to string values).  Missing bindings and unresolved
placeholders both fail closed."
  (check-type template llm-prompt-template)
  (unless (and (%proper-list-p bindings)
               (every (lambda (entry)
                        (and (consp entry)
                             (%non-empty-string-p (car entry))
                             (stringp (cdr entry))))
                      bindings))
    (%fail 'llm-prompt-render-error
           "Prompt bindings must be an alist of string names to string values."))
  (let ((body (llm-prompt-template-body template))
        (missing '())
        (rendered
          (with-output-to-string (stream)
            (flet ((lookup (name)
                     (cdr (assoc name bindings :test #'string=))))
              (let ((index 0)
                    (length (length body)))
                (loop
                  (when (>= index length) (return))
                  (let ((open (search "{{" body :start2 index)))
                    (unless open
                      (write-string body stream :start index)
                      (return))
                    (write-string body stream :start index :end open)
                    (let ((close (search "}}" body :start2 (+ open 2))))
                      (unless close
                        (%fail 'llm-prompt-render-error
                               "Template ~S has an unterminated placeholder."
                               (llm-prompt-template-id template)))
                      (let* ((name (string-trim
                                    " "
                                    (subseq body (+ open 2) close))))
                        (unless (%placeholder-name-p name)
                          (%fail 'llm-prompt-render-error
                                 "Template ~S has an invalid placeholder {{~A}}."
                                 (llm-prompt-template-id template) name))
                        (let ((value (lookup name)))
                          (unless value
                            (push name missing)
                            (setf value ""))
                          (write-string value stream))
                        (setf index (+ close 2)))))))))))
    (when missing
      (%fail 'llm-prompt-render-error
             "Template ~S is missing bindings for ~{~S~^, ~}."
             (llm-prompt-template-id template) (nreverse missing)))
    rendered))

;;;; ---------------------------------------------------------------------
;;;; Structured response schemas: output validates before expert state.

(defparameter +llm-schema-field-types+
  '("string" "integer" "boolean" "enum" "string-array"))

(defstruct (llm-schema-field
            (:constructor %make-llm-schema-field))
  name
  type
  values)

(defun make-llm-schema-field (&key name type (values '()))
  (%make-llm-schema-field
   :name (%require-camel-case
          name "schema field name" 'invalid-llm-response-schema-error)
   :type (cond
           ((and (stringp type) (member type +llm-schema-field-types+
                                        :test #'string=))
            (copy-seq type))
           (t (%fail 'invalid-llm-response-schema-error
                     "Schema field ~S has unsupported type ~S." name type)))
   :values (if (string= type "enum")
               (%normalize-string-list
                values "enum values" 'invalid-llm-response-schema-error)
               nil)))

(defstruct (llm-response-schema
            (:constructor %make-llm-response-schema))
  fields
  required)

(defun %schema-field-names (fields)
  (mapcar #'llm-schema-field-name fields))

(defun make-llm-response-schema (&key fields (required '()))
  (unless (and (%proper-list-p fields)
               (every #'llm-schema-field-p fields))
    (%fail 'invalid-llm-response-schema-error
           "Schema fields must be a list of schema fields, got ~S." fields))
  (let ((names (%schema-field-names fields)))
    (when (/= (length names) (length (remove-duplicates names :test #'string=)))
      (%fail 'invalid-llm-response-schema-error
             "Schema declares duplicate field names: ~S." names))
    (dolist (name required)
      (unless (member name names :test #'string=)
        (%fail 'invalid-llm-response-schema-error
               "Required field ~S is not declared in the schema." name)))
    (%make-llm-response-schema
     :fields (mapcar #'copy-structure fields)
     :required (%normalize-string-list
                required "required fields" 'invalid-llm-response-schema-error))))

(defun %validate-structured-value (field value)
  (let ((type (llm-schema-field-type field))
        (name (llm-schema-field-name field)))
    (labels ((fail (control &rest arguments)
               (%fail 'invalid-llm-structured-output-error
                      "Field ~S: ~?" name control arguments)))
      (cond
        ((string= type "string")
         (unless (stringp value) (fail "expected a string, got ~S." value))
         (copy-seq value))
        ((string= type "integer")
         (unless (and (integerp value) (not (typep value 'boolean)))
           (fail "expected an integer, got ~S." value))
         value)
        ((string= type "boolean")
         (unless (typep value 'boolean) (fail "expected a boolean, got ~S." value))
         value)
        ((string= type "enum")
         (unless (and (stringp value)
                      (member value (llm-schema-field-values field)
                              :test #'string=))
           (fail "expected one of ~S, got ~S."
                 (llm-schema-field-values field) value))
         (copy-seq value))
        ((string= type "string-array")
         (unless (and (%proper-list-p value)
                      (every #'stringp value))
           (fail "expected a list of strings, got ~S." value))
         (mapcar #'copy-seq value))
        (t (fail "unknown field type ~S." type))))))

(defun validate-llm-structured-output (schema payload)
  "Validate PAYLOAD (an alist keyed by camelCase field names) against
SCHEMA.  Returns a fresh normalized record.  Unknown fields are rejected
so model output can never smuggle undeclared keys (e.g. capability
grants) into expert state.  Signals invalid-llm-structured-output-error."
  (check-type schema llm-response-schema)
  (unless (and (%proper-list-p payload) (every #'consp payload))
    (%fail 'invalid-llm-structured-output-error
           "Structured output must be an alist of field name to value, got ~S."
           payload))
  (let ((fields (llm-response-schema-fields schema))
        (validated '()))
    (dolist (entry payload)
      (let ((name (car entry)))
        (unless (%non-empty-string-p name)
          (%fail 'invalid-llm-structured-output-error
                 "Structured output keys must be strings, got ~S." name))
        (let ((field (find name fields :test #'string=
                                        :key #'llm-schema-field-name)))
          (unless field
            (%fail 'invalid-llm-structured-output-error
                   "Structured output declares unknown field ~S." name))
          (push (cons name (%validate-structured-value field (cdr entry)))
                validated))))
    (dolist (name (llm-response-schema-required schema))
      (unless (assoc name validated :test #'string=)
        (%fail 'invalid-llm-structured-output-error
               "Required field ~S is missing from structured output." name)))
    ;; Deterministic field order (sorted) for downstream digests.
    (sort validated #'string< :key #'car)))

;;;; ---------------------------------------------------------------------
;;;; Tools and capability grants.
;;;;
;;;; A tool request is DATA that arrives from model output.  It must pass
;;;; schema validation of the declared tool AND authorization against the
;;;; grants declared by the compiled expert graph.  Model text never
;;;; grants capabilities.

(defstruct (llm-tool
            (:constructor %make-llm-tool))
  id
  description
  input-schema)

(defun make-llm-tool (&key id (description "") input-schema)
  (unless (or (null description) (stringp description))
    (%fail 'invalid-llm-tool-error "Tool description must be a string."))
  (check-type input-schema llm-response-schema)
  (%make-llm-tool
   :id (%require-camel-case id "tool id" 'invalid-llm-tool-error)
   :description (copy-seq description)
   :input-schema input-schema))

(defstruct (llm-tool-request
            (:constructor %make-llm-tool-request))
  tool
  arguments)

(defun make-llm-tool-request (&key tool arguments)
  (%make-llm-tool-request
   :tool (%require-non-empty-string
          tool "requested tool id" 'invalid-llm-tool-request-error)
   :arguments (if (null arguments)
                  nil
                  (%copy-portable-value arguments "tool arguments"
                                        'invalid-llm-tool-request-error))))

(defun %find-tool (expert tool-id)
  (find tool-id (llm-expert-tools expert)
        :test #'string= :key #'llm-tool-id))

(defun validate-llm-tool-request (expert request)
  "Shape-check REQUEST against the tools declared by EXPERT.  Returns T
when the request is well formed.  Unknown tool ids are untrusted
(untrusted-llm-tool-request-error); malformed arguments are invalid
(invalid-llm-tool-request-error)."
  (check-type expert llm-expert)
  (check-type request llm-tool-request)
  (let ((tool (%find-tool expert (llm-tool-request-tool request))))
    (unless tool
      (%fail 'untrusted-llm-tool-request-error
             "Tool request names undeclared tool ~S; rejected as untrusted."
             (llm-tool-request-tool request)))
    (handler-case
        (validate-llm-structured-output
         (llm-tool-input-schema tool) (llm-tool-request-arguments request))
      (invalid-llm-structured-output-error (condition)
        (%fail 'invalid-llm-tool-request-error
               "Tool request for ~S has malformed arguments: ~A."
               (llm-tool-request-tool request)
               (star-llm-expert-error-message condition))))
    t))

(defun authorize-llm-tool-request (expert request)
  "Return T only when EXPERT's declared grants authorize REQUEST.  The
grant list is static expert-graph data; nothing in model output can
extend it."
  (check-type expert llm-expert)
  (check-type request llm-tool-request)
  (and (member (llm-tool-request-tool request)
               (llm-expert-grants expert)
               :test #'string=)
       t))

;;;; ---------------------------------------------------------------------
;;;; Expert rules.

(defparameter +llm-rule-condition-ops+
  '("eq" "ne" "lt" "le" "gt" "ge" "present" "absent"))

(defparameter +llm-rule-action-kinds+ '("set-fact" "finish"))

(defstruct (llm-expert-rule
            (:constructor %make-llm-expert-rule))
  id
  condition-fact
  condition-op
  condition-value
  action-kind
  action-fact
  action-value)

(defun make-llm-expert-rule
    (&key id condition-fact condition-op condition-value
            action-kind action-fact action-value)
  (unless (and (stringp condition-op)
               (member condition-op +llm-rule-condition-ops+
                       :test #'string=))
    (%fail 'invalid-llm-expert-rule-error
           "Rule ~S has unknown condition operator ~S." id condition-op))
  (unless (and (stringp action-kind)
               (member action-kind +llm-rule-action-kinds+ :test #'string=))
    (%fail 'invalid-llm-expert-rule-error
           "Rule ~S has unknown action kind ~S." id action-kind))
  (when (and (string= condition-op "present")
             condition-value)
    (%fail 'invalid-llm-expert-rule-error
           "Rule ~S uses op present with a value." id))
  (when (string= action-kind "set-fact")
    (unless (%camel-case-p action-fact)
      (%fail 'invalid-llm-expert-rule-error
             "Rule ~S set-fact action needs a camelCase fact name." id)))
  (when (and action-value
             (not (or (stringp action-value)
                      (integerp action-value)
                      (typep action-value 'boolean))))
    (%fail 'invalid-llm-expert-rule-error
           "Rule ~S action value must be a string, integer or boolean." id))
  (%make-llm-expert-rule
   :id (%require-non-empty-string id "rule id" 'invalid-llm-expert-rule-error)
   :condition-fact (%require-camel-case
                    condition-fact "rule condition fact"
                    'invalid-llm-expert-rule-error)
   :condition-op (copy-seq condition-op)
   :condition-value (when condition-value
                      (%copy-portable-value
                       condition-value "rule condition value"
                       'invalid-llm-expert-rule-error))
   :action-kind (copy-seq action-kind)
   :action-fact (when action-fact
                  (%require-camel-case action-fact "rule action fact"
                                       'invalid-llm-expert-rule-error))
   :action-value action-value))

;;;; ---------------------------------------------------------------------
;;;; Budgets.

(defstruct (llm-budget
            (:constructor %make-llm-budget))
  max-model-calls
  max-tool-invocations
  max-total-tokens)

(defun make-llm-budget (&key max-model-calls max-tool-invocations
                             max-total-tokens)
  (%make-llm-budget
   :max-model-calls (%require-positive-integer
                     max-model-calls "maximum model calls"
                     'invalid-llm-budget-error)
   :max-tool-invocations (%require-positive-integer
                          max-tool-invocations "maximum tool invocations"
                          'invalid-llm-budget-error)
   :max-total-tokens (%require-positive-integer
                      max-total-tokens "maximum total tokens"
                      'invalid-llm-budget-error)))

;;;; ---------------------------------------------------------------------
;;;; Expert graph and compilation.

(defstruct (llm-expert
            (:constructor %make-llm-expert))
  id
  version
  route
  template
  response-schema
  tools
  grants
  rules
  verifiers
  budget)

(defun make-llm-expert (&key id version route template response-schema
                             tools (grants '()) (rules '())
                             (verifiers '()) budget)
  (macrolet ((require-list (values predicate what)
               `(progn
                  (unless (and (%proper-list-p ,values)
                               (every #',predicate ,values))
                    (%fail 'invalid-llm-expert-error
                           "Expert ~S ~A must be valid." id ,what))
                  ,values))
             (require-part (part predicate what)
               `(progn
                  (unless (funcall #',predicate ,part)
                    (%fail 'invalid-llm-expert-error
                           "Expert ~S needs ~A." id ,what))
                  ,part)))
    (unless (%non-empty-string-p id)
      (%fail 'invalid-llm-expert-error
             "Expert id must be a non-empty string, got ~S." id))
    (%make-llm-expert
     :id (copy-seq id)
     :version (%require-positive-integer version "expert version"
                                         'invalid-llm-expert-error)
     :route (require-list route llm-model-requirement-p "route")
     :template (require-part template llm-prompt-template-p "a prompt template")
     :response-schema (require-part response-schema llm-response-schema-p
                                    "a response schema")
     :tools (require-list tools llm-tool-p "tools")
     :grants (%normalize-string-list grants "expert grants"
                                     'invalid-llm-expert-error)
     :rules (require-list rules llm-expert-rule-p "rules")
     :verifiers (%normalize-string-list verifiers "expert verifiers"
                                        'invalid-llm-expert-error)
     :budget (require-part budget llm-budget-p "a budget"))))

(defstruct (compiled-llm-expert
            (:constructor %make-compiled-llm-expert))
  graph
  digest)

(defun make-llm-verifier-table ()
  (make-hash-table :test #'equal))

(defun register-llm-verifier (table id verifier)
  (check-type table hash-table)
  (unless (%non-empty-string-p id)
    (%fail 'invalid-llm-expert-error "Verifier id must be a non-empty string."))
  (unless (functionp verifier)
    (%fail 'invalid-llm-expert-error "Verifier ~S must be a function." id))
  (setf (gethash (copy-seq id) table) verifier)
  table)

(defun run-llm-verifier (table id facts)
  "Run the pure verifier predicate registered under ID against the fact
alist FACTS.  Verifiers are deterministic non-model stages."
  (check-type table hash-table)
  (let ((verifier (gethash id table)))
    (unless (functionp verifier)
      (%fail 'llm-verifier-not-found-error
             "No verifier registered under id ~S." id))
    (and (funcall verifier facts) t)))

(defun sha256-digest-string (octets)
  (format nil "sha256:~A"
          (ironclad:byte-array-to-hex-string
           (ironclad:digest-sequence (ironclad:make-digest :sha256) octets))))

(defun compile-llm-expert (expert &key verifier-table)
  "Validate the whole expert graph (route, grants against declared tools,
verifier references against VERIFIER-TABLE) and freeze it into a compiled
expert carrying a deterministic sha256 digest of its canonical form."
  (check-type expert llm-expert)
  (unless (and verifier-table (hash-table-p verifier-table))
    (%fail 'invalid-llm-expert-error
           "compile-llm-expert needs a verifier table (use make-llm-verifier-table)."))
  ;; Every grant must name a declared tool: grants are static data.
  (dolist (grant (llm-expert-grants expert))
    (unless (%find-tool expert grant)
      (%fail 'invalid-llm-expert-error
             "Grant ~S does not name a declared tool." grant)))
  ;; Every declared tool id must be granted or deliberately ungranted;
  ;; duplicates in the tool list are rejected so authorization is unambiguous.
  (let ((ids (mapcar #'llm-tool-id (llm-expert-tools expert))))
    (when (/= (length ids) (length (remove-duplicates ids :test #'string=)))
      (%fail 'invalid-llm-expert-error
             "Expert ~S declares duplicate tool ids." (llm-expert-id expert))))
  ;; Route must be non-empty and deterministic fallback order is the list
  ;; order; every referenced verifier must resolve in the verifier table.
  (unless (llm-expert-route expert)
    (%fail 'invalid-llm-expert-error
           "Expert ~S needs a non-empty fallback route." (llm-expert-id expert)))
  (dolist (id (llm-expert-verifiers expert))
    (unless (gethash id verifier-table)
      (%fail 'llm-verifier-not-found-error
             "Expert ~S references unregistered verifier ~S."
             (llm-expert-id expert) id)))
  (%make-compiled-llm-expert
   :graph expert
   :digest (sha256-digest-string
            (babel:string-to-octets
             (llm-expert-json-string expert) :encoding :utf-8))))
