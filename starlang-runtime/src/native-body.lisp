;;;; Native StarLang body execution (issue #69 runtime half).
;;;;
;;;; The runtime instantiates compiled body IR: typed state slots, message
;;;; handlers dispatched by wire message type, reply/correlation through the
;;;; real mailbox ask path, and deterministic effect evaluation. Body IR is
;;;; the closed surface lowered by starlang-compiler/src/actor-body.lisp.
;;;;
;;;; Body actors receive wire envelopes (staractorprotocol:make-wire-envelope
;;;; shape); handlers dispatch on :message-type and see :payload. Effects:
;;;; send/ask deliver constructed messages as envelopes to target actors.

(in-package :starlangruntime)

(define-condition body-fail-error (actor-runtime-error)
  ((code :initarg :code :reader body-fail-code)
   (detail :initarg :detail :reader body-fail-message))
  (:report
   (lambda (condition stream)
     (format stream "StarLang body fail ~A: ~A"
             (body-fail-code condition)
             (body-fail-message condition)))))

(define-condition body-unknown-message-error (actor-runtime-error) ())

(define-condition body-effect-error (actor-runtime-error) ())

;; Per-invocation interpreter state. Dynamic bindings keep nested asks (which
;; execute other handlers reentrantly on the deterministic scheduler) isolated.
(defvar *body-reply-value* nil)
(defvar *body-reply-p* nil)
(defvar *body-locals* '())
(defvar *body-states* '())
(defvar *body-message-var* "message")

(defun fail-body-effect (control &rest arguments)
  (error 'body-effect-error :message (apply #'format nil control arguments)))

(defun initial-body-state (states)
  (mapcar (lambda (slot)
            (cons (getf slot :name) (getf slot :initial)))
          states))

(defun reset-typed-actor-state (definition data)
  "Apply persistence classes on restart: ephemeral slots return to their
declared initial values; journaled, owned-document, and shared-readonly
slots keep committed values."
  (let ((data (copy-tree data)))
    (dolist (slot (actor-definition-states definition))
      (when (eq :ephemeral (getf slot :persistence))
        (let ((entry (assoc (getf slot :name) data :test #'string=)))
          (if entry
              (setf (cdr entry) (getf slot :initial))
              (push (cons (getf slot :name) (getf slot :initial)) data)))))
    data))

(defun typed-state-slot (states name)
  (find name states :key (lambda (slot) (getf slot :name)) :test #'string=))

(defun enforce-slot-type (states name value)
  (let ((slot (typed-state-slot states name)))
    (when slot
      (let ((valid
              (cond
                ((string= (getf slot :type) "integer") (integerp value))
                ((string= (getf slot :type) "string") (stringp value))
                ((string= (getf slot :type) "boolean")
                 (typep value 'boolean))
                ((string= (getf slot :type) "decimal")
                 (or (integerp value) (floatp value)))
                (t t))))
        (unless valid
          (fail-actor 'actor-contract-error
                      "State slot ~A requires type ~A, received ~S."
                      name
                      (getf slot :type)
                      value)))))
  value)

(defun body-state-write (state name value)
  (enforce-slot-type *body-states* name value)
  (let ((entry (assoc name state :test #'string=)))
    (if entry
        (progn (setf (cdr entry) value) state)
        (acons name value state))))

(defun body-field-value (value name)
  "Field access over portable payload values: string-keyed alists first,
then keyword property lists."
  (typecase value
    (cons
     (cond
       ((every #'consp value)
        (let ((entry (assoc name value :test #'string=)))
          (if entry (cdr entry) nil)))
       ((keywordp (first value))
        (getf value (intern (string-upcase name) :keyword)))
       (t nil)))
    (otherwise nil)))

(defun body-resolve-local (name)
  (let ((entry (assoc name *body-locals* :test #'string=)))
    (if entry
        (cdr entry)
        (fail-body-effect "Body let binding ~A is not in scope." name))))

(defun eval-body-form (form message context state runtime)
  "Evaluate one body IR form. Returns (VALUES value state)."
  (let ((op (first form)))
    (case op
      (:const (values (second form) state))
      (:do
       (values nil
               (eval-body-sequence (rest form) message context state runtime)))
      (:context
       (values
        (if (string= (second form) *body-message-var*)
            message
            context)
        state))
      (:local (values (body-resolve-local (second form)) state))
      (:state-read
       (let ((entry (assoc (second form) state :test #'string=)))
         (values (if entry (cdr entry) nil) state)))
      (:field
       (multiple-value-bind (base new-state)
           (eval-body-form (second form) message context state runtime)
         (values (body-field-value base (third form)) new-state)))
      (:let
       (let ((*body-locals* *body-locals*))
         (let ((new-state state))
           (dolist (binding (second form))
             (multiple-value-bind (value _)
                 (eval-body-form (cdr binding) message context new-state
                                 runtime)
               (declare (ignore _))
               (push (cons (car binding) value) *body-locals*)))
           (let ((body-state
                   (eval-body-sequence (rest (third form)) message context
                                       new-state runtime)))
             (values nil body-state)))))
      (:if
       (multiple-value-bind (test new-state)
           (eval-body-form (second form) message context state runtime)
         (if test
             (eval-body-form (third form) message context new-state runtime)
             (eval-body-form (fourth form) message context new-state runtime))))
      (:construct
       (let ((new-state state)
             (built '()))
         (dolist (entry (third form))
           (multiple-value-bind (value next-state)
               (eval-body-form (cdr entry) message context new-state runtime)
             (setf new-state next-state
                   built (acons (car entry) value built))))
         (values (nreverse built) new-state)))
      (:reply
       (multiple-value-bind (value new-state)
           (eval-body-form (second form) message context state runtime)
         (setf *body-reply-value* value
               *body-reply-p* t)
         (values value new-state)))
      (:fail
       (error 'body-fail-error
              :code (second form)
              :detail (third form)))
      (:state-write
       (multiple-value-bind (value new-state)
           (eval-body-form (third form) message context state runtime)
         (values value
                 (body-state-write new-state (second form) value))))
      (:send
       (unless runtime
         (fail-body-effect
          "send is only available inside a runtime-hosted actor."))
       (multiple-value-bind (envelope new-state)
           (eval-message-operand (third form) message context state runtime)
         (let ((target (eval-body-target (second form) message context
                                        new-state runtime)))
           (let ((delivery (tell runtime target envelope)))
             (unless (eq :accepted (delivery-result-status delivery))
               (fail-body-effect
                "send to ~A was rejected with status ~S."
                target (delivery-result-status delivery)))
             (values envelope new-state)))))
      (:ask
       (unless runtime
         (fail-body-effect
          "ask is only available inside a runtime-hosted actor."))
       (multiple-value-bind (envelope new-state)
           (eval-message-operand (third form) message context state runtime)
         (let ((target (eval-body-target (second form) message context
                                        new-state runtime)))
           (values (ask runtime target envelope) new-state))))
      (otherwise
       (fail-body-effect "Unknown body IR operation ~S." op)))))

(defun eval-body-target (form message context state runtime)
  (multiple-value-bind (target _)
      (eval-body-form form message context state runtime)
    (declare (ignore _))
    (if (stringp target)
        target
        (fail-body-effect "send/ask target must be an actor name or STAR \
URI string, received ~S." target))))

(defun eval-message-operand (form message context state runtime)
  "Evaluate a send/ask payload operand. Only constructed messages carry a
type on the closed surface; the construct type becomes the wire message
type and the constructed alist becomes the payload."
  (unless (and (consp form) (eq (first form) :construct))
    (fail-body-effect
     "send/ask payloads must be (construct type ...) messages, received ~S."
     form))
  (multiple-value-bind (payload new-state)
      (eval-body-form form message context state runtime)
    (values
     (staractorprotocol:make-wire-envelope
      :message-type (second form)
      :message-id (format nil "body-~D-~6,'0D"
                          (get-universal-time)
                          (mod (random most-positive-fixnum) 1000000))
      :actor "star.body"
      :payload payload)
     new-state)))

(defun eval-body-sequence (forms message context state runtime)
  (let ((new-state state))
    (dolist (form forms)
      (multiple-value-bind (value next-state)
          (eval-body-form form message context new-state runtime)
        (declare (ignore value))
        (setf new-state next-state)))
    new-state))

(defun make-body-handler (actor-ir)
  "Build the executable handler for compiled body IR. The handler follows
the native transition contract: (handler message state runtime) with an
optional second return value committing the next state."
  (let* ((states (getf actor-ir :states))
         (handlers (getf actor-ir :handlers))
         (table (make-hash-table :test #'equal)))
    (dolist (handler handlers)
      (setf (gethash (getf handler :message-type) table) handler))
    (lambda (message state runtime)
      (let ((message-type
              (typecase message
                (cons (or (getf message :message-type)
                          (cdr (assoc "messageType" message
                                      :test #'string=))))
                (otherwise nil))))
        (unless (stringp message-type)
          (error 'body-unknown-message-error
                 :message
                 (format nil
                         "Actor ~A requires envelope messages with a message \
type, received ~S."
                         (getf actor-ir :name)
                         (typecase message
                           (cons "<payload without message type>")
                           (otherwise message)))))
        (let ((handler (gethash message-type table)))
          (unless handler
            (error 'body-unknown-message-error
                   :message
                   (format nil "Actor ~A has no handler for message type ~A."
                           (getf actor-ir :name)
                           message-type)))
          (let* ((*body-reply-value* nil)
                 (*body-reply-p* nil)
                 (*body-locals* '())
                 (*body-states* states)
                 (*body-message-var* (or (getf handler :message-var)
                                         "message"))
                 (body (getf handler :body))
                 (message-payload
                   (if (and (consp message) (getf message :payload))
                       (getf message :payload)
                       message))
                 (final-state
                   (eval-body-sequence (rest body) message-payload nil
                                       (copy-tree state) runtime)))
            (values (and *body-reply-p* *body-reply-value*) final-state)))))))

(defun make-body-actor-definition (actor-ir &key input-validator output-validator)
  "Materialize a compiled body actor's IR into an executable definition."
  (unless (and (listp actor-ir) (eq (getf actor-ir :kind) :actor))
    (fail-actor 'actor-definition-error
                "Body actor materialization requires compiled actor IR."))
  (unless (eq :native (getf actor-ir :runtime))
    (fail-actor 'actor-definition-error
                "Only native actors can execute StarLang bodies."))
  (unless (getf actor-ir :handlers)
    (fail-actor 'actor-definition-error
                "Actor ~A carries no StarLang handlers."
                (getf actor-ir :name)))
  (let ((mailbox (getf actor-ir :mailbox)))
    (%make-actor-definition
     :name (getf actor-ir :name)
     :service-uri (or (getf actor-ir :service-uri) "")
     :resource-uri (getf actor-ir :resource-uri)
     :kind :native
     :handler (make-body-handler actor-ir)
     :accepts (copy-list (getf actor-ir :accepts))
     :produces (copy-list (getf actor-ir :produces))
     :input-validator input-validator
     :output-validator output-validator
     :initial-state (initial-body-state (getf actor-ir :states))
     :restart-policy (getf actor-ir :restart :permanent)
     :mailbox-capacity (getf mailbox :capacity 128)
     :states (copy-tree (getf actor-ir :states))
     :metadata (and (getf actor-ir :metadata)
                    (copy-alist (getf actor-ir :metadata))))))
