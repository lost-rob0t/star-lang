#!/usr/bin/env -S sbcl --script

(require :asdf)

(defparameter *repository-root*
  (uiop:pathname-parent-directory-pathname
   (uiop:pathname-directory-pathname *load-truename*)))

(asdf:load-asd
 (merge-pathnames "starlang-compiler/starlang-compiler.asd"
                  *repository-root*))
(asdf:load-system :starlang-compiler)

(defparameter *release-directory*
  (merge-pathnames "specs/starintel/0.10.1/" *repository-root*))
(defparameter *generated-directory*
  (merge-pathnames "generated/" *release-directory*))

(defparameter *binding-files*
  '((:common-lisp . "starintel.lisp")
    (:kotlin . "StarIntel.kt")
    (:java . "StarIntel.java")
    (:python . "starintel_types.py")
    (:typescript . "starintel_types.ts")
    (:nim . "starintel_types.nim")
    (:go . "starintel_types.go")
    (:rust . "starintel_types.rs")
    (:emacs-lisp . "starintel-types.el")
    (:prolog . "starintel_types.pl")))

(defparameter *release-binding-languages*
  '(:common-lisp :python :typescript :nim))

(defun with-trailing-newline (content)
  (concatenate 'string
               (string-right-trim '(#\Newline #\Return) content)
               (string #\Newline)))

(defun release-manifest ()
  (let* ((source-path (merge-pathnames "core.star" *release-directory*))
         (source (uiop:read-file-string source-path))
         (library
           (starlangcompiler:compile-spec-library
            (starlangcompiler:read-star-syntax
             source :source-id (namestring source-path)))))
    (starlangcompiler:emit-portable-manifest library nil)))

(defun release-outputs ()
  (let* ((manifest (release-manifest))
         (bindings
           (mapcar
            (lambda (language)
              (cons language
                    (starlangcompiler:generate-bindings manifest language)))
            *release-binding-languages*))
         (outputs
           (list
            (cons "portable-manifest.json"
                  (starcanonicaljson:canonical-manifest-json manifest))
            (cons "schema.json"
                  (starlangcompiler:generate-json-schema manifest)))))
    (dolist (binding bindings)
      (let ((filename (cdr (assoc (car binding) *binding-files*))))
        (unless filename
          (error "No release filename for binding language ~S." (car binding)))
        (push (cons filename (cdr binding)) outputs)))
    (sort outputs #'string< :key #'car)))

(defun write-output (relative content)
  (let ((pathname (merge-pathnames relative *generated-directory*)))
    (ensure-directories-exist pathname)
    (with-open-file (stream pathname
                            :direction :output
                            :if-exists :supersede
                            :if-does-not-exist :create
                            :external-format :utf-8)
      (write-string (with-trailing-newline content) stream))))

(defun check-output (relative content)
  (let ((pathname (merge-pathnames relative *generated-directory*))
        (expected (with-trailing-newline content)))
    (unless (probe-file pathname)
      (format *error-output* "Missing generated StarIntel artifact: ~A~%" pathname)
      (return-from check-output nil))
    (let ((actual (uiop:read-file-string pathname)))
      (unless (string= expected actual)
        (format *error-output* "Stale generated StarIntel artifact: ~A~%" pathname)
        (return-from check-output nil)))
    t))

(defun main ()
  (let* ((arguments (uiop:command-line-arguments))
         (check-p (member "--check" arguments :test #'string=))
         (outputs (release-outputs)))
    (when (and arguments
               (not (equal arguments '("--check"))))
      (format *error-output* "Usage: generate-starintel-release.lisp [--check]~%")
      (uiop:quit 2))
    (if check-p
        (unless (every (lambda (entry)
                         (check-output (car entry) (cdr entry)))
                       outputs)
          (uiop:quit 1))
        (dolist (entry outputs)
          (write-output (car entry) (cdr entry))))
    (format t "StarIntel 0.10.1 artifacts ~:[generated~;verified~]: ~D files~%"
            check-p (length outputs))))

(main)
