(in-package :staractorprotocol)

;;;; Generation-bearing portable actor references on the canonical
;;;; STAR-SERVER-041 value model: a reference carries the canonical
;;;; authority plus the actor resource path.  There are deliberately no
;;;; domain/address/actor-name slots.

(define-condition invalid-actor-reference-error
    (star-actor-protocol-error)
  ())

(defun fail-invalid-actor-reference (control &rest arguments)
  (error 'invalid-actor-reference-error
         :message (apply #'format nil control arguments)))

(defstruct (star-actor-reference
            (:constructor %make-star-actor-reference
                (authority resource-path generation
                 protocol-revision capability-set-hash)))
  (authority "" :type string)
  (resource-path '() :type list)
  (generation 0 :type (integer 0 *))
  (protocol-revision 1 :type (integer 1 *))
  capability-set-hash)

(defun make-star-actor-reference
    (&key authority resource-path (generation 0)
          (protocol-revision 1) capability-set-hash)
  (handler-case
      (let* ((segments
               (if (and (listp resource-path) resource-path)
                   (mapcar (lambda (segment)
                             (unless (stringp segment)
                               (fail-invalid-actor-reference
                                "Actor reference resource-path segments must be strings, received ~S."
                                segment))
                             segment)
                           resource-path)
                   (fail-invalid-actor-reference
                    "Actor reference requires a non-empty actor resource path.")))
             (candidate
               (format nil "star://~A/actor/~{~A~^/~}"
                       (if (stringp authority) authority "")
                       segments))
             (uri
               (progn
                 (unless (canonical-star-uri-p candidate)
                   (fail-invalid-actor-reference
                    "Actor reference identity ~S must already be a canonical STAR actor URI."
                    candidate))
                 (parse-star-uri candidate)))
             (canonical-authority (star-uri-authority uri))
             (canonical-path (star-uri-resource-path uri)))
        (unless (and (integerp generation) (>= generation 0))
          (fail-invalid-actor-reference
           "Actor reference generation must be a non-negative integer, received ~S."
           generation))
        (unless (and (integerp protocol-revision) (> protocol-revision 0))
          (fail-invalid-actor-reference
           "Actor reference protocol revision must be a positive integer, received ~S."
           protocol-revision))
        (unless (or (null capability-set-hash)
                    (and (stringp capability-set-hash)
                         (plusp (length capability-set-hash))))
          (fail-invalid-actor-reference
           "Actor reference capability-set hash must be NIL or a non-empty string, received ~S."
           capability-set-hash))
        (%make-star-actor-reference
         canonical-authority
         canonical-path
         generation
         protocol-revision
         capability-set-hash))
    (invalid-star-uri (condition)
      (fail-invalid-actor-reference "~A" condition))))

(defun star-actor-reference-service-uri (reference)
  "Serialize the canonical actor identity addressed by REFERENCE."
  (unless (star-actor-reference-p reference)
    (fail-invalid-actor-reference
     "Expected a STAR actor reference, received ~S."
     reference))
  (serialize-star-uri
   (parse-star-uri
    (format nil "star://~A/actor/~{~A~^/~}"
            (star-actor-reference-authority reference)
            (star-actor-reference-resource-path reference)))))

(defun star-actor-reference-same-logical-actor-p (left right)
  (and (star-actor-reference-p left)
       (star-actor-reference-p right)
       (string= (star-actor-reference-authority left)
                (star-actor-reference-authority right))
       (equal (star-actor-reference-resource-path left)
              (star-actor-reference-resource-path right))))