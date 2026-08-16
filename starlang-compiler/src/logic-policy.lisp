(in-package :starlangcompiler)

(define-condition logic-policy-compiler-error (error)
  ((message :initarg :message :reader logic-policy-compiler-error-message)
   (code :initarg :code :reader logic-policy-compiler-error-code)
   (source-span :initarg :source-span
                :initform nil
                :reader logic-policy-compiler-error-source-span)
   (cause :initarg :cause :reader logic-policy-compiler-error-cause))
  (:report (lambda (condition stream)
             (write-string (logic-policy-compiler-error-message condition) stream))))

(defun %raise-logic-policy-diagnostic (condition code source-span)
  (error 'logic-policy-compiler-error
         :message (princ-to-string condition)
         :code code
         :source-span source-span
         :cause condition))

(defun compile-logic-call
    (&key operation-id
          named-operation-id
          operation-kind
          semantic-profile
          (backend-policy +logic-backend-auto+)
          bindings
          answer-policy
          proof-policy
          required-capabilities
          required-hard-limits
          required-isolation
          package-identity
          budget
          source-span)
  "Construct the final-owned backend-neutral logic IR for checked compiler data.

This is intentionally a narrow compiler boundary. Parsing and syntax-object
ownership remain with the current compiler migration; this function does not
introduce a second parser or native backend lowering path."
  (handler-case
      (make-logic-call
       :operation-id operation-id
       :named-operation-id named-operation-id
       :operation-kind operation-kind
       :semantic-profile semantic-profile
       :backend-policy backend-policy
       :bindings bindings
       :answer-policy answer-policy
       :proof-policy proof-policy
       :required-capabilities required-capabilities
       :required-hard-limits required-hard-limits
       :required-isolation required-isolation
       :package-identity package-identity
       :budget budget
       :source-span source-span)
    (invalid-logic-backend-policy-error (condition)
      (%raise-logic-policy-diagnostic condition :unknown-logic-backend source-span))
    (invalid-logic-operation-error (condition)
      (%raise-logic-policy-diagnostic condition :invalid-logic-operation source-span))
    (invalid-logic-package-identity-error (condition)
      (%raise-logic-policy-diagnostic condition :invalid-logic-package source-span))
    (invalid-logic-value-error (condition)
      (%raise-logic-policy-diagnostic condition :invalid-logic-policy-value source-span))))

(defun materialize-compiled-logic-call (logic-call registry)
  "Materialize LOGIC-CALL through star-logic-protocol's existing selector."
  (let ((source-span (and (starlogicir:logic-call-p logic-call)
                          (logic-call-source-span logic-call))))
    (handler-case
        (materialize-logic-call logic-call registry)
      (logic-backend-not-found-error (condition)
        (%raise-logic-policy-diagnostic
         condition :logic-backend-unavailable source-span))
      (logic-backend-incompatible-error (condition)
        (%raise-logic-policy-diagnostic
         condition :logic-backend-incompatible source-span))
      (logic-backend-selection-error (condition)
        (%raise-logic-policy-diagnostic
         condition :logic-backend-selection-failed source-span))
      (invalid-logic-operation-error (condition)
        (%raise-logic-policy-diagnostic
         condition :invalid-logic-operation source-span)))))
