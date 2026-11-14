;;;; Final keyed domain-server lowering and manifest emission.
;;;;
;;;; Migrated from prototype/domain-server-core-prototype.lisp, which is now
;;;; a forwarding shell. Domain servers keep keyed-aggregate semantics:
;;;; stable typed keys own per-key state, and every accepted message type
;;;; resolves to exactly one handler. Native StarLang bodies (issue #69)
;;;; are optional: domain servers may declare (state ...) and keyed
;;;; (on type (key message context) ...) handlers instead of delegating to
;;;; host-side handler functions.

(in-package #:star-lang.compiler.core)

(define-condition domain-server-core-error (star-lang-core-error) ())
(define-condition domain-tool-error (domain-server-core-error) ())

(defun domain-declarations-of-kind (library kind)
  (remove-if-not (lambda (declaration)
                   (eq (getf declaration :kind) kind))
                 (getf library :declarations)))

(defun declaration-qualified-names (library kind)
  (mapcar (lambda (declaration)
            (getf declaration :qualified-name))
          (domain-declarations-of-kind library kind)))

(defun local-qualified-declaration (library kind value context)
  (let* ((library-name (getf library :name))
         (qualified (qualify-name library-name value)))
    (unless (member qualified
                    (declaration-qualified-names library kind)
                    :test #'string=)
      (fail 'domain-server-core-error
            "~A references unknown ~A ~A."
            context kind qualified))
    qualified))

(defun normalize-domain-capabilities (values)
  (unless (listp values)
    (fail 'domain-server-core-error
          "Domain server capabilities must be a list."))
  (mapcar #'identifier-string values))

(defun normalize-tool-argv-template (value tool-name)
  (unless (and (listp value) value)
    (fail 'domain-tool-error
          "Tool ~A requires a nonempty argv template."
          tool-name))
  (dolist (item value)
    (unless (or (stringp item)
                (member item '(:target :program-id :run-id) :test #'eq))
      (fail 'domain-tool-error
            "Tool ~A argv item ~S is not a fixed string or supported placeholder."
            tool-name item)))
  (copy-list value))

(defun compile-domain-tool (form library)
  (unless (and (listp form)
               (= (length form) 3)
               (string= (declaration-kind form) "tool"))
    (fail 'domain-tool-error
          "Expected (tool name (...options...))."))
  (destructuring-bind (operator name options) form
    (declare (ignore operator))
    (ensure-plist options "tool" 'domain-tool-error)
    (let* ((normalized-name (identifier-string name))
           (executable
             (required-option options :executable "tool" 'domain-tool-error))
           (input
             (local-qualified-declaration
              library :scalar
              (required-option options :input "tool" 'domain-tool-error)
              (format nil "Tool ~A" normalized-name)))
           (produces
             (local-qualified-declaration
              library :message
              (required-option options :produces "tool" 'domain-tool-error)
              (format nil "Tool ~A" normalized-name)))
           (timeout-ms
             (required-option options :timeout-ms "tool" 'domain-tool-error)))
      (unless (and (stringp executable) (> (length executable) 0))
        (fail 'domain-tool-error
              "Tool ~A executable must be a nonempty string."
              normalized-name))
      (unless (and (integerp timeout-ms) (> timeout-ms 0))
        (fail 'domain-tool-error
              "Tool ~A timeout must be a positive integer."
              normalized-name))
      (list :kind :tool
            :name normalized-name
            :executable executable
            :argv-template
            (normalize-tool-argv-template
             (required-option options :argv "tool" 'domain-tool-error)
             normalized-name)
            :input input
            :produces produces
            :timeout-ms timeout-ms
            :capabilities
            (mapcar #'identifier-string
                    (or (getf options :capabilities) '()))))))

(defun tool-name-set (tools)
  (mapcar (lambda (tool) (getf tool :name)) tools))

(defun domain-service-uri-entry (form options normalized-name)
  "Lower the optional domain :service-uri. Hierarchical resource URIs
(issue #72) become canonical :resource-uri entries; legacy tuples stay
compatibility input."
  (let ((value (getf options :service-uri)))
    (unless value
      (return-from domain-service-uri-entry '()))
    (let ((datum (if (star-syntax-p value) (syntax-atom value) value)))
      (unless (stringp datum)
        (fail 'domain-server-core-error
              "Domain server ~A service URI must be a string."
              normalized-name))
      (handler-case
          (if (staractorprotocol:hierarchical-star-uri-p datum)
              (let ((uri
                      (staractorprotocol:parse-star-resource-uri datum)))
                (unless (eq :service
                            (staractorprotocol:star-resource-uri-resource-kind uri))
                  (fail 'domain-server-core-error
                        "Domain server ~A requires a service resource URI."
                        normalized-name))
                (list :resource-uri
                      (staractorprotocol:star-resource-uri-string uri)))
              (list :service-uri
                    (staractorprotocol:star-service-uri-string
                     (staractorprotocol:ensure-star-service-uri datum))))
        (staractorprotocol:invalid-star-service-uri-error (condition)
          (fail 'domain-server-core-error "~A" condition))
        (staractorprotocol:invalid-star-resource-uri-error (condition)
          (fail 'domain-server-core-error "~A" condition))))))

(defun compile-domain-server (form library tools &key body)
  "Lower a trusted-host domain-server form with compiled spec-library
LIBRARY and TOOLS. BODY supplies optional native StarLang state and keyed
on declaration forms (issue #69); declarations after the options plist are
also accepted as the body."
  (unless (and (listp form)
               (>= (length form) 3)
               (string= (declaration-kind form) "domain-server"))
    (fail 'domain-server-core-error
          "Expected a domain-server name, options, and optional body."))
  (let ((body-declarations
          (append (if body body '()) (cdddr form))))
    (destructuring-bind (operator name options &rest ignored-elements) form
      (declare (ignore operator ignored-elements))
      (ensure-plist options "domain-server" 'domain-server-core-error)
      (let* ((normalized-name (identifier-string name))
             (context (format nil "Domain server ~A" normalized-name))
             (key-type
               (local-qualified-declaration
                library :scalar
                (required-option options :key-type
                                 "domain-server"
                                 'domain-server-core-error)
                context))
             (owns
               (mapcar
                (lambda (value)
                  (local-qualified-declaration
                   library :document value context))
                (required-option options :owns
                                 "domain-server"
                                 'domain-server-core-error)))
             (accepts
               (mapcar
                (lambda (value)
                  (local-qualified-declaration
                   library :message value context))
                (required-option options :accepts
                                 "domain-server"
                                 'domain-server-core-error)))
             (declared-tools
               (mapcar #'identifier-string
                       (required-option options :tools
                                        "domain-server"
                                        'domain-server-core-error)))
             (available-tools (tool-name-set tools)))
        (dolist (tool declared-tools)
          (unless (member tool available-tools :test #'string=)
            (fail 'domain-server-core-error
                  "Domain server ~A references undeclared tool ~A."
                  normalized-name tool)))
        (let ((domain
                (append
                 (list :kind :domain-server
                       :name normalized-name
                       :key-type key-type
                       :owns owns
                       :accepts accepts
                       :tools declared-tools
                       :restart
                       (normalize-restart
                        (required-option options :restart
                                         "domain-server"
                                         'domain-server-core-error))
                       :mailbox
                       (normalize-mailbox
                        (required-option options :mailbox
                                         "domain-server"
                                         'domain-server-core-error))
                       :dispatcher
                       (identifier-string (or (getf options :dispatcher) 'default))
                       :capabilities
                       (normalize-domain-capabilities
                        (or (getf options :capabilities) '())))
                 (domain-service-uri-entry form options normalized-name))))
          (when body-declarations
            (multiple-value-bind (states handlers)
                (compile-body-declarations
                 body-declarations 'key accepts
                 (lambda (type)
                   (local-qualified-declaration
                    library :message type context))
                 context)
              (ensure-body-covers-accepted-types
               accepts
               (mapcar (lambda (handler) (getf handler :message-type))
                       handlers)
               context)
              (setf domain
                    (append domain (list :states states :handlers handlers)))))
          domain)))))

(defun portable-domain-tool (tool)
  (list :name (getf tool :name)
        :executable (getf tool :executable)
        :argv-template (copy-list (getf tool :argv-template))
        :input (getf tool :input)
        :produces-message (getf tool :produces)
        :timeout-ms (getf tool :timeout-ms)
        :capabilities (copy-list (getf tool :capabilities))))

(defun domain-server-manifest-entry (definition)
  (append
   (list :name (getf definition :name)
         :authority :keyed-aggregate
         :key-type (getf definition :key-type)
         :owns (copy-list (getf definition :owns))
         :accepts (copy-list (getf definition :accepts))
         :tools (copy-list (getf definition :tools))
         :restart (getf definition :restart)
         :mailbox (copy-tree (getf definition :mailbox))
         :dispatcher (getf definition :dispatcher)
         :capabilities (copy-list (getf definition :capabilities)))
   (cond
     ((getf definition :resource-uri)
      (list :resource-uri (getf definition :resource-uri)))
     ((getf definition :service-uri)
      (list :service-uri (getf definition :service-uri)))
     (t '()))
   (when (getf definition :states)
     (list :states (copy-tree (getf definition :states))))
   (when (getf definition :handlers)
     (list :handlers (copy-tree (getf definition :handlers))))))

(defun emit-domain-program-manifest (library actors tools domain-servers)
  (append
   (emit-portable-manifest library actors)
   (list :tools (mapcar #'portable-domain-tool tools)
         :domain-servers
         (mapcar #'domain-server-manifest-entry domain-servers))))
