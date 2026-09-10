(defpackage :starlogicadapterswi-integration-tests
  (:use :cl :fiveam)
  (:import-from :starlogicadapterswi
                #:make-swi-backend
                #:swi-authentication-error
                #:swi-bootstrap-handshake-error
                #:swi-bootstrap-package-mismatch-error)
  (:import-from :starlogicprotocol
                #:logic-backend-descriptor-of
                #:logic-backend-descriptor-id
                #:logic-backend-descriptor-version
                #:logic-backend-descriptor-build-id
                #:logic-backend-descriptor-semantic-profiles
                #:logic-backend-descriptor-capabilities
                #:logic-backend-descriptor-isolation-classes
                #:open-logic-session
                #:close-logic-session
                #:logic-backend-health)
  (:import-from :starprocessport
                #:process-alive-p
                #:process-reaped-p
                #:kill-process))
(in-package :starlogicadapterswi-integration-tests)

(def-suite starlogicadapterswi-integration-tests
  :description "Real Nix-pinned SWI-Prolog MQI integration tests.")
(in-suite starlogicadapterswi-integration-tests)

(defun required-swipl ()
  (let ((path (uiop:getenv "STARLANG_SWI_EXECUTABLE")))
    (unless (and path (plusp (length path)))
      (error "STARLANG_SWI_EXECUTABLE is required for real SWI integration tests."))
    path))

(defun fresh-backend ()
  (make-swi-backend :swipl-executable (required-swipl)))

(defun worker-process (session)
  (starlogicadapterswi::swi-worker-process
   (starlogicadapterswi::swi-session-worker session)))

(test descriptor-is-honest-and-exact
  (let* ((backend (fresh-backend))
         (descriptor (logic-backend-descriptor-of backend)))
    (is (string= "swi-prolog" (logic-backend-descriptor-id descriptor)))
    (is (null (logic-backend-descriptor-semantic-profiles descriptor)))
    (is (null (logic-backend-descriptor-capabilities descriptor)))
    (is (equal '("process")
               (logic-backend-descriptor-isolation-classes descriptor)))
    (is (uiop:absolute-pathname-p
         (pathname (starlogicadapterswi::swi-backend-executable backend))))
    (is (uiop:string-prefix-p
         "sha256:" (logic-backend-descriptor-build-id descriptor)))
    (format t "~&STARLANG_REAL_SWI_VERSION=~A~%"
            (logic-backend-descriptor-version descriptor))
    (format t "STARLANG_REAL_SWI_BUILD_ID=~A~%"
            (logic-backend-descriptor-build-id descriptor))
    (format t "STARLANG_REAL_SWI_EXECUTABLE=~A~%"
            (starlogicadapterswi::swi-backend-executable backend))))

(test real-worker-auth-bootstrap-health-and-clean-close
  (let* ((backend (fresh-backend))
         (session nil)
         (process nil))
    (unwind-protect
         (progn
           (setf session (open-logic-session backend "integration-1")
                 process (worker-process session))
           (is (process-alive-p process))
           (let ((health (logic-backend-health backend)))
             (is (eq :usable (getf health :status)))
             (is (= 1 (getf health :active-sessions))))
           (let ((worker (starlogicadapterswi::swi-session-worker session)))
             (is (= 1 (starlogicadapterswi::swi-worker-mqi-major worker)))
             (is (>= (starlogicadapterswi::swi-worker-mqi-minor worker) 0))
             (format t "STARLANG_REAL_MQI_PROTOCOL=~D.~D~%"
                     (starlogicadapterswi::swi-worker-mqi-major worker)
                     (starlogicadapterswi::swi-worker-mqi-minor worker)))
           (close-logic-session backend session)
           (setf session nil)
           (is (process-reaped-p process))
           (is (not (process-alive-p process)))
           (is (= 0 (or (starprocessport:process-exit-code process) -1))))
      (when session
        (ignore-errors (close-logic-session backend session))))))

(test second-fresh-session-does-not-reuse-worker
  (let* ((backend (fresh-backend))
         (first (open-logic-session backend "integration-first"))
         (first-process (worker-process first)))
    (unwind-protect
         (progn
           (close-logic-session backend first)
           (setf first nil)
           (is (process-reaped-p first-process))
           (let* ((second (open-logic-session backend "integration-second"))
                  (second-process (worker-process second)))
             (unwind-protect
                  (progn
                    (is (not (eq first-process second-process)))
                    (is (process-alive-p second-process)))
               (close-logic-session backend second)
               (is (process-reaped-p second-process)))))
      (when first
        (ignore-errors (close-logic-session backend first))))))

(test bootstrap-digest-mismatch-fails-before-worker-launch
  (let ((backend (fresh-backend))
        (starlogicadapterswi::*last-owned-process* nil))
    (setf (starlogicadapterswi::swi-backend-bootstrap-digest backend)
          "sha256:0000000000000000000000000000000000000000000000000000000000000000")
    (signals swi-bootstrap-package-mismatch-error
      (open-logic-session backend "bad-bootstrap-digest"))
    (is (null starlogicadapterswi::*last-owned-process*))))

(test authentication-failure-reaps-worker
  (let ((backend (fresh-backend)))
    (let ((starlogicadapterswi::*authentication-password-transform*
            (lambda (password) (concatenate 'string password "-wrong"))))
      (signals swi-authentication-error
        (open-logic-session backend "bad-auth")))
    (let ((process starlogicadapterswi::*last-owned-process*))
      (is (not (null process)))
      (is (process-reaped-p process))
      (is (not (process-alive-p process))))))

(test bootstrap-mismatch-reaps-worker
  (let ((backend (fresh-backend)))
    (let ((starlogicadapterswi::+bootstrap-id+ "star.logic.bootstrap/wrong"))
      (signals swi-bootstrap-handshake-error
        (open-logic-session backend "bad-bootstrap")))
    (let ((process starlogicadapterswi::*last-owned-process*))
      (is (not (null process)))
      (is (process-reaped-p process))
      (is (not (process-alive-p process))))))

(test worker-crash-on-close-is-disposable-and-reaped
  (let* ((backend (fresh-backend))
         (session (open-logic-session backend "crash-close"))
         (process (worker-process session)))
    (kill-process process)
    (signals error
      (close-logic-session backend session))
    (is (process-reaped-p process))
    (is (not (process-alive-p process)))))

(defun run-tests ()
  (let ((results (run 'starlogicadapterswi-integration-tests)))
    (explain! results)
    (unless (results-status results)
      (error "star-logic-adapter-swi integration tests failed."))
    t))
