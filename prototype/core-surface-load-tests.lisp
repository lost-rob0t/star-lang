;;;; Regression tests for the core-surface compatibility shell's ASDF source
;;;; registry. A bare `sbcl --script` load must resolve starlang-compiler
;;;; from this checkout even when an inherited source registry offers a
;;;; stale clone (e.g. a ~/common-lisp checkout whose starlang-compiler is
;;;; version 0.0.0 and defines no star-lang.compiler.core package). Failures
;;;; signal so the prototype test runner and CI gates cannot pass silently.

(eval-when (:compile-toplevel :load-toplevel :execute)
  (require :asdf))

(in-package #:cl-user)

(defun decoy-registry-directory ()
  (ensure-directories-exist
   (merge-pathnames
    (make-pathname
     :directory
     (list :relative
           (format nil "star-lang-core-surface-~36R-~36R"
                   (get-universal-time)
                   (random most-positive-fixnum))))
    (uiop:temporary-directory))))

(defun write-decoy-tree (root)
  (let ((system-directory (merge-pathnames "starlang-compiler/" root)))
    (ensure-directories-exist system-directory)
    (with-open-file (stream (merge-pathnames "starlang-compiler.asd" system-directory)
                            :direction :output
                            :if-exists :supersede
                            :if-does-not-exist :create)
      (write-string "(defsystem \"starlang-compiler\"
  :version \"0.0.0\"
  :components ((:file \"decoy\")))"
                    stream))
    (with-open-file (stream (merge-pathnames "decoy.lisp" system-directory)
                            :direction :output
                            :if-exists :supersede
                            :if-does-not-exist :create)
      (write-string "(defpackage #:starelang-decoy
  (:use #:cl)
  (:export #:decoy-loaded))
(in-package #:starelang-decoy)
(defparameter *decoy-loaded* t)"
                    stream))))

(defun delete-decoy-tree (root)
  (ignore-errors
    (delete-file (merge-pathnames "starlang-compiler/starlang-compiler.asd" root))
    (delete-file (merge-pathnames "starlang-compiler/decoy.lisp" root))
    (uiop:delete-empty-directory (merge-pathnames "starlang-compiler/" root))
    (uiop:delete-empty-directory root)))

(defun assert-package-exists (name)
  (unless (find-package name)
    (error "Package ~A must exist after loading core-surface-prototype.lisp."
           name)))

(defun assert-package-absent (name)
  (when (find-package name)
    (error "Package ~A must not exist; the decoy stale tree was loaded." name)))

(defun run-tests ()
  (let ((decoy-root (decoy-registry-directory)))
    (handler-case
        (unwind-protect
             (progn
               (write-decoy-tree decoy-root)
               ;; Hostile environment: only the decoy tree is inherited, and
               ;; this checkout is absent from the inherited registry.
               (setf (uiop:getenv "CL_SOURCE_REGISTRY")
                     (concatenate 'string (namestring decoy-root) "//"))
               (asdf:clear-source-registry)
               ;; Load the sibling compatibility shell relative to this test
               ;; file, never relative to the process working directory.
               (load (merge-pathnames "core-surface-prototype.lisp" *load-truename*))
               (assert-package-exists "STAR-LANG.COMPILER.CORE")
               (let ((version
                       (asdf:component-version (asdf:find-system :starlang-compiler))))
                 (unless (string-equal "0.1.0" version)
                   (error "starlang-compiler version ~A was loaded; this checkout must win over the decoy tree."
                          version)))
               (assert-package-absent "STARELANG-DECOY")
               (format t "Star-Lang core surface source-registry tests passed.~%")
               t)
          (delete-decoy-tree decoy-root))
      (serious-condition (caught)
        (error "Star-Lang core surface source-registry tests failed: ~A" caught)))))

(unless (run-tests)
  (error "Star-Lang core surface source-registry tests failed."))
