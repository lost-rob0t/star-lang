(defpackage :starprocessport-tests
  (:use :cl :fiveam)
  (:import-from :starprocessport
                #:invalid-process-command-error
                #:launch-process))
(in-package :starprocessport-tests)

(def-suite starprocessport-tests
  :description "Generic process-port contract tests.")

(in-suite starprocessport-tests)

(test rejects-non-string-argv
  (signals invalid-process-command-error
    (launch-process "/definitely/not/launched" '("ok" 42))))

(test rejects-improper-argv
  (signals invalid-process-command-error
    (launch-process "/definitely/not/launched" (cons "ok" "bad-tail"))))

(test rejects-circular-argv
  (let ((argv (list "ok")))
    (setf (cdr argv) argv)
    (signals invalid-process-command-error
      (launch-process "/definitely/not/launched" argv))))

(test rejects-empty-executable
  (signals invalid-process-command-error
    (launch-process "" '())))

(defun run-tests ()
  (let ((results (run 'starprocessport-tests)))
    (explain! results)
    (unless (results-status results)
      (error "star-process-port tests failed."))
    t))
