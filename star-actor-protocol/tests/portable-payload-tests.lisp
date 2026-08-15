(defpackage :staractorprotocol-payload-tests
  (:use :cl)
  (:import-from :staractorprotocol
                #:invalid-wire-envelope-error
                #:make-command-envelope
                #:validate-lifecycle-envelope-against-manifest
                #:validate-portable-wire-value
                #:validate-portable-message-payload)
  (:export #:run-tests))

(in-package :staractorprotocol-payload-tests)

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

(defun payload-manifest-fixture ()
  (list
   :wire-version 1
   :types
   (list
    (list :kind :scalar
          :name "test/score"
          :base "integer"
          :minimum 1
          :maximum 5)
    (list :kind :scalar
          :name "test/amount"
          :base "decimal"
          :scale 2)
    (list :kind :enum
          :name "test/mode"
          :values '("fast" "slow"))
    (list :kind :document
          :name "test/base"
          :fields
          (list
           (list :name "id" :type "string" :required t)))
    (list :kind :document
          :name "test/job"
          :extends "test/base"
          :fields
          (list
           (list :name "score" :type "test/score" :required t)
           (list :name "amount" :type "test/amount" :required t)
           (list :name "mode" :type "test/mode" :required t)
           (list :name "evidenceRef" :type "reference" :required t)
           (list :name "metadata" :type "map" :required nil))))
   :messages
   (list
    (list :kind :message
          :name "test/run@1"
          :fields
          (list
           (list :name "job" :type "test/job" :required t)
           (list :name "tags" :type '(:list "string") :required t)
           (list :name "enabled" :type '(:optional "boolean") :required nil))))))

(defun valid-job-payload ()
  '(("id" . "job-1")
    ("score" . 3)
    ("amount" . "12.34")
    ("mode" . fast)
    ("evidenceRef"
     . (("schema" . "test/evidence")
        ("id" . "evidence-1")))
    ("metadata" . (("source" . "fixture")))))

(defun valid-message-payload ()
  (list
   (cons "job" (valid-job-payload))
   (cons "tags" '("one" "two"))
   (cons "enabled" t)))

(defun test-message-and-document-validation ()
  (let ((manifest (payload-manifest-fixture)))
    (check
     (validate-portable-message-payload
      manifest "test/run@1" (valid-message-payload))
     "Valid nested message payload was rejected.")
    (check
     (validate-portable-wire-value
      manifest "test/job" (valid-job-payload) "job")
     "Valid inherited document payload was rejected.")
    (let ((missing-parent (copy-tree (valid-job-payload))))
      (setf missing-parent
            (remove "id" missing-parent :key #'car :test #'string=))
      (check
       (signals-p
        'invalid-wire-envelope-error
        (lambda ()
          (validate-portable-wire-value
           manifest "test/job" missing-parent "job")))
       "Inherited required document field was not enforced."))
    (let ((unknown (copy-tree (valid-job-payload))))
      (push (cons "extra" 1) unknown)
      (check
       (signals-p
        'invalid-wire-envelope-error
        (lambda ()
          (validate-portable-wire-value
           manifest "test/job" unknown "job")))
       "Unknown document field was accepted."))))

(defun test-keyword-plist-field-compatibility ()
  (let ((manifest (payload-manifest-fixture)))
    (check
     (validate-portable-wire-value
      manifest
      "test/job"
      '(:id "job-1"
        :score 3
        :amount "1.25"
        :mode slow
        :evidence-ref (:schema "test/evidence" :id "evidence-1")
        :metadata (:source "fixture"))
      "job")
     "Keyword plist/camelCase field compatibility changed.")))

(defun test-scalar-enum-and-decimal_constraints ()
  (let ((manifest (payload-manifest-fixture)))
    (dolist (score '(1 3 5))
      (check (validate-portable-wire-value manifest "test/score" score "score")
             "In-range scalar was rejected."))
    (dolist (score '(0 6))
      (check
       (signals-p 'invalid-wire-envelope-error
                  (lambda ()
                    (validate-portable-wire-value
                     manifest "test/score" score "score")))
       "Out-of-range scalar was accepted."))
    (check (validate-portable-wire-value manifest "test/mode" 'fast "mode")
           "Enum symbol compatibility changed.")
    (check
     (signals-p 'invalid-wire-envelope-error
                (lambda ()
                  (validate-portable-wire-value
                   manifest "test/mode" "other" "mode")))
     "Unknown enum value was accepted.")
    (check (validate-portable-wire-value
            manifest "test/amount" "12.30" "amount")
           "Valid decimal string was rejected.")
    (check
     (signals-p 'invalid-wire-envelope-error
                (lambda ()
                  (validate-portable-wire-value
                   manifest "test/amount" "12.345" "amount")))
     "Decimal scale violation was accepted.")
    (check
     (signals-p 'invalid-wire-envelope-error
                (lambda ()
                  (validate-portable-wire-value
                   manifest "decimal" 12.3d0 "amount")))
     "Floating decimal input bypassed exact-string semantics.")))

(defun test-reference_map_list_and_any_validation ()
  (let ((manifest (payload-manifest-fixture)))
    (check
     (validate-portable-wire-value
      manifest "reference"
      '(:schema "test/evidence" :id "evidence-1")
      "reference")
     "Valid reference payload was rejected.")
    (check
     (signals-p
      'invalid-wire-envelope-error
      (lambda ()
        (validate-portable-wire-value
         manifest "reference" '(:schema "test/evidence") "reference")))
     "Reference missing id was accepted.")
    (check
     (validate-portable-wire-value
      manifest "map" '(:source "fixture" :count 2) "map")
     "Keyword plist map was rejected.")
    (check
     (signals-p
      'invalid-wire-envelope-error
      (lambda ()
        (validate-portable-wire-value
         manifest "map" '(:ratio 1.5d0) "map")))
     "Unsupported map value was accepted.")
    (check
     (signals-p
      'invalid-wire-envelope-error
      (lambda ()
        (validate-portable-wire-value
         manifest '(:list "integer") '(1 "two") "list")))
     "List element type mismatch was accepted.")
    (check
     (signals-p
      'invalid-wire-envelope-error
      (lambda ()
        (validate-portable-wire-value manifest "any" 1.5d0 "any")))
     "Unsupported generic wire value was accepted.")))

(defun test-lifecycle_manifest_validation ()
  (let* ((manifest (payload-manifest-fixture))
         (command
           (make-command-envelope
            :message-id "payload-command"
            :message-type "test/run@1"
            :actor "worker"
            :idempotency-key "payload-key"
            :payload (valid-message-payload))))
    (check
     (validate-lifecycle-envelope-against-manifest manifest command)
     "Valid lifecycle command failed manifest payload validation.")
    (let ((bad (copy-tree command)))
      (setf (getf bad :payload) '(("tags" . ("one"))))
      (check
       (signals-p
        'invalid-wire-envelope-error
        (lambda ()
          (validate-lifecycle-envelope-against-manifest manifest bad)))
       "Lifecycle validation accepted an invalid manifest payload."))
    (check
     (signals-p
      'invalid-wire-envelope-error
      (lambda ()
        (validate-lifecycle-envelope-against-manifest nil command)))
     "Tracked data lifecycle accepted a missing portable manifest.")))

(defun test-final-payload-validator-is-prototype-independent ()
  (check
   (null (find-package "STAR-LANG.CORE-SURFACE.PROTOTYPE"))
   "Portable payload validation loaded the prototype package transitively."))

(defun run-tests ()
  (test-message-and-document-validation)
  (test-keyword-plist-field-compatibility)
  (test-scalar-enum-and-decimal_constraints)
  (test-reference_map_list_and_any_validation)
  (test-lifecycle_manifest_validation)
  (test-final-payload-validator-is-prototype-independent)
  (format t "~&star-actor-protocol portable payload tests passed~%")
  t)
