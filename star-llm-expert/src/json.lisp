(in-package :starllmexpert)

;;;; Canonical, versioned, runtime-neutral serialization of expert graphs
;;;; (issue #138).  Wire keys are lower camelCase; output is canonical JSON
;;;; so equal graphs serialize byte-identically.

(defun %string-value (value)
  (copy-seq value))

(defun %string-list-json (values)
  (make-json-array (mapcar #'%string-value values)))

(defun %portable-scalar-json (value)
  (cond
    ((stringp value) (%string-value value))
    ((integerp value) value)
    ((eq value t) +json-true+)
    ((eq value nil) +json-null+)
    (t (%fail 'invalid-llm-expert-error
              "Cannot serialize portable value ~S." value))))

(defun %model-requirement-json (requirement)
  (make-json-object
   (list
    (cons "providers" (%string-list-json
                       (llm-model-requirement-providers requirement)))
    (cons "minContextTokens"
          (llm-model-requirement-min-context-tokens requirement))
    (cons "requiredCapabilities"
          (%string-list-json
           (llm-model-requirement-required-capabilities requirement))))))

(defun %response-schema-json (schema)
  (make-json-object
   (list
    (cons "fields"
          (make-json-array
           (mapcar
            (lambda (field)
              (make-json-object
               (remove nil
                       (list
                        (cons "name" (%string-value
                                      (llm-schema-field-name field)))
                        (cons "type" (%string-value
                                      (llm-schema-field-type field)))
                        (when (llm-schema-field-values field)
                          (cons "values"
                                (%string-list-json
                                 (llm-schema-field-values field))))))))
            (llm-response-schema-fields schema))))
    (cons "required" (%string-list-json
                      (llm-response-schema-required schema))))))

(defun %tool-json (tool)
  (make-json-object
   (list
    (cons "id" (%string-value (llm-tool-id tool)))
    (cons "description" (%string-value (llm-tool-description tool)))
    (cons "inputSchema" (%response-schema-json (llm-tool-input-schema tool))))))

(defun %rule-json (rule)
  (make-json-object
   (remove nil
           (list
            (cons "id" (%string-value (llm-expert-rule-id rule)))
            (cons "condition"
                  (make-json-object
                   (remove nil
                           (list
                            (cons "fact" (%string-value
                                          (llm-expert-rule-condition-fact rule)))
                            (cons "op" (%string-value
                                        (llm-expert-rule-condition-op rule)))
                            (when (llm-expert-rule-condition-value rule)
                              (cons "value"
                                    (%portable-scalar-json
                                     (llm-expert-rule-condition-value rule))))))))
            (cons "action"
                  (make-json-object
                   (remove nil
                           (list
                            (cons "kind" (%string-value
                                          (llm-expert-rule-action-kind rule)))
                            (when (llm-expert-rule-action-fact rule)
                              (cons "fact" (%string-value
                                            (llm-expert-rule-action-fact rule))))
                            (when (llm-expert-rule-action-value rule)
                              (cons "value"
                                    (%portable-scalar-json
                                     (llm-expert-rule-action-value rule))))))))))))

(defun llm-expert-json-object (graph-or-compiled)
  "Return the canonical JSON object of an expert graph.  Accepts a raw
graph or a compiled expert (the digest is compilation provenance, not
graph data, and is not serialized)."
  (let ((graph (if (compiled-llm-expert-p graph-or-compiled)
                   (compiled-llm-expert-graph graph-or-compiled)
                   graph-or-compiled)))
    (unless (llm-expert-p graph)
      (%fail 'invalid-llm-expert-error
             "Expected an expert graph, got ~S." graph-or-compiled))
    (make-json-object
     (list
      (cons "schema" (%string-value +llm-expert-schema+))
      (cons "id" (%string-value (llm-expert-id graph)))
      (cons "version" (llm-expert-version graph))
      (cons "route" (make-json-array
                     (mapcar #'%model-requirement-json
                             (llm-expert-route graph))))
      (cons "template" (make-json-object
                        (list
                         (cons "id" (%string-value
                                     (llm-prompt-template-id
                                      (llm-expert-template graph))))
                         (cons "version"
                               (llm-prompt-template-version
                                (llm-expert-template graph)))
                         (cons "body" (%string-value
                                       (llm-prompt-template-body
                                        (llm-expert-template graph)))))))
      (cons "responseSchema" (%response-schema-json
                              (llm-expert-response-schema graph)))
      (cons "tools" (make-json-array
                     (mapcar #'%tool-json (llm-expert-tools graph))))
      (cons "grants" (%string-list-json (llm-expert-grants graph)))
      (cons "rules" (make-json-array
                     (mapcar #'%rule-json (llm-expert-rules graph))))
      (cons "verifiers" (%string-list-json (llm-expert-verifiers graph)))
      (cons "budget" (make-json-object
                      (list
                       (cons "maxModelCalls"
                             (llm-budget-max-model-calls
                              (llm-expert-budget graph)))
                       (cons "maxToolInvocations"
                             (llm-budget-max-tool-invocations
                              (llm-expert-budget graph)))
                       (cons "maxTotalTokens"
                             (llm-budget-max-total-tokens
                              (llm-expert-budget graph))))))))))

(defun llm-expert-json-string (graph-or-compiled)
  "Canonical JSON string of the expert graph; deterministic bytes for
equal graphs."
  (canonical-json-string (llm-expert-json-object graph-or-compiled)))
