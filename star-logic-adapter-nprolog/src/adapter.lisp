(in-package :starlogicadapternprolog)

(defstruct (nprolog-backend (:constructor %make-nprolog-backend))
  executable
  version
  version-banner
  version-pair
  build-id
  descriptor
  (sessions '()))

(defstruct (nprolog-session (:constructor %make-nprolog-session))
  id
  backend
  worker
  (state :opening))

(defun make-nprolog-backend (&key nprolog-executable)
  "Create an N-Prolog backend pinned to one exact executable path.

There is deliberately no PATH lookup fallback. BUILD-ID is SHA-256 over the
resolved executable bytes; under Nix the exact store executable is also
retained in descriptor metadata."
  (multiple-value-bind (executable banner major minor version build-id)
      (%identify-executable nprolog-executable)
    (let* ((backend
             (%make-nprolog-backend
              :executable executable
              :version version
              :version-banner banner
              :version-pair (list major minor)
              :build-id build-id))
            (descriptor
              (make-logic-backend-descriptor
               :id +logic-backend-n-prolog+
               :version version
               :build-id build-id
               ;; Lifecycle/build conformance is not semantic query conformance.
               ;; Empty profiles/capabilities keep this backend out of :auto
               ;; until later slices prove those semantics.
               :semantic-profiles '()
               :capabilities '()
               :isolation-classes '("process")
               :hard-limits '()
               :cooperative-limits '()
               :metadata
               (list :adapter-version +nprolog-adapter-version+
                     :engine-name "N-Prolog"
                     :engine-upstream +nprolog-engine-upstream+
                     :executable executable
                     :version-banner banner
                     :version-pair (list major minor)
                     :repl-mode "plain"
                     :launch-argv (copy-list +nprolog-repl-launch-argv+)))))
      (setf (nprolog-backend-descriptor backend) descriptor)
      backend)))

(defmethod logic-backend-descriptor-of ((backend nprolog-backend))
  (nprolog-backend-descriptor backend))

;; This foundation slice publishes no trusted package identity: the plain REPL
;; boundary has no protocol negotiation yet. Any package expectation fails
;; closed instead of being silently ignored.
(defun %validate-package-expectation (backend package-id package-digest)
  (declare (ignore backend))
  (when (or package-id package-digest)
    (%nprolog-fail 'nprolog-package-unsupported-error
                   "This slice publishes no trusted N-Prolog package identity; session opens must not carry package expectations."))
  t)

(defun %validate-backend-identity (backend)
  "Re-identify the exact executable immediately before worker launch."
  (multiple-value-bind (executable banner major minor version build-id)
      (%identify-executable (nprolog-backend-executable backend))
    (declare (ignore banner))
    (unless (and (string= executable (nprolog-backend-executable backend))
                 (equal (list major minor) (nprolog-backend-version-pair backend))
                 (string= version (nprolog-backend-version backend))
                 (string= build-id (nprolog-backend-build-id backend)))
      (%nprolog-fail 'nprolog-backend-identity-mismatch-error
                     "N-Prolog executable identity changed after backend construction.")))
  t)

(defmethod open-logic-session ((backend nprolog-backend) session-id
                               &key package-id package-digest)
  (%validate-package-expectation backend package-id package-digest)
  (unless (and (stringp session-id) (plusp (length session-id)))
    (%nprolog-fail 'nprolog-handshake-error
                   "Logic session ID must be a non-empty string."))
  (%validate-backend-identity backend)
  (let ((session (%make-nprolog-session :id (copy-seq session-id)
                                        :backend backend)))
    (handler-case
        (progn
          (setf (nprolog-session-worker session)
                (%open-nprolog-worker
                 (nprolog-backend-executable backend)
                 (nprolog-backend-version-pair backend))
                (nprolog-session-state session) :open)
          (push session (nprolog-backend-sessions backend))
          session)
      (nprolog-adapter-error (cause)
        (setf (nprolog-session-state session) :failed)
        (error cause))
      (error (cause)
        (setf (nprolog-session-state session) :failed)
        (%nprolog-fail-diagnostic
         'nprolog-worker-launch-error
         (%bounded-diagnostic cause)
         "N-Prolog session open failed.")))))

(defmethod close-logic-session ((backend nprolog-backend) (session nprolog-session))
  (unless (eq backend (nprolog-session-backend session))
    (%nprolog-fail 'nprolog-shutdown-failure-error
                   "Logic session is not owned by this N-Prolog backend."))
  (case (nprolog-session-state session)
    (:closed t)
    (otherwise
     (setf (nprolog-session-state session) :closing)
     (unwind-protect
          (progn
            (%orderly-shutdown-worker (nprolog-session-worker session)))
       (setf (nprolog-session-state session) :closed
             (nprolog-backend-sessions backend)
             (delete session (nprolog-backend-sessions backend) :test #'eq)))
     t)))

(defun %active-session-health (session)
  (let* ((worker (nprolog-session-worker session))
         (process (and worker (nprolog-worker-process worker))))
    (list :session-id (nprolog-session-id session)
          :state (nprolog-session-state session)
          :worker-alive (and process (process-alive-p process)))))

(defmethod logic-backend-health ((backend nprolog-backend))
  (handler-case
      (multiple-value-bind (executable banner major minor version build-id)
          (%identify-executable (nprolog-backend-executable backend))
        (declare (ignore banner major minor))
        (let* ((sessions (mapcar #'%active-session-health
                                 (nprolog-backend-sessions backend)))
               (identity-ok
                 (and (string= executable (nprolog-backend-executable backend))
                      (string= version (nprolog-backend-version backend))
                      (string= build-id (nprolog-backend-build-id backend))))
               (workers-ok
                 (every (lambda (entry) (getf entry :worker-alive)) sessions)))
          (list :status (if (and identity-ok workers-ok) :usable :unusable)
                :backend-id +logic-backend-n-prolog+
                :backend-version (nprolog-backend-version backend)
                :backend-build-id (nprolog-backend-build-id backend)
                :adapter-version +nprolog-adapter-version+
                :executable (nprolog-backend-executable backend)
                :isolation "process"
                :active-sessions (length sessions)
                :sessions sessions)))
    (error (cause)
      (list :status :unusable
            :backend-id +logic-backend-n-prolog+
            :diagnostic (%bounded-diagnostic cause)))))
