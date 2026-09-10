;;;; Compatibility loader for the final-owned resolver effect protocol.
;;;;
;;;; Authoritative implementation lives in starlang-compiler/src/resolver-effects.lisp.

(eval-when (:compile-toplevel :load-toplevel :execute)
  (require :asdf)
  (unless (find-package "STAR-LANG.LOADER.EFFECTS")
    (funcall
     (find-symbol "LOAD-ASD" "ASDF")
     (merge-pathnames
      "../starlang-compiler/starlang-compiler.asd"
      *load-truename*))
    (funcall (find-symbol "LOAD-SYSTEM" "ASDF") :starlang-compiler)))
