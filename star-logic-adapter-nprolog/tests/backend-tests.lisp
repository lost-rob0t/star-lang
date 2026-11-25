(defpackage :starlogicadapternprolog-tests
  (:use :cl :fiveam)
  (:import-from :starlogicadapternprolog
                #:nprolog-executable-unavailable-error
                #:nprolog-package-unsupported-error
                #:nprolog-malformed-startup-data-error
                #:make-nprolog-backend)
  (:import-from :starlogicprotocol
                #:+logic-backend-n-prolog+
                #:star-logic-error)
  (:import-from :starprocessport
                #:%make-managed-process))
(in-package :starlogicadapternprolog-tests)

(def-suite starlogicadapternprolog-tests
  :description "Pure and fake-boundary N-Prolog adapter tests.")
(in-suite starlogicadapternprolog-tests)

;; Banner forms observed from the pinned upstream (sasagawa888/nprolog
;; 13d43e0c1b084d736ba15d26f1da085f00224b93, npl 5.20): -v output and the
;; REPL startup line.
(test version-banner-parses-observed-form
  (multiple-value-bind (major minor)
      (starlogicadapternprolog::%parse-version-banner "N-Prolog Ver 5.20")
    (is (= 5 major))
    (is (= 20 minor)))
  (is (string= "5.20"
               (starlogicadapternprolog::%version-string 5 20))))

(test startup-banner-parses-observed-cell-suffix-form
  (multiple-value-bind (major minor)
      (starlogicadapternprolog::%parse-startup-banner
       "N-Prolog Ver 5.20 [30M cells]")
    (is (= 5 major))
    (is (= 20 minor)))
  (multiple-value-bind (major minor)
      (starlogicadapternprolog::%parse-startup-banner "N-Prolog Ver 5.20")
    (is (= 5 major))
    (is (= 20 minor))))

(test version-banners-reject-foreign-forms
  (signals star-logic-error
    (starlogicadapternprolog::%parse-version-banner "SWI-Prolog version 9.2.9"))
  (signals star-logic-error
    (starlogicadapternprolog::%parse-version-banner "N-Prolog Ver x.y"))
  (signals star-logic-error
    (starlogicadapternprolog::%parse-version-banner "N-Prolog Ver "))
  (signals star-logic-error
    (starlogicadapternprolog::%parse-version-banner "")))

(test startup-banner-rejects-junk-suffix
  (signals star-logic-error
    (starlogicadapternprolog::%parse-startup-banner "N-Prolog Ver 5.20 junk")))

;; Observed N-Prolog 5.20: the plain -r REPL emits an ANSI reset before
;; verdicts; machine reads strip ANSI before matching.
(test ansi-stripping-removes-observed-reset
  (is (string= "yes" (starlogicadapternprolog::%strip-ansi-escapes
                      (format nil "~C[0myes" #\Escape))))
  (is (string= (format nil "?- yes~%")
               (starlogicadapternprolog::%strip-ansi-escapes
                (format nil "?- ~C[0myes~%" #\Escape))))
  (is (string= "plain" (starlogicadapternprolog::%strip-ansi-escapes "plain"))))

(test canary-accepts-observed-verdict-forms
  (is (starlogicadapternprolog::%canary-confirmed-p
       (format nil "?- ~C[0myes~C[0m~%" #\Escape #\Escape)))
  (is (starlogicadapternprolog::%canary-confirmed-p (format nil "yes~%")))
  (is (null (starlogicadapternprolog::%canary-confirmed-p (format nil "no~%"))))
  (is (null (starlogicadapternprolog::%canary-confirmed-p ""))))

(test repl-launch-argv-suppresses-editable-repl
  (is (equal '("-r") starlogicadapternprolog::+nprolog-repl-launch-argv+)))

(test package-expectation-rejects-any-package-identity
  ;; This slice publishes no trusted package; nothing may be silently ignored.
  (let ((backend (starlogicadapternprolog::%make-nprolog-backend)))
    (signals nprolog-package-unsupported-error
      (starlogicadapternprolog::%validate-package-expectation
       backend "some.package" nil))
    (signals nprolog-package-unsupported-error
      (starlogicadapternprolog::%validate-package-expectation
       backend nil "sha256:0000000000000000000000000000000000000000000000000000000000000000"))
    (signals nprolog-package-unsupported-error
      (starlogicadapternprolog::%validate-package-expectation
       backend "some.package" "sha256:0000000000000000000000000000000000000000000000000000000000000000"))
    (is (starlogicadapternprolog::%validate-package-expectation backend nil nil))))

(test missing-executable-fails-closed
  (signals nprolog-executable-unavailable-error
    (make-nprolog-backend :nprolog-executable
                          "/nonexistent/starlang-nprolog-missing/npl")))

(test startup-banner-bound-allows-exact-limit
  (let ((process
          (starprocessport::%make-managed-process
           :stdout (make-string-input-stream
                    (format nil "N-Prolog Ver 5.20 [30M cells]~%")))))
    (is (string= "N-Prolog Ver 5.20 [30M cells]"
                 (starlogicadapternprolog::%read-startup-banner
                  process :max-chars 28)))))

(test startup-banner-bound-rejects-oversize-before-newline
  (let ((process
          (starprocessport::%make-managed-process
           :stdout (make-string-input-stream
                    (format nil "N-Prolog Ver 5.20 [30M cells]~%")))))
    (signals nprolog-malformed-startup-data-error
      (starlogicadapternprolog::%read-startup-banner process :max-chars 10))))

(test worker-state-has-no-credential-slot
  ;; The plain REPL boundary has no authentication data at all. A clean load
  ;; of the worker structure must not grow a slot that could retain secrets.
  (multiple-value-bind (symbol status)
      (find-symbol "NPROLOG-WORKER-PASSWORD" :starlogicadapternprolog)
    (declare (ignore symbol))
    (is (null status))))

(defun run-tests ()
  (run 'starlogicadapternprolog-tests))
