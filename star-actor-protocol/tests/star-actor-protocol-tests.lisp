(defpackage :staractorprotocol-tests
  (:use :cl)
  (:import-from :staractorprotocol
                #:invalid-star-service-uri-error
                #:invalid-actor-reference-error
                #:invalid-wire-envelope-error
                #:star-service-uri-p
                #:star-service-uri-domain
                #:star-service-uri-address
                #:star-service-uri-actor-name
                #:make-star-service-uri
                #:parse-star-service-uri
                #:star-service-uri-string
                #:ensure-star-service-uri
                #:canonical-star-service-uri-for-actor
                #:star-actor-reference-p
                #:star-actor-reference-domain-id
                #:star-actor-reference-logical-path
                #:star-actor-reference-node-id
                #:star-actor-reference-generation
                #:star-actor-reference-protocol-revision
                #:make-star-actor-reference
                #:star-actor-reference-service-uri
                #:star-actor-reference-same-logical-actor-p
                #:+lifecycle-wire-version+
                #:make-command-envelope
                #:make-reply-envelope
                #:make-ack-envelope
                #:make-error-envelope
                #:make-cancel-envelope
                #:validate-lifecycle-envelope
                #:delivery-outcome
                #:terminal-lifecycle-envelope-p
                #:idempotency-scope-key
                #:lifecycle-message-id
                #:lifecycle-correlation-id
                #:lifecycle-causation-id
                #:cancel-target-message-id
                #:cancel-target-correlation-id)
  (:export #:run-tests))

(in-package :staractorprotocol-tests)

(defun assert-test (condition label)
  (unless condition
    (error "star-actor-protocol test failed: ~A" label)))

(defun assert-equal (expected actual label)
  (assert-test
   (equal expected actual)
   (format nil "~A expected ~S, received ~S"
           label expected actual)))

(defun signals-condition-p (condition-type thunk)
  (handler-case
      (progn
        (funcall thunk)
        nil)
    (error (condition)
      (typep condition condition-type))))

(defun signals-invalid-service-uri-p (thunk)
  (signals-condition-p 'invalid-star-service-uri-error thunk))

(defun signals-invalid-wire-envelope-p (thunk)
  (signals-condition-p 'invalid-wire-envelope-error thunk))

(defun test-canonical-service-uri-round-trip ()
  (dolist (value '("star://quasar:localhost:user-hunt"
                   "star://bbp:localhost:nmap"))
    (let ((uri (parse-star-service-uri value)))
      (assert-test (star-service-uri-p uri)
                   "parse returns a service URI")
      (assert-test (string= value (star-service-uri-string uri))
                   "canonical URI round-trips"))))

(defun test-service-uri-components ()
  (let ((uri
          (parse-star-service-uri
           "star://quasar:localhost:user-hunt")))
    (assert-test
     (string= "quasar" (star-service-uri-domain uri))
     "domain accessor")
    (assert-test
     (string= "localhost" (star-service-uri-address uri))
     "address accessor")
    (assert-test
     (string= "user-hunt" (star-service-uri-actor-name uri))
     "actor-name accessor")))

(defun test-service-uri-constructor ()
  (let ((uri (make-star-service-uri "bbp" "localhost" "nmap")))
    (assert-test
     (string= "star://bbp:localhost:nmap"
              (star-service-uri-string uri))
     "constructor canonical output")
    (assert-test
     (eq uri (ensure-star-service-uri uri))
     "ensure preserves URI objects")))

(defun test-malformed-service-uris-are-typed ()
  (dolist (value '("http://quasar:localhost:user-hunt"
                   "star://quasar:user-hunt"
                   "star://quasar:localhost:user-hunt:extra"
                   "star://Quasar:localhost:user-hunt"
                   "star://quasar:local:host:user-hunt"
                   "star://:localhost:user-hunt"
                   "star://quasar::user-hunt"
                   "star://quasar:localhost:"))
    (assert-test
     (signals-invalid-service-uri-p
      (lambda () (parse-star-service-uri value)))
     (format nil "malformed URI is typed: ~S" value))))

(defun test-invalid-constructor-tokens-are-typed ()
  (assert-test
   (signals-invalid-service-uri-p
    (lambda ()
      (make-star-service-uri
       "Quasar" "localhost" "user-hunt")))
   "uppercase constructor token rejected")
  (assert-test
   (signals-invalid-service-uri-p
    (lambda ()
      (make-star-service-uri
       "quasar" "local:host" "user-hunt")))
   "colon constructor token rejected"))

(defun test-actor-name-consistency ()
  (assert-test
   (string= "star://quasar:localhost:user-hunt"
            (canonical-star-service-uri-for-actor
             "user-hunt"
             "star://quasar:localhost:user-hunt"))
   "matching actor name remains canonical")
  (assert-test
   (signals-invalid-service-uri-p
    (lambda ()
      (canonical-star-service-uri-for-actor
       "different-actor"
       "star://quasar:localhost:user-hunt")))
   "mismatched actor name rejected"))

(defun test-actor-reference-round-trip ()
  (let* ((reference
           (make-star-actor-reference
            :domain-id "quasar"
            :logical-path "user-hunt"
            :node-id "localhost"
            :generation 7
            :protocol-revision 1
            :capability-set-hash "sha256:fixture"))
         (same-logical
           (make-star-actor-reference
            :domain-id "quasar"
            :logical-path "user-hunt"
            :node-id "localhost"
            :generation 8)))
    (assert-test
     (star-actor-reference-p reference)
     "actor reference constructor")
    (assert-test
     (string= "quasar"
              (star-actor-reference-domain-id reference))
     "actor reference domain")
    (assert-test
     (string= "user-hunt"
              (star-actor-reference-logical-path reference))
     "actor reference logical path")
    (assert-test
     (string= "localhost"
              (star-actor-reference-node-id reference))
     "actor reference node")
    (assert-test
     (= 7 (star-actor-reference-generation reference))
     "actor reference generation")
    (assert-test
     (= 1 (star-actor-reference-protocol-revision reference))
     "actor reference protocol revision")
    (assert-test
     (string= "star://quasar:localhost:user-hunt"
              (star-actor-reference-service-uri reference))
     "actor reference service URI")
    (assert-test
     (star-actor-reference-same-logical-actor-p
      reference same-logical)
     "generation does not change logical actor identity")))

(defun test-invalid-actor-reference-is-typed ()
  (assert-test
   (signals-condition-p
    'invalid-actor-reference-error
    (lambda ()
      (make-star-actor-reference
       :domain-id "quasar"
       :logical-path "user-hunt"
       :node-id "localhost"
       :generation -1)))
   "negative generation rejected")
  (assert-test
   (signals-condition-p
    'invalid-actor-reference-error
    (lambda ()
      (make-star-actor-reference
       :domain-id "Quasar"
       :logical-path "user-hunt"
       :node-id "localhost")))
   "invalid service identity rejected"))

(defun sample-command (&key
                         (message-id "cmd-0001")
                         (idempotency-key "scope-0001"))
  (make-command-envelope
   :message-id message-id
   :message-type "org.starintel/test@1/run"
   :actor "worker"
   :sender "test"
   :idempotency-key idempotency-key
   :dataset "fixture"
   :payload '((:value . 1))))

(defun test-command-construction-and-validation ()
  (let ((command (sample-command))
        (payload-validations 0))
    (assert-equal
     +lifecycle-wire-version+
     (getf command :star-version)
     "command wire revision")
    (assert-equal
     :command
     (getf command :kind)
     "command kind")
    (assert-equal
     "cmd-0001"
     (lifecycle-message-id command)
     "message identity")
    (assert-equal
     "cmd-0001"
     (lifecycle-correlation-id command)
     "command correlation identity")
    (assert-equal
     '("worker" "org.starintel/test@1/run" "scope-0001")
     (idempotency-scope-key command)
     "portable idempotency scope identity")
    (assert-test
     (validate-lifecycle-envelope
      command
      :payload-validator
      (lambda (envelope)
        (incf payload-validations)
        (assert-test
         (eq envelope command)
         "payload validator receives final envelope")))
     "command validates")
    (assert-equal
     1 payload-validations
     "data payload validation hook called once")))

(defun test-command-validation-failures ()
  (assert-test
   (signals-invalid-wire-envelope-p
    (lambda ()
      (make-command-envelope
       :message-id "missing-key"
       :message-type "org.starintel/test@1/run"
       :actor "worker"
       :payload nil)))
   "command requires idempotency key")
  (let ((command (sample-command)))
    (setf (getf command :attempt) 0)
    (assert-test
     (signals-invalid-wire-envelope-p
      (lambda ()
        (validate-lifecycle-envelope command)))
     "attempt zero rejected"))
  (let ((command (sample-command)))
    (setf (getf command :star-version) 2)
    (assert-test
     (signals-invalid-wire-envelope-p
      (lambda ()
        (validate-lifecycle-envelope command)))
     "unsupported protocol revision rejected"))
  (assert-test
   (signals-invalid-wire-envelope-p
    (lambda ()
      (validate-lifecycle-envelope
       '(:star-version 1 :kind :command))))
   "malformed command envelope rejected"))

(defun test-reply-classification-and-correlation ()
  (let* ((command (sample-command))
         (reply
           (make-reply-envelope
            command
            :message-id "reply-0001"
            :message-type "org.starintel/test@1/result"
            :actor "client"
            :sender "worker"
            :payload '((:ok . t)))))
    (assert-test
     (validate-lifecycle-envelope reply)
     "reply validates")
    (assert-equal
     "cmd-0001"
     (lifecycle-correlation-id reply)
     "reply preserves correlation")
    (assert-equal
     "cmd-0001"
     (lifecycle-causation-id reply)
     "reply references originating request")
    ;; Current v1 dispatcher emits reply followed by :completed ACK.
    ;; Preserve that contract: reply data itself is not terminal.
    (assert-equal
     :pending
     (delivery-outcome reply)
     "reply outcome remains non-terminal pending")
    (assert-test
     (not (terminal-lifecycle-envelope-p reply))
     "reply does not replace completed ACK terminality")))

(defun test-ack-classification ()
  (let* ((command (sample-command))
         (accepted
           (make-ack-envelope
            command
            :message-id "ack-accepted"
            :actor "worker"
            :status :accepted))
         (completed
           (make-ack-envelope
            command
            :message-id "ack-completed"
            :actor "worker"
            :status :completed))
         (retry
           (make-ack-envelope
            command
            :message-id "ack-retry"
            :actor "worker"
            :status :retry
            :retry-after-ms 250)))
    (assert-equal
     :accepted
     (delivery-outcome accepted)
     "accepted ACK classification")
    (assert-test
     (not (terminal-lifecycle-envelope-p accepted))
     "accepted ACK is non-terminal")
    (assert-equal
     :completed
     (delivery-outcome completed)
     "completed ACK classification")
    (assert-test
     (terminal-lifecycle-envelope-p completed)
     "completed ACK is terminal")
    (assert-equal
     :retry
     (delivery-outcome retry)
     "retry ACK classification")
    (assert-test
     (signals-invalid-wire-envelope-p
      (lambda ()
        (make-ack-envelope
         command
         :message-id "bad-retry"
         :actor "worker"
         :status :retry)))
     "retry ACK requires delay")))

(defun test-error-classification-correlation-and-details ()
  (let* ((command (sample-command))
         (details '((:http-status . 429)
                    (:provider . "fixture")))
         (retryable
           (make-error-envelope
            command
            :message-id "error-retry"
            :actor "worker"
            :code "test.retry"
            :message "retry"
            :retryable t
            :details details))
         (terminal
           (make-error-envelope
            command
            :message-id "error-terminal"
            :actor "worker"
            :code "test.failed"
            :message "failed"
            :retryable nil
            :details details)))
    (assert-equal
     :retry
     (delivery-outcome retryable)
     "retryable error classification")
    (assert-test
     (not (terminal-lifecycle-envelope-p retryable))
     "retryable error is non-terminal")
    (assert-equal
     :failed
     (delivery-outcome terminal)
     "terminal error classification")
    (assert-test
     (terminal-lifecycle-envelope-p terminal)
     "non-retryable error is terminal")
    (assert-equal
     "cmd-0001"
     (getf (getf terminal :payload) :for-message-id)
     "error references originating request")
    (assert-equal
     details
     (getf (getf terminal :payload) :details)
     "structured error details preserved")
    (let ((malformed (copy-tree terminal)))
      (setf (getf (getf malformed :payload) :for-message-id)
            "other-command")
      (assert-test
       (signals-invalid-wire-envelope-p
        (lambda ()
          (validate-lifecycle-envelope malformed)))
       "error correlation mismatch rejected"))))

(defun test-cancel-construction-validation-and-correlation ()
  (let* ((command (sample-command))
         (cancel
           (make-cancel-envelope
            command
            :message-id "cancel-0001"
            :actor "worker"
            :sender "client"
            :reason "no longer needed")))
    (assert-test
     (validate-lifecycle-envelope cancel)
     "cancel validates")
    (assert-equal
     :cancel-requested
     (delivery-outcome cancel)
     "cancel request classification")
    (assert-test
     (not (terminal-lifecycle-envelope-p cancel))
     "cancel request itself is non-terminal")
    (assert-equal
     "cmd-0001"
     (cancel-target-message-id cancel)
     "cancel target message identity")
    (assert-equal
     "cmd-0001"
     (cancel-target-correlation-id cancel)
     "cancel target correlation identity")
    (assert-equal
     "cmd-0001"
     (lifecycle-causation-id cancel)
     "cancel causation identity")
    (let ((malformed (copy-tree cancel)))
      (setf
       (getf (getf malformed :payload) :target-correlation-id)
       "wrong-correlation")
      (assert-test
       (signals-invalid-wire-envelope-p
        (lambda ()
          (validate-lifecycle-envelope malformed)))
       "cancel correlation mismatch rejected"))))

(defun test-terminal-replay-classification-is-stable ()
  (let* ((command (sample-command))
         (terminal
           (make-ack-envelope
            command
            :message-id "ack-terminal"
            :actor "worker"
            :status :completed))
         (replayed (copy-tree terminal)))
    (assert-test
     (terminal-lifecycle-envelope-p terminal)
     "first terminal classification")
    (assert-test
     (terminal-lifecycle-envelope-p replayed)
     "replayed terminal classification")
    (assert-equal
     (lifecycle-correlation-id terminal)
     (lifecycle-correlation-id replayed)
     "terminal replay keeps correlation identity")
    (assert-equal
     (getf (getf terminal :payload) :for-message-id)
     (getf (getf replayed :payload) :for-message-id)
     "terminal replay keeps originating request identity")))

(defun test-actor-reference-generation-remains-orthogonal-to-v1-envelope ()
  (let* ((reference
           (make-star-actor-reference
            :domain-id "local"
            :logical-path "worker"
            :node-id "localhost"
            :generation 3
            :protocol-revision 1))
         (command (sample-command)))
    (assert-test
     (validate-lifecycle-envelope command)
     "v1 command validates without inventing ActorRef wire fields")
    (assert-equal
     3
     (star-actor-reference-generation reference)
     "ActorRef generation remains separately versioned")
    (assert-equal
     1
     (star-actor-reference-protocol-revision reference)
     "ActorRef protocol revision remains intact")))

(defun run-tests ()
  (test-canonical-service-uri-round-trip)
  (test-service-uri-components)
  (test-service-uri-constructor)
  (test-malformed-service-uris-are-typed)
  (test-invalid-constructor-tokens-are-typed)
  (test-actor-name-consistency)
  (test-actor-reference-round-trip)
  (test-invalid-actor-reference-is-typed)
  (test-command-construction-and-validation)
  (test-command-validation-failures)
  (test-reply-classification-and-correlation)
  (test-ack-classification)
  (test-error-classification-correlation-and-details)
  (test-cancel-construction-validation-and-correlation)
  (test-terminal-replay-classification-is-stable)
  (test-actor-reference-generation-remains-orthogonal-to-v1-envelope)
  (format t "star-actor-protocol tests passed.~%")
  t)
