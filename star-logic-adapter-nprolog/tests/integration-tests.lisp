(defpackage :starlogicadapternprolog-integration-tests
  (:use :cl :fiveam)
  (:import-from :starlogicadapternprolog
                #:make-nprolog-backend
                #:nprolog-backend-identity-mismatch-error
                #:nprolog-package-mismatch-error)
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

(defun worker-stream (session)
  (starlogicadapternprolog::nprolog-worker-stream
   (starlogicadapternprolog::nprolog-session-worker session)))

(test descriptor-is-honest-and-exact
  (let* ((backend (fresh-backend))
         (descriptor (logic-backend-descriptor-of backend))
         (metadata (starlogicprotocol::logic-backend-descriptor-metadata descriptor)))
    (is (string= "n-prolog" (logic-backend-descriptor-id descriptor)))
    (is (null (logic-backend-descriptor-semantic-profiles descriptor)))
    (is (null (logic-backend-descriptor-capabilities descriptor)))
    (is (equal '("process")
               (logic-backend-descriptor-isolation-classes descriptor)))
    (is (uiop:absolute-pathname-p
         (pathname (starlogicadapternprolog::nprolog-backend-executable backend))))
    (is (uiop:string-prefix-p
         "sha256:" (logic-backend-descriptor-build-id descriptor)))
    ;; The bridge is the only in-engine code this adapter owns; its package
    ;; identity is published, its transport is described, and nothing else.
    (is (string= "star-logic-bridge" (getf metadata :package-id)))
    (is (string= (starlogicadapternprolog::nprolog-backend-bridge-digest backend)
                 (getf metadata :package-digest)))
    (is (string= "star-logic-nprolog-bridge-1" (getf metadata :wire-protocol)))
    (is (string= "socket-bridge" (getf metadata :transport)))
    (format t "~&STARLANG_REAL_NPROLOG_VERSION=~A~%"
            (logic-backend-descriptor-version descriptor))
    (format t "STARLANG_REAL_NPROLOG_BUILD_ID=~A~%"
            (logic-backend-descriptor-build-id descriptor))
    (format t "STARLANG_REAL_NPROLOG_BRIDGE_DIGEST=~A~%"
            (starlogicadapternprolog::nprolog-backend-bridge-digest backend))))

(test package-mismatch-fails-before-worker-launch
  (let ((backend (fresh-backend))
        (starlogicadapternprolog::*last-owned-process* nil))
    (signals nprolog-package-mismatch-error
      (open-logic-session backend "integration-package"
                          :package-id "star-logic-bridge"
                          :package-digest "sha256:0000000000000000000000000000000000000000000000000000000000000000"))
    (is (null starlogicadapternprolog::*last-owned-process*))
    (signals nprolog-package-mismatch-error
      (open-logic-session backend "integration-package"
                          :package-id "unknown.package"))))

(test bridge-digest-mismatch-fails-before-worker-launch
  (let ((backend (fresh-backend))
        (starlogicadapternprolog::*last-owned-process* nil))
    (setf (starlogicadapternprolog::nprolog-backend-bridge-digest backend)
          "sha256:0000000000000000000000000000000000000000000000000000000000000000")
    (signals nprolog-backend-identity-mismatch-error
      (open-logic-session backend "integration-tampered-bridge"))
    (is (null starlogicadapternprolog::*last-owned-process*))))

(test real-bridge-session-handshake-ping-and-clean-close
  (let* ((backend (fresh-backend))
         (session nil)
         (process nil))
    (unwind-protect
         (progn
           (setf session (open-logic-session backend "integration-1")
                 process (worker-process session))
           (is (process-alive-p process))
           (is (not (null (worker-stream session))))
           ;; Handshake already ran during open; ping proves live lock-step.
           (is (string= "pong"
                        (starlogicadapternprolog::%bridge-exchange
                         (worker-stream session) process "ping")))
           (let ((health (logic-backend-health backend)))
             (is (eq :usable (getf health :status)))
             (is (= 1 (getf health :active-sessions)))
             (is (string= (starlogicadapternprolog::nprolog-backend-bridge-digest
                           backend)
                          (getf health :bridge-digest))))
           (close-logic-session backend session)
           (setf session nil)
           (is (process-reaped-p process))
           (is (not (process-alive-p process)))
           (is (= 0 (process-exit-code process))))
      (when session
        (ignore-errors (close-logic-session backend session))))))

(test second-fresh-session-does-not-reuse-worker-or-port
  (let* ((backend (fresh-backend))
         (first-session (open-logic-session backend "integration-first"))
         (first-process (worker-process first-session))
         (first-port (starlogicadapternprolog::nprolog-worker-port
                      (starlogicadapternprolog::nprolog-session-worker
                       first-session))))
    (unwind-protect
         (progn
           (close-logic-session backend first-session)
           (setf first-session nil)
           (is (process-reaped-p first-process))
           (let* ((second-session (open-logic-session backend "integration-second"))
                  (second-process (worker-process second-session))
                  (second-port (starlogicadapternprolog::nprolog-worker-port
                                (starlogicadapternprolog::nprolog-session-worker
                                 second-session))))
             (unwind-protect
                  (progn
                    (is (not (eq first-process second-process)))
                    (is (/= first-port second-port))
                    (is (process-alive-p second-process)))
               (close-logic-session backend second-session)
               (is (process-reaped-p second-process)))))
       (when first-session
         (ignore-errors (close-logic-session backend first-session))))))

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
