(in-package :starlogicadapterswi)

(defstruct (swi-backend (:constructor %make-swi-backend))
  executable
  version
  version-banner
  version-triplet
  build-id
  bootstrap-path
  bootstrap-digest
  descriptor
  (sessions '()))

(defstruct (swi-session (:constructor %make-swi-session))
  id
  backend
  worker
  (state :opening))

(defun make-swi-backend (&key swipl-executable)
  "Create a SWI backend pinned to one exact executable path.

There is deliberately no PATH lookup fallback. BUILD-ID is SHA-256 over the
resolved executable bytes; under Nix the exact store executable is also retained
in descriptor metadata."
  (multiple-value-bind (executable version-banner version-triplet build-id)
      (%identify-executable swipl-executable)
    (let* ((bootstrap-path (%trusted-bootstrap-path))
           (bootstrap-digest (%sha256-file bootstrap-path))
           (version (format nil "~{~D~^.~}" version-triplet))
           (backend (%make-swi-backend
                     :executable executable
                     :version version
                     :version-banner version-banner
                     :version-triplet version-triplet
                     :build-id build-id
                     :bootstrap-path bootstrap-path
                     :bootstrap-digest bootstrap-digest)))
      (setf (swi-backend-descriptor backend)
            (make-logic-backend-descriptor
             :id +logic-backend-swi-prolog+
             :version version
             :build-id build-id
             ;; Lifecycle/build conformance is not semantic query conformance.
             ;; Empty profiles/capabilities keep this backend out of :auto until
             ;; later STAR-LANG-011 slices prove those semantics.
             :semantic-profiles '()
             :capabilities '()
             :isolation-classes '("process")
             :hard-limits '()
             :cooperative-limits '()
             :metadata
             (list :adapter-version +swi-adapter-version+
                   :engine-name "SWI-Prolog"
                   :executable executable
                   :version-banner version-banner
                   :mqi-client-version
                   (list +supported-mqi-major+ +supported-mqi-minor+)
                   :bootstrap-id +bootstrap-id+
                   :bootstrap-digest bootstrap-digest)))
      backend)))

(defmethod logic-backend-descriptor-of ((backend swi-backend))
  (swi-backend-descriptor backend))

(defun %validate-package-expectation (backend package-id package-digest)
  (cond
    ((and (null package-id) (null package-digest)) t)
    ((or (null package-id) (null package-digest))
     (%swi-fail 'swi-bootstrap-package-mismatch-error
                "Package ID and digest must either both be absent or both match the trusted bootstrap."))
    ((not (and (string= package-id +bootstrap-id+)
               (string= package-digest (swi-backend-bootstrap-digest backend))))
     (%swi-fail 'swi-bootstrap-package-mismatch-error
                "This slice accepts only the exact trusted StarLang SWI bootstrap package."))
    (t t)))

(defun %validate-bootstrap-identity (backend)
  "Re-hash the exact trusted bootstrap immediately before worker launch."
  (let ((observed-digest (%sha256-file (swi-backend-bootstrap-path backend))))
    (unless (string= observed-digest (swi-backend-bootstrap-digest backend))
      (%swi-fail 'swi-bootstrap-package-mismatch-error
                 "Trusted SWI bootstrap bytes changed after backend construction.")))
  t)

(defmethod open-logic-session ((backend swi-backend) session-id
                               &key package-id package-digest)
  (%validate-package-expectation backend package-id package-digest)
  (unless (and (stringp session-id) (plusp (length session-id)))
    (%swi-fail 'swi-bootstrap-handshake-error
               "Logic session ID must be a non-empty string."))
  ;; Fail closed if either executable or trusted package bytes changed after
  ;; backend construction. Both checks happen before any worker is spawned.
  (%validate-bootstrap-identity backend)
  (multiple-value-bind (executable banner triplet build-id)
      (%identify-executable (swi-backend-executable backend))
    (declare (ignore banner))
    (unless (and (string= executable (swi-backend-executable backend))
                 (equal triplet (swi-backend-version-triplet backend))
                 (string= build-id (swi-backend-build-id backend)))
      (%swi-fail 'swi-backend-identity-mismatch-error
                 "SWI executable identity changed after backend construction.")))
  (let ((session (%make-swi-session :id (copy-seq session-id)
                                    :backend backend)))
    (handler-case
        (progn
          (setf (swi-session-worker session)
                (%open-swi-worker
                 (swi-backend-executable backend)
                 (swi-backend-version-triplet backend)
                 (swi-backend-bootstrap-path backend))
                (swi-session-state session) :open)
          (push session (swi-backend-sessions backend))
          session)
      (swi-adapter-error (cause)
        (setf (swi-session-state session) :failed)
        (error cause))
      (error (cause)
        (setf (swi-session-state session) :failed)
        (%swi-fail-diagnostic
         'swi-bootstrap-handshake-error
         (%bounded-diagnostic cause)
         "SWI session open failed.")))))

(defmethod close-logic-session ((backend swi-backend) (session swi-session))
  (unless (eq backend (swi-session-backend session))
    (%swi-fail 'swi-shutdown-failure-error
               "Logic session is not owned by this SWI backend."))
  (case (swi-session-state session)
    (:closed t)
    (otherwise
     (setf (swi-session-state session) :closing)
     (unwind-protect
          (%orderly-shutdown-worker (swi-session-worker session))
       (setf (swi-session-state session) :closed
             (swi-backend-sessions backend)
             (delete session (swi-backend-sessions backend) :test #'eq))))))

(defun %active-session-health (session)
  (let* ((worker (swi-session-worker session))
         (process (and worker (swi-worker-process worker))))
    (list :session-id (swi-session-id session)
          :state (swi-session-state session)
          :worker-alive (and process (process-alive-p process))
          :mqi-version (and worker
                            (list (swi-worker-mqi-major worker)
                                  (swi-worker-mqi-minor worker))))))

(defmethod logic-backend-health ((backend swi-backend))
  (handler-case
      (multiple-value-bind (executable banner triplet build-id)
          (%identify-executable (swi-backend-executable backend))
        (declare (ignore banner))
        (let* ((sessions (mapcar #'%active-session-health
                                 (swi-backend-sessions backend)))
               (identity-ok
                 (and (string= executable (swi-backend-executable backend))
                      (equal triplet (swi-backend-version-triplet backend))
                      (string= build-id (swi-backend-build-id backend))
                      (string= (%sha256-file (swi-backend-bootstrap-path backend))
                               (swi-backend-bootstrap-digest backend))))
               (workers-ok
                 (every (lambda (entry) (getf entry :worker-alive)) sessions)))
          (list :status (if (and identity-ok workers-ok) :usable :unusable)
                :backend-id +logic-backend-swi-prolog+
                :backend-version (swi-backend-version backend)
                :backend-build-id (swi-backend-build-id backend)
                :adapter-version +swi-adapter-version+
                :executable (swi-backend-executable backend)
                :isolation "process"
                :active-sessions (length sessions)
                :sessions sessions)))
    (error (cause)
      (list :status :unusable
            :backend-id +logic-backend-swi-prolog+
            :diagnostic (%bounded-diagnostic cause)))))
