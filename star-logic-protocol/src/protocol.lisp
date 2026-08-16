(in-package :starlogicprotocol)

(defconstant +logic-backend-lisa+ "lisa")
(defconstant +logic-backend-swi-prolog+ "swi-prolog")
(defconstant +logic-backend-n-prolog+ "n-prolog")

(defconstant +logic-operation-pending+ :pending)
(defconstant +logic-operation-running+ :running)
(defconstant +logic-operation-completed+ :completed)
(defconstant +logic-operation-no-answer+ :no-answer)
(defconstant +logic-operation-cancelled+ :cancelled)
(defconstant +logic-operation-failed+ :failed)

(define-condition star-logic-error (error)
  ((message :initarg :message :reader star-logic-error-message))
  (:report (lambda (condition stream)
             (format stream "~A" (slot-value condition 'message)))))

(define-condition invalid-logic-backend-descriptor-error (star-logic-error) ())
(define-condition duplicate-logic-backend-error (star-logic-error) ())
(define-condition logic-backend-not-found-error (star-logic-error) ())
(define-condition logic-backend-incompatible-error (star-logic-error) ())
(define-condition logic-backend-selection-error (star-logic-error) ())
(define-condition unsupported-logic-operation-error (star-logic-error) ())
(define-condition logic-session-error (star-logic-error) ())

(defun %fail (condition-type control &rest arguments)
  (error condition-type :message (apply #'format nil control arguments)))

(defun %non-empty-string-p (value)
  (and (stringp value) (plusp (length value))))

(defun %require-non-empty-string (value field)
  (unless (%non-empty-string-p value)
    (%fail 'invalid-logic-backend-descriptor-error
           "~A must be a non-empty string, got ~S."
           field value))
  value)

(defun %normalize-string-list (values field)
  (unless (listp values)
    (%fail 'invalid-logic-backend-descriptor-error
           "~A must be a list of strings, got ~S."
           field values))
  (dolist (value values)
    (unless (%non-empty-string-p value)
      (%fail 'invalid-logic-backend-descriptor-error
             "~A contains an invalid value ~S."
             field value)))
  (sort (remove-duplicates (copy-list values) :test #'string=) #'string<))

(defstruct (logic-backend-descriptor
            (:constructor %make-logic-backend-descriptor))
  id
  version
  build-id
  semantic-profiles
  capabilities
  isolation-classes
  hard-limits
  cooperative-limits
  metadata)

(defun make-logic-backend-descriptor
    (&key id
          version
          build-id
          semantic-profiles
          capabilities
          isolation-classes
          hard-limits
          cooperative-limits
          metadata)
  (%make-logic-backend-descriptor
   :id (%require-non-empty-string id "backend id")
   :version (%require-non-empty-string version "backend version")
   :build-id (%require-non-empty-string build-id "backend build id")
   :semantic-profiles (%normalize-string-list semantic-profiles "semantic profiles")
   :capabilities (%normalize-string-list capabilities "capabilities")
   :isolation-classes (%normalize-string-list isolation-classes "isolation classes")
   :hard-limits (%normalize-string-list hard-limits "hard limits")
   :cooperative-limits (%normalize-string-list cooperative-limits "cooperative limits")
   :metadata metadata))

(defstruct (logic-backend-registry
            (:constructor %make-logic-backend-registry))
  (table (make-hash-table :test #'equal)))

(defun make-logic-backend-registry ()
  (%make-logic-backend-registry))

(defgeneric logic-backend-descriptor-of (backend))

(defmethod logic-backend-descriptor-of ((backend logic-backend-descriptor))
  backend)

(defun register-logic-backend (registry backend &key replace)
  (check-type registry logic-backend-registry)
  (let* ((descriptor (logic-backend-descriptor-of backend))
         (id (logic-backend-descriptor-id descriptor))
         (table (logic-backend-registry-table registry)))
    (when (and (gethash id table) (not replace))
      (%fail 'duplicate-logic-backend-error
             "Logic backend ~S is already registered."
             id))
    (setf (gethash id table) backend)
    backend))

(defun unregister-logic-backend (registry backend-id)
  (check-type registry logic-backend-registry)
  (remhash backend-id (logic-backend-registry-table registry)))

(defun find-logic-backend (registry backend-id)
  (check-type registry logic-backend-registry)
  (gethash backend-id (logic-backend-registry-table registry)))

(defun list-logic-backends (registry)
  (check-type registry logic-backend-registry)
  (let ((backends '()))
    (maphash (lambda (id backend)
               (declare (ignore id))
               (push backend backends))
             (logic-backend-registry-table registry))
    (sort backends
          #'string<
          :key (lambda (backend)
                 (logic-backend-descriptor-id
                  (logic-backend-descriptor-of backend))))))

(defstruct (logic-selection-request
            (:constructor %make-logic-selection-request))
  backend-policy
  semantic-profile
  required-capabilities
  required-hard-limits
  required-isolation)

(defun make-logic-selection-request
    (&key
       (backend-policy "auto")
       semantic-profile
       required-capabilities
       required-hard-limits
       required-isolation)
  (unless (%non-empty-string-p backend-policy)
    (%fail 'logic-backend-selection-error
           "Backend policy must be a non-empty string, got ~S."
           backend-policy))
  (unless (%non-empty-string-p semantic-profile)
    (%fail 'logic-backend-selection-error
           "Semantic profile must be a non-empty string, got ~S."
           semantic-profile))
  (when (and required-isolation
             (not (%non-empty-string-p required-isolation)))
    (%fail 'logic-backend-selection-error
           "Required isolation must be NIL or a non-empty string, got ~S."
           required-isolation))
  (%make-logic-selection-request
   :backend-policy backend-policy
   :semantic-profile semantic-profile
   :required-capabilities (%normalize-string-list
                           required-capabilities
                           "required capabilities")
   :required-hard-limits (%normalize-string-list
                          required-hard-limits
                          "required hard limits")
   :required-isolation required-isolation))

(defstruct logic-selection-candidate
  backend-id
  status
  reason)

(defstruct logic-selection-evidence
  requested
  semantic-profile
  required-capabilities
  required-hard-limits
  required-isolation
  candidates
  selected
  policy)

(defun %subsetp-strings (required available)
  (every (lambda (item)
           (member item available :test #'string=))
         required))

(defun %candidate-rejection-reason (descriptor request)
  (cond
    ((not (member (logic-selection-request-semantic-profile request)
                  (logic-backend-descriptor-semantic-profiles descriptor)
                  :test #'string=))
     "semantic profile unavailable")
    ((not (%subsetp-strings
           (logic-selection-request-required-capabilities request)
           (logic-backend-descriptor-capabilities descriptor)))
     "required capability unavailable")
    ((not (%subsetp-strings
           (logic-selection-request-required-hard-limits request)
           (logic-backend-descriptor-hard-limits descriptor)))
     "required hard limit unavailable")
    ((and (logic-selection-request-required-isolation request)
          (not (member (logic-selection-request-required-isolation request)
                       (logic-backend-descriptor-isolation-classes descriptor)
                       :test #'string=)))
     "required isolation unavailable")
    (t nil)))

(defun %selection-evidence (request candidates selected)
  (make-logic-selection-evidence
   :requested (logic-selection-request-backend-policy request)
   :semantic-profile (logic-selection-request-semantic-profile request)
   :required-capabilities
   (copy-list (logic-selection-request-required-capabilities request))
   :required-hard-limits
   (copy-list (logic-selection-request-required-hard-limits request))
   :required-isolation (logic-selection-request-required-isolation request)
   :candidates candidates
   :selected selected
   :policy "star.logic.default-routing/1"))

(defun select-logic-backend (registry request)
  (check-type registry logic-backend-registry)
  (check-type request logic-selection-request)
  (let ((eligible '())
        (candidates '()))
    (dolist (backend (list-logic-backends registry))
      (let* ((descriptor (logic-backend-descriptor-of backend))
             (id (logic-backend-descriptor-id descriptor))
             (reason (%candidate-rejection-reason descriptor request)))
        (if reason
            (push (make-logic-selection-candidate
                   :backend-id id
                   :status :rejected
                   :reason reason)
                  candidates)
            (progn
              (push backend eligible)
              (push (make-logic-selection-candidate
                     :backend-id id
                     :status :accepted
                     :reason nil)
                    candidates)))))
    (setf candidates
          (sort candidates #'string< :key #'logic-selection-candidate-backend-id)
          eligible
          (sort eligible
                #'string<
                :key (lambda (backend)
                       (logic-backend-descriptor-id
                        (logic-backend-descriptor-of backend)))))
    (let ((policy (logic-selection-request-backend-policy request)))
      (if (string= policy "auto")
          (cond
            ((null eligible)
             (%fail 'logic-backend-selection-error
                    "No logic backend satisfies profile ~S."
                    (logic-selection-request-semantic-profile request)))
            ((cdr eligible)
             (%fail 'logic-backend-selection-error
                    "Automatic logic backend selection is ambiguous among ~{~A~^, ~}."
                    (mapcar (lambda (backend)
                              (logic-backend-descriptor-id
                               (logic-backend-descriptor-of backend)))
                            eligible)))
            (t
             (let* ((backend (first eligible))
                    (selected (logic-backend-descriptor-id
                               (logic-backend-descriptor-of backend))))
               (values backend
                       (%selection-evidence request candidates selected)))))
          (let ((backend (find-logic-backend registry policy)))
            (unless backend
              (%fail 'logic-backend-not-found-error
                     "Requested logic backend ~S is not registered."
                     policy))
            (let* ((descriptor (logic-backend-descriptor-of backend))
                   (reason (%candidate-rejection-reason descriptor request)))
              (when reason
                (%fail 'logic-backend-incompatible-error
                       "Requested logic backend ~S is incompatible: ~A."
                       policy reason))
              (values backend
                      (%selection-evidence request candidates policy))))))))

(defgeneric open-logic-session
    (backend session-id &key package-id package-digest))
(defgeneric close-logic-session (backend session))
(defgeneric apply-logic-fact-delta (backend session delta))
(defgeneric invoke-logic-operation
    (backend session operation-id parameters &key limits))
(defgeneric next-logic-result (backend session operation))
(defgeneric cancel-logic-operation (backend session operation reason))
(defgeneric logic-operation-status (backend session operation))
(defgeneric logic-backend-health (backend))

(defmethod open-logic-session
    ((backend t) session-id &key package-id package-digest)
  (declare (ignore session-id package-id package-digest))
  (%fail 'unsupported-logic-operation-error
         "Backend ~S does not implement OPEN-LOGIC-SESSION."
         backend))

(defmethod close-logic-session ((backend t) session)
  (declare (ignore session))
  (%fail 'unsupported-logic-operation-error
         "Backend ~S does not implement CLOSE-LOGIC-SESSION."
         backend))

(defmethod apply-logic-fact-delta ((backend t) session delta)
  (declare (ignore session delta))
  (%fail 'unsupported-logic-operation-error
         "Backend ~S does not implement APPLY-LOGIC-FACT-DELTA."
         backend))

(defmethod invoke-logic-operation
    ((backend t) session operation-id parameters &key limits)
  (declare (ignore session operation-id parameters limits))
  (%fail 'unsupported-logic-operation-error
         "Backend ~S does not implement INVOKE-LOGIC-OPERATION."
         backend))

(defmethod next-logic-result ((backend t) session operation)
  (declare (ignore session operation))
  (%fail 'unsupported-logic-operation-error
         "Backend ~S does not implement NEXT-LOGIC-RESULT."
         backend))

(defmethod cancel-logic-operation ((backend t) session operation reason)
  (declare (ignore session operation reason))
  (%fail 'unsupported-logic-operation-error
         "Backend ~S does not implement CANCEL-LOGIC-OPERATION."
         backend))

(defmethod logic-operation-status ((backend t) session operation)
  (declare (ignore session operation))
  (%fail 'unsupported-logic-operation-error
         "Backend ~S does not implement LOGIC-OPERATION-STATUS."
         backend))

(defmethod logic-backend-health ((backend t))
  (%fail 'unsupported-logic-operation-error
         "Backend ~S does not implement LOGIC-BACKEND-HEALTH."
         backend))
