(in-package :staripx)

(define-condition ipx-error (error)
  ((message :initarg :message :reader ipx-error-message))
  (:report
   (lambda (condition stream)
     (write-string (ipx-error-message condition) stream))))

(define-condition invalid-ipx-value-error (ipx-error) ())

(defun fail-ipx (control &rest arguments)
  (error 'invalid-ipx-value-error
         :message (apply #'format nil control arguments)))

(defun ensure-non-empty-string (value label)
  (unless (and (stringp value) (plusp (length value)))
    (fail-ipx "~A must be a non-empty string, received ~S." label value))
  (copy-seq value))

(defun ensure-non-negative-integer (value label)
  (unless (and (integerp value) (not (minusp value)))
    (fail-ipx "~A must be a non-negative integer, received ~S." label value))
  value)

(defstruct (ipx-evidence-ref
            (:constructor %make-ipx-evidence-ref
                (&key source-id record-offset byte-length digest)))
  (source-id "" :type string :read-only t)
  (record-offset 0 :type (integer 0 *) :read-only t)
  (byte-length 0 :type (integer 0 *) :read-only t)
  (digest "" :type string :read-only t))

(defun make-ipx-evidence-ref (source-id record-offset byte-length digest)
  "Reference an exact immutable byte range in operation-scoped capture custody."
  (%make-ipx-evidence-ref
   :source-id (ensure-non-empty-string source-id "source-id")
   :record-offset (ensure-non-negative-integer record-offset "record-offset")
   :byte-length (ensure-non-negative-integer byte-length "byte-length")
   :digest (ensure-non-empty-string digest "digest")))

(defun copy-evidence-ref (reference)
  (when reference
    (unless (ipx-evidence-ref-p reference)
      (fail-ipx "Expected an IPX evidence reference, received ~S." reference))
    (%make-ipx-evidence-ref
     :source-id (copy-seq (ipx-evidence-ref-source-id reference))
     :record-offset (ipx-evidence-ref-record-offset reference)
     :byte-length (ipx-evidence-ref-byte-length reference)
     :digest (copy-seq (ipx-evidence-ref-digest reference)))))

(defstruct (ipx-http-exchange
            (:constructor %make-ipx-http-exchange
                (&key operation-id capture-session-id exchange-id evidence-ref
                      timestamp-ms method scheme host port path query-ref
                      request-headers-ref request-body-ref response-status
                      response-headers-ref response-body-ref)))
  (operation-id "" :type string :read-only t)
  (capture-session-id "" :type string :read-only t)
  (exchange-id "" :type string :read-only t)
  (evidence-ref nil :read-only t)
  (timestamp-ms 0 :type (integer 0 *) :read-only t)
  (method "" :type string :read-only t)
  (scheme "" :type string :read-only t)
  (host "" :type string :read-only t)
  (port 0 :type (integer 0 65535) :read-only t)
  (path "" :type string :read-only t)
  (query-ref nil :read-only t)
  (request-headers-ref nil :read-only t)
  (request-body-ref nil :read-only t)
  (response-status 0 :type (integer 0 999) :read-only t)
  (response-headers-ref nil :read-only t)
  (response-body-ref nil :read-only t))

(defun optional-evidence-ref (reference label)
  (when (and reference (not (ipx-evidence-ref-p reference)))
    (fail-ipx "~A must be an IPX evidence reference or NIL, received ~S."
              label reference))
  (copy-evidence-ref reference))

(defun make-ipx-http-exchange
    (&key operation-id capture-session-id exchange-id evidence-ref timestamp-ms
          method scheme host port path query-ref request-headers-ref
          request-body-ref response-status response-headers-ref response-body-ref)
  "Build a passive HTTP exchange whose raw values remain in lossless capture custody.

Metadata needed for routing/correlation is carried directly. Query, header, and body
bytes are represented only by exact byte-range references; this layer never redacts,
rewrites, hashes-away, or substitutes the canonical captured evidence."
  (unless (ipx-evidence-ref-p evidence-ref)
    (fail-ipx "evidence-ref must identify the exact source capture record."))
  (unless (and (integerp port) (<= 1 port 65535))
    (fail-ipx "port must be an integer from 1 through 65535, received ~S." port))
  (unless (and (integerp response-status) (<= 0 response-status 999))
    (fail-ipx "response-status must be an integer from 0 through 999, received ~S."
              response-status))
  (%make-ipx-http-exchange
   :operation-id (ensure-non-empty-string operation-id "operation-id")
   :capture-session-id
   (ensure-non-empty-string capture-session-id "capture-session-id")
   :exchange-id (ensure-non-empty-string exchange-id "exchange-id")
   :evidence-ref (copy-evidence-ref evidence-ref)
   :timestamp-ms (ensure-non-negative-integer timestamp-ms "timestamp-ms")
   :method (ensure-non-empty-string method "method")
   :scheme (ensure-non-empty-string scheme "scheme")
   :host (ensure-non-empty-string host "host")
   :port port
   :path (ensure-non-empty-string path "path")
   :query-ref (optional-evidence-ref query-ref "query-ref")
   :request-headers-ref
   (optional-evidence-ref request-headers-ref "request-headers-ref")
   :request-body-ref (optional-evidence-ref request-body-ref "request-body-ref")
   :response-status response-status
   :response-headers-ref
   (optional-evidence-ref response-headers-ref "response-headers-ref")
   :response-body-ref (optional-evidence-ref response-body-ref "response-body-ref")))

(defun copy-http-exchange (exchange)
  (unless (ipx-http-exchange-p exchange)
    (fail-ipx "Expected an IPX HTTP exchange, received ~S." exchange))
  (%make-ipx-http-exchange
   :operation-id (copy-seq (ipx-http-exchange-operation-id exchange))
   :capture-session-id (copy-seq (ipx-http-exchange-capture-session-id exchange))
   :exchange-id (copy-seq (ipx-http-exchange-exchange-id exchange))
   :evidence-ref (copy-evidence-ref (ipx-http-exchange-evidence-ref exchange))
   :timestamp-ms (ipx-http-exchange-timestamp-ms exchange)
   :method (copy-seq (ipx-http-exchange-method exchange))
   :scheme (copy-seq (ipx-http-exchange-scheme exchange))
   :host (copy-seq (ipx-http-exchange-host exchange))
   :port (ipx-http-exchange-port exchange)
   :path (copy-seq (ipx-http-exchange-path exchange))
   :query-ref (copy-evidence-ref (ipx-http-exchange-query-ref exchange))
   :request-headers-ref
   (copy-evidence-ref (ipx-http-exchange-request-headers-ref exchange))
   :request-body-ref
   (copy-evidence-ref (ipx-http-exchange-request-body-ref exchange))
   :response-status (ipx-http-exchange-response-status exchange)
   :response-headers-ref
   (copy-evidence-ref (ipx-http-exchange-response-headers-ref exchange))
   :response-body-ref
   (copy-evidence-ref (ipx-http-exchange-response-body-ref exchange))))

(defun valid-http-exchange-p (exchange)
  (and (ipx-http-exchange-p exchange)
       (plusp (length (ipx-http-exchange-operation-id exchange)))
       (plusp (length (ipx-http-exchange-capture-session-id exchange)))
       (plusp (length (ipx-http-exchange-exchange-id exchange)))
       (ipx-evidence-ref-p (ipx-http-exchange-evidence-ref exchange))))

(defstruct ipx-submit-command exchange)
(defstruct ipx-index-command exchange)
(defstruct ipx-project-command exchange)
(defstruct ipx-read-command operation-id capture-session-id)

(defstruct (ipx-ingest-ack
            (:constructor %make-ipx-ingest-ack (status exchange-id)))
  (status :accepted :type keyword :read-only t)
  (exchange-id "" :type string :read-only t))

(defstruct (ipx-projection-snapshot
            (:constructor %make-ipx-projection-snapshot (exchanges)))
  (exchanges '() :type list :read-only t))

(defstruct (ipx-correlator-state
            (:constructor make-ipx-correlator-state (&optional (seen '()))))
  (seen '() :type list :read-only t))

(defstruct (ipx-projection-state
            (:constructor make-ipx-projection-state (&optional (exchanges '()))))
  (exchanges '() :type list :read-only t))

(defstruct (ipx-actor-system
            (:constructor %make-ipx-actor-system
                (&key runtime ingress-name correlator-name projection-name
                      owns-runtime-p)))
  runtime
  (ingress-name "" :type string :read-only t)
  (correlator-name "" :type string :read-only t)
  (projection-name "" :type string :read-only t)
  (owns-runtime-p nil :type boolean :read-only t))

(defun ipx-contract-valid-p (contract value)
  (case contract
    (:ipx-submit
     (and (ipx-submit-command-p value)
          (valid-http-exchange-p (ipx-submit-command-exchange value))))
    (:ipx-index
     (and (ipx-index-command-p value)
          (valid-http-exchange-p (ipx-index-command-exchange value))))
    (:ipx-project-or-read
     (or (and (ipx-project-command-p value)
              (valid-http-exchange-p (ipx-project-command-exchange value)))
         (ipx-read-command-p value)))
    (:ipx-ingest-ack (ipx-ingest-ack-p value))
    (:ipx-projection-result
     (or (ipx-ingest-ack-p value)
         (ipx-projection-snapshot-p value)))
    (otherwise nil)))

(defun exchange-key (exchange)
  (list (ipx-http-exchange-operation-id exchange)
        (ipx-http-exchange-capture-session-id exchange)
        (ipx-http-exchange-exchange-id exchange)))

(defun projection-matches-p (exchange command)
  (and
   (or (null (ipx-read-command-operation-id command))
       (equal (ipx-read-command-operation-id command)
              (ipx-http-exchange-operation-id exchange)))
   (or (null (ipx-read-command-capture-session-id command))
       (equal (ipx-read-command-capture-session-id command)
              (ipx-http-exchange-capture-session-id exchange)))))

(defun make-projection-actor-definition (name mailbox-capacity)
  (starlangruntime:make-native-actor-definition
   name
   (lambda (message state runtime)
     (declare (ignore runtime))
     (typecase message
       (ipx-project-command
        (let ((exchange (copy-http-exchange (ipx-project-command-exchange message))))
          (values
           (%make-ipx-ingest-ack :projected
                                 (copy-seq (ipx-http-exchange-exchange-id exchange)))
           (make-ipx-projection-state
            (cons exchange (ipx-projection-state-exchanges state))))))
       (ipx-read-command
        (let ((matches
                (remove-if-not
                 (lambda (exchange) (projection-matches-p exchange message))
                 (ipx-projection-state-exchanges state))))
          (values
           (%make-ipx-projection-snapshot
            (mapcar #'copy-http-exchange (reverse matches)))
           state)))
       (otherwise
        (fail-ipx "Projection actor received unsupported message ~S." message))))
   :accepts :ipx-project-or-read
   :produces :ipx-projection-result
   :input-validator #'ipx-contract-valid-p
   :output-validator #'ipx-contract-valid-p
   :initial-state #'make-ipx-projection-state
   :mailbox-capacity mailbox-capacity
   :metadata '(:subsystem :ipx :role :projection)))

(defun make-correlator-actor-definition (name projection-name mailbox-capacity)
  (starlangruntime:make-native-actor-definition
   name
   (lambda (message state runtime)
     (let* ((exchange (ipx-index-command-exchange message))
            (key (exchange-key exchange)))
       (if (member key (ipx-correlator-state-seen state) :test #'equal)
           (values
            (%make-ipx-ingest-ack
             :duplicate (copy-seq (ipx-http-exchange-exchange-id exchange)))
            state)
           (let ((projection-ack
                   (starlangruntime:ask
                    runtime
                    projection-name
                    (make-ipx-project-command :exchange (copy-http-exchange exchange)))))
             (unless (and (ipx-ingest-ack-p projection-ack)
                          (eq :projected (ipx-ingest-ack-status projection-ack)))
               (fail-ipx "Projection actor did not commit exchange ~A."
                         (ipx-http-exchange-exchange-id exchange)))
             (values
              (%make-ipx-ingest-ack
               :accepted (copy-seq (ipx-http-exchange-exchange-id exchange)))
              (make-ipx-correlator-state
               (cons key (ipx-correlator-state-seen state))))))))
   :accepts :ipx-index
   :produces :ipx-ingest-ack
   :input-validator #'ipx-contract-valid-p
   :output-validator #'ipx-contract-valid-p
   :initial-state #'make-ipx-correlator-state
   :mailbox-capacity mailbox-capacity
   :metadata '(:subsystem :ipx :role :correlator)))

(defun make-ingress-actor-definition (name correlator-name mailbox-capacity)
  (starlangruntime:make-native-actor-definition
   name
   (lambda (message state runtime)
     (values
      (starlangruntime:ask
       runtime
       correlator-name
       (make-ipx-index-command
        :exchange (copy-http-exchange (ipx-submit-command-exchange message))))
      state))
   :accepts :ipx-submit
   :produces :ipx-ingest-ack
   :input-validator #'ipx-contract-valid-p
   :output-validator #'ipx-contract-valid-p
   :initial-state nil
   :mailbox-capacity mailbox-capacity
   :metadata '(:subsystem :ipx :role :ingress)))

(defun start-ipx-actor-system
    (&key runtime (name-prefix "ipx") (mailbox-capacity 128))
  "Create the deterministic IPX ingress -> correlator -> projection topology."
  (let* ((owns-runtime-p (null runtime))
         (actor-runtime (or runtime (starlangruntime:make-runtime)))
         (prefix (ensure-non-empty-string name-prefix "name-prefix"))
         (projection-name (format nil "~A-projection" prefix))
         (correlator-name (format nil "~A-correlator" prefix))
         (ingress-name (format nil "~A-ingress" prefix)))
    (unless (and (integerp mailbox-capacity) (plusp mailbox-capacity))
      (fail-ipx "mailbox-capacity must be a positive integer, received ~S."
                mailbox-capacity))
    (starlangruntime:create-actor
     actor-runtime
     (make-projection-actor-definition projection-name mailbox-capacity))
    (starlangruntime:create-actor
     actor-runtime
     (make-correlator-actor-definition
      correlator-name projection-name mailbox-capacity))
    (starlangruntime:create-actor
     actor-runtime
     (make-ingress-actor-definition ingress-name correlator-name mailbox-capacity))
    (%make-ipx-actor-system
     :runtime actor-runtime
     :ingress-name ingress-name
     :correlator-name correlator-name
     :projection-name projection-name
     :owns-runtime-p owns-runtime-p)))

(defun submit-ipx-exchange (system exchange)
  "Submit one exchange through the real StarLang mailbox path."
  (check-type system ipx-actor-system)
  (unless (valid-http-exchange-p exchange)
    (fail-ipx "Expected a valid IPX HTTP exchange, received ~S." exchange))
  (starlangruntime:ask
   (ipx-actor-system-runtime system)
   (ipx-actor-system-ingress-name system)
   (make-ipx-submit-command :exchange (copy-http-exchange exchange))))

(defun ipx-system-projections
    (system &key operation-id capture-session-id)
  "Read an immutable snapshot through the projection actor mailbox."
  (check-type system ipx-actor-system)
  (starlangruntime:ask
   (ipx-actor-system-runtime system)
   (ipx-actor-system-projection-name system)
   (make-ipx-read-command
    :operation-id (and operation-id
                       (ensure-non-empty-string operation-id "operation-id"))
    :capture-session-id
    (and capture-session-id
         (ensure-non-empty-string capture-session-id "capture-session-id")))))

(defun shutdown-ipx-actor-system (system)
  (check-type system ipx-actor-system)
  (let ((runtime (ipx-actor-system-runtime system)))
    (if (ipx-actor-system-owns-runtime-p system)
        (starlangruntime:shutdown-runtime runtime)
        (dolist (name (list (ipx-actor-system-ingress-name system)
                            (ipx-actor-system-correlator-name system)
                            (ipx-actor-system-projection-name system))
                      :stopped)
          (let ((actor (starlangruntime:find-actor runtime name)))
            (when (and actor (starlangruntime:actor-running-p actor))
              (starlangruntime:stop-actor runtime actor)))))))
