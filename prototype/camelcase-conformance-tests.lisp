(load (merge-pathnames "core-surface-prototype.lisp" *load-truename*))
(load (merge-pathnames "actor-wire-prototype.lisp" *load-truename*))
(load (merge-pathnames "canonical-json-prototype.lisp" *load-truename*))

(in-package #:star-lang.core-surface.prototype)

(defun camel-assert (value label)
  (unless value
    (fail 'test-error "Assertion failed: ~A." label)))

(defun camel-equal (expected actual label)
  (unless (equal expected actual)
    (fail 'test-error "~A expected ~S, received ~S." label expected actual)))

(defun compile-camel-source (source)
  (let* ((syntax (read-star-syntax source :source-id "camel-test"))
         (expanded (expand-star-syntax syntax)))
    (validate-star-core expanded)
    (compile-star-core expanded)))

(defun captured-invalid-field (source)
  (handler-case
      (progn (compile-camel-source source) nil)
    (invalid-field-error (condition) condition)))

(defun test-camel-field-preservation ()
  (let* ((library
           (compile-camel-source
            "(spec-library \"test/camel@1\" (:version \"1\")
               (scalar message-id (:base string))
               (document sample (:persistence transient)
                 (messageId message-id :required))
               (message ping (:fields ((replyTo string :optional)))))"))
         (document (find "sample" (getf library :declarations)
                         :key (lambda (item) (getf item :name))
                         :test #'string=))
         (message (find "ping" (getf library :declarations)
                        :key (lambda (item) (getf item :name))
                        :test #'string=)))
    (camel-equal +normalized-ir-version+ (getf library :ir-version)
                 "normalized IR version")
    (camel-equal +normalized-ir-schema+ (getf library :ir-schema)
                 "normalized IR schema")
    (camel-equal "messageId" (getf (first (getf document :fields)) :name)
                 "document field spelling")
    (camel-equal "replyTo" (getf (first (getf message :fields)) :name)
                 "message field spelling")
    (camel-assert
     (find "message-id" (getf library :declarations)
           :key (lambda (item) (getf item :name)) :test #'string=)
     "non-field declaration remains kebab-case")))

(defun test-invalid-field-spellings ()
  (dolist (name '("bad-field" "bad_field" "UpperCamel"))
    (let* ((source
             (format nil
                     "(spec-library \"test/camel@1\" (:version \"1\") (document sample (:persistence transient) (~A string :required)))"
                     name))
           (condition (captured-invalid-field source)))
      (camel-assert condition (format nil "~A field rejected" name))
      (camel-equal :invalid-field-name (star-lang-core-error-code condition)
                   (format nil "~A diagnostic code" name))
      (let ((span (star-lang-core-error-span condition)))
        (camel-assert span (format nil "~A diagnostic span" name))
        (camel-equal (length name)
                     (- (star-source-span-end-byte span)
                        (star-source-span-start-byte span))
                     (format nil "~A exact token span" name))))))

(defun test-camel-manifest-keys ()
  (let* ((library
           (compile-camel-source
            "(spec-library \"test/camel@1\" (:version \"1\")
               (message ping (:fields ((messageId string :required)))))"))
         (manifest (emit-portable-manifest library nil))
         (json (canonical-manifest-json manifest)))
    (camel-assert (search "\"wireVersion\":1" json)
                  "manifest key is lower camelCase")
    (camel-assert (not (search "\"wire_version\"" json))
                  "manifest does not emit snake_case key")))

(defun run-camelcase-conformance-tests ()
  (test-camel-field-preservation)
  (test-invalid-field-spellings)
  (test-camel-manifest-keys)
  (format t "Star-Lang camelCase conformance tests passed.~%")
  t)

(unless (run-camelcase-conformance-tests)
  (error "Star-Lang camelCase conformance tests failed."))
