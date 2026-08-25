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

(test rejects-empty-executable
  (signals invalid-process-command-error
    (launch-process "" '())))

(defun run-tests ()
  (let ((results (run 'starprocessport-tests)))
    (explain! results)
    (unless (results-status results)
      (error "star-process-port tests failed."))
    t))
