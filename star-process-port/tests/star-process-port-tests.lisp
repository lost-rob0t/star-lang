(defpackage :starprocessport-tests
  (:use :cl :fiveam)
  (:import-from :starprocessport
                #:invalid-process-command-error
                #:process-launch-error
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

(test launch-failure-does-not-render-secret-argv
  (let ((secret "STARLANG-PROCESS-SECRET-DO-NOT-RENDER"))
    (handler-case
        (progn
          (launch-process "/definitely/not/a/star-process-port-program"
                          (list secret))
          (fail "Missing executable unexpectedly launched."))
      (process-launch-error (condition)
        (let ((rendered (princ-to-string condition)))
          (is (null (search secret rendered :test #'char=))
              "Launch failure rendered a secret-bearing argv value: ~S"
              rendered))))))

(defun run-tests ()
  (let ((results (run 'starprocessport-tests)))
    (explain! results)
    (unless (results-status results)
      (error "star-process-port tests failed."))
    t))
