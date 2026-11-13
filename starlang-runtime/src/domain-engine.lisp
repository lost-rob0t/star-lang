;;;; Keyed domain-server engine (issue #69/#72 "domain service" stage).
;;;;
;;;; Migrated from prototype/domain-server-core-prototype.lisp; the prototype
;;;; file is now a forwarding shell. Domain servers keep keyed-aggregate
;;;; semantics: every command names a stable typed key, per-key state owns
;;;; that key's data, and every accepted message type resolves to exactly
;;;; one handler. Handlers are either native StarLang body IR (definition
;;;; :handlers) or trusted host functions (:handlers keyword argument as
;;;; (message-type . function) pairs).

(in-package :starlangruntime)

(define-condition domain-server-core-error (actor-runtime-error) ())
(define-condition domain-tool-error (domain-server-core-error) ())

(defstruct (tool-runner-port (:constructor %make-tool-runner-port))
  run-fn)

(defun make-tool-runner-port (&key run)
  (unless (functionp run)
    (fail-actor 'domain-tool-error
                "Tool runner operation must be a function."))
  (%make-tool-runner-port :run-fn run))

(defun required-nonempty-string (value label)
  (unless (and (stringp value) (plusp (length value)))
    (fail-actor 'domain-server-core-error
                "~A requires a non-empty string."
                label))
  value)

(defun domain-request-key-string (key)
  "Normalize a host-language keyword to a camelCase field key
(kebab-case and snake_case both collapse; strings pass through)."
  (if (stringp key)
      key
      (let ((name (string-downcase (substitute #\- #\_ (symbol-name key)))))
        (with-output-to-string (stream)
          (loop with uppercase-next = nil
                for character across name
                do (cond
                     ((char= character #\-)
                      (setf uppercase-next t))
                     (uppercase-next
                      (write-char (char-upcase character) stream)
                      (setf uppercase-next nil))
                     (t (write-char character stream))))))))

(defun request-option (request key)
  (cond
    ((and (listp request) (every #'consp request))
     (cdr (assoc (domain-request-key-string key) request :test #'string=)))
    ((listp request)
     (getf request key))
    (t nil)))

(defun required-request-option (request key context)
  (or (request-option request key)
      (fail-actor 'domain-tool-error
                  "~A requires request value ~A."
                  context key)))

(defun tool-command-argv (tool request)
  (let ((values
          (list (cons :target
                      (required-request-option request :target "Tool command"))
                (cons :program-id
                      (required-request-option request :program-id "Tool command"))
                (cons :run-id
                      (required-request-option request :run-id "Tool command")))))
    (cons
     (getf tool :executable)
     (mapcar
      (lambda (item)
        (if (keywordp item)
            (let ((entry (assoc item values :test #'eq)))
              (unless entry
                (fail-actor 'domain-tool-error
                            "Tool ~A has unresolved argv placeholder ~S."
                            (getf tool :name) item))
              (let ((value (cdr entry)))
                (unless (stringp value)
                  (fail-actor 'domain-tool-error
                              "Tool ~A placeholder ~S requires a string value."
                              (getf tool :name) item))
                value))
            item))
      (getf tool :argv-template)))))

(defun validate-tool-run-result (tool result)
  (unless (and (listp result) (evenp (length result)))
    (fail-actor 'domain-tool-error
                "Tool ~A result must be a property list."
                (getf tool :name)))
  (unless (integerp (getf result :exit-code))
    (fail-actor 'domain-tool-error
                "Tool ~A result requires integer exit-code."
                (getf tool :name)))
  (dolist (key '(:stdout :stderr))
    (unless (stringp (getf result key))
      (fail-actor 'domain-tool-error
                  "Tool ~A result requires string ~A."
                  (getf tool :name) key)))
  result)

(defun run-domain-tool (runner tool request)
  (unless (tool-runner-port-p runner)
    (fail-actor 'domain-tool-error
                "Domain tool execution requires a tool runner port."))
  (let ((argv (tool-command-argv tool request)))
    (let ((result (funcall (tool-runner-port-run-fn runner)
                           tool argv request)))
      (append (validate-tool-run-result tool result)
              (list :argv argv)))))

(defstruct (domain-server-instance
            (:constructor make-domain-server-instance (&key key state)))
  key
  state)

(defstruct (domain-server-engine
            (:constructor %make-domain-server-engine))
  definition
  (tools (make-hash-table :test #'equal))
  tool-runner
  (handlers (make-hash-table :test #'equal))
  initializer
  (instances (make-hash-table :test #'equal)))

(defun make-domain-handler-table (handlers)
  (let ((table (make-hash-table :test #'equal)))
    (dolist (entry handlers)
      (unless (and (consp entry)
                   (stringp (car entry))
                   (functionp (cdr entry)))
        (fail-actor 'domain-server-core-error
                    "Domain handlers must be (qualified-message . function) pairs."))
      (when (gethash (car entry) table)
        (fail-actor 'domain-server-core-error
                    "Duplicate domain handler for ~A."
                    (car entry)))
      (setf (gethash (car entry) table) (cdr entry)))
    table))

(defun make-domain-tool-table (tools)
  (let ((table (make-hash-table :test #'equal)))
    (dolist (tool tools)
      (let ((name (getf tool :name)))
        (when (gethash name table)
          (fail-actor 'domain-tool-error "Duplicate tool ~A." name))
        (setf (gethash name table) tool)))
    table))

(defun make-domain-server-engine
    (&key definition tools tool-runner handlers initializer)
  (unless (and (listp definition)
               (eq (getf definition :kind) :domain-server))
    (fail-actor 'domain-server-core-error
                "Domain engine requires compiled domain-server IR."))
  (unless (functionp initializer)
    (fail-actor 'domain-server-core-error
                "Domain engine initializer must be a function."))
  (let ((handler-table
          (if handlers
              (make-domain-handler-table handlers)
              (make-domain-body-handler-table definition))))
    (dolist (message-type (getf definition :accepts))
      (unless (gethash message-type handler-table)
        (fail-actor 'domain-server-core-error
                    "Domain server ~A has no handler for ~A."
                    (getf definition :name) message-type)))
    (%make-domain-server-engine
     :definition definition
     :tools (make-domain-tool-table (or tools '()))
     :tool-runner tool-runner
     :handlers handler-table
     :initializer initializer)))

(defun domain-server-engine-instance-count (engine)
  (hash-table-count (domain-server-engine-instances engine)))

(defun ensure-domain-server-instance (engine key)
  (or (gethash key (domain-server-engine-instances engine))
      (setf (gethash key (domain-server-engine-instances engine))
            (make-domain-server-instance
             :key key
             :state (funcall (domain-server-engine-initializer engine)
                             key engine)))))

(defun domain-server-engine-instance-state (engine key)
  (let ((instance (gethash key (domain-server-engine-instances engine))))
    (and instance (domain-server-instance-state instance))))

(defun invoke-domain-operation (engine key message-type payload)
  (unless (domain-server-engine-p engine)
    (fail-actor 'domain-server-core-error
                "Domain operation requires a domain-server engine."))
  (required-nonempty-string key "domain key")
  (required-nonempty-string message-type "domain message type")
  (unless (member message-type
                  (getf (domain-server-engine-definition engine) :accepts)
                  :test #'string=)
    (fail-actor 'domain-server-core-error
                "Domain server ~A does not accept ~A."
                (getf (domain-server-engine-definition engine) :name)
                message-type))
  (let ((handler (gethash message-type
                          (domain-server-engine-handlers engine))))
    (unless handler
      (fail-actor 'domain-server-core-error
                  "Domain server ~A has no runtime handler for ~A."
                  (getf (domain-server-engine-definition engine) :name)
                  message-type))
    (let ((instance (ensure-domain-server-instance engine key)))
      (if (functionp handler)
          (funcall handler instance payload engine)
          (invoke-domain-body-handler
           engine handler instance payload key)))))

;;; -------------------------------------------------- body IR handlers

(defun make-domain-body-handler-table (definition)
  (let ((table (make-hash-table :test #'equal)))
    (dolist (handler (getf definition :handlers))
      (setf (gethash (getf handler :message-type) table) handler))
    table))

(defun domain-body-initial-state (definition)
  (initial-body-state (getf definition :states)))

(defun invoke-domain-body-handler (engine handler instance payload key)
  "Execute one native StarLang body handler for a keyed instance. State is
per-key; transitions commit only after the handler completes without a
typed failure."
  (let* ((*body-reply-value* nil)
         (*body-reply-p* nil)
         (*body-locals* '())
         (*body-states* (getf (domain-server-engine-definition engine)
                              :states))
         (*body-message-var* (or (getf handler :message-var) "message"))
         (body (getf handler :body))
         (context
           (list (cons "key" key)
                 (cons "domain"
                       (getf (domain-server-engine-definition engine)
                             :name))))
         (final-state
           (eval-body-sequence (rest body) payload context
                               (copy-tree
                                (domain-server-instance-state instance))
                               nil)))
    (setf (domain-server-instance-state instance) final-state)
    (and *body-reply-p* *body-reply-value*)))
