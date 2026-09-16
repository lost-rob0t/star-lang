(defpackage :starprocessport-tests
  (:use :cl :fiveam)
  (:import-from :bordeaux-threads
                #:join-thread
                #:make-thread)
  (:import-from :starprocessport
                #:cancel-process-operation
                #:ensure-process-success
                #:invalid-process-command-error
                #:launch-process
                #:make-process-cancellation-token
                #:process-cancelled-error
                #:process-exit-error
                #:process-generation
                #:process-instance-id
                #:process-launch-error
                #:process-provenance
                #:process-result-exit-code
                #:process-result-generation
                #:process-result-instance-id
                #:process-result-outcome
                #:process-result-provenance
                #:process-result-stderr
                #:process-result-stderr-truncated-p
                #:process-result-stdout
                #:process-result-stdout-truncated-p
                #:process-result-success-p
                #:process-timeout-error
                #:run-process
                #:dispose-process))
(in-package :starprocessport-tests)

(def-suite starprocessport-tests
  :description "Generic process-port contract tests.")

(in-suite starprocessport-tests)

(defun %test-shell ()
  (or (uiop:getenv "STARLANG_TEST_SHELL") "/bin/sh"))

(defun %fixture-script ()
  (namestring
   (asdf:system-relative-pathname
    "star-process-port-tests"
    "fixtures/process-fixture.sh")))

(defun %run-fixture (arguments &rest keys)
  (apply #'run-process
         (%test-shell)
         (cons (%fixture-script) arguments)
         keys))

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

(test exact-argv-remains-literal
  (let* ((literal "$HOME;$(printf hacked);*;space value")
         (result (%run-fixture (list "echo" literal))))
    (is (process-result-success-p result))
    (is (string= literal (process-result-stdout result)))))

(test process-identity-and-provenance-are-stable-and-secret-safe
  (let* ((secret "argv-secret-should-not-enter-provenance")
         (process (launch-process (%test-shell)
                                  (list (%fixture-script) "echo" secret)
                                  :generation 41)))
    (unwind-protect
         (progn
           (is (= 41 (process-generation process)))
           (is (stringp (process-instance-id process)))
           (is (null (search secret
                             (prin1-to-string (process-provenance process))
                             :test #'char=))))
      (dispose-process process :terminate-timeout 0.05d0))))

(test bounded-output-is-drained-without-unbounded-retention
  (let ((result (%run-fixture '("flood" "70000")
                              :stdout-limit 31
                              :stderr-limit 17
                              :timeout 10.0d0)))
    (is (process-result-success-p result))
    (is (= 31 (length (process-result-stdout result))))
    (is (= 17 (length (process-result-stderr result))))
    (is (process-result-stdout-truncated-p result))
    (is (process-result-stderr-truncated-p result))))

(test nonzero-exit-is-a-typed-result
  (let ((result (%run-fixture '("exit" "7"))))
    (is (eq :exited (process-result-outcome result)))
    (is (= 7 (process-result-exit-code result)))
    (is (not (process-result-success-p result)))
    (signals process-exit-error
      (ensure-process-success result))))

(test timeout-escalates-and-reaps-an-uncooperative-process
  (let ((result (%run-fixture '("ignore-term")
                              :timeout 0.05d0
                              :terminate-timeout 0.02d0)))
    (is (eq :timeout (process-result-outcome result)))
    (is (stringp (process-result-instance-id result)))
    (signals process-timeout-error
      (ensure-process-success result))))

(test active-cancellation-stops-and-reaps
  (let* ((token (make-process-cancellation-token))
         (canceller (make-thread
                     (lambda ()
                       (sleep 0.05d0)
                       (cancel-process-operation token))
                     :name "star-process-port cancellation test"))
         (result nil))
    (unwind-protect
         (setf result
               (%run-fixture '("spin")
                             :cancellation-token token
                             :terminate-timeout 0.05d0))
      (join-thread canceller))
    (is (eq :cancelled (process-result-outcome result)))
    (signals process-cancelled-error
      (ensure-process-success result))))

(test generated-result-carries-generation-and-safe-provenance
  (let* ((secret "result-secret")
         (result (%run-fixture (list "echo" secret) :generation 9)))
    (is (= 9 (process-result-generation result)))
    (is (stringp (process-result-instance-id result)))
    (is (null (search secret
                      (prin1-to-string (process-result-provenance result))
                      :test #'char=)))))

(test rejects-negative-generation-and-output-limits
  (signals invalid-process-command-error
    (%run-fixture '("exit" "0") :generation -1))
  (signals invalid-process-command-error
    (%run-fixture '("exit" "0") :stdout-limit -1))
  (signals invalid-process-command-error
    (%run-fixture '("exit" "0") :stderr-limit -1)))

(defun run-tests ()
  (let ((results (run 'starprocessport-tests)))
    (explain! results)
    (unless (results-status results)
      (error "star-process-port tests failed."))
    t))
