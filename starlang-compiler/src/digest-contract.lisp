;;;; Final digest-lock contract shared by compiler-owned import and program IR.

(in-package #:star-lang.compiler.core)

(defun full-sha256-digest-p (value)
  "True for sha256:<64 hex digits>. Case of hex digits is intentionally accepted."
  (and (stringp value)
       (= (length value) 71)
       (string= "sha256:" value :end2 7)
       (loop for index from 7 below 71
             for character = (char value index)
             always (or (digit-char-p character)
                        (char<= #\a (char-downcase character) #\f)))))

(defun digest-p (value)
  "Compiler-facing exact SHA-256 digest predicate."
  (full-sha256-digest-p
   (if (star-syntax-p value) (syntax-atom value) value)))

(export '(full-sha256-digest-p))
