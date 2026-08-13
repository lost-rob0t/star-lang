(defpackage :staractorprotocol-tests
  (:use :cl)
  (:import-from :staractorprotocol
                #:invalid-star-service-uri-error
                #:star-service-uri-p
                #:star-service-uri-domain
                #:star-service-uri-address
                #:star-service-uri-actor-name
                #:make-star-service-uri
                #:parse-star-service-uri
                #:star-service-uri-string
                #:ensure-star-service-uri
                #:canonical-star-service-uri-for-actor)
  (:export #:run-tests))

(in-package :staractorprotocol-tests)

(defun assert-test (condition label)
  (unless condition
    (error "star-actor-protocol test failed: ~A" label)))

(defun signals-invalid-service-uri-p (thunk)
  (handler-case
      (progn
        (funcall thunk)
        nil)
    (invalid-star-service-uri-error () t)))

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

(defun run-tests ()
  (test-canonical-service-uri-round-trip)
  (test-service-uri-components)
  (test-service-uri-constructor)
  (test-malformed-service-uris-are-typed)
  (test-invalid-constructor-tokens-are-typed)
  (test-actor-name-consistency)
  (format t "star-actor-protocol service URI tests passed.~%")
  t)
