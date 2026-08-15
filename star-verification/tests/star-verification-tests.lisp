(defpackage :starverification-tests
  (:use :cl)
  (:import-from :starverification
                #:invalid-verification-certificate-error
                #:+verification-certificate-schema+
                #:+verification-class-model-checked+
                #:+verification-result-valid+
                #:+claim-topology-protocol-deadlock-free+
                #:verification-certificate-classes
                #:verification-certificate-results
                #:verification-claims
                #:verification-class-p
                #:verification-result-p
                #:verification-claim-p
                #:sha256-digest-p
                #:make-verification-certificate
                #:verification-certificate-p
                #:verification-certificate-schema
                #:verification-certificate-certificate-id
                #:verification-certificate-class
                #:verification-certificate-claim
                #:verification-certificate-subject-type
                #:verification-certificate-subject-hash
                #:verification-certificate-specification-digest
                #:verification-certificate-plan-digest
                #:verification-certificate-verifier
                #:verification-certificate-verifier-version
                #:verification-certificate-assumptions
                #:verification-certificate-bounds
                #:verification-certificate-evidence
                #:verification-certificate-result
                #:verification-certificate-field-names
                #:verification-certificate-fields
                #:verification-certificate-semantic-identity)
  (:export #:run-tests))

(in-package :starverification-tests)

(defparameter +subject-hash+
  "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")
(defparameter +specification-digest+
  "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb")
(defparameter +plan-digest+
  "sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc")
(defparameter +evidence-hash+
  "sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd")

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

(defun field-value (name fields)
  (cdr (assoc name fields :test #'string=)))

(defun make-model-certificate (&key
                                 (certificate-id "verify_01")
                                 (subject-hash +subject-hash+)
                                 (bounds '(("retryLimit" . 2)
                                           ("actors" . 2))))
                                 (assumptions '("weak-fair-next")))
  (make-verification-certificate
   :certificate-id certificate-id
   :class +verification-class-model-checked+
   :claim +claim-topology-protocol-deadlock-free+
   :subject-type "star.actor-topology/1"
   :subject-hash subject-hash
   :specification-digest +specification-digest+
   :plan-digest +plan-digest+
   :verifier "star.verify.tlc/1"
   :verifier-version "TLC2-2.19"
   :assumptions assumptions
   :bounds bounds
   :evidence (list +evidence-hash+)
   :result +verification-result-valid+))

(defun test-frozen-vocabularies ()
  (check
   (equal '("evidence"
            "checked-conformance"
            "lifecycle-verified"
            "model-checked"
            "solver-certificate"
            "theorem-artifact")
          (verification-certificate-classes))
   "Verification classes changed unexpectedly.")
  (check
   (equal '("valid" "invalid" "inconclusive")
          (verification-certificate-results))
   "Verification results changed unexpectedly.")
  (dolist (claim '("star.subject.identity-bound"
                   "star.document.schema-conformant"
                   "star.document.valid-for-domain"
                   "star.document.domain-constraint-satisfied"
                   "star.actor.accepts-message"
                   "star.actor.emits-message"
                   "star.actor.protocol-conformant"
                   "star.lifecycle.transition-valid"
                   "star.poison.terminal-disposition"
                   "star.poison.active-path-nonreturn"
                   "star.topology.hard-wait-acyclic"
                   "star.topology.protocol-deadlock-free"
                   "star.topology.protocol-progress"))
    (check (verification-claim-p claim)
           "Verification claim ~A is missing from the vocabulary."
           claim))
  (check (not (verification-claim-p "verified"))
         "Generic verified claim was accepted.")
  (check (not (verification-class-p "proved"))
         "Generic proved class was accepted.")
  (check (not (verification-result-p "safe"))
         "Generic safe result was accepted."))

(defun test-digest-contract ()
  (check (sha256-digest-p +subject-hash+)
         "Valid lowercase SHA-256 digest was rejected.")
  (check
   (not
    (sha256-digest-p
     "sha256:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"))
   "Uppercase SHA-256 digest was accepted.")
  (check (not (sha256-digest-p "sha256:abc"))
         "Short SHA-256 digest was accepted.")
  (check (not (sha256-digest-p +evidence-hash+))
         "Digest fixture should not alias through mutable state."))

(defun test-certificate-shape-and-scope ()
  (let* ((certificate (make-model-certificate))
         (fields (verification-certificate-fields certificate)))
    (check (verification-certificate-p certificate)
           "Certificate constructor did not return a certificate.")
    (check (string= +verification-certificate-schema+
                    (verification-certificate-schema certificate))
           "Certificate schema changed unexpectedly.")
    (check (string= "verify_01"
                    (verification-certificate-certificate-id certificate))
           "Certificate id was not retained.")
    (check (string= "model-checked"
                    (verification-certificate-class certificate))
           "Certificate class was not retained.")
    (check (string= "star.topology.protocol-deadlock-free"
                    (verification-certificate-claim certificate))
           "Certificate claim was not retained.")
    (check (string= "star.actor-topology/1"
                    (verification-certificate-subject-type certificate))
           "Certificate subject type was not retained.")
    (check (string= +subject-hash+
                    (verification-certificate-subject-hash certificate))
           "Certificate subject hash was not retained.")
    (check (string= +specification-digest+
                    (verification-certificate-specification-digest certificate))
           "Certificate specification digest was not retained.")
    (check (string= +plan-digest+
                    (verification-certificate-plan-digest certificate))
           "Certificate plan digest was not retained.")
    (check (string= "star.verify.tlc/1"
                    (verification-certificate-verifier certificate))
           "Certificate verifier was not retained.")
    (check (string= "TLC2-2.19"
                    (verification-certificate-verifier-version certificate))
           "Certificate verifier version was not retained.")
    (check (equal '("weak-fair-next")
                  (verification-certificate-assumptions certificate))
           "Certificate assumptions were not retained.")
    (check (equal '(("actors" . 2) ("retryLimit" . 2))
                  (verification-certificate-bounds certificate))
           "Certificate bounds were not normalized by key.")
    (check (equal (list +evidence-hash+)
                  (verification-certificate-evidence certificate))
           "Certificate evidence was not retained.")
    (check (string= "valid" (verification-certificate-result certificate))
           "Certificate result was not retained.")
    (check
     (equal '("schema"
              "certificateId"
              "class"
              "claim"
              "subjectType"
              "subjectHash"
              "specificationDigest"
              "planDigest"
              "verifier"
              "verifierVersion"
              "assumptions"
              "bounds"
              "evidence"
              "result")
            (verification-certificate-field-names))
     "Portable certificate field vocabulary changed unexpectedly.")
    (check (equal (verification-certificate-field-names)
                  (mapcar #'car fields))
           "Portable certificate field projection does not match the frozen shape.")))

(defun test-semantic-identity-projection ()
  (let* ((first (make-model-certificate :certificate-id "verify_a"))
         (second (make-model-certificate :certificate-id "verify_b"))
         (identity-a (verification-certificate-semantic-identity first))
         (identity-b (verification-certificate-semantic-identity second)))
    (check (equal identity-a identity-b)
           "Certificate id incorrectly changed semantic identity.")
    (check
     (equal '("claim"
              "subjectHash"
              "specificationDigest"
              "planDigest"
              "verifier"
              "verifierVersion"
              "assumptions"
              "bounds"
              "evidence"
              "result")
            (mapcar #'car identity-a))
     "Semantic identity field set changed unexpectedly.")
    (check (null (assoc "certificateId" identity-a :test #'string=))
           "Certificate id leaked into semantic identity.")
    (check (null (assoc "schema" identity-a :test #'string=))
           "Schema marker leaked into semantic identity.")
    (check (string= +plan-digest+ (field-value "planDigest" identity-a))
           "Plan digest is missing from semantic identity.")))

(defun test-certificate-is-immutable-through-public-api ()
  (let* ((subject-hash (copy-seq +subject-hash+))
         (assumption (copy-seq "weak-fair-next"))
         (assumptions (list assumption))
         (bounds (list (cons (copy-seq "actors") 2)))
         (certificate
           (make-model-certificate
            :subject-hash subject-hash
            :assumptions assumptions
            :bounds bounds)))
    (setf (char subject-hash 7) #\f
          (char assumption 0) #\X
          (cdr (first bounds)) 99)
    (check (string= +subject-hash+
                    (verification-certificate-subject-hash certificate))
           "Mutating constructor input changed the certificate subject hash.")
    (check (equal '("weak-fair-next")
                  (verification-certificate-assumptions certificate))
           "Mutating constructor input changed certificate assumptions.")
    (check (equal '(("actors" . 2))
                  (verification-certificate-bounds certificate))
           "Mutating constructor input changed certificate bounds.")
    (let ((read-hash (verification-certificate-subject-hash certificate))
          (read-assumptions
            (verification-certificate-assumptions certificate))
          (read-bounds (verification-certificate-bounds certificate)))
      (setf (char read-hash 7) #\e
            (char (first read-assumptions) 0) #\Y
            (cdr (first read-bounds)) 100)
      (check (string= +subject-hash+
                      (verification-certificate-subject-hash certificate))
             "Mutating a public reader result changed certificate state.")
      (check (equal '("weak-fair-next")
                    (verification-certificate-assumptions certificate))
             "Mutating returned assumptions changed certificate state.")
      (check (equal '(("actors" . 2))
                    (verification-certificate-bounds certificate))
             "Mutating returned bounds changed certificate state."))))

(defun test-invalid-certificates-fail-closed ()
  (flet ((invalid-p (&rest arguments)
           (signals-p
            'invalid-verification-certificate-error
            (lambda ()
              (apply #'make-verification-certificate arguments)))))
    (let ((base
            (list :certificate-id "verify_bad"
                  :class "model-checked"
                  :claim "star.topology.protocol-deadlock-free"
                  :subject-type "star.actor-topology/1"
                  :subject-hash +subject-hash+
                  :plan-digest +plan-digest+
                  :verifier "star.verify.tlc/1"
                  :verifier-version "TLC2-2.19"
                  :result "valid")))
      (check (apply #'invalid-p
                    (append base (list :claim "verified")))
             "Unknown generic claim was accepted.")
      (check (apply #'invalid-p
                    (append base (list :class "proved")))
             "Unknown verification class was accepted.")
      (check (apply #'invalid-p
                    (append base (list :result "safe")))
             "Unknown verification result was accepted.")
      (check (apply #'invalid-p
                    (append base (list :subject-hash "sha256:abc")))
             "Malformed subject hash was accepted.")
      (check
       (apply #'invalid-p
              (append base
                      (list :bounds '(("actors" . 2)
                                      ("actors" . 3)))))
       "Duplicate bound keys were accepted."))))

(defun test-final-system-is-prototype-independent ()
  (check (null (find-package "STAR-LANG.PROTOTYPE"))
         "star-verification loaded the prototype package transitively.")
  (check (null (find-package "STAR-LANG.CORE-SURFACE.PROTOTYPE"))
         "star-verification loaded core prototype state transitively."))

(defun run-tests ()
  (test-frozen-vocabularies)
  (test-digest-contract)
  (test-certificate-shape-and-scope)
  (test-semantic-identity-projection)
  (test-certificate-is-immutable-through-public-api)
  (test-invalid-certificates-fail-closed)
  (test-final-system-is-prototype-independent)
  (format t "~&star-verification tests passed~%")
  t)
