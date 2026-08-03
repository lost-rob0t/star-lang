(defsystem "starlang-prototype"
  :description "Transitional ASDF system for the authoritative StarLang Common Lisp implementation in prototype/. Final star-* and starlang-* systems are populated incrementally from this base."
  :author "lost-rob0t"
  :license "AGPL-3.0-only"
  :version "0.1.0"
  :depends-on ()
  :serial t
  :components
  ((:module "prototype"
    :components
    (;; Core surface defines the shared package everything else uses
     (:file "core-surface-prototype")
     (:file "macro-expander-prototype")
     (:file "actor-wire-prototype")
     (:file "core-semantics-prototype")
     (:file "canonical-json-prototype")
     (:file "message-lifecycle-prototype")
     (:file "message-lifecycle-bindings-prototype")
     (:file "binding-generator-prototype")
     (:file "deterministic-dispatcher-prototype")
     (:file "deferred-dispatch-completion-prototype")
     (:file "dispatcher-idempotency-identity-prototype")
     (:file "transport-port-prototype")
     (:file "dispatcher-transport-adapter-prototype")
     (:file "runtime-directory-prototype")
     (:file "domain-server-core-prototype")
     (:file "bbp-domain-server-prototype")
     (:file "bbp-run-idempotency-prototype")
     (:file "runtime-journal-port-prototype")
     (:file "domain-remoting-prototype")
     (:file "bbp-remote-reconnect-prototype")
     (:file "domain-remoting-runtime-port-prototype")
     (:file "domain-remoting-lease-prototype")
     (:file "domain-remoting-journal-prototype")
     (:file "domain-remoting-config-prototype")
     (:file "cl-gserver-runtime-facade-prototype")
     ;; Standalone prototypes
     (:file "compiler-ir-prototype")
     (:file "spec-domain-prototype")
     (:file "prototype")
     ;; Loader / document / constructor / api chain
     (:file "star-loader")
     (:file "document-runtime")
     (:file "relation-compatibility")
     (:file "constructor-runtime")
     (:file "star-lang-api"))))
  :in-order-to ((test-op (test-op "starlang-prototype/tests"))))

(defsystem "starlang-prototype/tests"
  :description "Deterministic test entry point for the transitional StarLang prototype system."
  :author "lost-rob0t"
  :license "AGPL-3.0-only"
  :depends-on ("starlang-prototype")
  :serial t
  :components
  ((:module "prototype"
    :components
    ((:file "test-runner"))))
  :perform
  (test-op (operation component)
    (declare (ignore operation component))
    (uiop:symbol-call :starlang-prototype.test-runner :run-tests)))
