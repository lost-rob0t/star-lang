(defpackage :staractorprotocol-tests
  (:use :cl :fiveam)
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
  (:export))

(in-package :staractorprotocol-tests)

(def-suite staractorprotocol-tests
  :description "Portable STAR actor protocol tests.")

(in-suite staractorprotocol-tests)

(test canonical-service-uri-round-trip
  (dolist (value '("star://quasar:localhost:user-hunt"
                   "star://bbp:localhost:nmap"))
    (let ((uri (parse-star-service-uri value)))
      (is (star-service-uri-p uri))
      (is (string= value (star-service-uri-string uri))))))

(test service-uri-components
  (let ((uri (parse-star-service-uri "star://quasar:localhost:user-hunt")))
    (is (string= "quasar" (star-service-uri-domain uri)))
    (is (string= "localhost" (star-service-uri-address uri)))
    (is (string= "user-hunt" (star-service-uri-actor-name uri)))))

(test service-uri-constructor
  (let ((uri (make-star-service-uri "bbp" "localhost" "nmap")))
    (is (string= "star://bbp:localhost:nmap"
                 (star-service-uri-string uri)))
    (is (eq uri (ensure-star-service-uri uri)))))

(test malformed-service-uris-are-typed
  (dolist (value '("http://quasar:localhost:user-hunt"
                   "star://quasar:user-hunt"
                   "star://quasar:localhost:user-hunt:extra"
                   "star://Quasar:localhost:user-hunt"
                   "star://quasar:local:host:user-hunt"
                   "star://:localhost:user-hunt"
                   "star://quasar::user-hunt"
                   "star://quasar:localhost:"))
    (signals invalid-star-service-uri-error
      (parse-star-service-uri value))))

(test invalid-constructor-tokens-are-typed
  (signals invalid-star-service-uri-error
    (make-star-service-uri "Quasar" "localhost" "user-hunt"))
  (signals invalid-star-service-uri-error
    (make-star-service-uri "quasar" "local:host" "user-hunt")))

(test actor-name-consistency
  (is (string= "star://quasar:localhost:user-hunt"
               (canonical-star-service-uri-for-actor
                "user-hunt"
                "star://quasar:localhost:user-hunt")))
  (signals invalid-star-service-uri-error
    (canonical-star-service-uri-for-actor
     "different-actor"
     "star://quasar:localhost:user-hunt")))
