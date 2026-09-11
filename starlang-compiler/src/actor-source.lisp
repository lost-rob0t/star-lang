;;;; Final actor source pipeline: read a .star actor unit through the closed
;;;; parser, expand it, validate its declaration head, and lower it to
;;;; runtime-neutral actor IR. No host READ or EVAL ever touches .star source.

(in-package #:star-lang.compiler.core)

(defun compile-actor-declaration-syntax (syntax)
  "Validate that a single expanded declaration is an actor declaration and
lower it."
  (validate-list-head syntax *program-declaration-heads*
                      "program declaration" 'invalid-declaration-error)
  (let ((head (syntax-head-name syntax)))
    (unless (string= head "actor")
      (fail 'invalid-declaration-error
            "Expected an actor declaration, received ~S." head)))
  (compile-actor syntax))

(defun compile-actor-source (source &key limits source-id pathname origin)
  "Compile one .star actor unit (UTF-8 octets or string) to actor IR."
  (let* ((syntax (read-star-syntax source
                                   :limits limits
                                   :source-id source-id
                                   :pathname pathname
                                   :origin origin))
         (expanded (expand-star-syntax syntax :limits limits)))
    (compile-actor-declaration-syntax expanded)))

(defun compile-actor-file (pathname &key limits)
  "Compile a .star file holding exactly one actor declaration."
  (let ((path (pathname pathname)))
    (unless (and (pathname-type path)
                 (string-equal (pathname-type path) "star"))
      (fail 'star-lang-source-error
            "Star source pathname must use the .star extension."))
    (let* ((effective-limits (or limits (make-star-parser-limits)))
           (octets (read-star-path-octets path effective-limits)))
      (compile-actor-source octets
                            :limits effective-limits
                            :source-id (namestring path)
                            :pathname path))))
