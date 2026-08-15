(defpackage :staractorprotocol-wire-tests
  (:use :cl)
  (:import-from :staractorprotocol
                #:invalid-star-service-uri-error
                #:invalid-wire-envelope-error
                #:make-wire-envelope
                #:validate-wire-envelope
                #:portable-manifest-message-contract
                #:portable-manifest-actor-contract
                #:portable-actor-accepts-message-p)
  (:export #:run-tests))

(in-package :staractorprotocol-wire-tests)

(defun check (truth control &rest arguments)
  (unless truth
    (error (apply #'format nil control arguments))))

(defun signals-p (condition-type thunk)
  (handler-case
      (progn
        (funcall thunk)
        nil)
    (error (condition)
      (typep condition condition-type))))

(defun portable-manifest-fixture ()
  (list
   :wire-version 1
   :messages
   (list
    (list :kind :message
          :name "org.starintel/test@1/run"
          :fields
          (list (list :name "target" :type "string" :required t)
                (list :name "limit" :type "integer" :required nil))))
   :actors
   (list
    (list :name "worker"
          :service-uri "star://test:localhost:worker"
          :runtime :external
          :accepts '("org.starintel/test@1/run")
          :produces '()))))

(defun test-wire-envelope-construction-and-required-fields ()
  (let* ((manifest (portable-manifest-fixture))
         (envelope
           (make-wire-envelope
            :message-type "org.starintel/test@1/run"
            :message-id "wire-1"
            :actor "worker"
            :dataset "fixture"
            :payload '(("target" . "example.org")))))
    (check (= 1 (getf envelope :star-version))
           "Legacy wire envelope did not retain version one.")
    (check (validate-wire-envelope manifest envelope)
           "Valid legacy wire envelope was rejected.")
    (let ((keyword-payload (copy-tree envelope)))
      (setf (getf keyword-payload :payload)
            '(:target "example.org"))
      (check (validate-wire-envelope manifest keyword-payload)
             "Keyword plist payload compatibility changed."))
    (let ((missing (copy-tree envelope)))
      (setf (getf missing :payload) '())
      (check
       (signals-p 'invalid-wire-envelope-error
                  (lambda ()
                    (validate-wire-envelope manifest missing)))
       "Missing required wire field was accepted."))))

(defun test-message-contract-lookup ()
  (let* ((manifest (portable-manifest-fixture))
         (contract
           (portable-manifest-message-contract
            manifest "org.starintel/test@1/run")))
    (check (string= "org.starintel/test@1/run"
                    (getf contract :name))
           "Portable message lookup returned the wrong contract.")
    (check
     (null
      (portable-manifest-message-contract
       manifest "org.starintel/test@1/missing"))
     "Portable message lookup invented a missing contract.")))

(defun test-actor-contract-lookup-and-accepts ()
  (let* ((manifest (portable-manifest-fixture))
         (by-name (portable-manifest-actor-contract manifest "worker"))
         (by-uri
           (portable-manifest-actor-contract
            manifest "star://test:localhost:worker")))
    (check (equal by-name by-uri)
           "Actor name and exact STAR URI did not resolve the same contract.")
    (check
     (portable-actor-accepts-message-p
      by-uri "org.starintel/test@1/run")
     "Actor accepts contract rejected a declared message.")
    (check
     (not
      (portable-actor-accepts-message-p
       by-uri "org.starintel/test@1/other"))
     "Actor accepts contract allowed an undeclared message.")
    (check
     (null
      (portable-manifest-actor-contract
       manifest "star://test:localhost:other"))
     "Exact STAR URI lookup matched a different actor.")
    (check
     (signals-p
      'invalid-star-service-uri-error
      (lambda ()
        (portable-manifest-actor-contract manifest "star://bad")))
     "Malformed STAR actor target was not typed by the protocol boundary.")))

(defun test-wire-validation-failures-are-typed ()
  (let* ((manifest (portable-manifest-fixture))
         (unknown
           (make-wire-envelope
            :message-type "org.starintel/test@1/missing"
            :message-id "wire-missing"
            :actor "worker"
            :payload nil)))
    (check
     (signals-p 'invalid-wire-envelope-error
                (lambda ()
                  (validate-wire-envelope manifest unknown)))
     "Unknown wire message type was not rejected.")
    (check
     (signals-p
      'invalid-wire-envelope-error
      (lambda ()
        (make-wire-envelope
         :message-type :not-a-string
         :message-id "wire-bad"
         :actor "worker"
         :payload nil)))
     "Legacy wire constructor accepted a non-string message type.")))

(defun test-final-wire-contract-is-prototype-independent ()
  (check
   (null (find-package "STAR-LANG.CORE-SURFACE.PROTOTYPE"))
   "Portable wire contract loaded the prototype package transitively."))

(defun run-tests ()
  (test-wire-envelope-construction-and-required-fields)
  (test-message-contract-lookup)
  (test-actor-contract-lookup-and-accepts)
  (test-wire-validation-failures-are-typed)
  (test-final-wire-contract-is-prototype-independent)
  (format t "~&star-actor-protocol portable wire tests passed~%")
  t)
