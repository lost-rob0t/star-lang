;;;; Regression coverage for the closed StarLang field-marker grammar.

(defpackage :starlang-field-marker-tests
  (:use :cl :fiveam)
  (:export #:run-tests))

(in-package :starlang-field-marker-tests)

(def-suite starlang-field-marker-tests
  :description "Closed document/message field marker grammar tests.")

(in-suite starlang-field-marker-tests)

(defun compile-source-library (declaration)
  (starlangcompiler:compile-spec-library
   (starlangcompiler:read-star-syntax
    (format nil
            "(spec-library \"test/fields@1\" (:version \"1.0.0\") ~A)"
            declaration)
    :source-id "field-marker-test.star")))

(defun compile-document-field (field)
  (compile-source-library
   (format nil
           "(document preferences (:persistence transient) ~A)"
           field)))

(defun compile-message-field (field)
  (compile-source-library
   (format nil
           "(message update (:fields (~A)))"
           field)))

(defun first-field (library)
  (getf (first (getf library :declarations)) :fields))

(defun first-compiled-field (library)
  (first (first-field library)))

(defun invalid-field-condition (thunk)
  (handler-case
      (progn
        (funcall thunk)
        nil)
    (star-lang.compiler.core:invalid-field-error (condition)
      condition)))

(defun check-invalid-source-field (field)
  (let ((condition
          (invalid-field-condition
           (lambda () (compile-document-field field)))))
    (is (typep condition 'star-lang.compiler.core:invalid-field-error))
    condition))

(test duplicate-defaults-are-rejected-and-identify-both-occurrences
  "A second :default is rejected at its own span and points at the first one."
  (dolist (field
            '("(enabled boolean :optional :default nil :default t)"
              "(enabled boolean :optional :default nil :default nil)"))
    (let* ((condition (check-invalid-source-field field))
           (span (star-lang.compiler.core:star-lang-core-error-span condition))
           (related
             (star-lang.compiler.core:star-lang-core-error-related-spans condition)))
      (is (not (null span)))
      (is (= 1 (length related)))
      (is (< (star-lang.compiler.core:star-source-span-start-column
              (first related))
             (star-lang.compiler.core:star-source-span-start-column span))))))

(test presence-marker-grammar-is-closed
  "Repeated/conflicting presence markers and unconsumed source are rejected."
  (dolist (field
            '("(enabled boolean :optional :optional)"
              "(enabled boolean :required :required)"
              "(enabled boolean :required :optional)"
              "(enabled boolean :optional bogus 1)"
              "(enabled boolean :optional :maximum 5)"
              "(enabled boolean :optional (bogus 1))"))
    (check-invalid-source-field field)))

(test default-requires-exactly-one-consumed-value
  "A default marker consumes one following syntax occurrence and leaves no junk."
  (let ((condition
          (check-invalid-source-field
           "(enabled boolean :optional :default)")))
    (is (star-lang.compiler.core:star-lang-core-error-span condition)))
  (check-invalid-source-field
   "(enabled boolean :optional :default nil trailing)"))

(test consumed-default-value-is-not-rescanned-as-a-marker
  "A keyword occurrence consumed as the default value is not interpreted twice."
  (let* ((library
           (compile-document-field
            "(mode symbol :default :optional :optional)"))
         (field (first-compiled-field library)))
    (is (not (getf field :required)))
    (is (getf field :default-p))
    (is (eq :optional (getf field :default)))))

(test valid-field-markers-preserve-default-presence
  "Valid required/optional forms keep existing lowering semantics."
  (let ((required
          (first-compiled-field
           (compile-document-field "(name string :required)")))
        (false-default
          (first-compiled-field
           (compile-document-field
            "(enabled boolean :optional :default nil)")))
        (empty-list-default
          (first-compiled-field
           (compile-document-field
            "(tags (list string) :optional :default ())")))
        (reordered
          (first-compiled-field
           (compile-document-field
            "(enabled boolean :default nil :optional)"))))
    (is (getf required :required))
    (is (not (getf required :default-p)))
    (dolist (field (list false-default empty-list-default reordered))
      (is (not (getf field :required)))
      (is (getf field :default-p))
      (is (null (getf field :default))))))

(test required-field-default-survives-public-source-lowering
  "A required field may carry an explicit default through public source lowering."
  (let ((field
          (first-compiled-field
           (compile-document-field
            "(retries integer :required :default 7)"))))
    (is (getf field :required))
    (is (getf field :default-p))
    (is (= 7 (getf field :default)))))

(test message-fields-use-the-same-closed-marker-grammar
  "Message :fields entries cannot bypass the document field grammar."
  (let ((condition
          (invalid-field-condition
           (lambda ()
             (compile-message-field
              "(enabled boolean :optional :default nil :default t)")))))
    (is (typep condition 'star-lang.compiler.core:invalid-field-error))))

(test trusted-host-entry-point-uses-the-same-marker-grammar
  "Trusted compatibility data gets identical semantic marker validation."
  (let ((condition
          (invalid-field-condition
           (lambda ()
             (starlangcompiler:compile-spec-library
              '(spec-library "test/fields@1" (:version "1.0.0")
                (document preferences (:persistence transient)
                  (enabled boolean :optional bogus 1))))))))
    (is (typep condition 'star-lang.compiler.core:invalid-field-error))))

(defun run-tests ()
  (unless (run! 'starlang-field-marker-tests)
    (error "starlang-compiler field-marker tests failed.")))
