(defpackage :staractorprotocol-remote-tests
  (:use :cl)
  (:import-from :staractorprotocol
                #:invalid-star-uri-error
                #:invalid-remote-object-reference-error
                #:star-uri-p
                #:star-uri-authority
                #:star-uri-resource-kind
                #:star-uri-resource-path
                #:make-star-uri
                #:parse-star-uri
                #:star-uri-string
                #:ensure-star-uri
                #:remote-object-ref-p
                #:remote-object-ref-protocol-version
                #:remote-object-ref-resource-uri
                #:remote-object-ref-resource-kind
                #:remote-object-ref-interface-id
                #:remote-object-ref-interface-version
                #:remote-object-ref-interface-digest
                #:remote-object-ref-object-id
                #:remote-object-ref-instance-generation
                #:remote-object-ref-authority
                #:remote-object-ref-capability-set
                #:make-remote-object-ref
                #:validate-remote-object-ref
                #:remote-object-ref-portable-map
                #:parse-remote-object-ref
                #:remote-object-ref-stale-generation-p
                #:remote-operation-id-p)
  (:export #:run-tests))

(in-package :staractorprotocol-remote-tests)

(defun check (condition label)
  (unless condition
    (error "remote-object test failed: ~A" label)))

(defun check-equal (expected actual label)
  (check (equal expected actual)
         (format nil "~A expected ~S, received ~S" label expected actual)))

(defun signals-p (condition-type thunk)
  (handler-case
      (progn
        (funcall thunk)
        nil)
    (error (condition)
      (typep condition condition-type))))

(defun test-canonical-star-uri-round-trip ()
  (let ((uri (parse-star-uri "star://node.example/actor/wifi/Kismet")))
    (check (star-uri-p uri) "parse returns canonical STAR URI")
    (check-equal "node.example" (star-uri-authority uri) "authority")
    (check-equal "actor" (star-uri-resource-kind uri) "resource kind")
    (check-equal "wifi/Kismet" (star-uri-resource-path uri) "resource path")
    (check-equal "star://node.example/actor/wifi/Kismet"
                 (star-uri-string uri)
                 "canonical URI string")
    (check (eq uri (ensure-star-uri uri)) "ensure preserves URI object")))

(defun test-star-uri-normalizes-authority-and-percent-encoding ()
  (check-equal
   "star://node.example/object/a~b/%2F"
   (star-uri-string
    (parse-star-uri "STAR://NODE.EXAMPLE/object/a%7eb/%2f"))
   "scheme, authority and percent encoding normalize deterministically"))

(defun test-star-uri-constructor ()
  (check-equal
   "star://authority.example/service/geo/query"
   (star-uri-string
    (make-star-uri "AUTHORITY.EXAMPLE" "service" '("geo" "query")))
   "constructor emits canonical hierarchical URI"))

(defun test-malformed-star-uris-are-typed ()
  (dolist (value '("http://node.example/actor/wifi"
                   "star://node.example"
                   "star://node.example/actor"
                   "star://node.example:5555/actor/wifi"
                   "star://user@node.example/actor/wifi"
                   "star://node.example/actor/../wifi"
                   "star://node.example/actor/./wifi"
                   "star://node.example/actor/wifi?x=1"
                   "star://node.example/actor/wifi#fragment"
                   "star://node.example//wifi"
                   "star:///actor/wifi"))
    (check
     (signals-p 'invalid-star-uri-error
                (lambda () (parse-star-uri value)))
     (format nil "invalid STAR URI is typed: ~S" value))))

(defun sample-remote-ref (&key
                            (resource-uri "star://node.example/actor/wifi/kismet")
                            (resource-kind "actor")
                            (generation 7))
  (make-remote-object-ref
   :protocol-version 1
   :resource-uri resource-uri
   :resource-kind resource-kind
   :interface-id "org.starintel.wifi.kismet"
   :interface-version "1.0.0"
   :interface-digest "sha256:fixture-interface"
   :object-id "sensor-1"
   :instance-generation generation
   :capability-set '("wifi.observe" "remote.fetch")))

(defun test-remote-object-ref-round-trip ()
  (let* ((reference (sample-remote-ref))
         (portable (remote-object-ref-portable-map reference))
         (decoded (parse-remote-object-ref portable)))
    (check (remote-object-ref-p reference) "constructor returns remote ref")
    (check (validate-remote-object-ref reference) "reference validates")
    (check-equal 1 (remote-object-ref-protocol-version reference)
                 "protocol version")
    (check-equal "star://node.example/actor/wifi/kismet"
                 (remote-object-ref-resource-uri reference)
                 "canonical resource URI")
    (check-equal "actor" (remote-object-ref-resource-kind reference)
                 "resource kind")
    (check-equal "node.example" (remote-object-ref-authority reference)
                 "derived authority")
    (check-equal '("remote.fetch" "wifi.observe")
                 (remote-object-ref-capability-set reference)
                 "capability set canonical ordering")
    (check-equal (remote-object-ref-portable-map reference)
                 (remote-object-ref-portable-map decoded)
                 "portable map round-trip is stable")))

(defun test-remote-object-ref-kind-must-match-uri ()
  (check
   (signals-p
    'invalid-remote-object-reference-error
    (lambda ()
      (sample-remote-ref :resource-kind "service")))
   "resource kind mismatch is rejected"))

(defun test-remote-object-ref-rejects-unknown-kind ()
  (check
   (signals-p
    'invalid-remote-object-reference-error
    (lambda ()
      (sample-remote-ref
       :resource-uri "star://node.example/widget/wifi/kismet"
       :resource-kind "widget")))
   "unknown remote object kind is rejected"))

(defun test-remote-object-ref-generation-is-fenced ()
  (let ((reference (sample-remote-ref :generation 7)))
    (check (not (remote-object-ref-stale-generation-p reference 7))
           "matching generation is current")
    (check (remote-object-ref-stale-generation-p reference 8)
           "newer generation makes old reference stale")
    (check
     (signals-p
      'invalid-remote-object-reference-error
      (lambda () (sample-remote-ref :generation -1)))
     "negative generation rejected")))

(defun test-remote-operation-vocabulary-is-closed ()
  (dolist (operation '("remote.resolve"
                       "remote.describe"
                       "remote.fetch"
                       "remote.invoke"
                       "remote.ask"
                       "remote.tell"
                       "remote.subscribe"
                       "remote.unsubscribe"
                       "remote.cancel"
                       "remote.release"))
    (check (remote-operation-id-p operation)
           (format nil "known remote operation accepted: ~A" operation)))
  (check (not (remote-operation-id-p "remote.eval"))
         "arbitrary remote operation rejected"))

(defun run-tests ()
  (test-canonical-star-uri-round-trip)
  (test-star-uri-normalizes-authority-and-percent-encoding)
  (test-star-uri-constructor)
  (test-malformed-star-uris-are-typed)
  (test-remote-object-ref-round-trip)
  (test-remote-object-ref-kind-must-match-uri)
  (test-remote-object-ref-rejects-unknown-kind)
  (test-remote-object-ref-generation-is-fenced)
  (test-remote-operation-vocabulary-is-closed)
  (format t "star-actor-protocol remote-object tests passed.~%")
  t)
