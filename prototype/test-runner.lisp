(defpackage #:starlang-prototype.test-runner
  (:use #:cl)
  (:export #:run-tests))

(in-package #:starlang-prototype.test-runner)

(defun prototype-test-files ()
  (let* ((root (merge-pathnames
                "prototype/"
                (asdf:system-source-directory "starlang-prototype")))
         (baseline (merge-pathnames "tests.lisp" root))
         (suites (sort (directory (merge-pathnames "*-tests.lisp" root))
                       #'string<
                       :key #'namestring)))
    (unless (probe-file baseline)
      (error "Missing baseline prototype test file: ~A" baseline))
    (cons baseline suites)))

(defun lisp-executable ()
  (or (uiop:getenv "LISP")
      #+sbcl
      (namestring sb-ext:*runtime-pathname*)
      #-sbcl
      "sbcl"))

(defun run-test-file (path)
  (format t "~&[starlang-prototype] running ~A~%" (file-namestring path))
  (finish-output)
  (uiop:run-program
   (list (lisp-executable) "--script" (namestring path))
   :output *standard-output*
   :error-output *error-output*))

(defun run-tests ()
  (let ((tests (prototype-test-files)))
    (dolist (test tests)
      (run-test-file test))
    (format t "~&[starlang-prototype] ~D test scripts passed.~%"
            (length tests))
    t))
