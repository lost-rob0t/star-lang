;;;; Canonical hierarchical STAR resource URI conformance (issue #72 slice 1):
;;;; star://<authority>/<resource-kind>/<resource-path> with legacy tuple URIs
;;;; accepted as compatibility input only and never re-emitted.

(defpackage :staractorprotocol-resource-uri-tests
  (:use :cl)
  (:import-from :staractorprotocol
                #:invalid-star-resource-uri-error
                #:star-resource-kind-error
                #:legacy-star-resource-uri-error
                #:star-resource-uri
                #:star-resource-uri-p
                #:star-resource-uri-authority
                #:star-resource-uri-resource-kind
                #:star-resource-uri-resource-path
                #:star-resource-uri-path-segments
                #:parse-star-resource-uri
                #:star-resource-uri-string
                #:ensure-star-resource-uri
                #:canonical-star-resource-uri-for-actor
                #:hierarchical-star-uri-p)
  (:export #:run-tests))

(in-package :staractorprotocol-resource-uri-tests)

(defun assert-test (condition label)
  (unless condition
    (error "star-actor-protocol resource-uri test failed: ~A" label)))

(defun assert-equal (expected actual label)
  (assert-test (equal expected actual) label))

(defun assert-eq (expected actual label)
  (assert-test (eq expected actual) label))

(defun assert-string= (expected actual label)
  (assert-test (and (stringp actual) (string= expected actual)) label))

(defmacro assert-invalid (form label)
  `(assert-test
    (handler-case (progn ,form nil)
      (staractorprotocol:invalid-star-resource-uri-error () t)
      (error (condition)
        (error "star-actor-protocol resource-uri test failed: ~A (~A)"
               ,label condition)))
    ,label))

(defun run-tests ()
  (assert-test t "smoke")

  ;; Round trip and accessors.
  (let ((uri (parse-star-resource-uri "star://starintel.example/actor/ingest-service")))
    (assert-test (star-resource-uri-p uri) "parsed value")
    (assert-string= "starintel.example" (star-resource-uri-authority uri) "authority")
    (assert-eq :actor (star-resource-uri-resource-kind uri) "actor kind")
    (assert-string= "ingest-service" (star-resource-uri-resource-path uri) "resource path")
    (assert-equal '("ingest-service") (star-resource-uri-path-segments uri) "segments")
    (assert-string= "star://starintel.example/actor/ingest-service"
                    (star-resource-uri-string uri) "canonical string"))

  ;; Service kind and multi-segment case-preserving resource path.
  (let ((uri (parse-star-resource-uri "star://bbpd.invalid/service/Programs/FEC")))
    (assert-eq :service (star-resource-uri-resource-kind uri) "service kind")
    (assert-string= "Programs/FEC" (star-resource-uri-resource-path uri)
                    "case-preserving resource path")
    (assert-equal '("Programs" "FEC") (star-resource-uri-path-segments uri)
                  "case-preserving segments")
    (assert-string= "star://bbpd.invalid/service/Programs/FEC"
                    (star-resource-uri-string uri) "service canonical string"))

  ;; Authority normalization rules.
  (assert-invalid (parse-star-resource-uri "STAR://a/actor/x")
                  "uppercase scheme rejected")
  (assert-invalid (parse-star-resource-uri "star://StarIntel.example/actor/x")
                  "uppercase authority rejected")
  (assert-invalid (parse-star-resource-uri "star://user@a/actor/x")
                  "userinfo rejected")
  (assert-invalid (parse-star-resource-uri "star://a:4222/actor/x")
                  "transport port rejected")
  (assert-invalid (parse-star-resource-uri "star:///actor/x")
                  "empty authority rejected")
  (assert-invalid (parse-star-resource-uri "star://a_b/actor/x")
                  "underscore authority rejected")

  ;; Path rules: no query, fragment, dot segments, or empty segments.
  (assert-invalid (parse-star-resource-uri "star://a/actor/x?y=1")
                  "query rejected")
  (assert-invalid (parse-star-resource-uri "star://a/actor/x#frag")
                  "fragment rejected")
  (assert-invalid (parse-star-resource-uri "star://a/actor/./x")
                  "dot segment rejected")
  (assert-invalid (parse-star-resource-uri "star://a/actor/../x")
                  "dotdot segment rejected")
  (assert-invalid (parse-star-resource-uri "star://a/actor//x")
                  "empty path segment rejected")
  (assert-invalid (parse-star-resource-uri "star://a/actor/x/")
                  "trailing slash rejected")

  ;; Reviewed resource kinds only.
  (assert-invalid (parse-star-resource-uri "star://a/domain/x")
                  "legacy domain kind rejected")
  (assert-test
   (handler-case (progn (parse-star-resource-uri "star://a/tool/x") nil)
     (staractorprotocol:star-resource-kind-error () t))
   "unknown kind is a typed wrong-kind failure")
  (assert-invalid (parse-star-resource-uri "star://a/actor")
                  "missing resource path rejected")
  (assert-invalid (parse-star-resource-uri "star://a/Actor/x")
                  "uppercase kind rejected")

  ;; Percent-encoding normalization.
  (assert-string=
   "star://a/actor/x%20y"
   (star-resource-uri-string
    (parse-star-resource-uri "star://a/actor/x%20y"))
   "reserved escape preserved uppercase")
  (assert-string=
   "star://a/actor/x%2Fy"
   (star-resource-uri-string
    (parse-star-resource-uri "star://a/actor/x%2fy"))
   "lowercase hex escape normalized uppercase")
  (assert-string=
   "star://a/actor/xAy"
   (star-resource-uri-string
    (parse-star-resource-uri "star://a/actor/x%41y"))
   "unreserved escape decoded")
  (assert-invalid (parse-star-resource-uri "star://a/actor/x%zz")
                  "invalid hex escape rejected")
  (assert-invalid (parse-star-resource-uri "star://a/actor/x%2")
                  "truncated escape rejected")

  ;; Legacy tuple URIs are compatibility input, never canonical values.
  (assert-test (not (hierarchical-star-uri-p "star://starintel:localhost:ingest"))
               "legacy tuple is not hierarchical")
  (assert-test (hierarchical-star-uri-p "star://starintel.example/actor/ingest")
               "canonical form is hierarchical")
  (assert-test
   (handler-case
       (progn (parse-star-resource-uri "star://starintel:localhost:ingest") nil)
     (staractorprotocol:legacy-star-resource-uri-error () t))
   "tuple input signals the typed legacy outcome")

  ;; Actor binding: last path segment must equal the actor contract name.
  (assert-string=
   "star://a/actor/ingest-service"
   (canonical-star-resource-uri-for-actor
    "ingest-service" "star://a/actor/ingest-service")
   "matching actor binding canonicalizes")
  (assert-test
   (handler-case
       (progn (canonical-star-resource-uri-for-actor
               "other" "star://a/actor/ingest-service")
              nil)
     (staractorprotocol:invalid-star-resource-uri-error () t))
   "mismatched actor binding rejected")

  ;; ensure-star-resource-uri accepts values and strings.
  (let ((uri (parse-star-resource-uri "star://a/actor/x")))
    (assert-test (eq uri (ensure-star-resource-uri uri)) "identity on value"))
  (assert-test
   (star-resource-uri-p (ensure-star-resource-uri "star://a/actor/x"))
   "string coerced through parse")

  (format t "star-actor-protocol resource-uri tests passed~%")
  t)
