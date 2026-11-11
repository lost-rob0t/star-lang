#!/usr/bin/env -S sbcl --script
;;;; Generate an additive library with its reachable, unmodified core types.
(require :asdf)

(defparameter *repository-root*
  (uiop:pathname-parent-directory-pathname
   (uiop:pathname-directory-pathname *load-truename*)))
(asdf:load-asd (merge-pathnames "starlang-compiler/starlang-compiler.asd"
                              *repository-root*))
(asdf:load-system :starlang-compiler)

(defparameter *extension-directory*
  (merge-pathnames "specs/starintel/extensions/face-intel/0.1.0/" *repository-root*))

(defun compile-source-manifest (relative)
  (let ((path (merge-pathnames relative *repository-root*)))
    (starlangcompiler:emit-portable-manifest
     (starlangcompiler:compile-spec-library
      (starlangcompiler:read-star-syntax (uiop:read-file-string path)
                                       :source-id (namestring path)))
     nil)))

(defun source-sha256 (path)
  (let ((result (uiop:run-program (list "sha256sum" (namestring path))
                                  :output :string)))
    (subseq result 0 64)))

(defun extension-manifests ()
  (let* ((core (compile-source-manifest "specs/starintel/0.10.1/core.star"))
         (extension
           (compile-source-manifest
            "specs/starintel/extensions/face-intel/0.1.0/face-intel.star"))
         (imports (getf extension :imports))
         (import (first imports))
         (available (append (getf core :types) (getf extension :types)))
         (needed (make-hash-table :test #'equal)))
    (unless (and (= (length imports) 1)
                 (string= (getf import :name) (getf (getf core :library) :name))
                 (string= (getf import :version) (getf (getf core :library) :version))
                 (string= (getf import :digest)
                          (concatenate 'string "sha256:"
                           (source-sha256
                            (merge-pathnames "specs/starintel/0.10.1/core.star"
                                             *repository-root*)))))
      (error "Face extension must import exactly the locked core source."))
    (labels ((visit-type (type)
               (cond
                 ((consp type) (visit-type (second type)))
                 ((and (stringp type) (find #\/ type))
                  (unless (gethash type needed)
                    (let ((contract (find type available :key (lambda (entry) (getf entry :name))
                                                        :test #'string=)))
                      (unless contract (error "Unresolved extension type ~A." type))
                      (setf (gethash type needed) t)
                      (when (getf contract :extends) (visit-type (getf contract :extends)))
                      (when (getf contract :base) (visit-type (getf contract :base)))
                      (dolist (field (getf contract :fields))
                        (visit-type (getf field :type)))))))))
      (dolist (type (getf extension :types)) (visit-type (getf type :name)))
      (dolist (predicate (getf extension :predicates))
        (visit-type (getf predicate :source))
        (visit-type (getf predicate :destination)))
      (dolist (message (getf extension :messages))
        (dolist (field (getf message :fields)) (visit-type (getf field :type)))))
    (let ((resolved (copy-list extension)))
      (setf (getf resolved :types)
            (remove-if-not (lambda (entry) (gethash (getf entry :name) needed)) available))
      (values extension resolved))))

(defun extension-outputs ()
  (multiple-value-bind (extension resolved) (extension-manifests)
    (append
     (list (cons "portable-manifest.json"
                 (starcanonicaljson:canonical-manifest-json extension))
           (cons "resolved-manifest.json"
                 (starcanonicaljson:canonical-manifest-json resolved))
           (cons "schema.json" (starlangcompiler:generate-json-schema resolved)))
     (loop for (language . filename) in
           '((:common-lisp . "face_intel.lisp") (:python . "face_intel_types.py")
             (:typescript . "face_intel_types.ts") (:nim . "face_intel_types.nim")
             (:kotlin . "FaceIntel.kt") (:java . "FaceIntel.java")
             (:go . "face_intel_types.go") (:rust . "face_intel_types.rs")
             (:emacs-lisp . "face-intel-types.el") (:prolog . "face_intel_types.pl"))
           collect (cons filename (starlangcompiler:generate-bindings resolved language))))))

(defun main ()
  (let* ((arguments (uiop:command-line-arguments))
         (check-p (equal arguments '("--check")))
         (directory (merge-pathnames "generated/" *extension-directory*)))
    (unless (or (null arguments) check-p)
      (format *error-output* "Usage: generate-face-intel-extension.lisp [--check]~%")
      (uiop:quit 2))
    (dolist (entry (extension-outputs))
      (let* ((path (merge-pathnames (car entry) directory))
             (expected (concatenate 'string
                        (string-right-trim '(#\Newline #\Return) (cdr entry))
                        (string #\Newline))))
        (if check-p
            (unless (and (probe-file path) (string= expected (uiop:read-file-string path)))
              (error "Missing or stale face extension artifact: ~A." path))
            (progn
              (ensure-directories-exist path)
              (with-open-file (stream path :direction :output :if-exists :supersede
                                           :external-format :utf-8)
                (write-string expected stream))))))
    (format t "FaceIntel 0.1.0 extension artifacts ~:[generated~;verified~].~%" check-p)))

(main)
