(in-package :starverification)

(defconstant +verification-certificate-schema+ "star.verify.certificate/1")

(defconstant +verification-class-evidence+ "evidence")
(defconstant +verification-class-checked-conformance+ "checked-conformance")
(defconstant +verification-class-lifecycle-verified+ "lifecycle-verified")
(defconstant +verification-class-model-checked+ "model-checked")
(defconstant +verification-class-solver-certificate+ "solver-certificate")
(defconstant +verification-class-theorem-artifact+ "theorem-artifact")

(defconstant +verification-result-valid+ "valid")
(defconstant +verification-result-invalid+ "invalid")
(defconstant +verification-result-inconclusive+ "inconclusive")

(defconstant +claim-subject-identity-bound+ "star.subject.identity-bound")
(defconstant +claim-document-schema-conformant+
  "star.document.schema-conformant")
(defconstant +claim-document-valid-for-domain+
  "star.document.valid-for-domain")
(defconstant +claim-document-domain-constraint-satisfied+
  "star.document.domain-constraint-satisfied")
(defconstant +claim-actor-accepts-message+ "star.actor.accepts-message")
(defconstant +claim-actor-emits-message+ "star.actor.emits-message")
(defconstant +claim-actor-protocol-conformant+
  "star.actor.protocol-conformant")
(defconstant +claim-lifecycle-transition-valid+
  "star.lifecycle.transition-valid")
(defconstant +claim-poison-terminal-disposition+
  "star.poison.terminal-disposition")
(defconstant +claim-poison-active-path-nonreturn+
  "star.poison.active-path-nonreturn")
(defconstant +claim-topology-hard-wait-acyclic+
  "star.topology.hard-wait-acyclic")
(defconstant +claim-topology-protocol-deadlock-free+
  "star.topology.protocol-deadlock-free")
(defconstant +claim-topology-protocol-progress+
  "star.topology.protocol-progress")

(define-condition star-verification-error (error)
  ((message :initarg :message :reader star-verification-error-message))
  (:report
   (lambda (condition stream)
     (write-string (star-verification-error-message condition) stream))))

(define-condition invalid-verification-certificate-error
    (star-verification-error)
  ())

(defun fail-certificate (control &rest arguments)
  (error 'invalid-verification-certificate-error
         :message (apply #'format nil control arguments)))

(defun copy-verification-data (value)
  (typecase value
    (string (copy-seq value))
    (cons
     (cons (copy-verification-data (car value))
           (copy-verification-data (cdr value))))
    (t value)))

(defun proper-list-p (value)
  (loop with slow = value
        with fast = value
        do (cond
             ((null fast) (return t))
             ((atom fast) (return nil)))
           (setf fast (cdr fast))
           (cond
             ((null fast) (return t))
             ((atom fast) (return nil)))
           (setf fast (cdr fast)
                 slow (cdr slow))
           (when (eq slow fast)
             (return nil))))

(defun non-empty-string-p (value)
  (and (stringp value)
       (> (length value) 0)))

(defun verification-certificate-classes ()
  (mapcar #'copy-seq
          (list +verification-class-evidence+
                +verification-class-checked-conformance+
                +verification-class-lifecycle-verified+
                +verification-class-model-checked+
                +verification-class-solver-certificate+
                +verification-class-theorem-artifact+)))

(defun verification-certificate-results ()
  (mapcar #'copy-seq
          (list +verification-result-valid+
                +verification-result-invalid+
                +verification-result-inconclusive+)))

(defun verification-claims ()
  (mapcar #'copy-seq
          (list +claim-subject-identity-bound+
                +claim-document-schema-conformant+
                +claim-document-valid-for-domain+
                +claim-document-domain-constraint-satisfied+
                +claim-actor-accepts-message+
                +claim-actor-emits-message+
                +claim-actor-protocol-conformant+
                +claim-lifecycle-transition-valid+
                +claim-poison-terminal-disposition+
                +claim-poison-active-path-nonreturn+
                +claim-topology-hard-wait-acyclic+
                +claim-topology-protocol-deadlock-free+
                +claim-topology-protocol-progress+)))

(defun string-vocabulary-member-p (value vocabulary)
  (and (stringp value)
       (not (null (member value vocabulary :test #'string=)))))

(defun verification-class-p (value)
  (string-vocabulary-member-p value (verification-certificate-classes)))

(defun verification-result-p (value)
  (string-vocabulary-member-p value (verification-certificate-results)))

(defun verification-claim-p (value)
  (string-vocabulary-member-p value (verification-claims)))

(defun lowercase-hex-digit-p (character)
  (or (char<= #\0 character #\9)
      (char<= #\a character #\f)))

(defun sha256-digest-p (value)
  (and (stringp value)
       (= (length value) 71)
       (string= value "sha256:" :end1 7)
       (loop for index from 7 below 71
             always (lowercase-hex-digit-p (char value index)))))

(defun require-string (value context)
  (unless (non-empty-string-p value)
    (fail-certificate "~A must be a non-empty string." context))
  (copy-seq value))

(defun require-digest (value context &key optional)
  (when (and optional (null value))
    (return-from require-digest nil))
  (unless (sha256-digest-p value)
    (fail-certificate
     "~A must be a lowercase sha256: digest with 64 hexadecimal digits."
     context))
  (copy-seq value))

(defun normalize-string-list (value context)
  (unless (proper-list-p value)
    (fail-certificate "~A must be a proper list." context))
  (mapcar
   (lambda (entry)
     (require-string entry context))
   value))

(defun bound-scalar-p (value)
  (or (and (integerp value) (>= value 0))
      (non-empty-string-p value)))

(defun bound-value-p (value)
  (or (bound-scalar-p value)
      (and (proper-list-p value)
           (every #'bound-scalar-p value))))

(defun normalize-bounds (bounds)
  (unless (proper-list-p bounds)
    (fail-certificate "Certificate bounds must be a proper association list."))
  (let ((seen '())
        (normalized '()))
    (dolist (entry bounds)
      (unless (and (consp entry)
                   (non-empty-string-p (car entry))
                   (bound-value-p (cdr entry)))
        (fail-certificate
         "Each certificate bound must map a non-empty string to a nonnegative integer, non-empty string, or a list of those values."))
      (when (member (car entry) seen :test #'string=)
        (fail-certificate "Duplicate certificate bound ~S." (car entry)))
      (push (copy-seq (car entry)) seen)
      (push (cons (copy-seq (car entry))
                  (copy-verification-data (cdr entry)))
            normalized))
    (sort normalized #'string< :key #'car)))

(defun normalize-evidence (evidence)
  (unless (proper-list-p evidence)
    (fail-certificate "Certificate evidence must be a proper list."))
  (mapcar
   (lambda (digest)
     (require-digest digest "Certificate evidence hash"))
   evidence))

(defstruct (verification-certificate
            (:constructor %make-verification-certificate)
            (:copier nil)
            (:conc-name %verification-certificate-))
  (schema +verification-certificate-schema+ :read-only t)
  (certificate-id nil :read-only t)
  (class nil :read-only t)
  (claim nil :read-only t)
  (subject-type nil :read-only t)
  (subject-hash nil :read-only t)
  (specification-digest nil :read-only t)
  (plan-digest nil :read-only t)
  (verifier nil :read-only t)
  (verifier-version nil :read-only t)
  (assumptions '() :read-only t)
  (bounds '() :read-only t)
  (evidence '() :read-only t)
  (result nil :read-only t))

(defun make-verification-certificate
    (&key
       certificate-id
       class
       claim
       subject-type
       subject-hash
       specification-digest
       plan-digest
       verifier
       verifier-version
       (assumptions '())
       (bounds '())
       (evidence '())
       result)
  (unless (verification-class-p class)
    (fail-certificate "Unknown verification class ~S." class))
  (unless (verification-claim-p claim)
    (fail-certificate "Unknown verification claim ~S." claim))
  (unless (verification-result-p result)
    (fail-certificate "Unknown verification result ~S." result))
  (%make-verification-certificate
   :certificate-id (require-string certificate-id "Certificate id")
   :class (copy-seq class)
   :claim (copy-seq claim)
   :subject-type (require-string subject-type "Certificate subject type")
   :subject-hash (require-digest subject-hash "Certificate subject hash")
   :specification-digest
   (require-digest specification-digest
                   "Certificate specification digest"
                   :optional t)
   :plan-digest
   (require-digest plan-digest "Certificate plan digest" :optional t)
   :verifier (require-string verifier "Certificate verifier")
   :verifier-version
   (require-string verifier-version "Certificate verifier version")
   :assumptions (normalize-string-list assumptions "Certificate assumption")
   :bounds (normalize-bounds bounds)
   :evidence (normalize-evidence evidence)
   :result (copy-seq result)))

(defun ensure-verification-certificate (certificate)
  (unless (verification-certificate-p certificate)
    (fail-certificate "Expected a verification certificate, received ~S."
                      certificate))
  certificate)

(defun verification-certificate-schema (certificate)
  (ensure-verification-certificate certificate)
  (copy-seq (%verification-certificate-schema certificate)))

(defun verification-certificate-certificate-id (certificate)
  (ensure-verification-certificate certificate)
  (copy-seq (%verification-certificate-certificate-id certificate)))

(defun verification-certificate-class (certificate)
  (ensure-verification-certificate certificate)
  (copy-seq (%verification-certificate-class certificate)))

(defun verification-certificate-claim (certificate)
  (ensure-verification-certificate certificate)
  (copy-seq (%verification-certificate-claim certificate)))

(defun verification-certificate-subject-type (certificate)
  (ensure-verification-certificate certificate)
  (copy-seq (%verification-certificate-subject-type certificate)))

(defun verification-certificate-subject-hash (certificate)
  (ensure-verification-certificate certificate)
  (copy-seq (%verification-certificate-subject-hash certificate)))

(defun verification-certificate-specification-digest (certificate)
  (ensure-verification-certificate certificate)
  (let ((digest (%verification-certificate-specification-digest certificate)))
    (and digest (copy-seq digest))))

(defun verification-certificate-plan-digest (certificate)
  (ensure-verification-certificate certificate)
  (let ((digest (%verification-certificate-plan-digest certificate)))
    (and digest (copy-seq digest))))

(defun verification-certificate-verifier (certificate)
  (ensure-verification-certificate certificate)
  (copy-seq (%verification-certificate-verifier certificate)))

(defun verification-certificate-verifier-version (certificate)
  (ensure-verification-certificate certificate)
  (copy-seq (%verification-certificate-verifier-version certificate)))

(defun verification-certificate-assumptions (certificate)
  (ensure-verification-certificate certificate)
  (copy-verification-data (%verification-certificate-assumptions certificate)))

(defun verification-certificate-bounds (certificate)
  (ensure-verification-certificate certificate)
  (copy-verification-data (%verification-certificate-bounds certificate)))

(defun verification-certificate-evidence (certificate)
  (ensure-verification-certificate certificate)
  (copy-verification-data (%verification-certificate-evidence certificate)))

(defun verification-certificate-result (certificate)
  (ensure-verification-certificate certificate)
  (copy-seq (%verification-certificate-result certificate)))

(defun verification-certificate-field-names ()
  (mapcar #'copy-seq
          '("schema"
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
            "result")))

(defun verification-certificate-fields (certificate)
  "Return the frozen portable field projection without serializing it as JSON."
  (ensure-verification-certificate certificate)
  (list
   (cons "schema" (verification-certificate-schema certificate))
   (cons "certificateId"
         (verification-certificate-certificate-id certificate))
   (cons "class" (verification-certificate-class certificate))
   (cons "claim" (verification-certificate-claim certificate))
   (cons "subjectType" (verification-certificate-subject-type certificate))
   (cons "subjectHash" (verification-certificate-subject-hash certificate))
   (cons "specificationDigest"
         (verification-certificate-specification-digest certificate))
   (cons "planDigest" (verification-certificate-plan-digest certificate))
   (cons "verifier" (verification-certificate-verifier certificate))
   (cons "verifierVersion"
         (verification-certificate-verifier-version certificate))
   (cons "assumptions" (verification-certificate-assumptions certificate))
   (cons "bounds" (verification-certificate-bounds certificate))
   (cons "evidence" (verification-certificate-evidence certificate))
   (cons "result" (verification-certificate-result certificate))))

(defun verification-certificate-semantic-identity (certificate)
  "Return the fields that define semantic certificate identity.

This projection intentionally does not hash or serialize the certificate.
STAR-CANONICAL-JSON remains the sole canonical JSON authority."
  (ensure-verification-certificate certificate)
  (list
   (cons "claim" (verification-certificate-claim certificate))
   (cons "subjectHash" (verification-certificate-subject-hash certificate))
   (cons "specificationDigest"
         (verification-certificate-specification-digest certificate))
   (cons "planDigest" (verification-certificate-plan-digest certificate))
   (cons "verifier" (verification-certificate-verifier certificate))
   (cons "verifierVersion"
         (verification-certificate-verifier-version certificate))
   (cons "assumptions" (verification-certificate-assumptions certificate))
   (cons "bounds" (verification-certificate-bounds certificate))
   (cons "evidence" (verification-certificate-evidence certificate))
   (cons "result" (verification-certificate-result certificate))))
