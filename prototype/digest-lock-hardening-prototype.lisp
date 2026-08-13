;;;; Transitional hardening for retained specification compatibility paths.
;;;;
;;;; The authoritative loader already requires sha256:<64 hex digits>.  The
;;;; older compiler-IR and spec-domain prototypes predate that rule and kept
;;;; prefix-only DIGEST-P predicates.  Keep one exact predicate shape across
;;;; those retained paths until their ownership moves into final ASDF systems.

(in-package #:cl-user)

(defun starlang-full-sha256-digest-string-p (value)
  (and (stringp value)
       (= (length value) 71)
       (string= "sha256:" value :end2 7)
       (every (lambda (character)
                (or (digit-char-p character)
                    (find character "abcdefABCDEF")))
              (subseq value 7))))

(in-package #:star-lang.compiler-ir.prototype)

(defun digest-p (value)
  (when (star-lang.core-surface.prototype:star-syntax-p value)
    (setf value (ir-atom value)))
  (cl-user::starlang-full-sha256-digest-string-p value))

(in-package #:star-lang.spec-domain.prototype)

(defun digest-p (digest)
  (cl-user::starlang-full-sha256-digest-string-p digest))

(in-package #:cl-user)
