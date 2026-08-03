(unless (find-package "STAR-LANG.CORE-SURFACE.PROTOTYPE")
  (load (merge-pathnames "core-surface-prototype.lisp" *load-truename*)))

(defpackage #:star-lang.compiler-ir.prototype
  (:use #:cl)
  (:export
   #:+normalized-ir-schema+
   #:+normalized-ir-version+
   #:bind-cl-gserver
   #:compile-program
   #:define-star-program
   #:example-program
   #:run-example
   #:run-tests))

(in-package #:star-lang.compiler-ir.prototype)

(defconstant +normalized-ir-version+ 2)
(defparameter +normalized-ir-schema+ "org.star-lang/normalized-ir@2")

(define-condition star-lang-compiler-error (error)
  ((message :initarg :message :reader compiler-error-message)
   (code :initarg :code :initform :compiler-error :reader compiler-error-code)
   (span :initarg :span :initform nil :reader compiler-error-span)
   (origin :initarg :origin :initform nil :reader compiler-error-origin)
   (syntax-kind :initarg :syntax-kind :initform nil
                :reader compiler-error-syntax-kind)
   (related-spans :initarg :related-spans :initform nil
                  :reader compiler-error-related-spans)
   (phase :initarg :phase :initform :compile :reader compiler-error-phase)
   (details :initarg :details :initform nil :reader compiler-error-details))
  (:report (lambda (condition stream)
             (write-string (compiler-error-message condition) stream))))

(define-condition invalid-declaration-error (star-lang-compiler-error) ())
(define-condition invalid-stage-error (star-lang-compiler-error) ())
(define-condition unresolved-spec-error (star-lang-compiler-error) ())
(define-condition adapter-binding-error (star-lang-compiler-error) ())
(define-condition test-error (star-lang-compiler-error) ())

(defvar *compiler-current-syntax* nil)

(defun fail (condition-type control &rest arguments)
  (let ((syntax *compiler-current-syntax*))
    (error condition-type
           :message (apply #'format nil control arguments)
           :span (and syntax
                      (star-lang.core-surface.prototype:star-syntax-span syntax))
           :origin (and syntax
                        (star-lang.core-surface.prototype:star-syntax-origin syntax))
           :syntax-kind
           (and syntax
                (star-lang.core-surface.prototype:star-syntax-kind syntax))
           :phase :compile)))

(defmacro with-compiler-syntax ((syntax) &body body)
  `(let ((*compiler-current-syntax* ,syntax)) ,@body))

(defun ir-list-p (value)
  (and (star-lang.core-surface.prototype:star-syntax-p value)
       (eq (star-lang.core-surface.prototype:star-syntax-kind value) :list)))

(defun ir-elements (value)
  (if (ir-list-p value)
      (star-lang.core-surface.prototype:star-syntax-children value)
      (fail 'invalid-declaration-error "Expected a StarLang list occurrence.")))

(defun ir-atom (value)
  (if (and (star-lang.core-surface.prototype:star-syntax-p value)
           (not (ir-list-p value)))
      (star-lang.core-surface.prototype:star-syntax-datum value)
      (fail 'invalid-declaration-error "Expected a StarLang atomic occurrence.")))

(defun identifier-string (value)
  (let ((datum (if (star-lang.core-surface.prototype:star-syntax-p value)
                   (ir-atom value)
                   value)))
    (etypecase datum
      (string datum)
      (symbol (string-downcase (symbol-name datum))))))

(defun identifier-key (value)
  (string-downcase (identifier-string value)))

(defun string-prefix-p (prefix string)
  (and (stringp string)
       (<= (length prefix) (length string))
       (string= prefix string :end2 (length prefix))))

(defun digest-p (value)
  (when (star-lang.core-surface.prototype:star-syntax-p value)
    (setf value (ir-atom value)))
  (and (stringp value)
       (> (length value) 7)
       (string-prefix-p "sha256:" value)))

(defun local-spec-path-p (value)
  (when (star-lang.core-surface.prototype:star-syntax-p value)
    (setf value (ir-atom value)))
  (and (stringp value)
       (not (string-prefix-p "http://" value))
       (not (string-prefix-p "https://" value))))

(defun plist-has-key-p (plist key)
  (loop for tail on (ir-elements plist) by #'cddr
        thereis (eq (ir-atom (first tail)) key)))

(defun required-option (options key context &optional condition-type)
  (unless (plist-has-key-p options key)
    (fail (or condition-type 'invalid-declaration-error)
          "~A requires option ~S."
          context key))
  (loop for (candidate value) on (ir-elements options) by #'cddr
        when (eq (ir-atom candidate) key)
          return value))

(defun ensure-proper-plist (options context)
  (unless (and (ir-list-p options)
               (evenp (length (ir-elements options))))
    (fail 'invalid-declaration-error "~A requires a property list." context))
  options)

(defun normalize-type (value)
  (cond
    ((ir-list-p value) (mapcar #'normalize-type (ir-elements value)))
    ((star-lang.core-surface.prototype:star-syntax-p value)
     (let ((datum (ir-atom value)))
       (cond
         ((keywordp datum) datum)
         ((stringp datum) datum)
         ((symbolp datum) (identifier-string datum))
         (t datum))))
    (t
     (fail 'invalid-declaration-error "Expected a StarLang syntax occurrence."))))

(defun normalize-capabilities (value)
  (unless (ir-list-p value)
    (fail 'invalid-declaration-error "Capabilities must be a list."))
  (mapcar #'normalize-type (ir-elements value)))

(defun compile-spec-import (import)
  (unless (and (ir-list-p import) (evenp (length (ir-elements import))))
    (fail 'unresolved-spec-error "Specification imports must be property lists."))
  (let ((name (required-option import :name "Specification import" 'unresolved-spec-error))
        (version (required-option import :version "Specification import" 'unresolved-spec-error))
        (digest (required-option import :digest "Specification import" 'unresolved-spec-error)))
    (unless (and (stringp (ir-atom name))
                 (stringp (ir-atom version))
                 (digest-p digest))
      (fail 'unresolved-spec-error
            "Specification import requires string name, exact version, and sha256 digest."))
    (list :name (ir-atom name)
          :version (ir-atom version)
          :digest (ir-atom digest))))

(defun compile-spec-library (library)
  (unless (and (ir-list-p library) (evenp (length (ir-elements library))))
    (fail 'unresolved-spec-error "Specification library entries must be property lists."))
  (let ((name (required-option library :name "Specification library" 'unresolved-spec-error))
        (version (required-option library :version "Specification library" 'unresolved-spec-error))
        (digest (required-option library :digest "Specification library" 'unresolved-spec-error))
        (path (required-option library :path "Specification library" 'unresolved-spec-error)))
    (unless (and (stringp (ir-atom name))
                 (stringp (ir-atom version))
                 (digest-p digest))
      (fail 'unresolved-spec-error
            "Specification library requires string name, exact version, and sha256 digest."))
    (unless (local-spec-path-p path)
      (fail 'unresolved-spec-error
            "Compiler received unresolved remote specification path ~S; resolve and lock it first."
            path))
    (list :name (ir-atom name)
          :version (ir-atom version)
          :digest (ir-atom digest)
          :path (ir-atom path)
          :origin (and (plist-has-key-p library :origin)
                       (normalize-type
                        (required-option library :origin "Specification library")))
          :imports (mapcar #'compile-spec-import
                           (if (plist-has-key-p library :imports)
                               (ir-elements
                                (required-option library :imports
                                                 "Specification library"))
                               '())))))

(defun compile-spec-graph (declaration)
  (destructuring-bind (operator options) (ir-elements declaration)
    (declare (ignore operator))
    (ensure-proper-plist options "spec-graph")
    (let ((lock-digest (required-option options :lock-digest "spec-graph" 'unresolved-spec-error))
          (libraries (required-option options :libraries "spec-graph" 'unresolved-spec-error)))
      (unless (digest-p lock-digest)
        (fail 'unresolved-spec-error "spec-graph requires a sha256 lock digest."))
      (unless (and (ir-list-p libraries) (ir-elements libraries))
        (fail 'unresolved-spec-error "spec-graph requires at least one resolved library."))
      (list :kind :spec-graph
            :lock-digest (ir-atom lock-digest)
            :libraries (mapcar #'compile-spec-library
                               (ir-elements libraries))))))

(defun compile-document (declaration)
  (destructuring-bind (operator name options) (ir-elements declaration)
    (declare (ignore operator))
    (ensure-proper-plist options "document")
    (let ((schema (required-option options :schema "document"))
          (persistence (required-option options :persistence "document")))
      (unless (stringp (ir-atom schema))
        (fail 'invalid-declaration-error "Document schema must be a locked schema identifier."))
      (unless (member (ir-atom persistence) '(:persistent :transient) :test #'eq)
        (fail 'invalid-declaration-error "Document persistence must be :persistent or :transient."))
      (list :kind :document
            :name (identifier-string name)
            :schema (ir-atom schema)
            :persistence (ir-atom persistence)))))

(defun normalize-mailbox (mailbox)
  (unless (and (ir-list-p mailbox) (= (length (ir-elements mailbox)) 2))
    (fail 'invalid-declaration-error "Actor mailbox must be (:bounded capacity)."))
  (destructuring-bind (kind capacity) (ir-elements mailbox)
    (unless (and (eq (ir-atom kind) :bounded)
                 (integerp (ir-atom capacity))
                 (> (ir-atom capacity) 0))
      (fail 'invalid-declaration-error "Actor mailbox must be (:bounded positive-integer)."))
    (list :kind :bounded :capacity (ir-atom capacity))))

(defun compile-actor (declaration)
  (destructuring-bind (operator name options) (ir-elements declaration)
    (declare (ignore operator))
    (ensure-proper-plist options "actor")
    (let ((accepts (required-option options :accepts "actor"))
          (produces (required-option options :produces "actor"))
          (handler (required-option options :handler "actor"))
          (mailbox (required-option options :mailbox "actor"))
          (restart (required-option options :restart "actor")))
      (unless (member (ir-atom restart)
                      '(:permanent :transient :temporary) :test #'eq)
        (fail 'invalid-declaration-error "Actor restart policy ~S is invalid." restart))
      (list :kind :actor
            :name (identifier-string name)
            :accepts (normalize-type accepts)
            :produces (normalize-type produces)
            :handler (identifier-string handler)
            :mailbox (normalize-mailbox mailbox)
            :restart (ir-atom restart)
            :capabilities
            (if (plist-has-key-p options :capabilities)
                (normalize-capabilities
                 (required-option options :capabilities "actor"))
                '())))))

(defun normalize-index (index)
  (unless (and (ir-list-p index) (= (length (ir-elements index)) 3))
    (fail 'invalid-declaration-error
          "Domain-server indexes must be (name schema field)."))
  (destructuring-bind (name schema field) (ir-elements index)
    (unless (stringp (ir-atom schema))
      (fail 'invalid-declaration-error "Domain-server index schema must be qualified."))
    (list :name (identifier-string name)
          :schema (ir-atom schema)
          :field (identifier-string field))))

(defun compile-domain-server (declaration)
  (destructuring-bind (operator name options) (ir-elements declaration)
    (declare (ignore operator))
    (ensure-proper-plist options "domain-server")
    (let ((key-schema (required-option options :key-schema "domain-server"))
          (owns (required-option options :owns "domain-server"))
          (indexes (required-option options :indexes "domain-server"))
          (accepts (required-option options :accepts "domain-server"))
          (restart (required-option options :restart "domain-server")))
      (unless (and (stringp (ir-atom key-schema))
                   (ir-list-p owns)
                   (every (lambda (item) (stringp (ir-atom item)))
                          (ir-elements owns))
                   (ir-list-p indexes)
                   (ir-list-p accepts))
        (fail 'invalid-declaration-error "Domain-server schema and protocol declarations are invalid."))
      (unless (member (ir-atom restart)
                      '(:permanent :transient :temporary) :test #'eq)
        (fail 'invalid-declaration-error "Domain-server restart policy ~S is invalid." restart))
      (list :kind :domain-server
            :name (identifier-string name)
            :authority :keyed-aggregate
            :actor-cardinality :per-key
            :key-schema (ir-atom key-schema)
            :owns (mapcar #'ir-atom (ir-elements owns))
            :indexes (mapcar #'normalize-index (ir-elements indexes))
            :accepts (normalize-type accepts)
            :restart (ir-atom restart)
            :capabilities
            (if (plist-has-key-p options :capabilities)
                (normalize-capabilities
                 (required-option options :capabilities "domain-server"))
                '())))))

(defun compile-relation-stage (dataflow-name index stage)
  (let ((options
          (star-lang.core-surface.prototype:make-star-syntax
           :kind :list
           :children (rest (ir-elements stage))
           :span (star-lang.core-surface.prototype:star-syntax-span stage)
           :scopes (star-lang.core-surface.prototype:star-syntax-scopes stage)
           :origin (star-lang.core-surface.prototype:star-syntax-origin stage))))
    (ensure-proper-plist options "relations stage")
    (let ((source (required-option options :source "relations stage" 'invalid-stage-error))
          (predicate (required-option options :predicate "relations stage" 'invalid-stage-error))
          (destination (required-option options :destination "relations stage" 'invalid-stage-error)))
      (list :node-id (format nil "~A/~3,'0D" dataflow-name index)
            :op :relations
            :source (normalize-type source)
            :predicate (normalize-type predicate)
            :destination (normalize-type destination)))))

(defun compile-stage (dataflow-name index stage target-names)
  (unless (and (ir-list-p stage) (ir-elements stage))
    (fail 'invalid-stage-error "Invalid dataflow stage."))
  (let ((node-id (format nil "~A/~3,'0D" dataflow-name index))
        (operator (identifier-key (first (ir-elements stage)))))
    (cond
      ((string= operator "from-dataset")
       (unless (and (= (length (ir-elements stage)) 2)
                    (stringp (ir-atom (second (ir-elements stage)))))
         (fail 'invalid-stage-error "from-dataset requires one dataset name string."))
       (list :node-id node-id :op :from-dataset
             :dataset (ir-atom (second (ir-elements stage)))))
      ((string= operator "relations")
       (compile-relation-stage dataflow-name index stage))
      ((string= operator "send")
       (unless (= (length (ir-elements stage)) 3)
         (fail 'invalid-stage-error "send requires target and message operands."))
       (let ((target (identifier-string (second (ir-elements stage)))))
         (unless (member target target-names :test #'string=)
           (fail 'invalid-stage-error "send targets undefined actor or domain server ~A." target))
         (list :node-id node-id
               :op :send
               :target target
               :message (normalize-type (third (ir-elements stage))))))
      ((string= operator "collect")
       (unless (= (length (ir-elements stage)) 2)
         (fail 'invalid-stage-error "collect requires one binding name."))
       (list :node-id node-id :op :collect
             :binding (normalize-type (second (ir-elements stage)))))
      (t
       (fail 'invalid-stage-error "Unknown dataflow stage ~S."
             (star-lang.core-surface.prototype:star-syntax-to-datum
              (first (ir-elements stage))))))))

(defun compile-dataflow (declaration target-names)
  (destructuring-bind (operator name &rest stages) (ir-elements declaration)
    (declare (ignore operator))
    (let ((normalized-name (identifier-string name)))
      (unless stages
        (fail 'invalid-stage-error "Dataflow ~A has no stages." normalized-name))
      (list :kind :dataflow
            :name normalized-name
            :nodes (loop for stage in stages
                         for index from 0
                         collect (compile-stage normalized-name index stage target-names))))))

(defun declaration-kind (declaration)
  (unless (and (ir-list-p declaration) (ir-elements declaration))
    (fail 'invalid-declaration-error "Invalid declaration."))
  (identifier-key (first (ir-elements declaration))))

(defun declared-target-names (declarations)
  (loop for declaration in declarations
        for kind = (declaration-kind declaration)
        when (member kind '("actor" "domain-server") :test #'string=)
          collect (identifier-string (second (ir-elements declaration)))))

(defun ensure-one-spec-graph (declarations)
  (let ((graphs (remove-if-not (lambda (declaration)
                                 (string= (declaration-kind declaration) "spec-graph"))
                               declarations)))
    (unless (= (length graphs) 1)
      (fail 'unresolved-spec-error "Program requires exactly one resolved spec-graph."))
    (first graphs)))

(defun compile-declaration (declaration target-names)
  (with-compiler-syntax (declaration)
  (let ((kind (declaration-kind declaration)))
    (cond
      ((string= kind "spec-graph") (compile-spec-graph declaration))
      ((string= kind "document") (compile-document declaration))
      ((string= kind "actor") (compile-actor declaration))
      ((string= kind "domain-server") (compile-domain-server declaration))
      ((string= kind "dataflow") (compile-dataflow declaration target-names))
      (t
       (fail 'invalid-declaration-error "Unknown declaration ~S."
             (star-lang.core-surface.prototype:star-syntax-to-datum
              (first (ir-elements declaration)))))))))

(defun compile-program (declarations)
  "Compile trusted host declarations through the syntax-object phase boundary.
This adapter is not a .star source reader."
  (let* ((syntax
           (if (star-lang.core-surface.prototype:star-syntax-p declarations)
               declarations
               (star-lang.core-surface.prototype:trusted-form-to-star-syntax
                declarations)))
         (expanded
           (star-lang.core-surface.prototype:expand-star-syntax syntax)))
    (star-lang.core-surface.prototype:validate-star-core
     expanded :specification-graph :program)
    (let ((declaration-syntax (ir-elements expanded)))
      (ensure-one-spec-graph declaration-syntax)
      (let* ((target-names (declared-target-names declaration-syntax))
         (compiled (mapcar (lambda (declaration)
                             (compile-declaration declaration target-names))
                           declaration-syntax))
         (spec-graph (find :spec-graph compiled :key (lambda (item) (getf item :kind)))))
        (list :ir-version +normalized-ir-version+
              :ir-schema +normalized-ir-schema+
              :kind :program
              :spec-lock-digest (getf spec-graph :lock-digest)
              :declarations compiled
              :source-map
              (star-lang.core-surface.prototype:star-syntax-source-map
               expanded))))))

(defmacro define-star-program (&body declarations)
  `(compile-program ',declarations))

(defun declaration-by-kind (program kind)
  (remove-if-not (lambda (declaration) (eq (getf declaration :kind) kind))
                 (getf program :declarations)))

(defun bind-actor-manifest (actor)
  (list :kind :actor-manifest
        :name (getf actor :name)
        :runtime :cl-gserver
        :constructor :actor-of
        :send-operation :tell
        :handler (getf actor :handler)
        :accepts (copy-tree (getf actor :accepts))
        :produces (copy-tree (getf actor :produces))
        :mailbox (copy-tree (getf actor :mailbox))
        :restart (getf actor :restart)
        :capabilities (copy-list (getf actor :capabilities))))

(defun bind-domain-server-manifest (domain-server)
  (list :kind :domain-server-manifest
        :name (getf domain-server :name)
        :runtime :cl-gserver
        :constructor :actor-of
        :send-operation :tell
        :authority :keyed-aggregate
        :actor-cardinality :per-key
        :key-schema (getf domain-server :key-schema)
        :owns (copy-list (getf domain-server :owns))
        :indexes (copy-tree (getf domain-server :indexes))
        :accepts (copy-tree (getf domain-server :accepts))
        :restart (getf domain-server :restart)
        :capabilities (copy-list (getf domain-server :capabilities))))

(defun bind-node (node)
  (if (eq (getf node :op) :send)
      (list :node-id (getf node :node-id)
            :op :tell
            :actor (getf node :target)
            :message (copy-tree (getf node :message)))
      (copy-tree node)))

(defun bind-dataflow (dataflow)
  (list :kind :bound-dataflow
        :name (getf dataflow :name)
        :nodes (mapcar #'bind-node (getf dataflow :nodes))))

(defun bind-cl-gserver (program)
  (unless (and (listp program)
               (= (getf program :ir-version) +normalized-ir-version+)
               (string= (or (getf program :ir-schema) "")
                        +normalized-ir-schema+)
               (eq (getf program :kind) :program))
    (fail 'adapter-binding-error
          "cl-gserver binder requires Star-Lang normalized IR schema ~A."
          +normalized-ir-schema+))
  (list :runtime :cl-gserver
        :ir-version +normalized-ir-version+
        :ir-schema +normalized-ir-schema+
        :spec-lock-digest (getf program :spec-lock-digest)
        :actors (mapcar #'bind-actor-manifest (declaration-by-kind program :actor))
        :domain-servers
        (mapcar #'bind-domain-server-manifest
                (declaration-by-kind program :domain-server))
        :dataflows (mapcar #'bind-dataflow (declaration-by-kind program :dataflow))))

(defun example-program ()
  (define-star-program
    (spec-graph
     (:lock-digest "sha256:employment-lock-v1"
      :libraries
      ((:name "org.starintel/core@1"
        :version "1.0.0"
        :digest "sha256:core-v1-example"
        :path "spec-lock/org.starintel-core-1/library.star"
        :origin "https://specs.starintel.actor/core/v1/library.star")
       (:name "org.starintel/employment@1"
        :version "1.0.0"
        :digest "sha256:employment-v1-example"
        :path "spec-lock/org.starintel-employment-1/library.star"
        :origin "https://specs.starintel.actor/employment/v1/library.star"
        :imports ((:name "org.starintel/core@1"
                   :version "1.0.0"
                   :digest "sha256:core-v1-example"))))))
    (document relation
      (:schema "org.starintel/core@1/relation" :persistence :persistent))
    (actor combine-names-into-emails
      (:accepts (:list "org.starintel/core@1/relation")
       :produces (:list :email)
       :handler combine-names-handler
       :mailbox (:bounded 128)
       :restart :transient
       :capabilities (:read-dataset)))
    (domain-server employment-domain
      (:key-schema "org.starintel/core@1/organization"
       :owns ("org.starintel/core@1/person"
              "org.starintel/core@1/organization"
              "org.starintel/core@1/relation")
       :indexes ((by-predicate "org.starintel/core@1/relation" predicate)
                 (by-source "org.starintel/core@1/relation" source)
                 (by-destination "org.starintel/core@1/relation" destination))
       :accepts ((employees-for-organization :reference)
                 (relations-for-predicate :symbol))
       :restart :transient
       :capabilities (:read-dataset :write-transient)))
    (dataflow employment-emails
      (from-dataset "flock")
      (relations :source :any :predicate employed :destination employer)
      (send combine-names-into-emails :current)
      (collect emails))))

(defun run-example ()
  (let ((program (example-program)))
    (values program (bind-cl-gserver program))))

(defun condition-signaled-p (condition-type thunk)
  (handler-case
      (progn (funcall thunk) nil)
    (condition (caught)
      (if (typep caught condition-type)
          t
          (error caught)))))

(defun assert-true (value label)
  (unless value
    (fail 'test-error "Assertion failed: ~A." label)))

(defun assert-equal (expected actual label)
  (unless (equal expected actual)
    (fail 'test-error "~A expected ~S, received ~S." label expected actual)))

(defun find-node (dataflow operation)
  (find operation (getf dataflow :nodes) :key (lambda (node) (getf node :op))))

(defun test-macro-expands-to-compiler-call ()
  (multiple-value-bind (expansion expanded-p)
      (macroexpand-1 '(define-star-program
                        (spec-graph
                         (:lock-digest "sha256:test-lock"
                          :libraries
                          ((:name "test/core"
                            :version "1.0.0"
                            :digest "sha256:test-core"
                            :path "spec-lock/test-core/library.star"))))))
    (assert-true expanded-p "define-star-program expands")
    (assert-equal 'compile-program (first expansion) "macro compiler entry point")))

(defun test-core-ir-preserves-runtime-neutral-send ()
  (let* ((program (example-program))
         (dataflow (first (declaration-by-kind program :dataflow)))
         (send (find-node dataflow :send)))
    (assert-true send "core IR contains send")
    (assert-equal +normalized-ir-version+ (getf program :ir-version)
                  "normalized IR version")
    (assert-equal +normalized-ir-schema+ (getf program :ir-schema)
                  "normalized IR schema")
    (assert-equal :program (getf program :kind) "normalized IR root kind")
    (assert-equal "combine-names-into-emails" (getf send :target) "core send target")))

(defun test-adapter-rejects-legacy-ir ()
  (let ((legacy (copy-list (example-program))))
    (setf (getf legacy :ir-version) 1)
    (assert-true
     (condition-signaled-p 'adapter-binding-error
                           (lambda () (bind-cl-gserver legacy)))
     "adapter rejects legacy normalized IR")))

(defun test-cl-gserver-binding-lowers-send-to-tell ()
  (let* ((bound (bind-cl-gserver (example-program)))
         (dataflow (first (getf bound :dataflows)))
         (tell (find-node dataflow :tell))
         (actor (first (getf bound :actors))))
    (assert-true tell "bound dataflow contains tell")
    (assert-equal "combine-names-into-emails" (getf tell :actor) "tell actor")
    (assert-equal :actor-of (getf actor :constructor) "actor constructor")
    (assert-equal :tell (getf actor :send-operation) "actor send operation")))

(defun test-domain-server-is-keyed-authority ()
  (let* ((bound (bind-cl-gserver (example-program)))
         (domain-server (first (getf bound :domain-servers))))
    (assert-equal :keyed-aggregate (getf domain-server :authority) "domain authority")
    (assert-equal :per-key (getf domain-server :actor-cardinality) "domain actor cardinality")
    (assert-true (not (eq (getf domain-server :actor-cardinality) :per-document))
                 "domain server is not one actor per document")))

(defun test-remote-spec-path-is-rejected ()
  (assert-true
   (condition-signaled-p
    'unresolved-spec-error
    (lambda ()
      (compile-program
       '((spec-graph
          (:lock-digest "sha256:test-lock"
           :libraries
           ((:name "test/core"
             :version "1.0.0"
             :digest "sha256:test-core"
             :path "https://example.invalid/library.star"))))))))
   "compiler rejects unresolved remote specification path"))

(defun test-relations-require-explicit-positions ()
  (assert-true
   (condition-signaled-p
    'invalid-stage-error
    (lambda ()
      (compile-program
       '((spec-graph
          (:lock-digest "sha256:test-lock"
           :libraries
           ((:name "test/core"
             :version "1.0.0"
             :digest "sha256:test-core"
             :path "spec-lock/test-core/library.star"))))
         (dataflow broken
           (relations :predicate employed :destination employer))))))
   "relation traversal requires source, predicate, and destination"))

(defun test-unknown-send-target-is-rejected ()
  (assert-true
   (condition-signaled-p
    'invalid-stage-error
    (lambda ()
      (compile-program
       '((spec-graph
          (:lock-digest "sha256:test-lock"
           :libraries
           ((:name "test/core"
             :version "1.0.0"
             :digest "sha256:test-core"
             :path "spec-lock/test-core/library.star"))))
         (dataflow broken
           (send missing-actor :current))))))
   "send target must be declared"))

(defun test-compilation-is-deterministic ()
  (assert-equal (example-program) (example-program) "deterministic compilation"))

(defun run-tests ()
  (mapc #'funcall
        (list #'test-macro-expands-to-compiler-call
              #'test-core-ir-preserves-runtime-neutral-send
              #'test-adapter-rejects-legacy-ir
              #'test-cl-gserver-binding-lowers-send-to-tell
              #'test-domain-server-is-keyed-authority
              #'test-remote-spec-path-is-rejected
              #'test-relations-require-explicit-positions
              #'test-unknown-send-target-is-rejected
              #'test-compilation-is-deterministic))
  (format t "Star-Lang normalized IR and cl-gserver adapter tests passed.~%")
  t)
