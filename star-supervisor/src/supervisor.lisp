(in-package :starsupervisor)

(define-condition supervisor-error (error)
  ((message :initarg :message :reader supervisor-error-message))
  (:report
   (lambda (condition stream)
     (write-string (supervisor-error-message condition) stream))))

(define-condition invalid-supervisor-error (supervisor-error) ())

(define-condition restart-budget-exhausted-error (supervisor-error)
  ((supervisor-id :initarg :supervisor-id
                  :reader restart-budget-exhausted-supervisor-id)
   (child-id :initarg :child-id
             :reader restart-budget-exhausted-child-id)
   (max-restarts :initarg :max-restarts
                 :reader restart-budget-exhausted-max-restarts)
   (restart-window :initarg :restart-window
                   :reader restart-budget-exhausted-restart-window)))

(defun fail-supervisor (condition-type control &rest arguments)
  (error condition-type :message (apply #'format nil control arguments)))

(defun valid-id-p (value)
  (and (stringp value) (> (length value) 0)))

(defun ensure-id (value label)
  (unless (valid-id-p value)
    (fail-supervisor 'invalid-supervisor-error
                     "~A must be a non-empty string, received ~S."
                     label value))
  value)

(defun ensure-restart-class (value)
  (unless (member value '(:permanent :transient :temporary) :test #'eq)
    (fail-supervisor 'invalid-supervisor-error
                     "Restart class must be :PERMANENT, :TRANSIENT, or :TEMPORARY, received ~S."
                     value))
  value)

(defun default-clock ()
  (/ (get-internal-real-time)
     internal-time-units-per-second))

(defun ensure-supervisor-options (max-restarts restart-window clock)
  (unless (and (integerp max-restarts) (>= max-restarts 0))
    (fail-supervisor 'invalid-supervisor-error
                     "MAX-RESTARTS must be a non-negative integer, received ~S."
                     max-restarts))
  (unless (and (realp restart-window) (> restart-window 0))
    (fail-supervisor 'invalid-supervisor-error
                     "RESTART-WINDOW must be a positive real number, received ~S."
                     restart-window))
  (unless (functionp clock)
    (fail-supervisor 'invalid-supervisor-error
                     "CLOCK must be a function, received ~S."
                     clock))
  (values max-restarts restart-window clock))

(defun plist-without-key (plist key)
  (loop for (candidate value) on plist by #'cddr
        unless (eq candidate key)
          append (list candidate value)))

(defstruct (child-spec (:constructor %make-child-spec))
  id
  kind
  definition
  name
  receive
  options
  restart-class)

(defun make-runtime-child-spec (id definition)
  (ensure-id id "Child id")
  (unless (starlangruntime:actor-definition-p definition)
    (fail-supervisor 'invalid-supervisor-error
                     "Runtime child ~A requires an actor definition, received ~S."
                     id definition))
  (%make-child-spec
   :id id
   :kind :runtime
   :definition definition
   :restart-class
   (ensure-restart-class
    (starlangruntime:actor-definition-restart-policy definition))))

(defun make-sento-child-spec (id name receive &rest options)
  (ensure-id id "Child id")
  (ensure-id name "Sento actor name")
  (unless (functionp receive)
    (fail-supervisor 'invalid-supervisor-error
                     "Sento child ~A requires a receive function, received ~S."
                     id receive))
  (let ((restart-class (getf options :restart-class :permanent)))
    (%make-child-spec
     :id id
     :kind :sento
     :name name
     :receive receive
     :options (plist-without-key options :restart-class)
     :restart-class (ensure-restart-class restart-class))))

(defstruct (supervised-child (:constructor %make-supervised-child))
  spec
  backend-ref
  (generation 0)
  (status :new)
  last-exit
  last-condition)

(defstruct (supervisor (:constructor %make-supervisor))
  id
  kind
  context
  port
  children
  child-order
  (status :new)
  (max-restarts 3)
  (restart-window 5)
  clock
  restart-times
  terminal-condition)

(defun make-child-table (specs)
  (let ((children (make-hash-table :test #'equal))
        (order '()))
    (dolist (spec specs)
      (unless (child-spec-p spec)
        (fail-supervisor 'invalid-supervisor-error
                         "Supervisor child spec must be a STAR-SUPERVISOR child spec, received ~S."
                         spec))
      (let ((id (child-spec-id spec)))
        (when (gethash id children)
          (fail-supervisor 'invalid-supervisor-error
                           "Duplicate supervisor child id ~S."
                           id))
        (setf (gethash id children)
              (%make-supervised-child :spec spec))
        (push id order)))
    (values children (nreverse order))))

(defun make-supervisor-common
    (id kind context port specs max-restarts restart-window clock)
  (ensure-id id "Supervisor id")
  (ensure-supervisor-options max-restarts restart-window clock)
  (multiple-value-bind (children order)
      (make-child-table specs)
    (%make-supervisor
     :id id
     :kind kind
     :context context
     :port port
     :children children
     :child-order order
     :max-restarts max-restarts
     :restart-window restart-window
     :clock clock
     :restart-times '())))

(defun make-runtime-supervisor
    (id runtime specs
     &key (max-restarts 3) (restart-window 5) (clock #'default-clock))
  (unless (starlangruntime:runtime-p runtime)
    (fail-supervisor 'invalid-supervisor-error
                     "Runtime supervisor requires a StarLang runtime, received ~S."
                     runtime))
  (dolist (spec specs)
    (unless (and (child-spec-p spec)
                 (eq :runtime (child-spec-kind spec)))
      (fail-supervisor 'invalid-supervisor-error
                       "Runtime supervisor child ~S is not a runtime child spec."
                       spec)))
  (make-supervisor-common
   id :runtime runtime nil specs max-restarts restart-window clock))

(defun make-sento-supervisor
    (id port context specs
     &key (max-restarts 3) (restart-window 5) (clock #'default-clock))
  (unless (starsentocompat:runtime-port-p port)
    (fail-supervisor 'invalid-supervisor-error
                     "Sento supervisor requires a runtime port, received ~S."
                     port))
  (dolist (spec specs)
    (unless (and (child-spec-p spec)
                 (eq :sento (child-spec-kind spec)))
      (fail-supervisor 'invalid-supervisor-error
                       "Sento supervisor child ~S is not a Sento child spec."
                       spec)))
  (make-supervisor-common
   id :sento context port specs max-restarts restart-window clock))

(defun find-supervised-child (supervisor child-id)
  (unless (supervisor-p supervisor)
    (fail-supervisor 'invalid-supervisor-error
                     "Expected a supervisor, received ~S."
                     supervisor))
  (or (gethash child-id (supervisor-children supervisor))
      (fail-supervisor 'invalid-supervisor-error
                       "Supervisor ~A has no child ~S."
                       (supervisor-id supervisor) child-id)))

(defun runtime-child-reference (child actor)
  (declare (ignore child))
  (starlangruntime:actor-reference actor))

(defun spawn-child (supervisor child)
  (let ((spec (supervised-child-spec child)))
    (ecase (supervisor-kind supervisor)
      (:runtime
       (let ((actor
               (starlangruntime:spawn
                (supervisor-context supervisor)
                (child-spec-definition spec))))
         (setf (supervised-child-backend-ref child)
               (runtime-child-reference child actor)
               (supervised-child-generation child)
               (starlangruntime:actor-instance-generation actor)
               (supervised-child-status child) :running
               (supervised-child-last-exit child) nil
               (supervised-child-last-condition child) nil)))
      (:sento
       (let ((actor
               (apply #'starsentocompat:runtime-spawn
                      (supervisor-port supervisor)
                      (supervisor-context supervisor)
                      (child-spec-name spec)
                      (child-spec-receive spec)
                      (child-spec-options spec))))
         (setf (supervised-child-backend-ref child) actor
               (supervised-child-status child) :running
               (supervised-child-last-exit child) nil
               (supervised-child-last-condition child) nil)))))
  child)

(defun stop-runtime-child (supervisor child)
  (let* ((runtime (supervisor-context supervisor))
         (reference (supervised-child-backend-ref child))
         (actor (and reference
                     (handler-case
                         (starlangruntime:resolve-actor runtime reference)
                       (starlangruntime:actor-not-found-error () nil)))))
    (when (and actor (starlangruntime:actor-running-p actor))
      (starlangruntime:stop-actor runtime reference))))

(defun stop-sento-child (supervisor child)
  (let ((actor (supervised-child-backend-ref child)))
    (when (and actor
               (starsentocompat:sento-actor-live-p
                (supervisor-context supervisor) actor))
      (starsentocompat:runtime-stop
       (supervisor-port supervisor)
       (supervisor-context supervisor)
       actor
       :wait t))))

(defun stop-child (supervisor child)
  (ecase (supervisor-kind supervisor)
    (:runtime (stop-runtime-child supervisor child))
    (:sento (stop-sento-child supervisor child)))
  (setf (supervised-child-status child) :stopped)
  child)

(defun start-supervisor (supervisor)
  (unless (supervisor-p supervisor)
    (fail-supervisor 'invalid-supervisor-error
                     "Expected a supervisor, received ~S."
                     supervisor))
  (case (supervisor-status supervisor)
    (:running supervisor)
    (:new
     (handler-case
         (progn
           (dolist (id (supervisor-child-order supervisor))
             (spawn-child supervisor (find-supervised-child supervisor id)))
           (setf (supervisor-status supervisor) :running)
           supervisor)
       (error (condition)
         (dolist (id (supervisor-child-order supervisor))
           (let ((child (find-supervised-child supervisor id)))
             (when (eq :running (supervised-child-status child))
               (ignore-errors (stop-child supervisor child)))))
         (setf (supervisor-status supervisor) :failed
               (supervisor-terminal-condition supervisor) condition)
         (error condition))))
    (otherwise
     (fail-supervisor 'invalid-supervisor-error
                      "Supervisor ~A is terminal in state ~S and cannot be started."
                      (supervisor-id supervisor)
                      (supervisor-status supervisor)))))

(defun restart-required-p (restart-class reason)
  (ecase restart-class
    (:permanent t)
    (:transient (eq reason :failure))
    (:temporary nil)))

(defun prune-restart-times (supervisor now)
  (setf (supervisor-restart-times supervisor)
        (remove-if
         (lambda (timestamp)
           (>= (- now timestamp) (supervisor-restart-window supervisor)))
         (supervisor-restart-times supervisor))))

(defun mark-budget-exhausted (supervisor child)
  (let ((condition
          (make-condition
           'restart-budget-exhausted-error
           :message
           (format nil
                   "Supervisor ~A exhausted restart budget (~D restarts in ~A seconds) while restarting child ~A."
                   (supervisor-id supervisor)
                   (supervisor-max-restarts supervisor)
                   (supervisor-restart-window supervisor)
                   (child-spec-id (supervised-child-spec child)))
           :supervisor-id (supervisor-id supervisor)
           :child-id (child-spec-id (supervised-child-spec child))
           :max-restarts (supervisor-max-restarts supervisor)
           :restart-window (supervisor-restart-window supervisor))))
    (setf (supervisor-status supervisor) :failed
          (supervisor-terminal-condition supervisor) condition)
    (dolist (id (supervisor-child-order supervisor))
      (let ((owned-child (find-supervised-child supervisor id)))
        (when (eq :running (supervised-child-status owned-child))
          (stop-child supervisor owned-child))))
    (setf (supervised-child-status child) :failed)
    (error condition)))

(defun consume-restart-budget (supervisor child)
  (let ((now (funcall (supervisor-clock supervisor))))
    (unless (realp now)
      (fail-supervisor 'invalid-supervisor-error
                       "Supervisor clock returned non-real value ~S."
                       now))
    (prune-restart-times supervisor now)
    (when (>= (length (supervisor-restart-times supervisor))
              (supervisor-max-restarts supervisor))
      (mark-budget-exhausted supervisor child))
    (push now (supervisor-restart-times supervisor))
    now))

(defun restart-runtime-child (supervisor child)
  (let* ((runtime (supervisor-context supervisor))
         (actor
           (starlangruntime:restart-actor
            runtime (supervised-child-backend-ref child)))
         (reference (starlangruntime:actor-reference actor)))
    (setf (supervised-child-backend-ref child) reference
          (supervised-child-generation child)
          (starlangruntime:actor-instance-generation actor)
          (supervised-child-status child) :running)
    child))

(defun restart-sento-child (supervisor child)
  (stop-sento-child supervisor child)
  (let* ((spec (supervised-child-spec child))
         (actor
           (apply #'starsentocompat:runtime-spawn
                  (supervisor-port supervisor)
                  (supervisor-context supervisor)
                  (child-spec-name spec)
                  (child-spec-receive spec)
                  (child-spec-options spec))))
    (incf (supervised-child-generation child))
    (setf (supervised-child-backend-ref child) actor
          (supervised-child-status child) :running)
    child))

(defun restart-child (supervisor child)
  (consume-restart-budget supervisor child)
  (ecase (supervisor-kind supervisor)
    (:runtime (restart-runtime-child supervisor child))
    (:sento (restart-sento-child supervisor child))))

(defun supervisor-handle-child-exit
    (supervisor child-id reason
     &key condition (observed-generation nil observed-generation-p))
  (unless (member reason '(:normal :failure) :test #'eq)
    (fail-supervisor 'invalid-supervisor-error
                     "Child exit reason must be :NORMAL or :FAILURE, received ~S."
                     reason))
  (unless observed-generation-p
    (fail-supervisor 'invalid-supervisor-error
                     "Child exit observation for ~S requires :OBSERVED-GENERATION."
                     child-id))
  (unless (and (integerp observed-generation) (>= observed-generation 0))
    (fail-supervisor 'invalid-supervisor-error
                     "Observed child generation must be a non-negative integer, received ~S."
                     observed-generation))
  (let* ((child (find-supervised-child supervisor child-id))
         (restart-class
           (child-spec-restart-class (supervised-child-spec child))))
    (unless (= observed-generation (supervised-child-generation child))
      (return-from supervisor-handle-child-exit :stale))
    (setf (supervised-child-last-exit child) reason
          (supervised-child-last-condition child) condition)
    (cond
      ((not (eq :running (supervisor-status supervisor)))
       (stop-child supervisor child)
       :suppressed)
      ((restart-required-p restart-class reason)
       (restart-child supervisor child)
       :restarted)
      (t
       (stop-child supervisor child)
       :stopped))))

(defun supervisor-step (supervisor)
  (unless (eq :runtime (supervisor-kind supervisor))
    (fail-supervisor 'invalid-supervisor-error
                     "SUPERVISOR-STEP is only valid for final StarLang runtime supervisors."))
  (unless (eq :running (supervisor-status supervisor))
    (return-from supervisor-step 0))
  (let ((processed 0)
        (runtime (supervisor-context supervisor)))
    (dolist (id (supervisor-child-order supervisor))
      (let ((child (find-supervised-child supervisor id)))
        (when (eq :running (supervised-child-status child))
          (let* ((reference (supervised-child-backend-ref child))
                 (observed-generation (supervised-child-generation child))
                 (actor (starlangruntime:resolve-actor runtime reference)))
            (if (starlangruntime:actor-running-p actor)
                (let ((result (starlangruntime:dispatch-next runtime reference)))
                  (when result
                    (incf processed)
                    (when (eq :failed
                              (starlangruntime:dispatch-result-status result))
                      (supervisor-handle-child-exit
                       supervisor id :failure
                       :condition
                       (starlangruntime:dispatch-result-condition result)
                       :observed-generation observed-generation))))
                (supervisor-handle-child-exit
                 supervisor id :normal
                 :observed-generation observed-generation))))))
    processed))

(defun supervisor-child-reference (supervisor child-id)
  (unless (eq :runtime (supervisor-kind supervisor))
    (fail-supervisor 'invalid-supervisor-error
                     "Portable actor references are only available for final StarLang runtime children."))
  (supervised-child-backend-ref
   (find-supervised-child supervisor child-id)))

(defun supervisor-child-backend-ref (supervisor child-id)
  (supervised-child-backend-ref
   (find-supervised-child supervisor child-id)))

(defun supervisor-child-snapshot (supervisor child-id)
  (let* ((child (find-supervised-child supervisor child-id))
         (spec (supervised-child-spec child)))
    (list :id (child-spec-id spec)
          :status (supervised-child-status child)
          :restart-class (child-spec-restart-class spec)
          :generation (supervised-child-generation child)
          :last-exit (supervised-child-last-exit child)
          :last-condition (supervised-child-last-condition child))))

(defun supervisor-snapshot (supervisor)
  (unless (supervisor-p supervisor)
    (fail-supervisor 'invalid-supervisor-error
                     "Expected a supervisor, received ~S."
                     supervisor))
  (list :id (supervisor-id supervisor)
        :status (supervisor-status supervisor)
        :restart-count (length (supervisor-restart-times supervisor))
        :children
        (mapcar (lambda (id)
                  (supervisor-child-snapshot supervisor id))
                (supervisor-child-order supervisor))
        :terminal-condition (supervisor-terminal-condition supervisor)))

(defun drain-supervisor (supervisor)
  (unless (supervisor-p supervisor)
    (fail-supervisor 'invalid-supervisor-error
                     "Expected a supervisor, received ~S."
                     supervisor))
  (unless (member (supervisor-status supervisor) '(:stopped :failed) :test #'eq)
    (setf (supervisor-status supervisor) :draining)
    (dolist (id (supervisor-child-order supervisor))
      (let ((child (find-supervised-child supervisor id)))
        (when (eq :running (supervised-child-status child))
          (stop-child supervisor child))))
    (setf (supervisor-status supervisor) :stopped))
  supervisor)

(defun shutdown-supervisor (supervisor)
  (unless (supervisor-p supervisor)
    (fail-supervisor 'invalid-supervisor-error
                     "Expected a supervisor, received ~S."
                     supervisor))
  (if (eq :failed (supervisor-status supervisor))
      (dolist (id (supervisor-child-order supervisor))
        (let ((child (find-supervised-child supervisor id)))
          (when (eq :running (supervised-child-status child))
            (stop-child supervisor child))))
      (drain-supervisor supervisor))
  (setf (supervisor-status supervisor) :stopped)
  :stopped)