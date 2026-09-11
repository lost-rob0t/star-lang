;;;; Compatibility shell for the closed StarLang compiler core.
;;;; The parser, syntax model, expansion boundary, grammar validation,
;;;; specification lowering, and actor lowering are final-owned by
;;;; starlang-compiler (package star-lang.compiler.core). This file only
;;;; re-exports that surface under the historical package name so direct
;;;; (load) callers and remaining prototype composition files keep working.

(eval-when (:compile-toplevel :load-toplevel :execute)
  (require :asdf))

(eval-when (:compile-toplevel :load-toplevel :execute)
  (unless (find-package "STAR-LANG.COMPILER.CORE")
    ;; Register this repository tree first so the final systems and their
    ;; dependencies resolve from this checkout even in bare `sbcl --script`
    ;; processes without a configured CL_SOURCE_REGISTRY, and so an inherited
    ;; registry offering a stale checkout (e.g. under ~/common-lisp) can
    ;; never shadow this one. The tree must be a directory pathname before
    ;; :inherit-configuration so it takes precedence over inherited entries.
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
               (merge-pathnames "../starlang-compiler/starlang-compiler.asd"
                                *load-truename*))
      (funcall (find-symbol "LOAD-SYSTEM" "ASDF") :starlang-compiler))))

(defpackage #:star-lang.core-surface.prototype
  (:use #:cl)
  ;; Behavior that remains prototype-owned in this package.
  (:export
   #:bind-actor-runtime
   #:make-wire-envelope
   #:message-contract
   #:run-tests
   #:validate-wire-envelope))

(in-package #:star-lang.core-surface.prototype)

;; Re-export the entire final compiler core surface (pipeline entry points,
;; syntax model, diagnostics, and shared helpers) under this package name so
;; historical unqualified references keep resolving to the final symbols.
(do-external-symbols (symbol :star-lang.compiler.core)
  (import symbol)
  (export symbol))
