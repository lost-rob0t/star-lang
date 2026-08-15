(in-package :starverification-tests)

(defun make-scope-certificate
    (&key
       (class "checked-conformance")
       (claim "star.lifecycle.transition-valid")
       specification-digest
       plan-digest
       (bounds '())
       (evidence '()))
  (starverification:make-verification-certificate
   :certificate-id "verify_scope"
   :class class
   :claim claim
   :subject-type "star.verification-scope-test/1"
   :subject-hash +subject-hash+
   :specification-digest specification-digest
   :plan-digest plan-digest
   :verifier "star.verify.scope-test/1"
   :verifier-version "1.0.0"
   :assumptions '()
   :bounds bounds
   :evidence evidence
   :result "valid"))

(defun scope-error-p (thunk)
  (signals-p 'starverification:invalid-verification-certificate-error thunk))

(defun test-claim-scope-requirements ()
  (check
   (scope-error-p
    (lambda ()
      (make-scope-certificate
       :claim "star.document.schema-conformant")))
   "Document schema claim accepted without specificationDigest.")
  (check
   (scope-error-p
    (lambda ()
      (make-scope-certificate
       :claim "star.document.valid-for-domain"
       :specification-digest +specification-digest+)))
   "Domain-valid claim accepted without planDigest.")
  (check
   (scope-error-p
    (lambda ()
      (make-scope-certificate
       :claim "star.topology.hard-wait-acyclic")))
   "Topology claim accepted without planDigest."))

(defun test-assurance-scope-requirements ()
  (check
   (scope-error-p
    (lambda ()
      (make-scope-certificate
       :class "model-checked"
       :claim "star.lifecycle.transition-valid"
       :bounds '(("states" . 4))
       :evidence (list +evidence-hash+))))
   "model-checked accepted without planDigest.")
  (check
   (scope-error-p
    (lambda ()
      (make-scope-certificate
       :class "model-checked"
       :claim "star.lifecycle.transition-valid"
       :plan-digest +plan-digest+
       :evidence (list +evidence-hash+))))
   "model-checked accepted without explicit bounds.")
  (check
   (scope-error-p
    (lambda ()
      (make-scope-certificate
       :class "model-checked"
       :claim "star.lifecycle.transition-valid"
       :plan-digest +plan-digest+
       :bounds '(("states" . 4)))))
   "model-checked accepted without evidence.")
  (check
   (scope-error-p
    (lambda ()
      (make-scope-certificate
       :class "solver-certificate"
       :claim "star.lifecycle.transition-valid"
       :evidence (list +evidence-hash+))))
   "solver-certificate accepted without planDigest.")
  (check
   (scope-error-p
    (lambda ()
      (make-scope-certificate
       :class "evidence"
       :claim "star.subject.identity-bound")))
   "evidence certificate accepted without evidence hash."))

(defun test-lifecycle-certificate-is-not-overconstrained ()
  (let ((certificate
          (make-scope-certificate
           :class "lifecycle-verified"
           :claim "star.lifecycle.transition-valid")))
    (check (starverification:verification-certificate-p certificate)
           "Lifecycle certificate unexpectedly required unrelated scope.")))

(defun run-scope-tests ()
  (test-claim-scope-requirements)
  (test-assurance-scope-requirements)
  (test-lifecycle-certificate-is-not-overconstrained)
  (format t "~&star-verification scope tests passed~%")
  t)

(export 'run-scope-tests)
