;;;; Final actor lowering: compile an `actor` declaration (closed syntax
;;;; object or trusted host form) into runtime-neutral actor IR.
;;;; Moved from prototype/actor-wire-prototype.lisp; that file now forwards
;;;; here. The lowering accepts .star syntax objects in addition to trusted
;;;; raw forms, adds the optional :metadata contract, and canonicalizes
;;;; service URIs through the final star-actor-protocol authority.

(in-package #:star-lang.compiler.core)

(define-condition invalid-star-service-uri-error (star-lang-core-error) ())

(defparameter +actor-common-option-keys+
  '(:runtime :service-uri :accepts :produces :restart :mailbox
    :capabilities :metadata))

(defparameter +actor-all-option-keys+
  (append +actor-common-option-keys+ '(:handler :protocol :endpoint)))

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

(defun signal-actor-option-error (key code message &key first-key details)
  "Signal an actor-option error anchored to KEY.

When FIRST-KEY is source syntax, retain its span as related evidence so a
duplicate diagnostic identifies both occurrences without changing the public
compiler condition hierarchy."
  (let* ((syntax (and (star-syntax-p key) key))
         (first-syntax (and (star-syntax-p first-key) first-key))
         (first-span (and first-syntax (star-syntax-span first-syntax))))
    (error 'invalid-actor-error
           :message message
           :code code
           :span (and syntax (star-syntax-span syntax))
           :origin (and syntax (star-syntax-origin syntax))
           :syntax-kind (and syntax (star-syntax-kind syntax))
           :related-spans (if first-span (list first-span) '())
           :phase :lower
           :details details)))

(defun actor-option-key (key)
  "Return a validated actor option keyword without coercing other syntax."
  (cond
    ((star-syntax-p key)
     (unless (eq (star-syntax-kind key) :keyword)
       (signal-actor-option-error
        key :invalid-actor-option-key
        "Actor option keys must be Star-Lang keyword occurrences."))
     (syntax-atom key))
    ((keywordp key) key)
    (t
     (signal-actor-option-error
      key :invalid-actor-option-key
      "Trusted actor option keys must be Common Lisp keywords."))))

(defun validate-actor-option-keys (options allowed-keys)
  "Require unique actor option keys drawn from ALLOWED-KEYS.

Validation happens before option values are consumed. The first occurrence is
retained so duplicate source diagnostics can point at the second occurrence and
relate the first."
  (let ((seen '()))
    (loop for tail on (plist-elements options) by #'cddr
          for key = (first tail)
          for normalized-key = (actor-option-key key)
          do (unless (member normalized-key allowed-keys :test #'eq)
               (signal-actor-option-error
                key :unsupported-actor-option
                (format nil "Actor option ~S is not valid in this actor contract."
                        normalized-key)
                :details (list :option normalized-key)))
             (let ((first (assoc normalized-key seen :test #'eq)))
               (when first
                 (signal-actor-option-error
                  key :duplicate-actor-option
                  (format nil "Actor option ~S must not be repeated."
                          normalized-key)
                  :first-key (cdr first)
                  :details (list :option normalized-key)))
               (push (cons normalized-key key) seen))))
  options)

(defun actor-runtime-option-keys (runtime)
  (ecase runtime
    (:native (append +actor-common-option-keys+ '(:handler)))
    (:external (append +actor-common-option-keys+ '(:protocol :endpoint)))))

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

(defun actor-capability-identifier (value)
  "Lower one validated source or trusted-host capability identifier."
  (with-star-source-position (value)
    (cond
      ((star-syntax-p value)
       (unless (eq (star-syntax-kind value) :identifier)
         (fail 'invalid-actor-error
               "Actor capabilities must contain identifiers."))
       (identifier-string value))
      ((stringp value) value)
      ((and (symbolp value)
            value
            (not (eq value t))
            (not (keywordp value)))
       (identifier-string value))
      (t
       (fail 'invalid-actor-error
             "Actor capabilities must contain identifiers.")))))

(defun normalize-actor-capabilities (value)
  "Validate and lower an explicitly present actor capability list."
  (let ((*star-current-phase* :lower))
    (with-star-source-position (value)
      (unless (or (syntax-list-p value)
                  (and (listp value) (not (star-syntax-p value))))
        (fail 'invalid-actor-error
              "Actor capabilities must be a list of identifiers."))
      (mapcar #'actor-capability-identifier (plist-elements value)))))

(defun compile-actor (form &optional library)
  (let* ((elements (actor-declaration-elements form))
         (operator (first elements))
         (name (second elements))
         (options (third elements)))
    (declare (ignore operator))
    (let ((*star-current-syntax*
            (or (and (star-syntax-p form) form) *star-current-syntax*))
          (*star-current-phase* :lower))
      (ensure-plist options "actor" 'invalid-actor-error)
      (validate-actor-option-keys options +actor-all-option-keys+)
      (let* ((runtime (normalize-runtime
                       (required-option options :runtime "actor"
                                        'invalid-actor-error)))
             (actor-name (identifier-string name)))
        (validate-actor-option-keys options (actor-runtime-option-keys runtime))
        (let* ((service-uri-value (optional-option options :service-uri))
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
                        (if (plist-has-key-p options :capabilities)
                            (normalize-actor-capabilities
                             (required-option options :capabilities "actor"
                                              'invalid-actor-error))
                            '()))))
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
            actor))))))
