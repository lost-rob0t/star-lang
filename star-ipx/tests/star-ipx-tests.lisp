(defpackage :staripx-tests
  (:use :cl)
  (:export #:run-tests))

(in-package :staripx-tests)

(defun check (condition control &rest arguments)
  (unless condition
    (error (apply #'format nil control arguments))))

(defun make-ref (offset length digest)
  (staripx:make-ipx-evidence-ref
   "operation-spool-01"
   offset
   length
   digest))

(defun fixture-exchange ()
  (staripx:make-ipx-http-exchange
   :operation-id "operation-01"
   :capture-session-id "capture-01"
   :exchange-id "exchange-0001"
   :evidence-ref (make-ref 0 2048 "sha256:whole-exchange")
   :timestamp-ms 1788206400123
   :method "POST"
   :scheme "https"
   :host "example.test"
   :port 443
   :path "/session"
   :query-ref (make-ref 120 47 "sha256:exact-query-bytes")
   :request-headers-ref (make-ref 200 431 "sha256:exact-request-header-bytes")
   :request-body-ref (make-ref 631 233 "sha256:exact-request-body-bytes")
   :response-status 302
   :response-headers-ref (make-ref 864 387 "sha256:exact-response-header-bytes")
   :response-body-ref (make-ref 1251 797 "sha256:exact-response-body-bytes")))

(defun check-ref-equal (expected actual label)
  (check (and (staripx:ipx-evidence-ref-p actual)
              (equal (staripx:ipx-evidence-ref-source-id expected)
                     (staripx:ipx-evidence-ref-source-id actual))
              (= (staripx:ipx-evidence-ref-record-offset expected)
                 (staripx:ipx-evidence-ref-record-offset actual))
              (= (staripx:ipx-evidence-ref-byte-length expected)
                 (staripx:ipx-evidence-ref-byte-length actual))
              (equal (staripx:ipx-evidence-ref-digest expected)
                     (staripx:ipx-evidence-ref-digest actual)))
         "~A evidence reference changed across the actor pipeline." label))

(defun run-actor-pipeline-test ()
  (let* ((system (staripx:start-ipx-actor-system :name-prefix "ipx-test"))
         (runtime (staripx:ipx-actor-system-runtime system))
         (exchange (fixture-exchange)))
    (unwind-protect
         (progn
           (check (= 3 (starlangruntime:runtime-actor-count runtime))
                  "IPX must boot exactly three real StarLang actors in this slice.")
           (let ((first (staripx:submit-ipx-exchange system exchange))
                 (second (staripx:submit-ipx-exchange system exchange)))
             (check (eq :accepted (staripx:ipx-ingest-ack-status first))
                    "First exchange was not accepted: ~S"
                    (staripx:ipx-ingest-ack-status first))
             (check (eq :duplicate (staripx:ipx-ingest-ack-status second))
                    "Replay was not idempotently rejected as duplicate: ~S"
                    (staripx:ipx-ingest-ack-status second)))
           (let* ((snapshot (staripx:ipx-system-projections system))
                  (projected (staripx:ipx-projection-snapshot-exchanges snapshot)))
             (check (= 1 (length projected))
                    "Replay produced ~D projections instead of one."
                    (length projected))
             (let ((actual (first projected)))
               (check (equal "POST" (staripx:ipx-http-exchange-method actual))
                      "HTTP method changed across the actor pipeline.")
               (check (equal "/session" (staripx:ipx-http-exchange-path actual))
                      "HTTP path changed across the actor pipeline.")
               (check-ref-equal
                (staripx:ipx-http-exchange-evidence-ref exchange)
                (staripx:ipx-http-exchange-evidence-ref actual)
                "whole exchange")
               (check-ref-equal
                (staripx:ipx-http-exchange-query-ref exchange)
                (staripx:ipx-http-exchange-query-ref actual)
                "query")
               (check-ref-equal
                (staripx:ipx-http-exchange-request-headers-ref exchange)
                (staripx:ipx-http-exchange-request-headers-ref actual)
                "request headers")
               (check-ref-equal
                (staripx:ipx-http-exchange-request-body-ref exchange)
                (staripx:ipx-http-exchange-request-body-ref actual)
                "request body")
               (check-ref-equal
                (staripx:ipx-http-exchange-response-headers-ref exchange)
                (staripx:ipx-http-exchange-response-headers-ref actual)
                "response headers")
               (check-ref-equal
                (staripx:ipx-http-exchange-response-body-ref exchange)
                (staripx:ipx-http-exchange-response-body-ref actual)
                "response body")))
           (check (= 2
                     (starlangruntime:actor-instance-invocation-count
                      (starlangruntime:find-actor runtime "ipx-test-ingress")))
                  "Ingress did not execute through the real actor runtime twice.")
           (check (= 2
                     (starlangruntime:actor-instance-invocation-count
                      (starlangruntime:find-actor runtime "ipx-test-correlator")))
                  "Correlator did not execute through the real actor runtime twice.")
           (check (= 2
                     (starlangruntime:actor-instance-invocation-count
                      (starlangruntime:find-actor runtime "ipx-test-projection")))
                  "Projection actor invocation count proves the duplicate was projected.")
           (let ((other
                   (staripx:ipx-system-projections
                    system :operation-id "another-operation")))
             (check (null (staripx:ipx-projection-snapshot-exchanges other))
                    "Operation filter leaked another operation's projection."))
           t)
      (staripx:shutdown-ipx-actor-system system))
    (check (eq :stopped (starlangruntime:runtime-status runtime))
           "Owned StarLang runtime did not stop with the IPX system.")))

(defun run-constructor-validation-test ()
  (handler-case
      (progn
        (staripx:make-ipx-evidence-ref "source" -1 10 "digest")
        (error "Negative evidence offsets must be rejected."))
    (staripx:invalid-ipx-value-error () t)))

(defun run-tests ()
  (run-constructor-validation-test)
  (run-actor-pipeline-test)
  (format t "star-ipx tests passed.~%")
  t)
