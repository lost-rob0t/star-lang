(in-package :starlangruntime)

(define-condition actor-runtime-error (error)
  ((message :initarg :message :reader actor-runtime-error-message))
  (:report
   (lambda (condition stream)
     (write-string (actor-runtime-error-message condition) stream))))

(define-condition actor-definition-error (actor-runtime-error) ())
(define-condition actor-already-registered-error (actor-runtime-error) ())
(define-condition actor-not-found-error (actor-runtime-error) ())
(define-condition actor-stopped-error (actor-runtime-error) ())
(define-condition actor-stale-reference-error (actor-runtime-error) ())
(define-condition actor-mailbox-full-error (actor-runtime-error) ())
(define-condition actor-ask-timeout-error (actor-runtime-error) ())
(define-condition actor-external-dispatch-required-error (actor-runtime-error) ())
(define-condition actor-contract-error (actor-runtime-error) ())

(defun fail-actor (condition-type control &rest arguments)
  (error condition-type :message (apply #'format nil control arguments)))

(defstruct (actor-definition
            (:constructor %make-actor-definition
                (&key name
                      service-uri
                      kind
                      handler
                      accepts
                      produces
                      input-validator
                      output-validator
                      initial-state
                      restart-policy
                      mailbox-capacity
                      metadata)))
  (name "" :type string)
  (service-uri "" :type string)
  (kind :native :type keyword)
  handler
  accepts
  produces
  input-validator
  output-validator
  initial-state
  (restart-policy :permanent :type keyword)
  (mailbox-capacity 128 :type (integer 1 *))
  metadata)

(defstruct (actor-instance
            (:constructor %make-actor-instance
                (&key definition data mailbox)))
  (definition (error "DEFINITION is required") :type actor-definition)
  (status :running :type keyword)
  data
  (generation 0 :type (integer 0 *))
  (invocation-count 0 :type (integer 0 *))
  last-error
  mailbox
  (processing-p nil :type boolean))

(defstruct (runtime (:constructor %make-runtime))
  (actors-by-name (make-hash-table :test #'equal) :type hash-table)
  (actors-by-uri (make-hash-table :test #'equal) :type hash-table)
  (actor-order '() :type list)
  (sequence 0 :type (integer 0 *)))

(defstruct (delivery-result
            (:constructor %make-delivery-result
                (status reference depth capacity)))
  (status :accepted :type keyword)
  reference
  (depth 0 :type (integer 0 *))
  (capacity 1 :type (integer 1 *)))

(defstruct (dispatch-result
            (:constructor %make-dispatch-result
                (&key status reference correlation-id value condition)))
  (status :completed :type keyword)
  reference
  correlation-id
  value
  condition)

(defstruct (ask-cell (:constructor make-ask-cell (correlation-id)))
  correlation-id
  (status :pending :type keyword)
  value
  condition)

(defstruct (runtime-message
            (:constructor make-runtime-message
                (&key correlation-id payload reply-cell)))
  correlation-id
  payload
  reply-cell)

(defun make-runtime ()
  (%make-runtime))

(defun default-local-service-uri (name)
  (format nil "star://local:localhost:~A" name))

(defun ensure-actor-kind (kind)
  (unless (member kind '(:native :external) :test #'eq)
    (fail-actor 'actor-definition-error
                "Actor kind must be :NATIVE or :EXTERNAL, received ~S."
                kind))
  kind)

(defun ensure-validator (validator label)
  (unless (or (null validator) (functionp validator))
    (fail-actor 'actor-definition-error
                "Actor ~A validator must be a function or NIL, received ~S."
                label validator))
  validator)

(defun ensure-mailbox-capacity (capacity)
  (unless (and (integerp capacity) (> capacity 0))
    (fail-actor 'actor-definition-error
                "Actor mailbox capacity must be a positive integer, received ~S."
                capacity))
  capacity)

(defun canonical-service-uri (name service-uri)
  (handler-case
      (staractorprotocol:canonical-star-service-uri-for-actor
       name
       (or service-uri (default-local-service-uri name)))
    (staractorprotocol:invalid-star-service-uri-error (condition)
      (fail-actor 'actor-definition-error "~A" condition))))

(defun make-native-actor-definition
    (name handler
     &key
       service-uri
       accepts
       produces
       input-validator
       output-validator
       initial-state
       (restart-policy :permanent)
       (mailbox-capacity 128)
       metadata)
  (unless (functionp handler)
    (fail-actor 'actor-definition-error
                "Native actor ~S requires a function handler."
                name))
  (%make-actor-definition
   :name name
   :service-uri (canonical-service-uri name service-uri)
   :kind :native
   :handler handler
   :accepts accepts
   :produces produces
   :input-validator (ensure-validator input-validator "input")
   :output-validator (ensure-validator output-validator "output")
   :initial-state initial-state
   :restart-policy restart-policy
   :mailbox-capacity (ensure-mailbox-capacity mailbox-capacity)
   :metadata metadata))

(defun make-external-actor-definition
    (name service-uri
     &key
       accepts
       produces
       input-validator
       output-validator
       (restart-policy :permanent)
       (mailbox-capacity 128)
       metadata)
  (%make-actor-definition
   :name name
   :service-uri (canonical-service-uri name service-uri)
   :kind :external
   :handler nil
   :accepts accepts
   :produces produces
   :input-validator (ensure-validator input-validator "input")
   :output-validator (ensure-validator output-validator "output")
   :initial-state nil
   :restart-policy restart-policy
   :mailbox-capacity (ensure-mailbox-capacity mailbox-capacity)
   :metadata metadata))

(defun initialized-actor-state (initial-state)
  (cond
    ((functionp initial-state) (funcall initial-state))
    ((consp initial-state) (copy-tree initial-state))
    (t initial-state)))

(defun validate-definition (definition)
  (unless (actor-definition-p definition)
    (fail-actor 'actor-definition-error
                "Expected an actor definition, received ~S."
                definition))
  (ensure-actor-kind (actor-definition-kind definition))
  (setf (actor-definition-service-uri definition)
        (canonical-service-uri
         (actor-definition-name definition)
         (actor-definition-service-uri definition)))
  (when (and (eq :native (actor-definition-kind definition))
             (not (functionp (actor-definition-handler definition))))
    (fail-actor 'actor-definition-error
                "Native actor ~A has no callable handler."
                (actor-definition-name definition)))
  (ensure-validator (actor-definition-input-validator definition) "input")
  (ensure-validator (actor-definition-output-validator definition) "output")
  (ensure-mailbox-capacity (actor-definition-mailbox-capacity definition))
  definition)

(defun fresh-actor-mailbox (definition)
  (starmailbox:make-mailbox (actor-definition-mailbox-capacity definition)))

(defun instantiate-actor (definition)
  (validate-definition definition)
  (%make-actor-instance
   :definition definition
   :data (initialized-actor-state (actor-definition-initial-state definition))
   :mailbox (fresh-actor-mailbox definition)))

(defun actor-running-p (actor)
  (and (actor-instance-p actor)
       (eq :running (actor-instance-status actor))))

(defun runtime-actor-count (runtime)
  (hash-table-count (runtime-actors-by-name runtime)))

(defun actor-name (actor)
  (actor-definition-name (actor-instance-definition actor)))

(defun actor-service-uri (actor)
  (actor-definition-service-uri (actor-instance-definition actor)))

(defun actor-reference (actor)
  (unless (actor-instance-p actor)
    (fail-actor 'actor-definition-error
                "Expected an actor instance, received ~S."
                actor))
  (let ((uri (staractorprotocol:parse-star-service-uri
              (actor-service-uri actor))))
    (staractorprotocol:make-star-actor-reference
     :domain-id (staractorprotocol:star-service-uri-domain uri)
     :logical-path (staractorprotocol:star-service-uri-actor-name uri)
     :node-id (staractorprotocol:star-service-uri-address uri)
     :generation (actor-instance-generation actor)
     :protocol-revision 1)))

(defun actor-mailbox-depth (actor)
  (unless (actor-instance-p actor)
    (fail-actor 'actor-definition-error
                "Expected an actor instance, received ~S."
                actor))
  (starmailbox:mailbox-depth (actor-instance-mailbox actor)))

(defun register-actor (runtime actor)
  (unless (runtime-p runtime)
    (fail-actor 'actor-runtime-error
                "Expected a StarLang runtime, received ~S."
                runtime))
  (unless (actor-instance-p actor)
    (fail-actor 'actor-definition-error
                "Expected an actor instance, received ~S."
                actor))
  (let ((name (actor-name actor))
        (service-uri (actor-service-uri actor)))
    (when (or (gethash name (runtime-actors-by-name runtime))
              (gethash service-uri (runtime-actors-by-uri runtime)))
      (fail-actor 'actor-already-registered-error
                  "Actor ~A (~A) is already registered."
                  name service-uri))
    (setf (gethash name (runtime-actors-by-name runtime)) actor
          (gethash service-uri (runtime-actors-by-uri runtime)) actor
          (runtime-actor-order runtime)
          (append (runtime-actor-order runtime) (list name)))
    actor))

(defun create-actor (runtime definition)
  (register-actor runtime (instantiate-actor definition)))

(defun create-native-actor (runtime name handler &rest options)
  (create-actor runtime
                (apply #'make-native-actor-definition name handler options)))

(defun create-external-actor (runtime name service-uri &rest options)
  (create-actor runtime
                (apply #'make-external-actor-definition name service-uri options)))

(defun find-actor (runtime target)
  (cond
    ((actor-instance-p target) target)
    ((staractorprotocol:star-actor-reference-p target)
     (gethash
      (staractorprotocol:star-actor-reference-service-uri target)
      (runtime-actors-by-uri runtime)))
    ((and (stringp target)
          (staractorprotocol:star-service-uri-target-p target))
     (handler-case
         (gethash
          (staractorprotocol:star-service-uri-string
           (staractorprotocol:parse-star-service-uri target))
          (runtime-actors-by-uri runtime))
       (staractorprotocol:invalid-star-service-uri-error () nil)))
    ((stringp target)
     (gethash target (runtime-actors-by-name runtime)))
    (t nil)))

(defun ensure-reference-generation (target actor)
  (when (and (staractorprotocol:star-actor-reference-p target)
             (/= (staractorprotocol:star-actor-reference-generation target)
                 (actor-instance-generation actor)))
    (fail-actor
     'actor-stale-reference-error
     "Actor reference ~A generation ~D is stale; current generation is ~D."
     (staractorprotocol:star-actor-reference-service-uri target)
     (staractorprotocol:star-actor-reference-generation target)
     (actor-instance-generation actor)))
  actor)

(defun resolve-actor (runtime target)
  (let ((actor (find-actor runtime target)))
    (unless actor
      (fail-actor 'actor-not-found-error
                  "No actor registered for target ~S."
                  target))
    (ensure-reference-generation target actor)))

(defun unregister-actor (runtime target)
  (let* ((actor (resolve-actor runtime target))
         (name (actor-name actor))
         (service-uri (actor-service-uri actor)))
    (remhash name (runtime-actors-by-name runtime))
    (remhash service-uri (runtime-actors-by-uri runtime))
    (setf (runtime-actor-order runtime)
          (remove name (runtime-actor-order runtime) :test #'string=))
    actor))

(defun stop-actor (runtime target)
  (let ((actor (resolve-actor runtime target)))
    (setf (actor-instance-status actor) :stopped)
    (starmailbox:close-mailbox
     (actor-instance-mailbox actor)
     :discard-p t)
    actor))

(defun start-actor (runtime target)
  (let ((actor (resolve-actor runtime target)))
    (unless (eq :running (actor-instance-status actor))
      (incf (actor-instance-generation actor))
      (setf (actor-instance-mailbox actor)
            (fresh-actor-mailbox (actor-instance-definition actor))))
    (setf (actor-instance-status actor) :running
          (actor-instance-processing-p actor) nil
          (actor-instance-last-error actor) nil)
    actor))

(defun restart-actor (runtime target)
  (let ((actor (resolve-actor runtime target)))
    ;; Current v1 policy preserves committed actor state and drops queued work.
    ;; The new generation receives a fresh bounded mailbox.
    (stop-actor runtime actor)
    (start-actor runtime actor)))

(defun contract-valid-p (validator contract value)
  (or (null validator)
      (funcall validator contract value)))

(defun validate-contract (condition-label validator contract value actor)
  (unless (contract-valid-p validator contract value)
    (fail-actor 'actor-contract-error
                "Actor ~A rejected its ~A contract ~S for value ~S."
                (actor-name actor)
                condition-label
                contract
                value)))

(defun invoke-native-transition (actor message runtime)
  (let* ((definition (actor-instance-definition actor))
         (values
           (multiple-value-list
            (funcall (actor-definition-handler definition)
                     message
                     (actor-instance-data actor)
                     runtime))))
    (unless values
      (fail-actor 'actor-contract-error
                  "Actor ~A returned no values."
                  (actor-name actor)))
    (let ((result (first values))
          (state-supplied-p (> (length values) 1))
          (next-state (and (> (length values) 1) (second values))))
      (validate-contract
       "output"
       (actor-definition-output-validator definition)
       (actor-definition-produces definition)
       result actor)
      ;; Actor-local state commits only after the complete transition succeeds.
      (when state-supplied-p
        (setf (actor-instance-data actor) next-state))
      (incf (actor-instance-invocation-count actor))
      (setf (actor-instance-last-error actor) nil)
      result)))

(defun next-correlation-id (runtime)
  (incf (runtime-sequence runtime))
  (format nil "runtime-correlation-~8,'0D" (runtime-sequence runtime)))

(defun delivery-from-mailbox-result (actor mailbox-result)
  (%make-delivery-result
   (case (starmailbox:mailbox-delivery-status mailbox-result)
     (:accepted :accepted)
     (:full :mailbox-full)
     (:closed :stopped)
     (otherwise :rejected))
   (actor-reference actor)
   (starmailbox:mailbox-delivery-depth mailbox-result)
   (starmailbox:mailbox-delivery-capacity mailbox-result)))

(defun enqueue-message (actor runtime-message)
  (delivery-from-mailbox-result
   actor
   (starmailbox:mailbox-offer
    (actor-instance-mailbox actor)
    runtime-message)))

(defun ensure-local-running-actor (actor)
  (unless (actor-running-p actor)
    (return-from ensure-local-running-actor :stopped))
  (when (eq :external
            (actor-definition-kind (actor-instance-definition actor)))
    (fail-actor 'actor-external-dispatch-required-error
                "Actor ~A is external at ~A; a transport dispatcher is required."
                (actor-name actor)
                (actor-service-uri actor)))
  :running)

(defun tell (runtime target message)
  "Enqueue MESSAGE without executing the receiver handler synchronously."
  (let ((actor (resolve-actor runtime target)))
    (if (eq :stopped (ensure-local-running-actor actor))
        (%make-delivery-result
         :stopped
         (actor-reference actor)
         (actor-mailbox-depth actor)
         (actor-definition-mailbox-capacity
          (actor-instance-definition actor)))
        (enqueue-message
         actor
         (make-runtime-message
          :correlation-id (next-correlation-id runtime)
          :payload message
          :reply-cell nil)))))

(defun complete-ask-cell (cell value)
  (when cell
    (setf (ask-cell-value cell) value
          (ask-cell-condition cell) nil
          (ask-cell-status cell) :replied)))

(defun fail-ask-cell (cell condition)
  (when cell
    (setf (ask-cell-value cell) nil
          (ask-cell-condition cell) condition
          (ask-cell-status cell) :error)))

(defun dispatch-envelope (runtime actor envelope)
  (let ((reference (actor-reference actor))
        (correlation-id (runtime-message-correlation-id envelope))
        (cell (runtime-message-reply-cell envelope)))
    (handler-case
        (progn
          (validate-contract
           "input"
           (actor-definition-input-validator
            (actor-instance-definition actor))
           (actor-definition-accepts
            (actor-instance-definition actor))
           (runtime-message-payload envelope)
           actor)
          (let ((result
                  (invoke-native-transition
                   actor (runtime-message-payload envelope) runtime)))
            (complete-ask-cell cell result)
            (%make-dispatch-result
             :status :completed
             :reference reference
             :correlation-id correlation-id
             :value result)))
      (error (condition)
        ;; Failed transitions never commit their proposed state. Async tells
        ;; surface failure through dispatch results; ask re-signals from its cell.
        (setf (actor-instance-last-error actor) condition)
        (fail-ask-cell cell condition)
        (%make-dispatch-result
         :status :failed
         :reference reference
         :correlation-id correlation-id
         :condition condition)))))

(defun dispatch-next (runtime target)
  "Execute at most one FIFO message for TARGET. Never re-enters a busy actor."
  (let ((actor (resolve-actor runtime target)))
    (when (and (actor-running-p actor)
               (not (actor-instance-processing-p actor)))
      (multiple-value-bind (envelope present-p)
          (starmailbox:mailbox-poll (actor-instance-mailbox actor))
        (when present-p
          (setf (actor-instance-processing-p actor) t)
          (unwind-protect
               (dispatch-envelope runtime actor envelope)
            (setf (actor-instance-processing-p actor) nil)))))))

(defun ensure-ask-delivery (delivery target)
  (case (delivery-result-status delivery)
    (:accepted delivery)
    (:mailbox-full
     (fail-actor 'actor-mailbox-full-error
                 "Actor ~S mailbox is full (~D/~D)."
                 target
                 (delivery-result-depth delivery)
                 (delivery-result-capacity delivery)))
    (:stopped
     (fail-actor 'actor-stopped-error
                 "Actor ~S is stopped."
                 target))
    (otherwise
     (fail-actor 'actor-runtime-error
                 "Actor ~S rejected delivery with status ~S."
                 target (delivery-result-status delivery)))))

(defun ask (runtime target message &key (timeout-steps 1000))
  "Send through the normal mailbox and await a correlated reply/error.
TIMEOUT-STEPS is deterministic scheduler work, not wall-clock time."
  (unless (and (integerp timeout-steps) (>= timeout-steps 0))
    (fail-actor 'actor-definition-error
                "ASK timeout-steps must be a non-negative integer, received ~S."
                timeout-steps))
  (let* ((actor (resolve-actor runtime target))
         (running-status (ensure-local-running-actor actor)))
    (when (eq running-status :stopped)
      (fail-actor 'actor-stopped-error "Actor ~S is stopped." target))
    (let* ((correlation-id (next-correlation-id runtime))
           (cell (make-ask-cell correlation-id))
           (delivery
             (enqueue-message
              actor
              (make-runtime-message
               :correlation-id correlation-id
               :payload message
               :reply-cell cell))))
      (ensure-ask-delivery delivery target)
      (loop repeat timeout-steps
            until (not (eq :pending (ask-cell-status cell)))
            do (dispatch-next runtime actor))
      (case (ask-cell-status cell)
        (:replied (ask-cell-value cell))
        (:error (error (ask-cell-condition cell)))
        (otherwise
         (fail-actor
          'actor-ask-timeout-error
          "ASK to actor ~A timed out after ~D deterministic dispatch steps (correlation ~A)."
          (actor-name actor) timeout-steps correlation-id))))))

(defun run-until-idle (runtime)
  "Deterministically drain one message per actor per round until no work remains."
  (let ((processed 0))
    (loop
      with progressed-p = nil
      do (setf progressed-p nil)
         (dolist (name (copy-list (runtime-actor-order runtime)))
           (let ((actor (gethash name (runtime-actors-by-name runtime))))
             (when (and actor (actor-running-p actor))
               (when (dispatch-next runtime actor)
                 (incf processed)
                 (setf progressed-p t)))))
      until (not progressed-p))
    processed))

(defun invoke-actor (runtime target message)
  "Compatibility API. Invocation now uses ASK and therefore the real mailbox path."
  (ask runtime target message))