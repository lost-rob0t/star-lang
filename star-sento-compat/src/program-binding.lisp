;;;; Runtime-specific projection of normalized StarLang program IR.

(in-package :starsentocompat)

(define-condition invalid-program-binding-error (star-sento-compat-error) ())

(defconstant +normalized-program-ir-version+ 2)
(defparameter +normalized-program-ir-schema+ "org.star-lang/normalized-ir@2")

(defun program-declarations-of-kind (program kind)
  (remove-if-not (lambda (declaration)
                   (eq (getf declaration :kind) kind))
                 (getf program :declarations)))

(defun bind-program-actor (actor)
  (unless (eq (getf actor :runtime) :native)
    (error 'invalid-program-binding-error
           :operation :bind-program
           :message
           (format nil
                   "cl-gserver binding requires native actor ~A; received runtime ~S."
                   (getf actor :name) (getf actor :runtime))))
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

(defun bind-program-domain-server (domain-server)
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

(defun bind-program-node (node)
  (if (eq (getf node :op) :send)
      (list :node-id (getf node :node-id)
            :op :tell
            :actor (getf node :target)
            :message (copy-tree (getf node :message)))
      (copy-tree node)))

(defun bind-program-dataflow (dataflow)
  (list :kind :bound-dataflow
        :name (getf dataflow :name)
        :nodes (mapcar #'bind-program-node (getf dataflow :nodes))))

(defun bind-normalized-program (program)
  "Project backend-neutral normalized program IR into cl-gserver/Sento terms."
  (unless (and (listp program)
               (= (or (getf program :ir-version) -1)
                  +normalized-program-ir-version+)
               (string= (or (getf program :ir-schema) "")
                        +normalized-program-ir-schema+)
               (eq (getf program :kind) :program))
    (error 'invalid-program-binding-error
           :operation :bind-program
           :message
           (format nil
                   "cl-gserver binder requires normalized IR schema ~A."
                   +normalized-program-ir-schema+)))
  (list :runtime :cl-gserver
        :ir-version +normalized-program-ir-version+
        :ir-schema +normalized-program-ir-schema+
        :spec-lock-digest (getf program :spec-lock-digest)
        :actors
        (mapcar #'bind-program-actor
                (program-declarations-of-kind program :actor))
        :domain-servers
        (mapcar #'bind-program-domain-server
                (program-declarations-of-kind program :domain-server))
        :dataflows
        (mapcar #'bind-program-dataflow
                (program-declarations-of-kind program :dataflow))))
