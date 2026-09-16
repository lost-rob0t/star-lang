(defpackage :starcanonicaljson-wire-tests
  (:use :cl)
  (:import-from :starcanonicaljson
                #:canonical-manifest-json
                #:canonical-envelope-json
                #:canonical-lifecycle-envelope-json)
  (:export #:run-tests))

(in-package :starcanonicaljson-wire-tests)

(defun check (truth control &rest arguments)
  (unless truth
    (error (apply #'format nil control arguments))))

(defun plist-key-present-p (plist key)
  (loop for tail on plist by #'cddr
        thereis (eq (first tail) key)))

(defun wire-manifest-fixture ()
  (list
   :wire-version 1
   :library (list :name "test" :version "1" :digest "sha256:test")
   :imports '()
   :types '()
   :predicates '()
   :messages
   (list
    (list :kind :message
          :name "test/run@1"
          :fields
          (list
           (list :name "target" :type "string" :required t)
           (list :name "count" :type "integer" :required nil))))
   :actors
   (list
    (list :name "worker"
          :runtime :external
          :service-uri "star://test:localhost:worker"
          :accepts '("test/run@1")
          :produces '()
          :capabilities '()))))

(defun default-manifest-fixture ()
  (list
   :wire-version 1
   :library (list :name "defaults" :version "1" :digest "sha256:test")
   :imports '()
   :types
   (list
    (list :kind :scalar
          :name "test/count@1"
          :base "integer"
          :pattern nil
          :format nil
          :minimum nil
          :maximum nil
          :scale nil)
    (list :kind :enum
          :name "test/mode@1"
          :values '("fast" "slow"))
    (list :kind :document
          :name "test/base@1"
          :extends nil
          :persistence :transient
          :fields
          (list
           (list :name "inheritedEnabled"
                 :type "boolean"
                 :required nil
                 :default nil)))
    (list :kind :document
          :name "test/child@1"
          :extends "test/base@1"
          :persistence :transient
          :fields
          (list
           (list :name "localLabel"
                 :type "string"
                 :required nil
                 :default ""))))
   :predicates '()
   :messages
   (list
    (list :kind :message
          :name "test/defaults@1"
          :fields
          (list
           (list :name "noDefault" :type "string" :required nil)
           (list :name "disabled" :type "boolean" :required nil :default nil)
           (list :name "enabled" :type "boolean" :required nil :default t)
           (list :name "nullable" :type (list :optional "string")
                 :required nil :default nil)
           (list :name "emptyTags" :type (list :list "string")
                 :required nil :default nil)
           (list :name "tags" :type (list :list "string")
                 :required nil :default '("alpha" "beta"))
           (list :name "metadata" :type "map" :required nil :default nil)
           (list :name "count" :type "integer" :required nil :default 0)
           (list :name "label" :type "string" :required nil :default "")
           (list :name "amount" :type "decimal" :required nil :default "0.00")
           (list :name "aliasCount" :type "test/count@1" :required nil :default 0)
           (list :name "mode" :type "test/mode@1" :required nil :default :fast))))
   :actors '()))

(defun test-canonical-manifest-bytes ()
  (check
   (string=
    "{\"actors\":[],\"imports\":[],\"library\":{\"name\":\"x\"},\"messages\":[],\"predicates\":[],\"types\":[],\"wireVersion\":1}"
    (canonical-manifest-json
     (list :wire-version 1
           :library (list :name "x")
           :imports '()
           :types '()
           :predicates '()
           :messages '()
           :actors '())))
   "Canonical portable manifest bytes changed."))

(defun test-manifest-default-presence-is-type-aware ()
  (let* ((manifest (default-manifest-fixture))
         (json (canonical-manifest-json manifest)))
    (check
     (search "{\"name\":\"noDefault\",\"required\":false,\"type\":\"string\"}"
             json)
     "A field without a default acquired one during manifest serialization.")
    (check
     (search "{\"default\":false,\"name\":\"disabled\",\"required\":false,\"type\":\"boolean\"}"
             json)
     "An explicit boolean false default was omitted or encoded incorrectly.")
    (check
     (search "{\"default\":true,\"name\":\"enabled\",\"required\":false,\"type\":\"boolean\"}"
             json)
     "An explicit boolean true default was omitted or encoded incorrectly.")
    (check
     (search "{\"default\":null,\"name\":\"nullable\",\"required\":false,\"type\":{\"optional\":\"string\"}}"
             json)
     "An explicit optional null default was omitted or encoded incorrectly.")
    (check
     (search "{\"default\":[],\"name\":\"emptyTags\",\"required\":false,\"type\":{\"list\":\"string\"}}"
             json)
     "An explicit empty list default was omitted or encoded incorrectly.")
    (check
     (search "{\"default\":[\"alpha\",\"beta\"],\"name\":\"tags\",\"required\":false,\"type\":{\"list\":\"string\"}}"
             json)
     "A non-empty list default changed during manifest serialization.")
    (check
     (search "{\"default\":{},\"name\":\"metadata\",\"required\":false,\"type\":\"map\"}"
             json)
     "An explicit empty map default was omitted or encoded incorrectly.")
    (check
     (search "{\"default\":0,\"name\":\"count\",\"required\":false,\"type\":\"integer\"}"
             json)
     "A zero default changed during manifest serialization.")
    (check
     (search "{\"default\":\"\",\"name\":\"label\",\"required\":false,\"type\":\"string\"}"
             json)
     "An empty string default changed during manifest serialization.")
    (check
     (search "{\"default\":\"0.00\",\"name\":\"amount\",\"required\":false,\"type\":\"decimal\"}"
             json)
     "A decimal-string default changed during manifest serialization.")
    (check
     (search "{\"default\":0,\"name\":\"aliasCount\",\"required\":false,\"type\":\"test/count@1\"}"
             json)
     "A scalar-alias default was not encoded through its declared contract.")
    (check
     (search "{\"default\":\"fast\",\"name\":\"mode\",\"required\":false,\"type\":\"test/mode@1\"}"
             json)
     "An enum default was not encoded through its declared contract.")
    (check
     (search "{\"default\":false,\"name\":\"inheritedEnabled\",\"required\":false,\"type\":\"boolean\"}"
             json)
     "A document-field false default was lost during manifest serialization.")
    (check
     (search "{\"default\":\"\",\"name\":\"localLabel\",\"required\":false,\"type\":\"string\"}"
             json)
     "A child document-field empty-string default changed during serialization.")))

(defun test-inherited-document-field-default-presence-survives-projection ()
  (let* ((manifest (default-manifest-fixture))
         (child
           (staractorprotocol:portable-manifest-type-contract
            manifest "test/child@1"))
         (fields
           (staractorprotocol:portable-manifest-document-fields
            manifest child))
         (inherited (first fields))
         (local (second fields)))
    (check (= 2 (length fields))
           "Inherited document field projection changed shape.")
    (check (string= "inheritedEnabled" (getf inherited :name))
           "Inherited document field was not projected first.")
    (check (plist-key-present-p inherited :default)
           "Inherited document field lost explicit default presence.")
    (check (null (getf inherited :default))
           "Inherited boolean false default changed value.")
    (check (and (string= "localLabel" (getf local :name))
                (plist-key-present-p local :default)
                (string= "" (getf local :default)))
           "Local child field default changed during projection.")))

(defun test-invalid-manifest-default-is-rejected-by-type ()
  (let* ((manifest (default-manifest-fixture))
         (message (first (getf manifest :messages)))
         (disabled (second (getf message :fields))))
    (setf (getf disabled :default) "not-a-boolean")
    (check
     (handler-case
         (progn
           (canonical-manifest-json manifest)
           nil)
       (staractorprotocol:invalid-wire-envelope-error () t))
     "Manifest serialization accepted a default that violates its declared type.")))

(defun test-canonical-legacy-envelope-bytes ()
  (let ((manifest (wire-manifest-fixture))
        (envelope
          (staractorprotocol:make-wire-envelope
           :message-type "test/run@1"
           :message-id "legacy-1"
           :actor "worker"
           :dataset "fixture"
           :reply-to "reply.queue"
           :payload '(("target" . "example.org")
                      ("count" . 2)))))
    (check
     (string=
      "{\"actor\":\"worker\",\"dataset\":\"fixture\",\"messageId\":\"legacy-1\",\"messageType\":\"test/run@1\",\"payload\":{\"count\":2,\"target\":\"example.org\"},\"replyTo\":\"reply.queue\",\"starVersion\":1}"
      (canonical-envelope-json manifest envelope))
     "Canonical legacy envelope bytes changed.")))

(defun lifecycle-command ()
  (staractorprotocol:make-command-envelope
   :message-id "cmd-1"
   :message-type "test/run@1"
   :actor "worker"
   :sender "caller"
   :idempotency-key "idem-1"
   :dataset "fixture"
   :payload '(("target" . "example.org")
              ("count" . 2))))

(defun test-canonical-command-lifecycle-bytes ()
  (let ((manifest (wire-manifest-fixture)))
    (check
     (string=
      "{\"actor\":\"worker\",\"attempt\":1,\"correlationId\":\"cmd-1\",\"dataset\":\"fixture\",\"idempotencyKey\":\"idem-1\",\"kind\":\"command\",\"messageId\":\"cmd-1\",\"messageType\":\"test/run@1\",\"payload\":{\"count\":2,\"target\":\"example.org\"},\"sender\":\"caller\",\"starVersion\":1}"
      (canonical-lifecycle-envelope-json manifest (lifecycle-command)))
     "Canonical command lifecycle bytes changed.")))

(defun test-canonical-control-lifecycle-bytes ()
  (let* ((manifest (wire-manifest-fixture))
         (command (lifecycle-command))
         (ack
           (staractorprotocol:make-ack-envelope
            command
            :message-id "ack-1"
            :actor "caller"
            :sender "worker"
            :status :accepted))
         (failure
           (staractorprotocol:make-error-envelope
            command
            :message-id "error-1"
            :actor "caller"
            :sender "worker"
            :code "star.test"
            :message "fixture failure"
            :retryable nil
            :details '(("attempt" . 1)
                       ("source" . "fixture")))))
    (check
     (string=
      "{\"actor\":\"caller\",\"attempt\":1,\"causationId\":\"cmd-1\",\"correlationId\":\"cmd-1\",\"dataset\":\"fixture\",\"kind\":\"ack\",\"messageId\":\"ack-1\",\"messageType\":\"star.protocol/ack@1\",\"payload\":{\"forMessageId\":\"cmd-1\",\"status\":\"accepted\"},\"sender\":\"worker\",\"starVersion\":1}"
      (canonical-lifecycle-envelope-json manifest ack))
     "Canonical ACK lifecycle bytes changed.")
    (check
     (string=
      "{\"actor\":\"caller\",\"attempt\":1,\"causationId\":\"cmd-1\",\"correlationId\":\"cmd-1\",\"dataset\":\"fixture\",\"kind\":\"error\",\"messageId\":\"error-1\",\"messageType\":\"star.protocol/error@1\",\"payload\":{\"code\":\"star.test\",\"details\":{\"attempt\":1,\"source\":\"fixture\"},\"forMessageId\":\"cmd-1\",\"message\":\"fixture failure\",\"retryable\":false},\"sender\":\"worker\",\"starVersion\":1}"
      (canonical-lifecycle-envelope-json manifest failure))
     "Canonical structured error lifecycle bytes changed.")))

(defun test-final-wire-encoder-is-prototype-independent ()
  (check
   (null (find-package "STAR-LANG.CORE-SURFACE.PROTOTYPE"))
   "StarLang canonical wire encoding loaded the prototype package."))

(defun run-tests ()
  (test-canonical-manifest-bytes)
  (test-manifest-default-presence-is-type-aware)
  (test-inherited-document-field-default-presence-survives-projection)
  (test-invalid-manifest-default-is-rejected-by-type)
  (test-canonical-legacy-envelope-bytes)
  (test-canonical-command-lifecycle-bytes)
  (test-canonical-control-lifecycle-bytes)
  (test-final-wire-encoder-is-prototype-independent)
  (format t "~&star-canonical-json StarLang wire tests passed~%")
  t)
