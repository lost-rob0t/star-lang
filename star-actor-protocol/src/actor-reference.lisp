(in-package :staractorprotocol)

(define-condition invalid-actor-reference-error
    (star-actor-protocol-error)
  ())

(defun fail-invalid-actor-reference (control &rest arguments)
  (error 'invalid-actor-reference-error
         :message (apply #'format nil control arguments)))

(defstruct (star-actor-reference
            (:constructor %make-star-actor-reference
                (domain-id logical-path node-id generation
                 protocol-revision capability-set-hash)))
  (domain-id "" :type string)
  (logical-path "" :type string)
  (node-id "" :type string)
  (generation 0 :type (integer 0 *))
  (protocol-revision 1 :type (integer 1 *))
  capability-set-hash)

(defun make-star-actor-reference
    (&key domain-id logical-path node-id (generation 0)
          (protocol-revision 1) capability-set-hash)
  (handler-case
      (let ((uri (make-star-service-uri domain-id node-id logical-path)))
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
         (star-service-uri-domain uri)
         (star-service-uri-actor-name uri)
         (star-service-uri-address uri)
         generation
         protocol-revision
         capability-set-hash))
    (invalid-star-service-uri-error (condition)
      (fail-invalid-actor-reference "~A" condition))))

(defun make-star-resource-actor-reference
    (&key authority resource-path
          (generation 0) (protocol-revision 1) capability-set-hash)
  "Build an actor reference bound to a canonical hierarchical resource URI.
The legacy node-id stays empty so tuple serialization is never emitted for
canonical references (issue #72)."
  (unless (and (stringp authority) (plusp (length authority)))
    (fail-invalid-actor-reference
     "Canonical actor reference requires a non-empty authority."))
  (unless (and (stringp resource-path) (plusp (length resource-path)))
    (fail-invalid-actor-reference
     "Canonical actor reference requires a non-empty resource path."))
  (unless (and (integerp generation) (>= generation 0))
    (fail-invalid-actor-reference
     "Actor reference generation must be a non-negative integer, received ~S."
     generation))
  (unless (and (integerp protocol-revision) (> protocol-revision 0))
    (fail-invalid-actor-reference
     "Actor reference protocol revision must be a positive integer, received ~S."
     protocol-revision))
  (%make-star-actor-reference
   authority resource-path "" generation protocol-revision
   capability-set-hash))

(defun star-actor-reference-canonical-p (reference)
  "True when REFERENCE is bound to a canonical hierarchical resource URI
(empty legacy node-id)."
  (and (star-actor-reference-p reference)
       (zerop (length (star-actor-reference-node-id reference)))))

(defun star-actor-reference-service-uri (reference)
  (unless (star-actor-reference-p reference)
    (fail-invalid-actor-reference
     "Expected a STAR actor reference, received ~S."
     reference))
  (if (star-actor-reference-canonical-p reference)
      (format nil "star://~A/actor/~A"
              (star-actor-reference-domain-id reference)
              (star-actor-reference-logical-path reference))
      (star-service-uri-string
       (make-star-service-uri
        (star-actor-reference-domain-id reference)
        (star-actor-reference-node-id reference)
        (star-actor-reference-logical-path reference)))))

(defun star-actor-reference-same-logical-actor-p (left right)
  (and (star-actor-reference-p left)
       (star-actor-reference-p right)
       (string= (star-actor-reference-domain-id left)
                (star-actor-reference-domain-id right))
       (string= (star-actor-reference-node-id left)
                (star-actor-reference-node-id right))
       (string= (star-actor-reference-logical-path left)
                (star-actor-reference-logical-path right))))