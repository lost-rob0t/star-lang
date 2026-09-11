(defpackage :staractorprotocol-tests
  (:use :cl)
  (:import-from :staractorprotocol
                #:star-actor-protocol-error
                #:invalid-star-uri
                #:invalid-star-service-uri-error
                #:invalid-actor-reference-error
                #:invalid-wire-envelope-error
                #:+star-uri-resource-kinds+
                #:star-uri
                #:star-uri-p
                #:star-uri-authority
                #:star-uri-path-segments
                #:star-uri-resource-kind
                #:star-uri-resource-path
                #:parse-star-uri
                #:serialize-star-uri
                #:star-uri-string
                #:canonicalize-star-uri
                #:canonical-star-uri-p
                #:valid-star-uri-p
                #:actor-star-uri-p
                #:star-uri-text-p
                #:ensure-star-uri
                #:canonical-star-actor-uri-for-actor
                #:legacy-star-actor-uri-p
                #:migrate-legacy-star-uri
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
                #:star-actor-reference-authority
                #:star-actor-reference-resource-path
                #:star-actor-reference-generation
                #:star-actor-reference-protocol-revision
                #:star-actor-reference-capability-set-hash
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

(defun signals-invalid-star-uri-p (thunk)
  (signals-condition-p 'invalid-star-uri thunk))

(defun signals-invalid-service-uri-p (thunk)
  (signals-condition-p 'invalid-star-service-uri-error thunk))

(defun signals-invalid-wire-envelope-p (thunk)
  (signals-condition-p 'invalid-wire-envelope-error thunk))

;;;; Shared RFC 3986 STAR URI conformance (STAR-SERVER-041 v1 profile).
;;;; The fixture set is shared with the starintel-server STAR URI
;;;; conformance suite; do not fork a second grammar here.

(defun test-canonical-actor-uri-parses-into-authority-kind-and-path ()
  (let ((uri (parse-star-uri "star://gserver.starintel.actor/actor/user-hunt")))
    (assert-test (star-uri-p uri) "parse returns a star-uri value")
    (assert-equal "gserver.starintel.actor" (star-uri-authority uri)
                  "actor URI authority")
    (assert-equal '("actor" "user-hunt") (star-uri-path-segments uri)
                  "actor URI path segments")
    (assert-equal "actor" (star-uri-resource-kind uri)
                  "actor URI resource kind")
    (assert-equal '("user-hunt") (star-uri-resource-path uri)
                  "actor URI resource path")
    (assert-equal "star://gserver.starintel.actor/actor/user-hunt"
                  (serialize-star-uri uri)
                  "canonical actor URI round-trips through serialization")
    (assert-equal (serialize-star-uri uri) (star-uri-string uri)
                  "star-uri-string aliases serialize-star-uri")))

(defun test-multi-segment-actor-path-has-no-domain-field ()
  (let ((uri
          (parse-star-uri "star://gserver.starintel.actor/actor/quasar/user-hunt")))
    (assert-equal '("quasar" "user-hunt") (star-uri-resource-path uri)
                  "multi-segment actor resource path")
    ;; STAR-RESEARCH-041: /actor/quasar/user-hunt is a two-segment resource
    ;; path, not a revived domain/address actor tuple. The value model must
    ;; not expose domain/address/actor-name URI fields at all.
    (assert-test
     (not (find-symbol "STAR-URI-DOMAIN" :staractorprotocol))
     "star-uri value model must not expose a domain field")
    (assert-test
     (not (find-symbol "STAR-URI-ADDRESS" :staractorprotocol))
     "star-uri value model must not expose an address field")
    (assert-test
     (not (find-symbol "STAR-URI-ACTOR-NAME" :staractorprotocol))
     "star-uri value model must not expose an actor-name field")))

(defun test-every-reviewed-resource-kind-parses ()
  (dolist (kind +star-uri-resource-kinds+)
    (let ((uri (parse-star-uri
                (format nil "star://gserver.starintel.actor/~A/probe" kind))))
      (assert-equal kind (star-uri-resource-kind uri)
                    "reviewed resource kind parses"))))

(defun test-scheme-and-authority-canonicalize-to-lowercase ()
  (assert-equal
   "star://gserver.starintel.actor/actor/User-Hunt"
   (canonicalize-star-uri "STAR://GServer.StarIntel.Actor/actor/User-Hunt")
   "scheme and authority canonicalize to lowercase"))

(defun test-resource-path-case-is-preserved ()
  (let ((uri (parse-star-uri "star://gserver.starintel.actor/actor/User-Hunt")))
    (assert-equal '("User-Hunt") (star-uri-resource-path uri)
                  "resource path case is preserved")))

(defun test-resource-kind-is-case-sensitive ()
  (assert-test
   (signals-invalid-star-uri-p
    (lambda () (parse-star-uri "star://gserver.starintel.actor/Actor/user-hunt")))
   "non-lowercase resource kind is rejected"))

(defun test-percent-encoding-normalization ()
  (assert-equal
   "star://gserver.starintel.actor/actor/user-hunt"
   (canonicalize-star-uri "star://gserver.starintel.actor/actor/user%2Dhunt")
   "percent-encoded unreserved characters normalize to unreserved form")
  (assert-equal
   "star://gserver.starintel.actor/actor/a%2Fb%3Fc"
   (canonicalize-star-uri "star://gserver.starintel.actor/actor/a%2fb%3fc")
   "remaining percent escapes serialize with uppercase hex digits")
  (assert-equal
   '("user.hunt")
   (star-uri-resource-path
    (parse-star-uri "star://gserver.starintel.actor/actor/user%2Ehunt"))
   "percent-encoded dots inside a segment do not create dot segments"))

(defun test-canonicalization-is-idempotent ()
  (let ((once (canonicalize-star-uri "STAR://GServer.StarIntel.Actor/actor/User-Hunt")))
    (assert-equal once (canonicalize-star-uri once)
                  "canonicalization is idempotent")))

(defun test-canonical-v1-rejections ()
  (dolist (value
           '("star://user@gserver.starintel.actor/actor/user-hunt"
             "star://gserver.starintel.actor:5672/actor/user-hunt"
             "star://gserver.starintel.actor/actor/user-hunt?trace=1"
             "star://gserver.starintel.actor/actor/user-hunt#frag"
             "star://gserver.starintel.actor/actor/./user-hunt"
             "star://gserver.starintel.actor/actor/../user-hunt"
             "star://gserver.starintel.actor/actor/user-hunt/."
             "star://gserver.starintel.actor/actor/user-hunt/.."
             "star://gserver.starintel.actor/actor/%2E/user-hunt"
             "star://gserver.starintel.actor/actor/%2E%2E/user-hunt"
             "star://gserver.starintel.actor/actor/%2e%2e/user-hunt"
             "star://gserver.starintel.actor/actor/%2E./user-hunt"
             "star://gserver.starintel.actor/actor/.%2E/user-hunt"
             "star://gserver.starintel.actor/actor/user%ZZ-hunt"
             "star://gserver.starintel.actor/actor/user%2-hunt"
             "star://gserver.starintel.actor/actor/user hunt"
             "star://gserver.starintel.actor/actor/user[hunt]"
             "star://"
             "star:///actor/user-hunt"
             "star://gserver.starintel.actor"
             "star://gserver.starintel.actor/"
             "star://gserver.starintel.actor//user-hunt"
             "star://gserver.starintel.actor/actor/"
             "star://gserver.starintel.actor/actor//user-hunt"
             "star://gserver.starintel.actor/widget/01K"
             "http://example.org/actor/x"
             ""))
    (assert-test
     (signals-invalid-star-uri-p (lambda () (parse-star-uri value)))
     (format nil "canonical v1 rejection: ~S" value)))
  (assert-test
   (signals-invalid-star-uri-p (lambda () (parse-star-uri nil)))
   "non-string input is rejected"))

(defun test-canonical-star-uri-p-distinguishes-canonical-from-canonicalizable ()
  (dolist (value '("star://gserver.starintel.actor/actor/user-hunt"
                   "star://gserver.starintel.actor/actor/a%2Fb"))
    (assert-test (canonical-star-uri-p value)
                 (format nil "already canonical: ~S" value)))
  (dolist (value '("STAR://GServer.StarIntel.Actor/actor/User-Hunt"
                   "star://gserver.starintel.actor/actor/user%2Dhunt"
                   "star://gserver.starintel.actor/actor/a%2fb"
                   "star://gserver.starintel.actor/actor/../user-hunt"))
    (assert-test (not (canonical-star-uri-p value))
                 (format nil "not yet canonical: ~S" value))))

(defun test-valid-star-uri-p-accepts-canonicalizable-input ()
  (assert-test (valid-star-uri-p
                "star://gserver.starintel.actor/actor/user%2Dhunt")
               "canonicalizable input is valid")
  (assert-test (not (valid-star-uri-p
                     "star://gserver.starintel.actor:5672/actor/user-hunt"))
               "port-bearing authority is invalid"))

(defun test-actor-star-uri-p-requires-actor-kind-and-resource-path ()
  (assert-test (actor-star-uri-p "star://bbpd.starintel.actor/actor/subfinder")
               "actor URI with resource path")
  (assert-test (not (actor-star-uri-p
                     "star://gserver.starintel.actor/service/starintel-mcp"))
               "service URI is not an actor URI")
  (assert-test (not (actor-star-uri-p "star://gserver.starintel.actor/actor"))
               "bare actor kind has no resource path"))

(defun test-star-uri-text-p-and-ensure-star-uri ()
  (assert-test (star-uri-text-p "star://quasar:localhost:user-hunt")
               "legacy tuple is still textual star:// input")
  (assert-test (star-uri-text-p "star://gserver.starintel.actor/actor/user-hunt")
               "canonical URI is textual star:// input")
  (assert-test (not (star-uri-text-p "worker"))
               "bare name is not star:// text")
  (let ((uri (parse-star-uri "star://gserver.starintel.actor/actor/user-hunt")))
    (assert-test (eq uri (ensure-star-uri uri))
                 "ensure-star-uri preserves star-uri values")
    (assert-test (star-uri-p (ensure-star-uri
                             "star://gserver.starintel.actor/actor/user-hunt"))
                 "ensure-star-uri parses strings")))

(defun test-canonical-star-actor-uri-for-actor ()
  (assert-equal
   "star://gserver.starintel.actor/actor/user-hunt"
   (canonical-star-actor-uri-for-actor
    "user-hunt" "star://gserver.starintel.actor/actor/user-hunt")
   "matching actor name remains canonical")
  (assert-equal
   "star://gserver.starintel.actor/actor/quasar/user-hunt"
   (canonical-star-actor-uri-for-actor
    "user-hunt" "star://gserver.starintel.actor/actor/quasar/user-hunt")
   "multi-segment actor path ending in the actor name is canonical")
  (assert-equal
   "star://gserver.starintel.actor/actor/User-Hunt"
   (canonical-star-actor-uri-for-actor
    "User-Hunt" "STAR://GServer.StarIntel.Actor/actor/User-Hunt")
   "canonicalizable actor input normalizes to canonical form")
  (assert-test
   (signals-invalid-star-uri-p
    (lambda ()
      (canonical-star-actor-uri-for-actor
       "different-actor" "star://gserver.starintel.actor/actor/user-hunt")))
   "actor name/URI terminal segment mismatch is rejected")
  (assert-test
   (signals-invalid-star-uri-p
    (lambda ()
      (canonical-star-actor-uri-for-actor
       "starintel-mcp" "star://gserver.starintel.actor/service/starintel-mcp")))
   "non-actor resource kind is rejected for actor identity")
  (assert-test
   (signals-invalid-star-uri-p
    (lambda ()
      (canonical-star-actor-uri-for-actor
       "user-hunt" "star://quasar:localhost:user-hunt")))
   "legacy tuple input is not accepted as canonical actor identity"))

;;;; Legacy star://domain:address:actor-name compatibility input.
;;;; The tuple is accepted only through this explicit compatibility API
;;;; (STAR-SERVER-041, STAR-LANG-004); parse-star-uri rejects it.

(defun test-legacy-tuple-is-not-a-canonical-star-uri ()
  (assert-test
   (signals-invalid-star-uri-p
    (lambda () (parse-star-uri "star://quasar:localhost:user-hunt")))
   "canonical parser rejects the legacy tuple"))

(defun test-legacy-service-uri-round-trip ()
  (dolist (value '("star://quasar:localhost:user-hunt"
                   "star://bbp:localhost:nmap"))
    (let ((uri (parse-star-service-uri value)))
      (assert-test (star-service-uri-p uri)
                    "legacy parse returns a tuple value")
      (assert-test (string= value (star-service-uri-string uri))
                   "legacy tuple round-trips unchanged"))))

(defun test-legacy-service-uri-components ()
  (let ((uri (parse-star-service-uri "star://quasar:localhost:user-hunt")))
    (assert-test (string= "quasar" (star-service-uri-domain uri))
                 "legacy domain accessor")
    (assert-test (string= "localhost" (star-service-uri-address uri))
                 "legacy address accessor")
    (assert-test (string= "user-hunt" (star-service-uri-actor-name uri))
                 "legacy actor-name accessor")))

(defun test-legacy-service-uri-constructor ()
  (let ((uri (make-star-service-uri "bbp" "localhost" "nmap")))
    (assert-test
     (string= "star://bbp:localhost:nmap" (star-service-uri-string uri))
     "legacy constructor output")
    (assert-test (eq uri (ensure-star-service-uri uri))
                 "legacy ensure preserves tuple values")))

(defun test-legacy-malformed-service-uris-are-typed ()
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
     (format nil "legacy malformed URI is typed: ~S" value))))

(defun test-legacy-invalid-constructor-tokens-are-typed ()
  (assert-test
   (signals-invalid-service-uri-p
    (lambda () (make-star-service-uri "Quasar" "localhost" "user-hunt")))
   "legacy uppercase constructor token rejected")
  (assert-test
   (signals-invalid-service-uri-p
    (lambda () (make-star-service-uri "quasar" "local:host" "user-hunt")))
   "legacy colon constructor token rejected"))

(defun test-legacy-actor-name-consistency ()
  (assert-test
   (string= "star://quasar:localhost:user-hunt"
            (canonical-star-service-uri-for-actor
             "user-hunt" "star://quasar:localhost:user-hunt"))
   "legacy matching actor name remains tuple-canonical")
  (assert-test
   (signals-invalid-service-uri-p
    (lambda ()
      (canonical-star-service-uri-for-actor
       "different-actor" "star://quasar:localhost:user-hunt")))
   "legacy mismatched actor name rejected"))

(defun test-legacy-star-actor-uri-p ()
  (assert-test (legacy-star-actor-uri-p "star://quasar:localhost:user-hunt")
               "legacy tuple recognized as compatibility input")
  (assert-test
   (not (legacy-star-actor-uri-p
         "star://gserver.starintel.actor/actor/user-hunt"))
   "canonical RFC URI is not legacy tuple input")
  (assert-test (not (legacy-star-actor-uri-p "http://quasar:localhost:nmap"))
               "non-star scheme is not legacy tuple input"))

(defun test-legacy-migration-requires-explicit-canonical-target ()
  (assert-test
   (signals-invalid-star-uri-p
    (lambda () (migrate-legacy-star-uri "star://quasar:localhost:user-hunt")))
   "legacy migration without an explicit target is rejected")
  (assert-test
   (signals-invalid-star-uri-p
    (lambda ()
      (migrate-legacy-star-uri
       "star://quasar:localhost:user-hunt"
       :to "star://gserver.starintel.actor/actor/user%2Dhunt")))
   "canonicalizable (not yet canonical) migration target is rejected")
  (assert-equal
   "star://gserver.starintel.actor/actor/user-hunt"
   (migrate-legacy-star-uri
    "star://quasar:localhost:user-hunt"
    :to "star://gserver.starintel.actor/actor/user-hunt")
   "explicit canonical migration target normalizes immediately"))

(defun test-legacy-migration-accepts-an-explicit-migration-map ()
  (assert-equal
   "star://gserver.starintel.actor/actor/user-hunt"
   (migrate-legacy-star-uri
    "star://bbp:localhost:nmap"
    :map '(("star://bbp:localhost:nmap"
            . "star://gserver.starintel.actor/actor/user-hunt")))
   "explicit migration map entry normalizes immediately")
  (assert-test
   (signals-invalid-star-uri-p
    (lambda ()
      (migrate-legacy-star-uri
       "star://bbp:localhost:nmap"
       :map '(("star://quasar:localhost:user-hunt"
               . "star://gserver.starintel.actor/actor/user-hunt"))))))
  (assert-test
   (signals-invalid-star-uri-p
    (lambda ()
      (migrate-legacy-star-uri
       "star://bbp:localhost:nmap"
       :map '(("star://bbp:localhost:nmap"
               . "star://gserver.starintel.actor/actor/user%2Dhunt")))))
   "migration map targets must already be canonical"))

(defun test-legacy-domain-is-never-mapped-to-an-authority ()
  ;; STAR-SERVER-041 forbids automatic domain->authority rewrites such as
  ;; legacy.<domain> or domain -> first path segment. Only the explicit
  ;; target is returned.
  (assert-equal
   "star://bbpd.starintel.actor/actor/subfinder"
   (migrate-legacy-star-uri
    "star://quasar:localhost:user-hunt"
    :to "star://bbpd.starintel.actor/actor/subfinder")
   "migration returns exactly the explicit canonical target")
  (assert-test
   (not (canonical-star-uri-p "star://legacy.quasar/actor/user-hunt"))
   "invented legacy.<domain> authorities are not part of the model"))

;;;; Generation-bearing actor references on the canonical value model.

(defun test-actor-reference-round-trip ()
  (let* ((reference
           (make-star-actor-reference
            :authority "gserver.starintel.actor"
            :resource-path '("quasar" "user-hunt")
            :generation 7
            :protocol-revision 1
            :capability-set-hash "sha256:fixture"))
         (same-logical
           (make-star-actor-reference
            :authority "gserver.starintel.actor"
            :resource-path '("quasar" "user-hunt")
            :generation 8)))
    (assert-test (star-actor-reference-p reference)
                 "actor reference constructor")
    (assert-test (string= "gserver.starintel.actor"
                          (star-actor-reference-authority reference))
                 "actor reference authority")
    (assert-test (equal '("quasar" "user-hunt")
                        (star-actor-reference-resource-path reference))
                 "actor reference resource path")
    (assert-test (= 7 (star-actor-reference-generation reference))
                 "actor reference generation")
    (assert-test (= 1 (star-actor-reference-protocol-revision reference))
                 "actor reference protocol revision")
    (assert-test (string= "sha256:fixture"
                          (star-actor-reference-capability-set-hash reference))
                 "actor reference capability-set hash")
    (assert-test
     (string= "star://gserver.starintel.actor/actor/quasar/user-hunt"
              (star-actor-reference-service-uri reference))
     "actor reference service URI serializes canonically")
    (assert-test
     (star-actor-reference-same-logical-actor-p reference same-logical)
     "generation does not change logical actor identity")))

(defun test-invalid-actor-reference-is-typed ()
  (assert-test
   (signals-condition-p
    'invalid-actor-reference-error
    (lambda ()
      (make-star-actor-reference
       :authority "gserver.starintel.actor"
       :resource-path '("user-hunt")
       :generation -1)))
   "negative generation rejected")
  (assert-test
   (signals-condition-p
    'invalid-actor-reference-error
    (lambda ()
      (make-star-actor-reference
       :authority "GServer.StarIntel.Actor"
       :resource-path '("user-hunt"))))
   "non-canonical authority rejected")
  (assert-test
   (signals-condition-p
    'invalid-actor-reference-error
    (lambda ()
      (make-star-actor-reference
       :authority "gserver.starintel.actor"
       :resource-path '())))
   "empty actor resource path rejected"))

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
      (lambda () (validate-lifecycle-envelope command)))
     "attempt zero rejected"))
  (let ((command (sample-command)))
    (setf (getf command :star-version) 2)
    (assert-test
     (signals-invalid-wire-envelope-p
      (lambda () (validate-lifecycle-envelope command)))
     "unsupported protocol revision rejected"))
  (assert-test
   (signals-invalid-wire-envelope-p
    (lambda () (validate-lifecycle-envelope '(:star-version 1 :kind :command))))
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
        (lambda () (validate-lifecycle-envelope malformed)))
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
        (lambda () (validate-lifecycle-envelope malformed)))
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
            :authority "local"
            :resource-path '("worker")
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
  (test-canonical-actor-uri-parses-into-authority-kind-and-path)
  (test-multi-segment-actor-path-has-no-domain-field)
  (test-every-reviewed-resource-kind-parses)
  (test-scheme-and-authority-canonicalize-to-lowercase)
  (test-resource-path-case-is-preserved)
  (test-resource-kind-is-case-sensitive)
  (test-percent-encoding-normalization)
  (test-canonicalization-is-idempotent)
  (test-canonical-v1-rejections)
  (test-canonical-star-uri-p-distinguishes-canonical-from-canonicalizable)
  (test-valid-star-uri-p-accepts-canonicalizable-input)
  (test-actor-star-uri-p-requires-actor-kind-and-resource-path)
  (test-star-uri-text-p-and-ensure-star-uri)
  (test-canonical-star-actor-uri-for-actor)
  (test-legacy-tuple-is-not-a-canonical-star-uri)
  (test-legacy-service-uri-round-trip)
  (test-legacy-service-uri-components)
  (test-legacy-service-uri-constructor)
  (test-legacy-malformed-service-uris-are-typed)
  (test-legacy-invalid-constructor-tokens-are-typed)
  (test-legacy-actor-name-consistency)
  (test-legacy-star-actor-uri-p)
  (test-legacy-migration-requires-explicit-canonical-target)
  (test-legacy-migration-accepts-an-explicit-migration-map)
  (test-legacy-domain-is-never-mapped-to-an-authority)
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