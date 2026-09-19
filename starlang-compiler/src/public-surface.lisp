;;;; Public starlang-compiler surface: re-export the final parser, macro
;;;; expander, actor lowering, manifest emission, and diagnostics from the core
;;;; package.

(in-package #:starlangcompiler)

(defun re-export-from (package symbols)
  (dolist (name symbols)
    (let ((symbol (find-symbol (string name) package)))
      (unless symbol
        (error "starlang-compiler public surface is missing ~A in ~A."
               name package))
      (import symbol)
      (export symbol))))

(re-export-from :star-lang.compiler.core
  '(
    ;; Pipeline entry points.
    #:compile-actor
    #:compile-actor-source
    #:compile-actor-file
    #:compile-spec-library
    #:compile-star-core
    #:emit-lifecycle-manifest
    #:emit-portable-manifest
    #:expand-star-syntax
    #:lifecycle-transition-table
    #:load-star-form
    #:portable-actor
    #:read-star-syntax
    #:trusted-form-to-star-syntax
    #:validate-star-core
    #:+normalized-ir-schema+
    #:+normalized-ir-version+
    ;; Declarative hygienic macro surface.
    #:collect-star-macro-environment
    #:expanded-star-source
    #:expand-star-syntax-1
    #:make-star-expansion-limits
    #:merge-star-macro-environments
    #:star-expansion-limits
    #:star-expansion-trace
    #:star-macro-dependencies
    #:star-macro-environment
    ;; Diagnostics.
    #:star-lang-core-error
    #:star-lang-core-error-code
    #:star-lang-core-error-column
    #:star-lang-core-error-details
    #:star-lang-core-error-line
    #:star-lang-core-error-message
    #:star-lang-core-error-origin
    #:star-lang-core-error-pathname
    #:star-lang-core-error-phase
    #:star-lang-core-error-related-spans
    #:star-lang-core-error-span
    #:star-lang-core-error-syntax-kind
    #:star-lang-source-error
    #:invalid-actor-error
    #:invalid-declaration-error
    #:invalid-envelope-error
    #:invalid-field-error
    #:invalid-library-error
    #:invalid-macro-error
    #:invalid-star-service-uri-error
    #:invalid-type-error
    #:macro-context-error
    #:macro-expansion-error
    #:macro-limit-error
    #:unsupported-macro-error))