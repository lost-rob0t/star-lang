;;;; starlang CLI entrypoint: loads only final systems and dispatches to the
;;;; star-lang.cli package. The transitional load/load-url commands are routed
;;;; to prototype/run-star.lisp by the installed wrapper script, never from
;;;; here, so this entrypoint keeps starlang-prototype out of the product
;;;; load path.

(require :asdf)

;; Invariant: this repository checkout must sit FIRST in the ASDF source
;; registry so the script always loads the sources it ships with. Entries are
;; searched in order, so anything registered ahead of the checkout can shadow
;; it; in particular a stale clone under ~/common-lisp (an ASDF built-in
;; default reached through :inherit-configuration) previously shadowed this
;; checkout because a file pathname was passed to :tree, which makes ASDF
;; drop the entry entirely (the same hazard fixed in
;; prototype/core-surface-prototype.lisp). The checkout must therefore be
;; registered as a DIRECTORY :tree entry before any inherited configuration.
;;
;; *load-truename* names this script inside starlang-cli/, so stripping the
;; last directory component yields the repository root.
;;
;; When the environment already carries a CL_SOURCE_REGISTRY (the nix sbcl
;; wrapper splices its dependency stores ahead of any caller value with a
;; ':' separator, CI exports the workspace), the checkout is PREPENDED to
;; that string and the ASDF configuration is cleared so the registry is
;; recomputed from the environment; this also overrides any registry that
;; the user's SBCL initialization file (for example a quicklisp setup)
;; registered before this script ran. Without a configured environment the
;; script owns the registry and declares :inherit-configuration itself, with
;; the checkout still first.
(let* ((root-directory
         (butlast (pathname-directory *load-truename*)))
       (root-namestring
         (string-right-trim
          "/"
          (namestring (make-pathname
                       :directory root-directory
                       :name nil
                       :type nil))))
       (existing-registry (uiop:getenv "CL_SOURCE_REGISTRY")))
  (if (and existing-registry (plusp (length existing-registry)))
      (progn
        (setf (uiop:getenv "CL_SOURCE_REGISTRY")
              (concatenate 'string root-namestring "//:" existing-registry))
        (asdf:clear-configuration))
      (asdf:initialize-source-registry
       `(:source-registry
         (:tree ,root-namestring)
         :inherit-configuration))))

(asdf:load-system :starlang-cli)

(handler-case
    (uiop:quit (star-lang.cli:run-cli (uiop:command-line-arguments)))
  (condition (caught)
    (format *error-output* "starlang: ~A~%" caught)
    (uiop:quit 1)))
