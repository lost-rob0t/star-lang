(defpackage :starlogicadapternprolog-integration-tests
  (:use :cl :fiveam)
  (:import-from :starlogicadapternprolog
                #:make-nprolog-backend
                #:nprolog-backend-identity-mismatch-error
                #:nprolog-package-unsupported-error)
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
                #:process-exit-code
                #:kill-process))
(in-package :starlogicadapternprolog-integration-tests)

(def-suite starlogicadapternprolog-integration-tests
  :description "Real Nix-pinned N-Prolog worker integration tests.")
(in-suite starlogicadapternprolog-integration-tests)

(defun required-nprolog ()
  (let ((path (uiop:getenv "STARLANG_NPROLOG_EXECUTABLE")))
    (unless (and path (plusp (length path)))
      (error "STARLANG_NPROLOG_EXECUTABLE is required for real N-Prolog integration tests."))
    path))

(defun fresh-backend ()
  (make-nprolog-backend :nprolog-executable (required-nprolog)))

(defun worker-process (session)
  (starlogicadapternprolog::nprolog-worker-process
   (starlogicadapternprolog::nprolog-session-worker session)))

(test descriptor-is-honest-and-exact
  (let* ((backend (fresh-backend))
         (descriptor (logic-backend-descriptor-of backend)))
    (is (string= "n-prolog" (logic-backend-descriptor-id descriptor)))
    (is (null (logic-backend-descriptor-semantic-profiles descriptor)))
    (is (null (logic-backend-descriptor-capabilities descriptor)))
    (is (equal '("process")
               (logic-backend-descriptor-isolation-classes descriptor)))
    (is (uiop:absolute-pathname-p
         (pathname (starlogicadapternprolog::nprolog-backend-executable backend))))
    (is (uiop:string-prefix-p
         "sha256:" (logic-backend-descriptor-build-id descriptor)))
    (format t "~&STARLANG_REAL_NPROLOG_VERSION=~A~%"
            (logic-backend-descriptor-version descriptor))
    (format t "STARLANG_REAL_NPROLOG_BUILD_ID=~A~%"
            (logic-backend-descriptor-build-id descriptor))
    (format t "STARLANG_REAL_NPROLOG_EXECUTABLE=~A~%"
            (starlogicadapternprolog::nprolog-backend-executable backend))))

(test package-expectation-fails-closed-before-worker-launch
  (let ((backend (fresh-backend))
        (starlogicadapternprolog::*last-owned-process* nil))
    (signals nprolog-package-unsupported-error
      (open-logic-session backend "integration-package"
                          :package-id "some.package"
                          :package-digest "sha256:0000000000000000000000000000000000000000000000000000000000000000"))
    (is (null starlogicadapternprolog::*last-owned-process*))))

(test real-worker-canary-health-and-clean-close
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
           (close-logic-session backend session)
           (setf session nil)
           (is (process-reaped-p process))
           (is (not (process-alive-p process)))
           (is (= 0 (or (process-exit-code process) -1))))
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

(test executable-replacement-fails-before-worker-launch
  (let* ((source (required-nprolog))
         (copy (uiop:merge-pathnames* "starlang-nprolog-copy"
                                      (uiop:ensure-directory-pathname
                                       (uiop:temporary-directory)))))
    (uiop:copy-file source copy)
    (let ((backend (make-nprolog-backend :nprolog-executable (namestring copy)))
          (starlogicadapternprolog::*last-owned-process* nil))
      (unwind-protect
           (progn
             ;; Replace the pinned bytes: identity must fail closed before any
             ;; worker is spawned.
             (with-open-file (out copy :direction :output
                                       :if-exists :supersede
                                       :if-does-not-exist :create)
               (write-string "not-npl" out))
             (signals nprolog-backend-identity-mismatch-error
               (open-logic-session backend "integration-replaced"))
             (is (null starlogicadapternprolog::*last-owned-process*)))
        (ignore-errors (delete-file copy))))))

(defun run-tests ()
  (run 'starlogicadapternprolog-integration-tests))
