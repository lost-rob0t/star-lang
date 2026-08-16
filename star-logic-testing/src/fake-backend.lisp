(in-package :starlogictesting)

(defstruct fake-operation
  id
  answers
  (index 0)
  (state +logic-operation-running+)
  cancel-reason)

(defclass fake-logic-backend ()
  ((descriptor
    :initarg :descriptor
    :reader %fake-backend-descriptor)
   (scripts
    :initarg :scripts
    :reader %fake-backend-scripts)
   (operation-sequence
    :initform 0
    :accessor %fake-backend-operation-sequence)))

(defun fake-logic-backend-p (value)
  (typep value 'fake-logic-backend))

(defclass fake-logic-session ()
  ((id
    :initarg :id
    :reader fake-logic-session-id)
   (backend
    :initarg :backend
    :reader %fake-session-backend)
   (closed-p
    :initform nil
    :accessor %fake-session-closed-p)
   (deltas
    :initform '()
    :accessor %fake-session-deltas)
   (operations
    :initform (make-hash-table :test #'equal)
    :reader %fake-session-operations)))

(defun fake-logic-session-p (value)
  (typep value 'fake-logic-session))

(defun fake-logic-session-deltas (session)
  (reverse (copy-tree (%fake-session-deltas session))))

(defun %copy-scripts (scripts)
  (unless (listp scripts)
    (error 'logic-session-error
           :message (format nil "Fake scripts must be an alist, got ~S." scripts)))
  (mapcar (lambda (entry)
            (unless (and (consp entry)
                         (stringp (car entry))
                         (listp (cdr entry)))
              (error 'logic-session-error
                     :message (format nil "Invalid fake script entry ~S." entry)))
            (cons (car entry) (copy-tree (cdr entry))))
          scripts))

(defun make-fake-logic-backend
    (&key
       (id "fake")
       (version "1")
       (build-id "fake-build")
       (semantic-profiles '("star.logic.query/1"))
       (capabilities '("named-query" "bounded-results"))
       (isolation-classes '("in-memory-test"))
       (hard-limits '("answers" "output-bytes"))
       (cooperative-limits '("wall-time"))
       scripts)
  (make-instance
   'fake-logic-backend
   :descriptor
   (make-logic-backend-descriptor
    :id id
    :version version
    :build-id build-id
    :semantic-profiles semantic-profiles
    :capabilities capabilities
    :isolation-classes isolation-classes
    :hard-limits hard-limits
    :cooperative-limits cooperative-limits)
   :scripts (%copy-scripts scripts)))

(defmethod logic-backend-descriptor-of ((backend fake-logic-backend))
  (%fake-backend-descriptor backend))

(defun %ensure-open-session (backend session)
  (unless (and (fake-logic-session-p session)
               (eq backend (%fake-session-backend session)))
    (error 'logic-session-error
           :message "Fake logic session belongs to a different backend."))
  (when (%fake-session-closed-p session)
    (error 'logic-session-error
           :message "Fake logic session is closed."))
  session)

(defun %lookup-operation (backend session operation-id)
  (%ensure-open-session backend session)
  (or (gethash operation-id (%fake-session-operations session))
      (error 'logic-session-error
             :message (format nil "Unknown fake operation ~S." operation-id))))

(defmethod open-logic-session
    ((backend fake-logic-backend) session-id &key package-id package-digest)
  (declare (ignore package-id package-digest))
  (unless (and (stringp session-id) (plusp (length session-id)))
    (error 'logic-session-error
           :message (format nil "Session id must be a non-empty string, got ~S."
                            session-id)))
  (make-instance 'fake-logic-session :id session-id :backend backend))

(defmethod close-logic-session
    ((backend fake-logic-backend) (session fake-logic-session))
  (%ensure-open-session backend session)
  (setf (%fake-session-closed-p session) t)
  :closed)

(defmethod apply-logic-fact-delta
    ((backend fake-logic-backend) (session fake-logic-session) delta)
  (%ensure-open-session backend session)
  (push (copy-tree delta) (%fake-session-deltas session))
  :applied)

(defmethod invoke-logic-operation
    ((backend fake-logic-backend)
     (session fake-logic-session)
     operation-id
     parameters
     &key limits)
  (declare (ignore parameters limits))
  (%ensure-open-session backend session)
  (let ((script (assoc operation-id (%fake-backend-scripts backend)
                       :test #'string=)))
    (unless script
      (error 'unsupported-logic-operation-error
             :message (format nil "Fake backend has no script for operation ~S."
                              operation-id)))
    (incf (%fake-backend-operation-sequence backend))
    (let* ((operation-handle
             (format nil "fake-op-~D" (%fake-backend-operation-sequence backend)))
           (operation
             (make-fake-operation
              :id operation-handle
              :answers (copy-tree (cdr script)))))
      (setf (gethash operation-handle (%fake-session-operations session)) operation)
      operation-handle)))

(defmethod next-logic-result
    ((backend fake-logic-backend)
     (session fake-logic-session)
     operation-handle)
  (let ((operation (%lookup-operation backend session operation-handle)))
    (case (fake-operation-state operation)
      (:cancelled
       (values nil +logic-operation-cancelled+))
      (:completed
       (values nil +logic-operation-completed+))
      (:no-answer
       (values nil +logic-operation-no-answer+))
      (otherwise
       (let* ((answers (fake-operation-answers operation))
              (index (fake-operation-index operation)))
         (if (>= index (length answers))
             (progn
               (setf (fake-operation-state operation)
                     (if (zerop index)
                         +logic-operation-no-answer+
                         +logic-operation-completed+))
               (values nil (fake-operation-state operation)))
             (let ((answer (copy-tree (nth index answers))))
               (incf (fake-operation-index operation))
               (when (= (fake-operation-index operation) (length answers))
                 (setf (fake-operation-state operation)
                       +logic-operation-completed+))
               (values answer :answer))))))))

(defmethod cancel-logic-operation
    ((backend fake-logic-backend)
     (session fake-logic-session)
     operation-handle
     reason)
  (let ((operation (%lookup-operation backend session operation-handle)))
    (unless (member (fake-operation-state operation)
                    (list +logic-operation-completed+
                          +logic-operation-no-answer+
                          +logic-operation-cancelled+)
                    :test #'eq)
      (setf (fake-operation-state operation) +logic-operation-cancelled+
            (fake-operation-cancel-reason operation) reason))
    (fake-operation-state operation)))

(defmethod logic-operation-status
    ((backend fake-logic-backend)
     (session fake-logic-session)
     operation-handle)
  (fake-operation-state (%lookup-operation backend session operation-handle)))

(defmethod logic-backend-health ((backend fake-logic-backend))
  (list :status :ok
        :backend-id
        (logic-backend-descriptor-id (%fake-backend-descriptor backend))))
