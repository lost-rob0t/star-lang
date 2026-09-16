;;;; Compatibility shell for the final StarLang declarative macro expander.
;;;; Macro parsing, bounded expansion, hygiene, provenance, dependency tracking,
;;;; and deterministic expanded-source rendering are final-owned by
;;;; starlang-compiler (package star-lang.compiler.core).

(in-package #:star-lang.core-surface.prototype)

(dolist (name '(collect-star-macro-environment
                expanded-star-source
                expand-star-syntax
                expand-star-syntax-1
                invalid-macro-error
                macro-context-error
                macro-expansion-error
                macro-limit-error
                make-star-expansion-limits
                merge-star-macro-environments
                star-expansion-limits
                star-expansion-trace
                star-macro-dependencies
                star-macro-environment))
  (multiple-value-bind (symbol status)
      (find-symbol (string name) :star-lang.compiler.core)
    (unless (and symbol (eq status :external))
      (error "Final macro surface is missing external symbol ~A." name))
    (multiple-value-bind (present present-status)
        (find-symbol (string name) *package*)
      (declare (ignore present-status))
      (cond
        ((null present)
         (import symbol *package*))
        ((not (eq present symbol))
         (error "Prototype macro compatibility symbol ~A does not resolve to the final compiler symbol."
                name))))
    (export symbol *package*)))