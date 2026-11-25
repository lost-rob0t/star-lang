(in-package :starlogicadapternprolog)

(defstruct (nprolog-backend (:constructor %make-nprolog-backend))
  executable
  version
  version-banner
  version-pair
  build-id
  bridge-path
  bridge-digest
  descriptor
  (sessions '()))

(defstruct (nprolog-session (:constructor %make-nprolog-session))
  id
  backend
  worker
  (state :opening))

(defun make-nprolog-backend (&key nprolog-executable)
  "Create an N-Prolog backend pinned to one exact executable and one exact
bridge file.

There is deliberately no PATH lookup fallback for either. BUILD-ID is
SHA-256 over the resolved executable bytes; BRIDGE-DIGEST is SHA-256 over
the shipped bridge file, which is the only in-engine code this adapter owns
and the package identity its sessions publish. Under Nix the exact store
executable is also retained in descriptor metadata."
  (multiple-value-bind (executable banner major minor version build-id)
      (%identify-executable nprolog-executable)
    (let* ((bridge-path (%bridge-path))
           (bridge-digest (%sha256-file bridge-path))
           (backend
             (%make-nprolog-backend
              :executable executable
              :version version
              :version-banner banner
              :version-pair (list major minor)
              :build-id build-id
              :bridge-path bridge-path
              :bridge-digest bridge-digest))
           (descriptor
             (make-logic-backend-descriptor
               :id +logic-backend-n-prolog+
               :version version
               :build-id build-id
               ;; Lifecycle/build conformance is not semantic query
               ;; conformance. Empty profiles/capabilities keep this backend
               ;; out of :auto until query slices prove those semantics; the
               ;; transport conformance of this slice does not change that.
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
                     :package-id +star-logic-bridge-package-id+
                     :package-digest bridge-digest
                     :bridge-path bridge-path
                     :wire-protocol +star-logic-bridge-protocol+
                     :transport "socket-bridge"
                     :launch-argv (%nprolog-launch-argv)))))
      (setf (nprolog-backend-descriptor backend) descriptor)
      backend)))

(defmethod logic-backend-descriptor-of ((backend nprolog-backend))
  (nprolog-backend-descriptor backend))

;; Sessions may pin the bridge package explicitly, or open with the implicit
;; bridge identity. Anything else fails closed: no silently ignored
;; expectations.
(defun %validate-package-expectation (backend package-id package-digest)
  (let ((bridge-digest (nprolog-backend-bridge-digest backend)))
    (cond
      ((and (null package-id) (null package-digest)) t)
      ((and (stringp package-id)
            (string= package-id +star-logic-bridge-package-id+)
            (stringp package-digest)
            (string= package-digest bridge-digest)) t)
      (t
       (%nprolog-fail 'nprolog-package-mismatch-error
                      "Package expectation ~S/~S does not match the pinned ~S bridge digest ~S."
                      package-id package-digest
                      +star-logic-bridge-package-id+ bridge-digest)))))

(defun %validate-backend-identity (backend)
  "Re-identify the exact executable and bridge file immediately before
worker launch."
  (multiple-value-bind (executable banner major minor version build-id)
      (%identify-executable (nprolog-backend-executable backend))
    (declare (ignore banner))
    (let ((bridge-path (%bridge-path))
          (bridge-digest (%sha256-file bridge-path)))
      (unless (and (string= executable (nprolog-backend-executable backend))
                   (equal (list major minor) (nprolog-backend-version-pair backend))
                   (string= version (nprolog-backend-version backend))
                   (string= build-id (nprolog-backend-build-id backend))
                   (string= bridge-digest (nprolog-backend-bridge-digest backend)))
        (%nprolog-fail 'nprolog-backend-identity-mismatch-error
                       "N-Prolog executable or bridge identity changed after backend construction."))))
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
                 (nprolog-backend-version-pair backend)
                 (nprolog-backend-bridge-path backend)))
          (setf (nprolog-session-state session) :open)
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
         (process (and worker (nprolog-worker-process worker)))
         (stream (and worker (nprolog-worker-stream worker))))
    (list :session-id (nprolog-session-id session)
          :state (nprolog-session-state session)
          :worker-alive (and process (process-alive-p process))
          :bridge-open (and stream (open-stream-p stream))
          :bridge-port (and worker (nprolog-worker-port worker)))))

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
                      (string= build-id (nprolog-backend-build-id backend))
                      (string= (%sha256-file (nprolog-backend-bridge-path backend))
                               (nprolog-backend-bridge-digest backend))))
               (workers-ok
                 (every (lambda (entry) (getf entry :worker-alive)) sessions)))
          (list :status (if (and identity-ok workers-ok) :usable :unusable)
                :backend-id +logic-backend-n-prolog+
                :backend-version (nprolog-backend-version backend)
                :backend-build-id (nprolog-backend-build-id backend)
                :adapter-version +nprolog-adapter-version+
                :executable (nprolog-backend-executable backend)
                :bridge-digest (nprolog-backend-bridge-digest backend)
                :isolation "process"
                :active-sessions (length sessions)
                :sessions sessions)))
    (error (cause)
      (list :status :unusable
            :backend-id +logic-backend-n-prolog+
            :diagnostic (%bounded-diagnostic cause)))))
