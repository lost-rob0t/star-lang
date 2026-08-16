(in-package :starlogicir)

(defparameter +logic-backend-auto+ "auto")
(defparameter +logic-operation-kinds+
  '("assert!" "retract!" "solve" "solutions" "exists?" "explain"))

(define-condition logic-ir-error (error)
  ((message :initarg :message :reader logic-ir-error-message))
  (:report (lambda (condition stream)
             (write-string (logic-ir-error-message condition) stream))))

(define-condition invalid-logic-backend-policy-error (logic-ir-error) ())
(define-condition invalid-logic-operation-error (logic-ir-error) ())
(define-condition invalid-logic-package-identity-error (logic-ir-error) ())
(define-condition invalid-logic-value-error (logic-ir-error) ())
(define-condition logic-materialized-backend-change-error (logic-ir-error) ())

(defun %fail (condition-type control &rest arguments)
  (error condition-type :message (apply #'format nil control arguments)))

(defun %non-empty-string-p (value)
  (and (stringp value) (plusp (length value))))

(defun %require-non-empty-string (value field condition-type)
  (unless (%non-empty-string-p value)
    (%fail condition-type "~A must be a non-empty string, got ~S." field value))
  (copy-seq value))

(defun %string-prefix-p (prefix value)
  (and (stringp value)
       (<= (length prefix) (length value))
       (string= prefix value :end2 (length prefix))))

(defun %digest-p (value)
  (and (%non-empty-string-p value)
       (> (length value) (length "sha256:"))
       (%string-prefix-p "sha256:" value)))

(defun %require-digest (value field)
  (unless (%digest-p value)
    (%fail 'invalid-logic-package-identity-error
           "~A must be a digest-locked sha256 identity, got ~S."
           field value))
  (copy-seq value))

(defun %proper-list-p (value)
  (handler-case
      (not (null (list-length value)))
    (type-error () nil)))

(defun %record-shape-p (value)
  (and (consp value)
       (%proper-list-p value)
       (every (lambda (entry)
                (and (consp entry)
                     (%non-empty-string-p (car entry))))
              value)))

(defun %normalize-string-list (values field condition-type)
  (unless (%proper-list-p values)
    (%fail condition-type "~A must be a proper list of strings, got ~S."
           field values))
  (let ((normalized
          (mapcar (lambda (value)
                    (%require-non-empty-string value field condition-type))
                  values)))
    (sort (remove-duplicates normalized :test #'string=) #'string<)))

(defun %copy-string-list (values)
  (mapcar #'copy-seq values))

(defun %copy-portable-value (value field)
  (cond
    ((stringp value) (copy-seq value))
    ((integerp value) value)
    ((eq value t) t)
    ((null value) nil)
    ((%record-shape-p value) (%normalize-record value field))
    ((%proper-list-p value)
     (mapcar (lambda (item) (%copy-portable-value item field)) value))
    (t
     (%fail 'invalid-logic-value-error
            "~A contains a non-portable value ~S; native objects, symbols, functions, and engine handles are forbidden in normalized logic IR."
            field value))))

(defun %normalize-record (value field)
  (unless (%proper-list-p value)
    (%fail 'invalid-logic-value-error
           "~A must be a proper string-keyed record, got ~S." field value))
  (let ((entries
          (mapcar
           (lambda (entry)
             (unless (and (consp entry) (%non-empty-string-p (car entry)))
               (%fail 'invalid-logic-value-error
                      "~A contains an invalid record entry ~S; keys must be non-empty strings."
                      field entry))
             (cons (copy-seq (car entry))
                   (%copy-portable-value (cdr entry) field)))
           value)))
    (setf entries (sort entries #'string< :key #'car))
    (loop for tail on entries
          while (cdr tail)
          when (string= (caar tail) (caadr tail))
            do (%fail 'invalid-logic-value-error
                      "~A contains duplicate field ~S."
                      field (caar tail)))
    entries))

(defun %normalize-optional-record (value field)
  (if (null value)
      nil
      (%normalize-record value field)))

(defun %copy-record (value)
  (and value (%normalize-record value "logic record")))

(defun logic-backend-policy-p (value)
  (and (stringp value)
       (member value
               (list +logic-backend-auto+
                     +logic-backend-lisa+
                     +logic-backend-swi-prolog+
                     +logic-backend-n-prolog+)
               :test #'string=)
       t))

(defun logic-operation-kind-p (value)
  (and (stringp value)
       (member value +logic-operation-kinds+ :test #'string=)
       t))

(defclass logic-package-identity ()
  ((package-id :initarg :package-id :reader %logic-package-identity-package-id)
   (package-version :initarg :package-version
                    :reader %logic-package-identity-package-version)
   (package-digest :initarg :package-digest
                   :reader %logic-package-identity-package-digest)
   (mapping-id :initarg :mapping-id :reader %logic-package-identity-mapping-id)
   (mapping-digest :initarg :mapping-digest
                   :reader %logic-package-identity-mapping-digest)))

(defun logic-package-identity-p (value)
  (typep value 'logic-package-identity))

(defun make-logic-package-identity
    (&key package-id package-version package-digest mapping-id mapping-digest)
  (make-instance
   'logic-package-identity
   :package-id
   (%require-non-empty-string package-id "package id"
                              'invalid-logic-package-identity-error)
   :package-version
   (%require-non-empty-string package-version "package version"
                              'invalid-logic-package-identity-error)
   :package-digest (%require-digest package-digest "package digest")
   :mapping-id
   (%require-non-empty-string mapping-id "mapping id"
                              'invalid-logic-package-identity-error)
   :mapping-digest (%require-digest mapping-digest "mapping digest")))

(defun logic-package-identity-package-id (identity)
  (copy-seq (%logic-package-identity-package-id identity)))

(defun logic-package-identity-package-version (identity)
  (copy-seq (%logic-package-identity-package-version identity)))

(defun logic-package-identity-package-digest (identity)
  (copy-seq (%logic-package-identity-package-digest identity)))

(defun logic-package-identity-mapping-id (identity)
  (copy-seq (%logic-package-identity-mapping-id identity)))

(defun logic-package-identity-mapping-digest (identity)
  (copy-seq (%logic-package-identity-mapping-digest identity)))

(defclass logic-call ()
  ((operation-id :initarg :operation-id :reader %logic-call-operation-id)
   (named-operation-id :initarg :named-operation-id
                       :reader %logic-call-named-operation-id)
   (operation-kind :initarg :operation-kind :reader %logic-call-operation-kind)
   (semantic-profile :initarg :semantic-profile
                     :reader %logic-call-semantic-profile)
   (backend-policy :initarg :backend-policy :reader %logic-call-backend-policy)
   (bindings :initarg :bindings :reader %logic-call-bindings)
   (answer-policy :initarg :answer-policy :reader %logic-call-answer-policy)
   (proof-policy :initarg :proof-policy :reader %logic-call-proof-policy)
   (required-capabilities :initarg :required-capabilities
                          :reader %logic-call-required-capabilities)
   (required-hard-limits :initarg :required-hard-limits
                         :reader %logic-call-required-hard-limits)
   (required-isolation :initarg :required-isolation
                       :reader %logic-call-required-isolation)
   (package-identity :initarg :package-identity
                     :reader %logic-call-package-identity)
   (budget :initarg :budget :reader %logic-call-budget)
   (source-span :initarg :source-span :reader %logic-call-source-span)))

(defun logic-call-p (value)
  (typep value 'logic-call))

(defun %query-operation-p (operation-kind)
  (member operation-kind '("solve" "solutions" "exists?") :test #'string=))

(defun %unnamed-operation-p (operation-kind)
  (member operation-kind '("assert!" "retract!" "explain") :test #'string=))

(defun make-logic-call
    (&key operation-id
          named-operation-id
          operation-kind
          semantic-profile
          backend-policy
          bindings
          answer-policy
          proof-policy
          required-capabilities
          required-hard-limits
          required-isolation
          package-identity
          budget
          source-span)
  (unless (logic-operation-kind-p operation-kind)
    (%fail 'invalid-logic-operation-error
           "Unknown logic operation kind ~S; expected one of ~{~S~^, ~}."
           operation-kind +logic-operation-kinds+))
  (unless (logic-backend-policy-p backend-policy)
    (%fail 'invalid-logic-backend-policy-error
           "Unknown or missing logic backend policy ~S; expected auto, lisa, swi-prolog, or n-prolog."
           backend-policy))
  (when (%query-operation-p operation-kind)
    (unless (%non-empty-string-p named-operation-id)
      (%fail 'invalid-logic-operation-error
             "Logic operation ~S requires a compiler-declared named operation id."
             operation-kind)))
  (when (and (%unnamed-operation-p operation-kind) named-operation-id)
    (%fail 'invalid-logic-operation-error
           "Logic operation ~S does not accept a named backend operation id."
           operation-kind))
  (unless (logic-package-identity-p package-identity)
    (%fail 'invalid-logic-package-identity-error
           "Logic calls require a digest-locked logic-package-identity, got ~S."
           package-identity))
  (when (and required-isolation
             (not (%non-empty-string-p required-isolation)))
    (%fail 'invalid-logic-value-error
           "Required isolation must be NIL or a non-empty string, got ~S."
           required-isolation))
  (make-instance
   'logic-call
   :operation-id
   (%require-non-empty-string operation-id "operation id"
                              'invalid-logic-operation-error)
   :named-operation-id (and named-operation-id (copy-seq named-operation-id))
   :operation-kind (copy-seq operation-kind)
   :semantic-profile
   (%require-non-empty-string semantic-profile "semantic profile"
                              'invalid-logic-operation-error)
   :backend-policy (copy-seq backend-policy)
   :bindings (%normalize-record bindings "bindings")
   :answer-policy (%normalize-optional-record answer-policy "answer policy")
   :proof-policy (%normalize-optional-record proof-policy "proof policy")
   :required-capabilities
   (%normalize-string-list required-capabilities "required capabilities"
                           'invalid-logic-value-error)
   :required-hard-limits
   (%normalize-string-list required-hard-limits "required hard limits"
                           'invalid-logic-value-error)
   :required-isolation (and required-isolation (copy-seq required-isolation))
   :package-identity package-identity
   :budget (%normalize-optional-record budget "budget")
   :source-span (%normalize-optional-record source-span "source span")))

(defun logic-call-operation-id (call)
  (copy-seq (%logic-call-operation-id call)))

(defun logic-call-named-operation-id (call)
  (let ((value (%logic-call-named-operation-id call)))
    (and value (copy-seq value))))

(defun logic-call-operation-kind (call)
  (copy-seq (%logic-call-operation-kind call)))

(defun logic-call-semantic-profile (call)
  (copy-seq (%logic-call-semantic-profile call)))

(defun logic-call-backend-policy (call)
  (copy-seq (%logic-call-backend-policy call)))

(defun logic-call-bindings (call)
  (%copy-record (%logic-call-bindings call)))

(defun logic-call-answer-policy (call)
  (%copy-record (%logic-call-answer-policy call)))

(defun logic-call-proof-policy (call)
  (%copy-record (%logic-call-proof-policy call)))

(defun logic-call-required-capabilities (call)
  (%copy-string-list (%logic-call-required-capabilities call)))

(defun logic-call-required-hard-limits (call)
  (%copy-string-list (%logic-call-required-hard-limits call)))

(defun logic-call-required-isolation (call)
  (let ((value (%logic-call-required-isolation call)))
    (and value (copy-seq value))))

(defun logic-call-package-identity (call)
  (%logic-call-package-identity call))

(defun logic-call-budget (call)
  (%copy-record (%logic-call-budget call)))

(defun logic-call-source-span (call)
  (%copy-record (%logic-call-source-span call)))

(defclass logic-materialization-request ()
  ((backend-policy :initarg :backend-policy
                   :reader %logic-materialization-request-backend-policy)
   (semantic-profile :initarg :semantic-profile
                     :reader %logic-materialization-request-semantic-profile)
   (required-capabilities :initarg :required-capabilities
                          :reader %logic-materialization-request-required-capabilities)
   (required-hard-limits :initarg :required-hard-limits
                         :reader %logic-materialization-request-required-hard-limits)
   (required-isolation :initarg :required-isolation
                       :reader %logic-materialization-request-required-isolation)
   (package-identity :initarg :package-identity
                     :reader %logic-materialization-request-package-identity)
   (proof-policy :initarg :proof-policy
                 :reader %logic-materialization-request-proof-policy)))

(defun logic-materialization-request-p (value)
  (typep value 'logic-materialization-request))

(defun logic-call-materialization-request (call)
  (unless (logic-call-p call)
    (%fail 'invalid-logic-operation-error
           "Materialization requires a normalized logic-call, got ~S." call))
  (make-instance
   'logic-materialization-request
   :backend-policy (logic-call-backend-policy call)
   :semantic-profile (logic-call-semantic-profile call)
   :required-capabilities (logic-call-required-capabilities call)
   :required-hard-limits (logic-call-required-hard-limits call)
   :required-isolation (logic-call-required-isolation call)
   :package-identity (logic-call-package-identity call)
   :proof-policy (logic-call-proof-policy call)))

(defun logic-materialization-request-backend-policy (request)
  (copy-seq (%logic-materialization-request-backend-policy request)))

(defun logic-materialization-request-semantic-profile (request)
  (copy-seq (%logic-materialization-request-semantic-profile request)))

(defun logic-materialization-request-required-capabilities (request)
  (%copy-string-list (%logic-materialization-request-required-capabilities request)))

(defun logic-materialization-request-required-hard-limits (request)
  (%copy-string-list (%logic-materialization-request-required-hard-limits request)))

(defun logic-materialization-request-required-isolation (request)
  (let ((value (%logic-materialization-request-required-isolation request)))
    (and value (copy-seq value))))

(defun logic-materialization-request-package-identity (request)
  (%logic-materialization-request-package-identity request))

(defun logic-materialization-request-proof-policy (request)
  (%copy-record (%logic-materialization-request-proof-policy request)))

(defclass materialized-logic-call ()
  ((logic-call :initarg :logic-call :reader %materialized-logic-call-logic-call)
   (backend-id :initarg :backend-id :reader %materialized-logic-call-backend-id)
   (backend-version :initarg :backend-version
                    :reader %materialized-logic-call-backend-version)
   (backend-build-id :initarg :backend-build-id
                     :reader %materialized-logic-call-backend-build-id)
   (selection-evidence :initarg :selection-evidence
                       :reader %materialized-logic-call-selection-evidence)
   (package-identity :initarg :package-identity
                     :reader %materialized-logic-call-package-identity)))

(defun materialized-logic-call-p (value)
  (typep value 'materialized-logic-call))

(defun materialize-logic-call (call registry)
  (let* ((request (logic-call-materialization-request call))
         (selection-request
           (make-logic-selection-request
            :backend-policy
            (logic-materialization-request-backend-policy request)
            :semantic-profile
            (logic-materialization-request-semantic-profile request)
            :required-capabilities
            (logic-materialization-request-required-capabilities request)
            :required-hard-limits
            (logic-materialization-request-required-hard-limits request)
            :required-isolation
            (logic-materialization-request-required-isolation request))))
    (multiple-value-bind (selected-backend evidence)
        (select-logic-backend registry selection-request)
      (let ((descriptor (logic-backend-descriptor-of selected-backend)))
        (make-instance
         'materialized-logic-call
         :logic-call call
         :backend-id (copy-seq (logic-backend-descriptor-id descriptor))
         :backend-version (copy-seq (logic-backend-descriptor-version descriptor))
         :backend-build-id (copy-seq (logic-backend-descriptor-build-id descriptor))
         :selection-evidence evidence
         :package-identity (logic-call-package-identity call))))))

(defun materialized-logic-call-logic-call (plan)
  (%materialized-logic-call-logic-call plan))

(defun materialized-logic-call-backend-id (plan)
  (copy-seq (%materialized-logic-call-backend-id plan)))

(defun materialized-logic-call-backend-version (plan)
  (copy-seq (%materialized-logic-call-backend-version plan)))

(defun materialized-logic-call-backend-build-id (plan)
  (copy-seq (%materialized-logic-call-backend-build-id plan)))

(defun materialized-logic-call-selection-evidence (plan)
  (%materialized-logic-call-selection-evidence plan))

(defun materialized-logic-call-package-identity (plan)
  (%materialized-logic-call-package-identity plan))

(defun ensure-materialized-backend-compatible (plan backend)
  (unless (materialized-logic-call-p plan)
    (%fail 'logic-materialized-backend-change-error
           "Expected a materialized logic call, got ~S." plan))
  (let ((descriptor (logic-backend-descriptor-of backend)))
    (unless (and
             (string= (materialized-logic-call-backend-id plan)
                      (logic-backend-descriptor-id descriptor))
             (string= (materialized-logic-call-backend-version plan)
                      (logic-backend-descriptor-version descriptor))
             (string= (materialized-logic-call-backend-build-id plan)
                      (logic-backend-descriptor-build-id descriptor)))
      (%fail 'logic-materialized-backend-change-error
             "Materialized backend ~A/~A/~A cannot be replaced by ~A/~A/~A; cross-backend or cross-build recovery requires a new explicit plan."
             (materialized-logic-call-backend-id plan)
             (materialized-logic-call-backend-version plan)
             (materialized-logic-call-backend-build-id plan)
             (logic-backend-descriptor-id descriptor)
             (logic-backend-descriptor-version descriptor)
             (logic-backend-descriptor-build-id descriptor)))
    t))
