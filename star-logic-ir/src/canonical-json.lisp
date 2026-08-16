(in-package :starlogicir)

(defun %nullable-string-json (value)
  (if value value +json-null+))

(defun %string-list-json (values)
  (make-json-array (mapcar #'copy-seq values)))

(defun %portable-value-json (value)
  (cond
    ((stringp value) value)
    ((integerp value) value)
    ((eq value t) +json-true+)
    ((null value) +json-null+)
    ((%record-shape-p value) (%record-json value))
    ((%proper-list-p value)
     (make-json-array (mapcar #'%portable-value-json value)))
    (t
     (%fail 'invalid-logic-value-error
            "Cannot serialize non-portable logic value ~S." value))))

(defun %record-json (record)
  (make-json-object
   (mapcar (lambda (entry)
             (cons (copy-seq (car entry))
                   (%portable-value-json (cdr entry))))
           record)))

(defun %optional-record-json (record)
  (if record (%record-json record) +json-null+))

(defun logic-call-json-object (call)
  (unless (logic-call-p call)
    (%fail 'invalid-logic-operation-error
           "Expected a logic-call for serialization, got ~S." call))
  (let ((identity (logic-call-package-identity call)))
    (make-json-object
     (list
      (cons "operationId" (logic-call-operation-id call))
      (cons "namedOperationId"
            (%nullable-string-json (logic-call-named-operation-id call)))
      (cons "operationKind" (logic-call-operation-kind call))
      (cons "semanticProfile" (logic-call-semantic-profile call))
      (cons "backendPolicy" (logic-call-backend-policy call))
      (cons "bindings" (%record-json (logic-call-bindings call)))
      (cons "answerPolicy"
            (%optional-record-json (logic-call-answer-policy call)))
      (cons "proofPolicy"
            (%optional-record-json (logic-call-proof-policy call)))
      (cons "requiredCapabilities"
            (%string-list-json (logic-call-required-capabilities call)))
      (cons "requiredHardLimits"
            (%string-list-json (logic-call-required-hard-limits call)))
      (cons "requiredIsolation"
            (%nullable-string-json (logic-call-required-isolation call)))
      (cons "packageId" (logic-package-identity-package-id identity))
      (cons "packageVersion"
            (logic-package-identity-package-version identity))
      (cons "packageDigest"
            (logic-package-identity-package-digest identity))
      (cons "mappingId" (logic-package-identity-mapping-id identity))
      (cons "mappingDigest"
            (logic-package-identity-mapping-digest identity))
      (cons "budget" (%optional-record-json (logic-call-budget call)))
      (cons "sourceSpan"
            (%optional-record-json (logic-call-source-span call)))))))

(defun %candidate-status-string (status)
  (unless (symbolp status)
    (%fail 'invalid-logic-value-error
           "Selection candidate status must be a symbol, got ~S." status))
  (string-downcase (symbol-name status)))

(defun %candidate-json-object (candidate)
  (make-json-object
   (list
    (cons "id" (logic-selection-candidate-backend-id candidate))
    (cons "status"
          (%candidate-status-string
           (logic-selection-candidate-status candidate)))
    (cons "reason"
          (%nullable-string-json
           (logic-selection-candidate-reason candidate))))))

(defun logic-selection-evidence-json-object (evidence)
  (make-json-object
   (list
    (cons "requested" (logic-selection-evidence-requested evidence))
    (cons "semanticProfile"
          (logic-selection-evidence-semantic-profile evidence))
    (cons "requiredCapabilities"
          (%string-list-json
           (logic-selection-evidence-required-capabilities evidence)))
    (cons "requiredHardLimits"
          (%string-list-json
           (logic-selection-evidence-required-hard-limits evidence)))
    (cons "requiredIsolation"
          (%nullable-string-json
           (logic-selection-evidence-required-isolation evidence)))
    (cons "candidates"
          (make-json-array
           (mapcar #'%candidate-json-object
                   (logic-selection-evidence-candidates evidence))))
    (cons "selected"
          (%nullable-string-json
           (logic-selection-evidence-selected evidence)))
    (cons "policy" (logic-selection-evidence-policy evidence)))))

(defun materialized-logic-call-json-object (plan)
  (unless (materialized-logic-call-p plan)
    (%fail 'invalid-logic-operation-error
           "Expected a materialized-logic-call for serialization, got ~S." plan))
  (make-json-object
   (list
    (cons "backendId" (materialized-logic-call-backend-id plan))
    (cons "backendVersion" (materialized-logic-call-backend-version plan))
    (cons "backendBuildId" (materialized-logic-call-backend-build-id plan))
    (cons "logicCall"
          (logic-call-json-object (materialized-logic-call-logic-call plan)))
    (cons "selectionEvidence"
          (logic-selection-evidence-json-object
           (materialized-logic-call-selection-evidence plan))))))

(defun logic-call-canonical-json (call)
  (canonical-json-string (logic-call-json-object call)))

(defun materialized-logic-call-canonical-json (plan)
  (canonical-json-string (materialized-logic-call-json-object plan)))
