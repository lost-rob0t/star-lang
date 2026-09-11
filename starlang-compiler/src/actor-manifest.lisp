;;;; Final portable actor manifest emission.
;;;; Moved from prototype/actor-wire-prototype.lisp; that file now forwards
;;;; here. The portable manifest is runtime-neutral wire data: no live actor
;;;; cells, sockets, queues, or process identifiers.

(in-package #:star-lang.compiler.core)

(defun declarations-of-kind (library kind)
  (remove-if-not (lambda (item) (eq (getf item :kind) kind))
                 (getf library :declarations)))

(defun portable-field (field)
  (let ((portable
          (list :name (getf field :name)
                :type (copy-tree (getf field :type))
                :required (getf field :required))))
    (if (getf field :default-p)
        (append portable (list :default (getf field :default)))
        portable)))

(defun portable-declaration (declaration)
  (case (getf declaration :kind)
    (:scalar
     (list :kind :scalar
           :name (getf declaration :qualified-name)
           :base (getf declaration :base)
           :pattern (getf declaration :pattern)
           :format (getf declaration :format)
           :minimum (getf declaration :minimum)
           :maximum (getf declaration :maximum)
           :scale (getf declaration :scale)))
    (:enum
     (list :kind :enum
           :name (getf declaration :qualified-name)
           :values (copy-list (getf declaration :values))))
    (:document
     (list :kind :document
           :name (getf declaration :qualified-name)
           :extends (getf declaration :extends)
           :persistence (getf declaration :persistence)
           :fields (mapcar #'portable-field (getf declaration :fields))))
    (:predicate
     (list :kind :predicate
           :name (getf declaration :qualified-name)
           :source (getf declaration :source)
           :destination (getf declaration :destination)))
    (:message
     (list :kind :message
           :name (getf declaration :qualified-name)
           :fields (mapcar #'portable-field (getf declaration :fields))))
    (otherwise
     (fail 'invalid-declaration-error
           "Cannot emit portable declaration for ~S."
           (getf declaration :kind)))))

(defun portable-actor (actor)
  (let ((portable
          (list :name (getf actor :name)
                :runtime (getf actor :runtime)
                :protocol (getf actor :protocol)
                :endpoint (getf actor :endpoint)
                :accepts (copy-list (getf actor :accepts))
                :produces (copy-list (getf actor :produces))
                :capabilities (copy-list (getf actor :capabilities)))))
    (when (getf actor :service-uri)
      (setf portable
            (append portable (list :service-uri (getf actor :service-uri)))))
    (when (getf actor :metadata)
      (setf portable
            (append portable
                    (list :metadata (copy-alist (getf actor :metadata))))))
    portable))

(defun emit-portable-manifest (library actors)
  (unless (and (listp library) (eq (getf library :kind) :spec-library))
    (fail 'invalid-library-error
          "Portable manifest requires compiled spec library IR."))
  (list :wire-version 1
        :library (list :name (getf library :name)
                       :version (getf library :version)
                       :digest (getf library :digest))
        :imports (copy-tree (getf library :imports))
        :types (mapcar #'portable-declaration
                       (append (declarations-of-kind library :scalar)
                               (declarations-of-kind library :enum)
                               (declarations-of-kind library :document)))
        :predicates (mapcar #'portable-declaration
                            (declarations-of-kind library :predicate))
        :messages (mapcar #'portable-declaration
                          (declarations-of-kind library :message))
        :actors (mapcar #'portable-actor actors)))
