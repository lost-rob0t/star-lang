;;;; Final actor lowering: compile an `actor` declaration (closed syntax
;;;; object or trusted host form) into runtime-neutral actor IR.
;;;; Moved from prototype/actor-wire-prototype.lisp; that file now forwards
;;;; here. The lowering accepts .star syntax objects in addition to trusted
;;;; raw forms, adds the optional :metadata contract, and canonicalizes
;;;; service URIs through the final star-actor-protocol authority.

(in-package #:star-lang.compiler.core)

(define-condition invalid-star-service-uri-error (star-lang-core-error) ())

(defun canonical-service-uri-for-actor (actor-name value)
  "Canonicalize a STAR service URI through the final protocol authority,
translating protocol failures into source-aware compiler conditions."
  (let ((datum (if (star-syntax-p value) (syntax-atom value) value)))
    (unless (stringp datum)
      (fail 'invalid-star-service-uri-error
            "Actor service URI must be a string, received ~S." datum))
    (handler-case
        (staractorprotocol:canonical-star-service-uri-for-actor actor-name datum)
      (staractorprotocol:invalid-star-service-uri-error (condition)
        (fail 'invalid-star-service-uri-error "~A" condition)))))

(defun actor-option-elements (value)
  "Return the element list of an actor options occurrence (syntax or raw)."
  (cond
    ((syntax-list-p value) (star-syntax-children value))
    ((and (listp value) (not (star-syntax-p value))) value)
    (t
     (fail 'invalid-actor-error "Actor options must be a property list."))))

(defun actor-declaration-elements (form)
  (let ((elements
          (cond
            ((and (star-syntax-p form) (syntax-list-p form))
             (star-syntax-children form))
            ((and (listp form) (not (star-syntax-p form))) form)
            (t
             (fail 'invalid-actor-error "Expected (actor name (...options...)).")))))
    (unless (and (= (length elements) 3)
                 (string= (declaration-kind form) "actor"))
      (fail 'invalid-actor-error "Expected (actor name (...options...))."))
    elements))

(defun metadata-scalar-value (value)
  "Metadata values are deterministic scalars: strings or integers."
  (let ((datum (if (star-syntax-p value) (syntax-atom value) value)))
    (cond
      ((stringp datum) datum)
      ((integerp datum) datum)
      (t
       (fail 'invalid-actor-error
             "Actor metadata values must be strings or integers, received ~S."
             datum)))))

(defun normalize-actor-metadata (value)
  "Metadata is a list of (lowerCamelCaseIdentifier scalar) pairs lowered to a
deterministic string alist."
  (let ((entries (actor-option-elements value)))
    (mapcar
     (lambda (entry)
       (let ((pair (actor-option-elements entry)))
         (unless (= (length pair) 2)
           (fail 'invalid-actor-error
                 "Actor metadata entries must be (key value) pairs."))
         (let ((key (identifier-string (first pair))))
           (unless (lower-camel-field-name-p key)
             (fail 'invalid-actor-error
                   "Actor metadata key ~S must use ASCII lower camelCase."
                   key))
           (cons key (metadata-scalar-value (second pair))))))
     entries)))

(defun compile-actor (form &optional library)
  (let* ((elements (actor-declaration-elements form))
         (operator (first elements))
         (name (second elements))
         (options (third elements)))
    (declare (ignore operator))
    (let ((*star-current-syntax*
            (or (and (star-syntax-p form) form) *star-current-syntax*)))
      (ensure-plist options "actor" 'invalid-actor-error)
      (let* ((runtime (normalize-runtime
                       (required-option options :runtime "actor"
                                        'invalid-actor-error)))
             (actor-name (identifier-string name))
             (service-uri-value (optional-option options :service-uri))
             (service-uri
               (and service-uri-value
                    (canonical-service-uri-for-actor
                     actor-name service-uri-value)))
             (library-name (and library (getf library :name)))
             (local-types
               (and library
                    (loop for item in (getf library :declarations)
                          when (member (getf item :kind)
                                       '(:scalar :enum :document :message))
                            collect (getf item :name))))
             (normalize-contract
               (lambda (types)
                 (unless (or (syntax-list-p types)
                             (and (listp types)
                                  (not (star-syntax-p types))))
                   (fail 'invalid-actor-error
                         "Actor accepts/produces must be lists."))
                 (mapcar (lambda (type)
                           (if library-name
                               (normalize-type-expression
                                type library-name local-types)
                               (identifier-string type)))
                         (plist-elements types)))))
        (let ((actor
                (list :kind :actor
                      :name actor-name
                      :runtime runtime
                      :service-uri service-uri
                      :accepts (funcall normalize-contract
                                        (required-option options :accepts "actor" 'invalid-actor-error))
                      :produces (funcall normalize-contract
                                         (required-option options :produces "actor" 'invalid-actor-error))
                      :restart (normalize-restart
                                (required-option options :restart "actor" 'invalid-actor-error))
                      :mailbox (normalize-mailbox
                                (required-option options :mailbox "actor" 'invalid-actor-error))
                      :capabilities
                      (mapcar #'identifier-string
                              (or (and (plist-has-key-p options :capabilities)
                                       (plist-elements
                                        (required-option options :capabilities "actor")))
                                  '())))))
          (ecase runtime
            (:native
             (let ((handler (required-option options :handler "native actor"
                                             'invalid-actor-error)))
               (setf actor (append actor (list :handler (identifier-string handler))))))
            (:external
             (let ((protocol (required-option options :protocol "external actor"
                                               'invalid-actor-error))
                   (endpoint (required-option options :endpoint "external actor"
                                               'invalid-actor-error)))
               (unless (stringp (if (star-syntax-p endpoint)
                                    (syntax-atom endpoint)
                                    endpoint))
                 (fail 'invalid-actor-error
                       "External actor endpoint must be a string."))
               (setf actor
                     (append actor
                             (list :protocol (identifier-string protocol)
                                   :endpoint (if (star-syntax-p endpoint)
                                                 (syntax-atom endpoint)
                                                 endpoint)))))))
          (when (plist-has-key-p options :metadata)
            (setf actor
                  (append actor
                          (list :metadata
                                (normalize-actor-metadata
                                 (required-option options :metadata "actor"))))))
          actor)))))
