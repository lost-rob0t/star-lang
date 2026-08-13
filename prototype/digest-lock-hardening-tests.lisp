(load (merge-pathnames "compiler-ir-prototype.lisp" *load-truename*))
(load (merge-pathnames "spec-domain-prototype.lisp" *load-truename*))
(load (merge-pathnames "digest-lock-hardening-prototype.lisp" *load-truename*))

(in-package #:cl-user)

(defun digest-lock-assert (condition label)
  (unless condition
    (error "Digest lock assertion failed: ~A" label)))

(defun digest-lock-predicates ()
  (list
   (symbol-function
    (or (find-symbol "DIGEST-P" "STAR-LANG.COMPILER-IR.PROTOTYPE")
        (error "Missing compiler digest predicate.")))
   (symbol-function
    (or (find-symbol "DIGEST-P" "STAR-LANG.SPEC-DOMAIN.PROTOTYPE")
        (error "Missing spec-domain digest predicate.")))))

(defun repeat-character-string (character count)
  (make-string count :initial-element character))

(defun run-digest-lock-hardening-tests ()
  (let* ((valid-lower
           (concatenate 'string "sha256:" (repeat-character-string #\a 64)))
         (valid-upper
           (concatenate 'string "sha256:" (repeat-character-string #\F 64)))
         (invalid
           (list
            "sha256:a"
            (concatenate 'string "sha256:" (repeat-character-string #\a 63))
            (concatenate 'string "sha256:" (repeat-character-string #\a 65))
            (concatenate 'string "sha256:" (repeat-character-string #\g 64))
            (concatenate 'string "SHA256:" (repeat-character-string #\a 64))
            (concatenate 'string "sha1:" (repeat-character-string #\a 64))
            nil
            42)))
    (dolist (predicate (digest-lock-predicates))
      (digest-lock-assert (funcall predicate valid-lower)
                          "64 lowercase hex digits accepted")
      (digest-lock-assert (funcall predicate valid-upper)
                          "64 uppercase hex digits accepted")
      (dolist (value invalid)
        (digest-lock-assert (not (funcall predicate value))
                            (format nil "invalid digest rejected: ~S" value)))))
  (format t "Full SHA-256 lock hardening tests passed.~%")
  t)

(unless (run-digest-lock-hardening-tests)
  (error "Full SHA-256 lock hardening tests failed."))
