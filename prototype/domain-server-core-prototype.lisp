(require :asdf)

;;;; Forwarding shell after the domain-server core migration.
;;;;
;;;; Domain-server/tool lowering is final-owned by starlang-compiler
;;;; (star-lang.compiler.core) and the keyed engine, tool-runner port, and
;;;; native body execution are final-owned by starlang-runtime
;;;; (starlangruntime). This shell re-exports that surface under the
;;;; historical prototype package name so remaining prototype composition
;;;; files keep working without duplicated behavior.

(eval-when (:compile-toplevel :load-toplevel :execute)
  (unless (find-package "STARLANGRUNTIME")
    (let ((repository-root
            (make-pathname
             :name nil
             :type nil
             :directory (butlast (pathname-directory *load-truename*)))))
      (funcall (find-symbol "INITIALIZE-SOURCE-REGISTRY" "ASDF")
               (list :source-registry
                     (list :tree (namestring repository-root))
                     :inherit-configuration))
      (funcall (find-symbol "LOAD-ASD" "ASDF")
               (merge-pathnames "../starlang-runtime/starlang-runtime.asd"
                                *load-truename*))
      (funcall (find-symbol "LOAD-SYSTEM" "ASDF") :starlang-runtime))))

(in-package #:star-lang.core-surface.prototype)

(defparameter *domain-core-forwarded-symbols*
  '(;; Lowering (starlang-compiler).
    #:compile-domain-server
    #:compile-domain-tool
    #:domain-server-manifest-entry
    #:emit-domain-program-manifest
    #:domain-server-core-error
    #:domain-tool-error
    ;; Keyed engine, tool ports, and native body execution
    ;; (starlang-runtime).
    #:make-domain-server-engine
    #:domain-server-engine-p
    #:domain-server-engine-instance-count
    #:domain-server-engine-instance-state
    #:domain-server-engine-tools
    #:domain-server-engine-tool-runner
    #:domain-server-engine-handlers
    #:domain-server-engine-initializer
    #:domain-server-engine-instances
    #:domain-server-engine-definition
    #:invoke-domain-operation
    #:make-domain-server-instance
    #:domain-server-instance
    #:domain-server-instance-p
    #:domain-server-instance-key
    #:domain-server-instance-state
    #:make-tool-runner-port
    #:tool-runner-port
    #:tool-runner-port-p
    #:tool-runner-port-run-fn
    #:run-domain-tool
    #:tool-command-argv))

(defun forward-domain-core-symbol (name)
  (or (find-symbol (symbol-name name) :star-lang.compiler.core)
      (find-symbol (symbol-name name) :starlangruntime)
      (error "Domain core forwarding lost symbol ~A." (symbol-name name))))

(dolist (name *domain-core-forwarded-symbols*)
  (let ((forwarded (forward-domain-core-symbol name)))
    (import forwarded)
    (export forwarded)))
