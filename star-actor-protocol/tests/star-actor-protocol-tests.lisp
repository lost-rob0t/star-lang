(defpackage :staractorprotocol-tests
  (:use :cl)
  (:import-from :staractorprotocol
                #:invalid-star-service-uri-error
                #:invalid-actor-reference-error
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
                #:star-actor-reference-same-logical-actor-p)
  (:export #:run-tests))

(in-package :staractorprotocol-tests)

(defun assert-test (condition label)
  (unless condition
    (error "star-actor-protocol test failed: ~A" label)))

(defun signals-condition-p (condition-type thunk)
  (handler-case
      (progn
        (funcall thunk)
        nil)
    (error (condition)
      (typep condition condition-type))))

(defun signals-invalid-service-uri-p (thunk)
  (signals-condition-p 'invalid-star-service-uri-error thunk))

(defun test-canonical-service-uri-round-trip ()
  (dolist (value '("star://quasar:localhost:user-hunt"
                   "star://bbp:localhost:nmap"))
    (let ((uri (parse-star-service-uri value)))
      (assert-test (star-service-uri-p uri)
                   "parse returns a service URI")
      (assert-test (string= value (star-service-uri-string uri))
                   "canonical URI round-trips"))))

(defun test-service-uri-components ()
  (let ((uri (parse-star-service-uri "star://quasar:localhost:user-hunt")))
    (assert-test (string= "quasar" (star-service-uri-domain uri))
                 "domain accessor")
    (assert-test (string= "localhost" (star-service-uri-address uri))
                 "address accessor")
    (assert-test (string= "user-hunt" (star-service-uri-actor-name uri))
                 "actor-name accessor")))

(defun test-service-uri-constructor ()
  (let ((uri (make-star-service-uri "bbp" "localhost" "nmap")))
    (assert-test (string= "star://bbp:localhost:nmap"
                          (star-service-uri-string uri))
                 "constructor canonical output")
    (assert-test (eq uri (ensure-star-service-uri uri))
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
      (make-star-service-uri "Quasar" "localhost" "user-hunt")))
   "uppercase constructor token rejected")
  (assert-test
   (signals-invalid-service-uri-p
    (lambda ()
      (make-star-service-uri "quasar" "local:host" "user-hunt")))
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
    (assert-test (star-actor-reference-p reference)
                 "actor reference constructor")
    (assert-test (string= "quasar" (star-actor-reference-domain-id reference))
                 "actor reference domain")
    (assert-test (string= "user-hunt"
                          (star-actor-reference-logical-path reference))
                 "actor reference logical path")
    (assert-test (string= "localhost" (star-actor-reference-node-id reference))
                 "actor reference node")
    (assert-test (= 7 (star-actor-reference-generation reference))
                 "actor reference generation")
    (assert-test (= 1 (star-actor-reference-protocol-revision reference))
                 "actor reference protocol revision")
    (assert-test
     (string= "star://quasar:localhost:user-hunt"
              (star-actor-reference-service-uri reference))
     "actor reference service URI")
    (assert-test
     (star-actor-reference-same-logical-actor-p reference same-logical)
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

(defun run-tests ()
  (test-canonical-service-uri-round-trip)
  (test-service-uri-components)
  (test-service-uri-constructor)
  (test-malformed-service-uris-are-typed)
  (test-invalid-constructor-tokens-are-typed)
  (test-actor-name-consistency)
  (test-actor-reference-round-trip)
  (test-invalid-actor-reference-is-typed)
  (format t "star-actor-protocol tests passed.~%")
  t)