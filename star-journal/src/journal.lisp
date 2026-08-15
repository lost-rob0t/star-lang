(in-package :starjournal)

(define-condition star-journal-error (error)
  ((message :initarg :message :reader star-journal-error-message))
  (:report
   (lambda (condition stream)
     (write-string (star-journal-error-message condition) stream))))

(defun fail-journal (control &rest arguments)
  (error 'star-journal-error
         :message (apply #'format nil control arguments)))

(defun proper-plist-p (value)
  (loop with rest = value
        do (cond
             ((null rest) (return t))
             ((and (consp rest) (consp (cdr rest)))
              (setf rest (cddr rest)))
             (t (return nil)))))

(defun ensure-journal-plist (value context)
  (unless (proper-plist-p value)
    (fail-journal "~A must be a property list." context))
  value)

(defun journal-plist-has-key-p (plist key)
  (loop for tail on plist by #'cddr
        when (eq (first tail) key)
          do (return t)
        finally (return nil)))

(defun required-nonempty-string (value context)
  (unless (and (stringp value) (> (length value) 0))
    (fail-journal "~A requires a non-empty string." context))
  value)

(defstruct (runtime-journal-port
            (:constructor %make-runtime-journal-port))
  append-fn
  replay-fn)

(defun make-runtime-journal-port (&key append replay)
  (unless (functionp append)
    (fail-journal "Runtime journal append operation must be a function."))
  (unless (functionp replay)
    (fail-journal "Runtime journal replay operation must be a function."))
  (%make-runtime-journal-port
   :append-fn append
   :replay-fn replay))

(defun runtime-journal-event-kind-p (kind)
  (member kind '(:pending :route-result :remote-result) :test #'eq))

(defun validate-runtime-journal-result (event)
  (unless (journal-plist-has-key-p event :result)
    (fail-journal
     "Settled runtime journal event requires a dispatch result."))
  (let ((result (getf event :result)))
    (ensure-journal-plist result "runtime journal dispatch result")
    (unless (member (getf result :outcome)
                    '(:complete :retry :fail)
                    :test #'eq)
      (fail-journal
       "Runtime journal result requires complete, retry, or fail outcome."))
    result))

(defun validate-runtime-journal-command (command)
  (handler-case
      (staractorprotocol:validate-lifecycle-envelope
       command
       :validate-payload nil)
    (staractorprotocol:invalid-wire-envelope-error (condition)
      (fail-journal "Invalid runtime journal command: ~A" condition)))
  (unless (eq (getf command :kind) :command)
    (fail-journal
     "Runtime journal command must be a lifecycle command envelope."))
  command)

(defun validate-runtime-journal-event (event)
  (ensure-journal-plist event "runtime journal event")
  (let ((kind (getf event :kind))
        (sequence (getf event :dispatcher-sequence))
        (now (getf event :dispatcher-now))
        (command (getf event :command)))
    (unless (runtime-journal-event-kind-p kind)
      (fail-journal "Unknown runtime journal event kind ~S." kind))
    (unless (and (integerp sequence) (>= sequence 0))
      (fail-journal
       "Runtime journal dispatcher sequence must be a nonnegative integer."))
    (required-nonempty-string now "runtime journal dispatcher clock")
    (validate-runtime-journal-command command)
    (if (eq kind :pending)
        (when (journal-plist-has-key-p event :result)
          (fail-journal
           "Pending runtime journal event may not carry a result."))
        (validate-runtime-journal-result event))
    event))

(defun validate-runtime-journal-order (events)
  (loop with previous-sequence = nil
        with previous-now = nil
        for event in events
        for sequence = (getf event :dispatcher-sequence)
        for now = (getf event :dispatcher-now)
        do (when (and previous-sequence
                      (< sequence previous-sequence))
             (fail-journal
              "Runtime journal dispatcher sequence moved backward from ~D to ~D."
              previous-sequence sequence))
           (when (and previous-now (string< now previous-now))
             (fail-journal
              "Runtime journal dispatcher clock moved backward from ~A to ~A."
              previous-now now))
           (setf previous-sequence sequence
                 previous-now now))
  events)

(defun runtime-journal-append (port event)
  (unless (runtime-journal-port-p port)
    (fail-journal "Runtime journal append requires a journal port."))
  (handler-case
      (progn
        (validate-runtime-journal-event event)
        (funcall (runtime-journal-port-append-fn port)
                 (copy-tree event)))
    (star-journal-error (condition)
      (error condition))
    (error (condition)
      (fail-journal "Runtime journal append failed: ~A" condition))))

(defun runtime-journal-replay (port)
  (unless (runtime-journal-port-p port)
    (fail-journal "Runtime journal replay requires a journal port."))
  (handler-case
      (let ((events (funcall (runtime-journal-port-replay-fn port))))
        (unless (listp events)
          (fail-journal "Runtime journal replay must return a list."))
        (let ((validated
                (mapcar
                 (lambda (event)
                   (validate-runtime-journal-event event)
                   (copy-tree event))
                 events)))
          (validate-runtime-journal-order validated)
          validated))
    (star-journal-error (condition)
      (error condition))
    (error (condition)
      (fail-journal "Runtime journal replay failed: ~A" condition))))

(defun make-memory-runtime-journal-port ()
  (let ((events '()))
    (make-runtime-journal-port
     :append
     (lambda (event)
       (setf events (append events (list (copy-tree event))))
       :appended)
     :replay
     (lambda ()
       (copy-tree events)))))

(defun make-file-runtime-journal-port (pathname)
  (let ((path (pathname pathname)))
    (make-runtime-journal-port
     :append
     (lambda (event)
       (ensure-directories-exist path)
       (with-open-file
           (stream path
                   :direction :output
                   :if-exists :append
                   :if-does-not-exist :create)
         (with-standard-io-syntax
           (let ((*print-readably* t)
                 (*print-pretty* nil)
                 (*print-circle* nil))
             (write event :stream stream)
             (terpri stream)
             (finish-output stream))))
       :appended)
     :replay
     (lambda ()
       (if (probe-file path)
           (with-open-file (stream path :direction :input)
             (with-standard-io-syntax
               (let ((*read-eval* nil)
                     (eof (gensym "EOF")))
                 (loop for event = (read stream nil eof)
                       until (eq event eof)
                       collect event))))
           '())))))
