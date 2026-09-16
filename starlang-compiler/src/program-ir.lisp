;;;; Final normalized program IR compiler.
;;;;
;;;; This is the final owner of the legacy compiler-ir prototype's useful
;;;; language behavior. Runtime-specific binding deliberately lives outside the
;;;; compiler.

(in-package #:star-lang.compiler.core)

(define-condition invalid-program-error (star-lang-core-error) ())
(define-condition invalid-stage-error (invalid-program-error) ())
(define-condition unresolved-spec-error (invalid-program-error) ())

(defun program-elements (value context)
  (cond
    ((syntax-list-p value) (syntax-elements value))
    ((and (listp value) (not (star-syntax-p value))) value)
    (t (fail 'invalid-program-error "~A must be a list." context))))

(defun program-atom (value)
  (if (star-syntax-p value) (syntax-atom value) value))

(defun program-normalize-value (value)
  (cond
    ((syntax-list-p value)
     (mapcar #'program-normalize-value (syntax-elements value)))
    ((star-syntax-p value)
     (let ((datum (syntax-atom value)))
       (cond
         ((keywordp datum) datum)
         ((or (stringp datum) (integerp datum)) datum)
         ((symbolp datum) (identifier-string value))
         (t datum))))
    ((consp value) (mapcar #'program-normalize-value value))
    ((symbolp value)
     (if (keywordp value) value (identifier-string value)))
    (t value)))

(defun remote-program-path-p (value)
  (and (stringp value)
       (or (and (<= 7 (length value)) (string= "http://" value :end2 7))
           (and (<= 8 (length value)) (string= "https://" value :end2 8)))))

(defun compile-program-import (import)
  (ensure-plist import "Specification import" 'unresolved-spec-error)
  (let ((name (required-option import :name "Specification import"
                               'unresolved-spec-error))
        (version (required-option import :version "Specification import"
                                  'unresolved-spec-error))
        (digest (required-option import :digest "Specification import"
                                 'unresolved-spec-error)))
    (unless (and (stringp (program-atom name))
                 (stringp (program-atom version))
                 (digest-p digest))
      (fail 'unresolved-spec-error
            "Specification import requires string name, exact version, and full sha256 digest."))
    (list :name (program-atom name)
          :version (program-atom version)
          :digest (program-atom digest))))

(defun compile-program-library (library)
  (ensure-plist library "Specification library" 'unresolved-spec-error)
  (let ((name (required-option library :name "Specification library"
                               'unresolved-spec-error))
        (version (required-option library :version "Specification library"
                                  'unresolved-spec-error))
        (digest (required-option library :digest "Specification library"
                                 'unresolved-spec-error))
        (path (required-option library :path "Specification library"
                               'unresolved-spec-error)))
    (unless (and (stringp (program-atom name))
                 (stringp (program-atom version))
                 (digest-p digest)
                 (stringp (program-atom path)))
      (fail 'unresolved-spec-error
            "Specification library requires string name/version/path and full sha256 digest."))
    (when (remote-program-path-p (program-atom path))
      (fail 'unresolved-spec-error
            "Compiler received unresolved remote specification path ~S; resolve and lock it first."
            (program-atom path)))
    (list :name (program-atom name)
          :version (program-atom version)
          :digest (program-atom digest)
          :path (program-atom path)
          :origin (and (plist-has-key-p library :origin)
                       (program-normalize-value
                        (required-option library :origin "Specification library")))
          :imports
          (if (plist-has-key-p library :imports)
              (mapcar #'compile-program-import
                      (program-elements
                       (required-option library :imports "Specification library")
                       "Specification imports"))
              '()))))

(defun compile-spec-graph (declaration)
  (destructuring-bind (operator options) (program-elements declaration "spec-graph")
    (declare (ignore operator))
    (ensure-plist options "spec-graph" 'unresolved-spec-error)
    (let ((lock-digest (required-option options :lock-digest "spec-graph"
                                        'unresolved-spec-error))
          (libraries (required-option options :libraries "spec-graph"
                                      'unresolved-spec-error)))
      (unless (digest-p lock-digest)
        (fail 'unresolved-spec-error "spec-graph requires a full sha256 lock digest."))
      (let ((library-list (program-elements libraries "spec-graph libraries")))
        (unless library-list
          (fail 'unresolved-spec-error "spec-graph requires at least one resolved library."))
        (list :kind :spec-graph
              :lock-digest (program-atom lock-digest)
              :libraries (mapcar #'compile-program-library library-list))))))

(defun compile-program-document (declaration)
  (destructuring-bind (operator name options)
      (program-elements declaration "program document")
    (declare (ignore operator))
    (ensure-plist options "program document" 'invalid-program-error)
    (let ((schema (required-option options :schema "program document"
                                   'invalid-program-error))
          (persistence (required-option options :persistence "program document"
                                        'invalid-program-error)))
      (unless (stringp (program-atom schema))
        (fail 'invalid-program-error
              "Program document schema must be a locked schema identifier."))
      (list :kind :document
            :name (identifier-string name)
            :schema (program-atom schema)
            :persistence (normalize-persistence persistence)))))

(defun program-capabilities (value)
  (mapcar #'identifier-string (program-elements value "capabilities")))

(defun compile-program-index (index)
  (let ((parts (program-elements index "domain-server index")))
    (unless (= (length parts) 3)
      (fail 'invalid-program-error
            "Domain-server indexes must be (name schema field)."))
    (destructuring-bind (name schema field) parts
      (unless (stringp (program-atom schema))
        (fail 'invalid-program-error
              "Domain-server index schema must be qualified."))
      (list :name (identifier-string name)
            :schema (program-atom schema)
            :field (identifier-string field)))))

(defun compile-program-domain-server (declaration)
  (destructuring-bind (operator name options)
      (program-elements declaration "domain-server")
    (declare (ignore operator))
    (ensure-plist options "domain-server" 'invalid-program-error)
    (let* ((key-schema (required-option options :key-schema "domain-server"
                                        'invalid-program-error))
           (owns (required-option options :owns "domain-server"
                                  'invalid-program-error))
           (indexes (required-option options :indexes "domain-server"
                                     'invalid-program-error))
           (accepts (required-option options :accepts "domain-server"
                                     'invalid-program-error))
           (restart (required-option options :restart "domain-server"
                                     'invalid-program-error))
           (key-schema-value (program-atom key-schema))
           (owns-values (mapcar #'program-atom
                                (program-elements owns "domain-server owns"))))
      (unless (and (stringp key-schema-value)
                   (every #'stringp owns-values))
        (fail 'invalid-program-error
              "Domain-server schema declarations must be qualified strings."))
      (list :kind :domain-server
            :name (identifier-string name)
            :authority :keyed-aggregate
            :actor-cardinality :per-key
            :key-schema key-schema-value
            :owns owns-values
            :indexes (mapcar #'compile-program-index
                             (program-elements indexes "domain-server indexes"))
            :accepts (program-normalize-value accepts)
            :restart (normalize-restart restart)
            :capabilities
            (if (plist-has-key-p options :capabilities)
                (program-capabilities
                 (required-option options :capabilities "domain-server"))
                '())))))

(defun compile-relation-stage (dataflow-name index stage)
  (let* ((parts (program-elements stage "relations stage"))
         (options (rest parts)))
    (ensure-plist options "relations stage" 'invalid-stage-error)
    (list :node-id (format nil "~A/~3,'0D" dataflow-name index)
          :op :relations
          :source (program-normalize-value
                   (required-option options :source "relations stage"
                                    'invalid-stage-error))
          :predicate (program-normalize-value
                      (required-option options :predicate "relations stage"
                                       'invalid-stage-error))
          :destination (program-normalize-value
                        (required-option options :destination "relations stage"
                                         'invalid-stage-error)))))

(defun compile-program-stage (dataflow-name index stage target-names)
  (let* ((parts (program-elements stage "dataflow stage"))
         (operator (and parts (identifier-key (first parts))))
         (node-id (format nil "~A/~3,'0D" dataflow-name index)))
    (cond
      ((string= operator "from-dataset")
       (unless (and (= (length parts) 2)
                    (stringp (program-atom (second parts))))
         (fail 'invalid-stage-error
               "from-dataset requires one dataset name string."))
       (list :node-id node-id :op :from-dataset
             :dataset (program-atom (second parts))))
      ((string= operator "relations")
       (compile-relation-stage dataflow-name index stage))
      ((string= operator "send")
       (unless (= (length parts) 3)
         (fail 'invalid-stage-error "send requires target and message operands."))
       (let ((target (identifier-string (second parts))))
         (unless (member target target-names :test #'string=)
           (fail 'invalid-stage-error
                 "send targets undefined actor or domain server ~A." target))
         (list :node-id node-id :op :send :target target
               :message (program-normalize-value (third parts)))))
      ((string= operator "collect")
       (unless (= (length parts) 2)
         (fail 'invalid-stage-error "collect requires one binding name."))
       (list :node-id node-id :op :collect
             :binding (program-normalize-value (second parts))))
      (t
       (fail 'invalid-stage-error "Unknown dataflow stage ~S."
             (and parts (program-normalize-value (first parts))))))))

(defun compile-program-dataflow (declaration target-names)
  (destructuring-bind (operator name &rest stages)
      (program-elements declaration "dataflow")
    (declare (ignore operator))
    (let ((normalized-name (identifier-string name)))
      (unless stages
        (fail 'invalid-stage-error "Dataflow ~A has no stages." normalized-name))
      (list :kind :dataflow
            :name normalized-name
            :nodes (loop for stage in stages
                         for index from 0
                         collect (compile-program-stage
                                  normalized-name index stage target-names))))))

(defun program-target-names (declarations)
  (loop for declaration in declarations
        for kind = (declaration-kind declaration)
        when (member kind '("actor" "domain-server") :test #'string=)
          collect (identifier-string
                   (second (program-elements declaration "program declaration")))))

(defun program-spec-graph (declarations)
  (let ((graphs (remove-if-not
                 (lambda (declaration)
                   (string= (declaration-kind declaration) "spec-graph"))
                 declarations)))
    (unless (= (length graphs) 1)
      (fail 'unresolved-spec-error
            "Program requires exactly one resolved spec-graph."))
    (first graphs)))

(defun compile-program-declaration (declaration target-names)
  (with-star-source-position (declaration)
    (let ((kind (declaration-kind declaration)))
      (cond
        ((string= kind "spec-graph") (compile-spec-graph declaration))
        ((string= kind "document") (compile-program-document declaration))
        ((string= kind "actor") (compile-actor declaration))
        ((string= kind "domain-server")
         (compile-program-domain-server declaration))
        ((string= kind "dataflow")
         (compile-program-dataflow declaration target-names))
        (t
         (fail 'invalid-program-error
               "Unknown program declaration ~S." kind))))))

(defun %compile-program-syntax (syntax)
  (let ((*star-current-phase* :compile))
    (validate-star-core syntax :specification-graph :program)
    (let ((declarations (syntax-elements syntax)))
      (program-spec-graph declarations)
      (let* ((target-names (program-target-names declarations))
             (compiled
               (mapcar (lambda (declaration)
                         (compile-program-declaration declaration target-names))
                       declarations))
             (spec-graph
               (find :spec-graph compiled :key (lambda (item) (getf item :kind)))))
        (list :ir-version +normalized-ir-version+
              :ir-schema +normalized-ir-schema+
              :kind :program
              :spec-lock-digest (getf spec-graph :lock-digest)
              :declarations compiled
              :source-map (star-syntax-source-map syntax))))))

(defun compile-program (declarations)
  "Compile trusted host declarations through the explicit syntax boundary."
  (let* ((syntax (if (star-syntax-p declarations)
                     declarations
                     (trusted-form-to-star-syntax declarations)))
         (expanded (expand-star-syntax syntax)))
    (%compile-program-syntax expanded)))

(defun compile-program-source (source &key pathname source-id origin limits)
  "Compile user .star program text/octet input through the closed reader."
  (let* ((effective-limits (or limits (make-star-parser-limits)))
         (syntax (read-star-syntax source
                                  :pathname pathname
                                  :source-id source-id
                                  :origin origin
                                  :limits effective-limits))
         (expanded (expand-star-syntax syntax :limits effective-limits)))
    (%compile-program-syntax expanded)))

(defmacro define-star-program (&body declarations)
  `(compile-program ',declarations))

(export '(compile-program
          compile-program-source
          define-star-program
          invalid-program-error
          invalid-stage-error
          unresolved-spec-error))
