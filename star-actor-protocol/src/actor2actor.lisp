(in-package :staractorprotocol)

(defparameter +actor2actor-semantic-profile+ "star.actor2actor/1")

(defparameter *actor2actor-statuses*
  '(:accepted :running :completed :failed :cancelled :rejected
    :deadline-exceeded))

(defparameter *actor2actor-terminal-statuses*
  '(:completed :failed :cancelled :rejected :deadline-exceeded))

(define-condition invalid-actor2actor-task-error
    (star-actor-protocol-error)
  ())

(defun fail-invalid-actor2actor-task (control &rest arguments)
  (error 'invalid-actor2actor-task-error
         :message (apply #'format nil control arguments)))

(defun actor2actor-name-string (value)
  (cond
    ((stringp value) value)
    ((symbolp value) (symbol-name value))
    (t nil)))

(defun normalize-actor2actor-status (value)
  (let* ((name (actor2actor-name-string value))
         (status (and name
                      (find name *actor2actor-statuses*
                            :test #'string-equal :key #'symbol-name))))
    (unless (member status *actor2actor-statuses* :test #'eq)
      (fail-invalid-actor2actor-task
       "Actor2Actor status must be one of ~S, received ~S."
       *actor2actor-statuses* value))
    status))

(defun actor2actor-terminal-status-p (status)
  (not (null
        (member (normalize-actor2actor-status status)
                *actor2actor-terminal-statuses*
                :test #'eq))))

(defstruct (actor2actor-task
            (:constructor %make-actor2actor-task))
  task-id
  actor
  correlation-id
  status
  terminal-p
  last-message-id
  sequence
  result
  observation)

(defun actor2actor-required-string (value context)
  (unless (and (stringp value) (plusp (length value)))
    (fail-invalid-actor2actor-task
     "~A requires a non-empty string." context))
  (copy-seq value))

(defun actor2actor-nonnegative-integer (value context)
  (unless (and (integerp value) (>= value 0))
    (fail-invalid-actor2actor-task
     "~A requires a non-negative integer." context))
  value)

(defun validate-actor2actor-result (result actor correlation-id status)
  (when result
    (validate-lifecycle-envelope result)
    (unless (and (equal correlation-id (lifecycle-correlation-id result))
                 (equal actor (getf result :actor))
                 (actor2actor-terminal-status-p status)
                 (eq status (actor2actor-status-for-envelope result)))
      (fail-invalid-actor2actor-task
       "Actor2Actor result identity/status does not match its task."))))

(defun make-actor2actor-task
    (&key task-id actor correlation-id status
          last-message-id (sequence 0) result observation)
  (setf result (snapshot-portable-wire-value result))
  (unless (member observation '(nil :outcome-unknown))
    (fail-invalid-actor2actor-task "Invalid invocation observation."))
  (let* ((normalized-status (normalize-actor2actor-status status))
         (terminal-p (actor2actor-terminal-status-p normalized-status)))
    (validate-actor2actor-result result actor correlation-id normalized-status)
    (%make-actor2actor-task
     :task-id (actor2actor-required-string task-id "Actor2Actor task-id")
     :actor (actor2actor-required-string actor "Actor2Actor actor")
     :correlation-id
     (actor2actor-required-string
      correlation-id "Actor2Actor correlation-id")
     :status normalized-status
     :terminal-p terminal-p
     :last-message-id
     (and last-message-id
          (actor2actor-required-string
           last-message-id "Actor2Actor last-message-id"))
     :sequence
     (actor2actor-nonnegative-integer
      sequence "Actor2Actor task sequence")
     :result result
     :observation observation)))

(defun validate-actor2actor-task (task)
  (unless (actor2actor-task-p task)
    (fail-invalid-actor2actor-task
     "Expected an Actor2Actor task, received ~S." task))
  (actor2actor-required-string
   (actor2actor-task-task-id task) "Actor2Actor task-id")
  (actor2actor-required-string
   (actor2actor-task-actor task) "Actor2Actor actor")
  (actor2actor-required-string
   (actor2actor-task-correlation-id task) "Actor2Actor correlation-id")
  (let ((status
          (normalize-actor2actor-status
           (actor2actor-task-status task))))
    (unless (eq (not (null (actor2actor-task-terminal-p task)))
                (actor2actor-terminal-status-p status))
      (fail-invalid-actor2actor-task
       "Actor2Actor terminal flag does not match task status ~S." status)))
  (unless (member (actor2actor-task-observation task) '(nil :outcome-unknown))
    (fail-invalid-actor2actor-task "Invalid invocation observation."))
  (actor2actor-nonnegative-integer
   (actor2actor-task-sequence task) "Actor2Actor task sequence")
  (validate-actor2actor-result
   (actor2actor-task-result task) (actor2actor-task-actor task)
   (actor2actor-task-correlation-id task)
   (normalize-actor2actor-status (actor2actor-task-status task)))
  t)

(defun actor2actor-status-for-envelope (envelope)
  "Project one lifecycle envelope onto the canonical Actor2Actor task state."
  (validate-lifecycle-envelope envelope)
  (case (delivery-outcome envelope)
    (:accepted :accepted)
    (:completed :completed)
    (:rejected :rejected)
    (:retry :running)
    (:failed
     (let ((code (getf (getf envelope :payload) :code)))
       (cond
         ((and (stringp code)
               (string= code "star.cancelled"))
          :cancelled)
         ((and (stringp code)
               (string= code "star.deadline-exceeded"))
          :deadline-exceeded)
         ((and (stringp code)
               (string= code "star.outcome-unknown"))
          :outcome-unknown)
         (t :failed))))
    (:cancel-requested :running)
    (otherwise
     (case (getf envelope :kind)
       ((:command :event) :accepted)
       (otherwise :running)))))

(defun actor2actor-advance-task (task envelope &key status)
  "Return a new task generation after ENVELOPE without mutating TASK.

Terminal tasks are first-terminal-wins: any later envelope is rejected."
  (validate-actor2actor-task task)
  (setf envelope (snapshot-portable-wire-value envelope))
  (validate-lifecycle-envelope envelope)
  (when (actor2actor-task-terminal-p task)
    (fail-invalid-actor2actor-task
     "Actor2Actor task ~A is already terminal."
     (actor2actor-task-task-id task)))
  (unless (string=
           (actor2actor-task-correlation-id task)
           (lifecycle-correlation-id envelope))
    (fail-invalid-actor2actor-task
     "Actor2Actor envelope correlation-id does not match task ~A."
     (actor2actor-task-task-id task)))
  (unless (equal (actor2actor-task-actor task) (getf envelope :actor))
    (fail-invalid-actor2actor-task "Envelope actor does not match task."))
  (let* ((projected (actor2actor-status-for-envelope envelope))
         (unknown-p (eq projected :outcome-unknown))
         (next-status (cond (unknown-p (actor2actor-task-status task))
                            ((and (eq projected :accepted)
                                  (eq (actor2actor-task-status task) :running)) :running)
                            (t projected))))
    (when (and status (not (eq (normalize-actor2actor-status status) next-status)))
      (fail-invalid-actor2actor-task
       "An explicit status cannot override lifecycle evidence."))
    (make-actor2actor-task
     :task-id (actor2actor-task-task-id task)
     :actor (actor2actor-task-actor task)
     :correlation-id (actor2actor-task-correlation-id task)
     :status next-status
     :last-message-id (lifecycle-message-id envelope)
     :sequence (1+ (actor2actor-task-sequence task))
     :observation (when unknown-p :outcome-unknown)
     :result (when (actor2actor-terminal-status-p next-status) envelope))))

(defstruct (actor2actor-stream-frame
            (:constructor %make-actor2actor-stream-frame))
  task-id
  correlation-id
  sequence
  envelope
  terminal-p)

(defun make-actor2actor-stream-frame
    (&key task-id correlation-id sequence envelope terminal-p)
  (setf envelope (snapshot-portable-wire-value envelope))
  (validate-lifecycle-envelope envelope)
  (unless (and (integerp sequence) (plusp sequence))
    (fail-invalid-actor2actor-task
     "Actor2Actor stream sequence must be a positive integer."))
  (unless (string=
           (actor2actor-required-string
            correlation-id "Actor2Actor stream correlation-id")
           (lifecycle-correlation-id envelope))
    (fail-invalid-actor2actor-task
     "Actor2Actor stream envelope correlation-id mismatch."))
  (%make-actor2actor-stream-frame
   :task-id (actor2actor-required-string
             task-id "Actor2Actor stream task-id")
   :correlation-id (copy-seq correlation-id)
   :sequence sequence
   :envelope envelope
   :terminal-p (not (null terminal-p))))

(defun validate-actor2actor-stream-frame (frame)
  (unless (actor2actor-stream-frame-p frame)
    (fail-invalid-actor2actor-task
     "Expected an Actor2Actor stream frame."))
  (make-actor2actor-stream-frame
   :task-id (actor2actor-stream-frame-task-id frame)
   :correlation-id (actor2actor-stream-frame-correlation-id frame)
   :sequence (actor2actor-stream-frame-sequence frame)
   :envelope (actor2actor-stream-frame-envelope frame)
   :terminal-p (actor2actor-stream-frame-terminal-p frame))
  t)
