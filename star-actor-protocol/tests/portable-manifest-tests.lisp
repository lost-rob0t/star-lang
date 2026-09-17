(defpackage :staractorprotocol-manifest-tests
  (:use :cl)
  (:import-from :staractorprotocol
                #:invalid-wire-envelope-error
                #:validate-portable-manifest)
  (:export #:run-tests))

(in-package :staractorprotocol-manifest-tests)

(defun check (truth control &rest arguments)
  (unless truth
    (error (apply #'format nil control arguments))))

(defun signals-p (condition-type thunk)
  (handler-case
      (progn (funcall thunk) nil)
    (error (condition)
      (typep condition condition-type))))

(defun scalar-contract (name base)
  (list :kind :scalar
        :name name
        :base base
        :pattern nil
        :format nil
        :minimum nil
        :maximum nil
        :scale nil))

(defun manifest-fixture ()
  (list
   :wire-version 1
   :library (list :name "test/contracts@1"
                  :version "1.0.0"
                  :digest "sha256:test")
   :imports (list (list :kind :import
                        :name "org.example/base@1"
                        :version "1.0.0"
                        :digest "sha256:base"))
   :types
   (list
    (scalar-contract "test/id" "string")
    (list :kind :document
          :name "test/base"
          :extends nil
          :persistence :persistent
          :fields (list (list :name "id"
                              :type "test/id"
                              :required t)))
    (list :kind :document
          :name "test/child"
          :extends "test/base"
          :persistence :persistent
          :fields (list (list :name "externalThing"
                              :type "org.example/thing@1"
                              :required nil))))
   :predicates
   (list (list :kind :predicate
               :name "test/relatedTo"
               :source "test/child"
               :destination "org.example/thing@1"))
   :messages
   (list (list :kind :message
               :name "test/run"
               :fields (list (list :name "target"
                                   :type "test/child"
                                   :required t))))
   :actors
   (list (list :name "worker"
               :runtime :native
               :protocol nil
               :endpoint nil
               :accepts '("test/run" "standalone-command")
               :produces '("test/child")
               :capabilities '("network")
               :service-uri "star://starintel:localhost:worker"
               :metadata '(("ownerTeam" . "tests")))))))

(defun test-valid-manifest ()
  (check (validate-portable-manifest (manifest-fixture))
         "Valid hardened manifest was rejected."))

(defun test-duplicate-key-rejected ()
  (let ((manifest (append (manifest-fixture) (list :actors '()))))
    (check
     (signals-p 'invalid-wire-envelope-error
                (lambda () (validate-portable-manifest manifest)))
     "Duplicate plist key was accepted.")))

(defun test-unknown-unqualified-type-rejected ()
  (let* ((manifest (manifest-fixture))
         (child (find "test/child"
                      (getf manifest :types)
                      :key (lambda (type) (getf type :name))
                      :test #'string=))
         (field (first (getf child :fields))))
    (setf (getf field :type) "missing")
    (check
     (signals-p 'invalid-wire-envelope-error
                (lambda () (validate-portable-manifest manifest)))
     "Unknown unqualified field type was accepted.")))

(defun test-malformed-import-rejected ()
  (let* ((manifest (manifest-fixture))
         (import (first (getf manifest :imports))))
    (setf (getf import :digest) "md5:nope")
    (check
     (signals-p 'invalid-wire-envelope-error
                (lambda () (validate-portable-manifest manifest)))
     "Non-sha256 import lock was accepted.")))

(defun test-duplicate-import-rejected ()
  (let* ((manifest (manifest-fixture))
         (import (copy-tree (first (getf manifest :imports)))))
    (push import (getf manifest :imports))
    (check
     (signals-p 'invalid-wire-envelope-error
                (lambda () (validate-portable-manifest manifest)))
     "Duplicate imported library was accepted.")))

(defun test-native-transport-data-rejected ()
  (let* ((manifest (manifest-fixture))
         (actor (first (getf manifest :actors))))
    (setf (getf actor :endpoint) "rabbitmq:queue")
    (check
     (signals-p 'invalid-wire-envelope-error
                (lambda () (validate-portable-manifest manifest)))
     "Native actor transport endpoint was accepted.")))

(defun test-service-uri-actor-mismatch-rejected ()
  (let* ((manifest (manifest-fixture))
         (actor (first (getf manifest :actors))))
    (setf (getf actor :service-uri) "star://starintel:localhost:other")
    (check
     (signals-p 'invalid-wire-envelope-error
                (lambda () (validate-portable-manifest manifest)))
     "Actor service URI naming a different actor was accepted.")))

(defun test-duplicate-capability-rejected ()
  (let* ((manifest (manifest-fixture))
         (actor (first (getf manifest :actors))))
    (setf (getf actor :capabilities) '("network" "network"))
    (check
     (signals-p 'invalid-wire-envelope-error
                (lambda () (validate-portable-manifest manifest)))
     "Duplicate capability was accepted.")))

(defun test-metadata-integer-range-rejected ()
  (let* ((manifest (manifest-fixture))
         (actor (first (getf manifest :actors))))
    (setf (getf actor :metadata)
          (list (cons "generation" (expt 2 80))))
    (check
     (signals-p 'invalid-wire-envelope-error
                (lambda () (validate-portable-manifest manifest)))
     "Unbounded metadata integer was accepted.")))

(defun test-type-message-name-collision-rejected ()
  (let ((manifest (manifest-fixture)))
    (push (list :kind :message :name "test/id" :fields '())
          (getf manifest :messages))
    (check
     (signals-p 'invalid-wire-envelope-error
                (lambda () (validate-portable-manifest manifest)))
     "Type/message contract-name collision was accepted.")))

(defun test-inheritance-cycle-rejected ()
  (let* ((manifest (manifest-fixture))
         (base (find "test/base"
                     (getf manifest :types)
                     :key (lambda (type) (getf type :name))
                     :test #'string=)))
    (setf (getf base :extends) "test/child")
    (check
     (signals-p 'invalid-wire-envelope-error
                (lambda () (validate-portable-manifest manifest)))
     "Document inheritance cycle was accepted.")))

(defun test-inherited-field-shadow-rejected ()
  (let* ((manifest (manifest-fixture))
         (child (find "test/child"
                      (getf manifest :types)
                      :key (lambda (type) (getf type :name))
                      :test #'string=)))
    (push (list :name "id" :type "string" :required t)
          (getf child :fields))
    (check
     (signals-p 'invalid-wire-envelope-error
                (lambda () (validate-portable-manifest manifest)))
     "Document redefinition of inherited field was accepted.")))

(defun run-tests ()
  (test-valid-manifest)
  (test-duplicate-key-rejected)
  (test-unknown-unqualified-type-rejected)
  (test-malformed-import-rejected)
  (test-duplicate-import-rejected)
  (test-native-transport-data-rejected)
  (test-service-uri-actor-mismatch-rejected)
  (test-duplicate-capability-rejected)
  (test-metadata-integer-range-rejected)
  (test-type-message-name-collision-rejected)
  (test-inheritance-cycle-rejected)
  (test-inherited-field-shadow-rejected)
  t)
