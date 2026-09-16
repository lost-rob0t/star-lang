(in-package :starsupervisor)

;; A single-threaded, host-driven policy layer, NOT a second actor engine.
;; All message delivery and lifecycle changes use the final runtime. See README.org.
(define-condition supervisor-error (error)
  ((message :initarg :message :reader supervisor-error-message))
  (:report (lambda (condition stream)
             (write-string (supervisor-error-message condition) stream))))
(define-condition invalid-supervisor-spec (supervisor-error) ())
(define-condition supervisor-clock-error (supervisor-error) ())
(define-condition supervisor-stopped-error (supervisor-error) ())

(defun fail (type control &rest arguments)
  (error type :message (apply #'format nil control arguments)))

(defstruct (supervisor-spec (:constructor %make-spec))
  (name "" :type string :read-only t)
  (children nil :type list :read-only t)
  (max-restarts 3 :type (integer 0 *) :read-only t)
  (period-ms 10000 :type (integer 1 *) :read-only t)
  (backoff-ms 0 :type (integer 0 *) :read-only t))

(defun make-supervisor-spec (name children
                            &key (strategy :one-for-one) (max-restarts 3)
                              (period-ms 10000) (backoff-ms 0))
  "Build a host-side specification from existing native actor definitions.
This is not portable IR. Only :ONE-FOR-ONE is implemented in this review slice."
  (unless (and (stringp name) (plusp (length name))
               (eq strategy :one-for-one)
               (typep max-restarts '(integer 0 *))
               (typep period-ms '(integer 1 *))
               (typep backoff-ms '(integer 0 *)))
    (fail 'invalid-supervisor-spec "Invalid supervisor name, strategy, or bounds."))
  (let ((count (and (listp children) (ignore-errors (list-length children))))
        (names (make-hash-table :test #'equal))
        (uris (make-hash-table :test #'equal)))
    (unless (and count (plusp count))
      (fail 'invalid-supervisor-spec "Children must be a nonempty proper list."))
    (dolist (definition children)
      (unless (and (starlangruntime:actor-definition-p definition)
                   (eq :native (starlangruntime:actor-definition-kind definition))
                   (member (starlangruntime:actor-definition-restart-policy definition)
                           '(:permanent :transient :temporary)))
        (fail 'invalid-supervisor-spec "Each child needs a native definition and restart class."))
      (let ((id (starlangruntime:actor-definition-name definition))
            (uri (starlangruntime:actor-definition-service-uri definition)))
        (when (or (gethash id names) (gethash uri uris))
          (fail 'invalid-supervisor-spec "Duplicate child name or service URI: ~S." id))
        (setf (gethash id names) t (gethash uri uris) t))))
  (%make-spec :name (copy-seq name)
              :children (mapcar #'copy-structure children)
              :max-restarts max-restarts :period-ms period-ms :backoff-ms backoff-ms))

(defstruct (child (:constructor make-child (actor)))
  actor
  (status :running :type keyword)
  (restarts 0 :type (integer 0 *))
  due-at
  last-exit)

(defstruct (supervisor (:constructor %make-supervisor))
  spec runtime clock
  (children nil :type list)
  (status :running :type keyword)
  (last-now 0 :type (integer 0 *))
  (restart-times nil :type list)
  terminal-reason
  (stepping-p nil :type boolean))

(defun monotonic-milliseconds ()
  (floor (* 1000 (get-internal-real-time)) internal-time-units-per-second))

(defun read-clock (supervisor)
  (let ((now (funcall (supervisor-clock supervisor))))
    (unless (and (typep now '(integer 0 *))
                 (>= now (supervisor-last-now supervisor)))
      (fail 'supervisor-clock-error "Clock must return nondecreasing integer milliseconds."))
    (setf (supervisor-last-now supervisor) now)))

(defun start-supervisor (spec &key (clock #'monotonic-milliseconds))
  "Start children in declaration order in a fresh, exclusively owned runtime.
A partial start is rolled back. There are no background threads or implicit ticks."
  (unless (and (supervisor-spec-p spec) (functionp clock))
    (fail 'invalid-supervisor-spec "Expected a supervisor specification and clock function."))
  (let* ((runtime (starlangruntime:make-runtime))
         (supervisor (%make-supervisor :spec spec :runtime runtime :clock clock)))
    (handler-case
        (progn
          (read-clock supervisor)
          (dolist (definition (supervisor-spec-children spec))
            (push (make-child (starlangruntime:spawn runtime (copy-structure definition)))
                  (supervisor-children supervisor)))
          (setf (supervisor-children supervisor)
                (nreverse (supervisor-children supervisor)))
          supervisor)
      (error (condition)
        ;; Children are still in reverse startup order on this failure path.
        (dolist (child (supervisor-children supervisor))
          (starlangruntime:stop-actor runtime (child-actor child)))
        (starlangruntime:shutdown-runtime runtime)
        (error condition)))))

(defmacro with-supervisor ((variable spec &rest options) &body body)
  `(let ((,variable (start-supervisor ,spec ,@options)))
     (unwind-protect (progn ,@body)
       (stop-supervisor ,variable))))

(defun ensure-accepting (supervisor)
  (unless (eq :running (supervisor-status supervisor))
    (fail 'supervisor-stopped-error "Supervisor is not accepting work (~S)."
          (supervisor-status supervisor))))

(defun resolve-child (supervisor target)
  ;; Resolve through the runtime so generation-bearing references fail closed.
  (unless (or (stringp target) (staractorprotocol:star-actor-reference-p target))
    (fail 'supervisor-error "Use a child name, service URI, or generation-bearing reference."))
  (let* ((actor (starlangruntime:resolve-actor (supervisor-runtime supervisor) target))
         (child (find actor (supervisor-children supervisor) :key #'child-actor :test #'eq)))
    (or child (fail 'supervisor-error "Target is not owned by this supervisor."))))

(defun child-reference (supervisor target)
  "Return the current reference; a stopped child's reference is not a liveness claim."
  (starlangruntime:actor-reference (child-actor (resolve-child supervisor target))))

(defun supervisor-tell (supervisor target message)
  "Enqueue through the real bounded mailbox; return the runtime delivery result."
  (ensure-accepting supervisor)
  (let ((child (resolve-child supervisor target)))
    (starlangruntime:tell (supervisor-runtime supervisor) (child-actor child) message)))

(defun stop-child (supervisor target)
  "Operator stop: suppress automatic restart, including an already pending restart."
  (let ((child (resolve-child supervisor target)))
    (starlangruntime:stop-actor (supervisor-runtime supervisor) (child-actor child))
    (setf (child-status child) :stopped
          (child-due-at child) nil
          (child-last-exit child) :operator-stop))
  :stopped)

(defun finish-supervisor (supervisor status reason)
  ;; Freeze policy BEFORE closing mailboxes. Intentional teardown cannot restart.
  (setf (supervisor-status supervisor) status
        (supervisor-terminal-reason supervisor) reason)
  (dolist (child (reverse (supervisor-children supervisor)))
    (starlangruntime:stop-actor (supervisor-runtime supervisor) (child-actor child))
    (setf (child-status child) :stopped (child-due-at child) nil))
  (starlangruntime:shutdown-runtime (supervisor-runtime supervisor))
  status)

(defun stop-supervisor (supervisor)
  "Idempotent immediate shutdown. Preserve a prior terminal failure classification."
  (if (member (supervisor-status supervisor) '(:stopped :failed))
      (supervisor-status supervisor)
      (finish-supervisor supervisor :stopped :operator-stop)))

(defun observe-exit (supervisor child reason now)
  (let ((policy (starlangruntime:actor-definition-restart-policy
                 (starlangruntime:actor-instance-definition (child-actor child)))))
    (starlangruntime:stop-actor (supervisor-runtime supervisor) (child-actor child))
    (setf (child-last-exit child) reason
          (child-status child) :stopped
          (child-due-at child) nil)
    (when (and (eq :running (supervisor-status supervisor))
               (or (eq policy :permanent)
                   (and (eq policy :transient) (eq reason :failure))))
      (setf (child-status child) :backoff
            (child-due-at child) (+ now (supervisor-spec-backoff-ms
                                       (supervisor-spec supervisor)))))))

(defun restart-due-children (supervisor now)
  (let ((spec (supervisor-spec supervisor)) (progress nil))
    ;; Keep the half-open window (now - period, now]. Retained history is bounded.
    (setf (supervisor-restart-times supervisor)
          (remove-if (lambda (time) (<= time (- now (supervisor-spec-period-ms spec))))
                     (supervisor-restart-times supervisor)))
    (dolist (child (supervisor-children supervisor) progress)
      (when (and (eq :running (supervisor-status supervisor))
                 (eq :backoff (child-status child))
                 (<= (child-due-at child) now))
        (when (>= (length (supervisor-restart-times supervisor))
                  (supervisor-spec-max-restarts spec))
          (finish-supervisor supervisor :failed :restart-intensity-exceeded)
          (return-from restart-due-children t))
        ;; Count attempted restarts, not initial starts or message retries.
        (push now (supervisor-restart-times supervisor))
        (handler-case
            (progn
              (starlangruntime:restart-actor (supervisor-runtime supervisor) (child-actor child))
              (incf (child-restarts child))
              (setf (child-status child) :running (child-due-at child) nil
                    progress t))
          (error ()
            (finish-supervisor supervisor :failed :restart-failed)
            (return-from restart-due-children t)))))))

(defun supervisor-step (supervisor)
  "One bounded round: at most one mailbox message per child, plus due restarts.
Return progress-p and the actual dispatch results. Handler failures are abnormal
exits; observed stops are normal exits. Raw runtime drivers bypass this policy."
  (unless (member (supervisor-status supervisor) '(:running :draining))
    (return-from supervisor-step (values nil nil)))
  (when (supervisor-stepping-p supervisor)
    (fail 'supervisor-error "Supervisor ticks may not re-enter."))
  (setf (supervisor-stepping-p supervisor) t)
  (unwind-protect
       (let* ((now (read-clock supervisor))
              (progress (restart-due-children supervisor now))
              (results nil))
         (dolist (child (supervisor-children supervisor))
           (when (and (member (supervisor-status supervisor) '(:running :draining))
                      (eq :running (child-status child)))
             (let* ((actor (child-actor child))
                    (result (starlangruntime:dispatch-next (supervisor-runtime supervisor) actor)))
               (when result (push result results) (setf progress t))
               (when (eq :running (child-status child))
                 (cond
                   ((and result (eq :failed (starlangruntime:dispatch-result-status result)))
                    (observe-exit supervisor child :failure (read-clock supervisor))
                    (setf progress t))
                   ((not (starlangruntime:actor-running-p actor))
                    (observe-exit supervisor child :normal (read-clock supervisor))
                    (setf progress t)))))))
         (when (restart-due-children supervisor (read-clock supervisor))
           (setf progress t))
         (values progress (nreverse results)))
    (setf (supervisor-stepping-p supervisor) nil)))

(defun next-restart-at (supervisor)
  "Return the next absolute clock deadline in milliseconds, or NIL. Never sleeps."
  (let ((deadlines (loop for child in (supervisor-children supervisor)
                         when (eq :backoff (child-status child)) collect (child-due-at child))))
    (when deadlines (reduce #'min deadlines))))

(defun run-supervisor (supervisor &key (max-steps 1000))
  "Pump at most MAX-STEPS rounds. Return :IDLE, :WAITING, :STEP-LIMIT, :FAILED,
or :STOPPED, plus rounds used. :WAITING requires a later host tick."
  (unless (typep max-steps '(integer 1 *))
    (fail 'supervisor-error "MAX-STEPS must be a positive integer."))
  (loop for steps from 1 to max-steps
        for progress = (supervisor-step supervisor)
        do (when (member (supervisor-status supervisor) '(:failed :stopped))
             (return-from run-supervisor (values (supervisor-status supervisor) steps)))
           (unless progress
             (return-from run-supervisor
               (values (if (next-restart-at supervisor) :waiting :idle) steps))))
  ;; Finishing the last allowed round exactly at idle is not budget exhaustion.
  (values (cond
            ((some (lambda (child)
                     (and (eq :running (child-status child))
                          (plusp (starlangruntime:actor-mailbox-depth (child-actor child)))))
                   (supervisor-children supervisor)) :step-limit)
            ((next-restart-at supervisor) :waiting)
            (t :idle))
          max-steps))

(defun drain-supervisor (supervisor &key (max-steps 1000))
  "Reject new supervised tells, suppress restarts, then drain a bounded number
of rounds. Remaining mailboxes are discarded on :DRAIN-LIMIT. No wall-time bound."
  (unless (typep max-steps '(integer 1 *))
    (fail 'supervisor-error "MAX-STEPS must be a positive integer."))
  (when (member (supervisor-status supervisor) '(:failed :stopped))
    (return-from drain-supervisor (supervisor-status supervisor)))
  (when (supervisor-stepping-p supervisor)
    (fail 'supervisor-error "Drain must be initiated outside a supervisor tick."))
  (setf (supervisor-status supervisor) :draining)
  (unwind-protect
       (multiple-value-bind (status steps) (run-supervisor supervisor :max-steps max-steps)
         (declare (ignore steps))
         (let ((reason (if (eq status :step-limit) :drain-limit :drained)))
           (finish-supervisor supervisor :stopped reason)
           reason))
    (unless (member (supervisor-status supervisor) '(:stopped :failed))
      (finish-supervisor supervisor :stopped :drain-aborted))))

(defun supervisor-snapshot (supervisor)
  "Fresh host-side diagnostic data; no mutable application state or condition text.
The plist is not a wire manifest and does not implement the StarIntel registry."
  (list :name (copy-seq (supervisor-spec-name (supervisor-spec supervisor)))
        :status (supervisor-status supervisor)
        :reason (supervisor-terminal-reason supervisor)
        :strategy :one-for-one
        :next-restart-at (next-restart-at supervisor)
        :children
        (loop for child in (supervisor-children supervisor)
              for actor = (child-actor child)
              collect (list :name (copy-seq (starlangruntime:actor-definition-name
                                            (starlangruntime:actor-instance-definition actor)))
                            :status (child-status child)
                            :generation (starlangruntime:actor-instance-generation actor)
                            :restart-class (starlangruntime:actor-definition-restart-policy
                                            (starlangruntime:actor-instance-definition actor))
                            :restarts (child-restarts child)
                            :last-exit (child-last-exit child)
                            :due-at (child-due-at child)
                            :mailbox-depth (starlangruntime:actor-mailbox-depth actor)))))
