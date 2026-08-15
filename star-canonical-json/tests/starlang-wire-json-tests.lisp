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
            :details '(:attempt 1 :source "fixture"))))
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
  (test-canonical-legacy-envelope-bytes)
  (test-canonical-command-lifecycle-bytes)
  (test-canonical-control-lifecycle-bytes)
  (test-final-wire-encoder-is-prototype-independent)
  (format t "~&star-canonical-json StarLang wire tests passed~%")
  t)
