(defpackage :starlang-object-bindings-tests
  (:use :cl :fiveam)
  (:export #:run-tests))

(in-package :starlang-object-bindings-tests)

(def-suite starlang-object-bindings-tests
  :description "Portable object binding and actor manifest hardening tests.")

(in-suite starlang-object-bindings-tests)

(defun scalar-contract (name base)
  (list :kind :scalar
        :name name
        :base base
        :pattern nil
        :format nil
        :minimum nil
        :maximum nil
        :scale nil))

(defun field-contract (name type required)
  (list :name name :type type :required required))

(defun test-manifest ()
  (list
   :wire-version 1
   :library (list :name "test/contracts@1"
                  :version "1.0.0"
                  :digest "sha256:test-contracts")
   :imports '()
   :types
   (list
    (scalar-contract "test/id" "string")
    (list :kind :enum :name "test/state" :values '("ready" "done"))
    (list :kind :document
          :name "test/base"
          :extends nil
          :persistence :persistent
          :fields (list (field-contract "id" "test/id" t)))
    (list :kind :document
          :name "test/child"
          :extends "test/base"
          :persistence :persistent
          :fields (list (field-contract "runState" "test/state" nil)
                        (field-contract "externalRecord"
                                        "org.external/record@1"
                                        nil))))
   :predicates
   (list (list :kind :predicate
               :name "test/relatedTo"
               :source "test/child"
               :destination "test/child"))
   :messages
   (list (list :kind :message
               :name "test/run"
               :fields (list (field-contract "target" "test/child" t))))
   :actors
   (list (list :name "worker"
               :runtime :native
               :protocol nil
               :endpoint nil
               :accepts '("test/run" "ingest-page")
               :produces '("test/child")
               :capabilities '("network")
               :service-uri "star://starintel:localhost:worker"
               :metadata '(("ownerTeam" . "tests")))))))

(test every-binding-target-defines-every-object-kind
  (let* ((manifest (test-manifest))
         (bindings (starlangcompiler:generate-all-object-bindings manifest)))
    (is (= (length bindings)
           (length starlangcompiler:+object-binding-targets+)))
    (dolist (entry bindings)
      (let ((source (string-downcase (cdr entry))))
        (is (plusp (length source)) (format nil "~A emitted source" (car entry)))
        (is (search "child" source) (format nil "~A defines document" (car entry)))
        (is (search "run" source) (format nil "~A defines message" (car entry)))
        (is (search "related" source) (format nil "~A defines predicate" (car entry)))
        (is (search "worker" source) (format nil "~A defines actor" (car entry)))
        (is (search "external" source)
            (format nil "~A defines opaque external contract" (car entry)))
        (is (search "ingest" source)
            (format nil "~A defines standalone actor contract reference" (car entry)))))))

(test binding-name-collisions-qualify-instead-of-overwriting
  (let* ((manifest (test-manifest))
         (types (getf manifest :types)))
    (setf (getf manifest :types)
          (append types
                  (list (scalar-contract "org.alpha/thing@1" "string")
                        (scalar-contract "org.beta/thing@1" "string"))))
    (let ((python (string-downcase
                   (starlangcompiler:generate-object-bindings manifest :python))))
      (is (search "orgalphathing1" python))
      (is (search "orgbetathing1" python)))))

(test manifest-rejects-unknown-top-level-keys
  (let ((manifest (append (test-manifest) (list :surprise t))))
    (signals staractorprotocol:invalid-wire-envelope-error
      (staractorprotocol:validate-portable-manifest manifest))))

(test manifest-rejects-duplicate-plist-keys
  (let ((manifest (append (test-manifest) (list :actors '()))))
    (signals staractorprotocol:invalid-wire-envelope-error
      (staractorprotocol:validate-portable-manifest manifest))))

(test manifest-rejects-duplicate-actor-capabilities
  (let* ((manifest (test-manifest))
         (actor (first (getf manifest :actors))))
    (setf (getf actor :capabilities) '("network" "network"))
    (signals staractorprotocol:invalid-wire-envelope-error
      (staractorprotocol:validate-portable-manifest manifest))))

(test manifest-allows-standalone-actor-contract-references
  (is (staractorprotocol:validate-portable-manifest (test-manifest))))

(test manifest-rejects-unknown-unqualified-field-types
  (let* ((manifest (test-manifest))
         (child (find "test/child"
                      (getf manifest :types)
                      :key (lambda (type) (getf type :name))
                      :test #'string=))
         (field (find "externalRecord"
                      (getf child :fields)
                      :key (lambda (item) (getf item :name))
                      :test #'string=)))
    (setf (getf field :type) "mystery")
    (signals staractorprotocol:invalid-wire-envelope-error
      (staractorprotocol:validate-portable-manifest manifest))))

(test manifest-rejects-malformed-imports
  (let ((manifest (test-manifest)))
    (setf (getf manifest :imports)
          (list (list :kind :import
                      :name "org.example/base@1"
                      :version "1.0.0"
                      :digest "md5:not-allowed")))
    (signals staractorprotocol:invalid-wire-envelope-error
      (staractorprotocol:validate-portable-manifest manifest))))

(test manifest-rejects-document-inheritance-cycles
  (let* ((manifest (test-manifest))
         (types (getf manifest :types))
         (base (find "test/base"
                     types
                     :key (lambda (type) (getf type :name))
                     :test #'string=)))
    (setf (getf base :extends) "test/child")
    (signals staractorprotocol:invalid-wire-envelope-error
      (staractorprotocol:validate-portable-manifest manifest))))

(defun run-tests ()
  (unless (run! 'starlang-object-bindings-tests)
    (error "StarLang object binding tests failed.")))
