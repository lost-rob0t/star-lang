(defpackage :starjournal-tests
  (:use :cl)
  (:import-from :starjournal
                #:star-journal-error
                #:make-runtime-journal-port
                #:make-memory-runtime-journal-port
                #:make-file-runtime-journal-port
                #:runtime-journal-append
                #:runtime-journal-replay)
  (:export #:run-tests))

(in-package :starjournal-tests)

(defun check (truth control &rest arguments)
  (unless truth
    (error (apply #'format nil control arguments))))

(defun signals-p (condition-type thunk)
  (handler-case
      (progn
        (funcall thunk)
        nil)
    (error (condition)
      (typep condition condition-type))))

(defun test-command (&key
                       (message-id "journal-command")
                       (idempotency-key "journal-key")
                       payload)
  (staractorprotocol:make-command-envelope
   :message-id message-id
   :message-type "test/journal@1/command"
   :actor "journal-test"
   :idempotency-key idempotency-key
   :payload payload))

(defun pending-event (&key
                        (sequence 1)
                        (now "1970-01-01T00:00:00Z")
                        (command (test-command)))
  (list :kind :pending
        :dispatcher-sequence sequence
        :dispatcher-now now
        :command command))

(defun settled-event (&key
                        (kind :route-result)
                        (outcome :retry)
                        (sequence 1)
                        (now "1970-01-01T00:00:00Z")
                        (command (test-command)))
  (list :kind kind
        :dispatcher-sequence sequence
        :dispatcher-now now
        :command command
        :result (list :outcome outcome)))

(defun nested-payload-string (event)
  (cdr (assoc "nested"
              (getf (getf event :command) :payload)
              :test #'string=)))

(defun payload-vector (event)
  (cdr (assoc "items"
              (getf (getf event :command) :payload)
              :test #'string=)))

(defun test-memory-journal-round-trip-and-copying ()
  (let* ((journal (make-memory-runtime-journal-port))
         (event (pending-event)))
    (check (eq :appended (runtime-journal-append journal event))
           "Memory journal append did not report success.")
    (let ((first-replay (runtime-journal-replay journal)))
      (check (equal (list event) first-replay)
             "Memory journal did not replay the appended event.")
      (setf (getf (first first-replay) :kind) :remote-result)
      (check (eq :pending
                 (getf (first (runtime-journal-replay journal)) :kind))
             "Memory journal replay did not return defensive copies."))))

(defun test-memory-journal-owns-mutable-leaves-on-append ()
  (let* ((journal (make-memory-runtime-journal-port))
         (message-id (copy-seq "command-1"))
         (clock (copy-seq "1970-01-01T00:00:00Z"))
         (nested (copy-seq "alpha"))
         (items (vector (copy-seq "first") (copy-seq "second")))
         (command
           (test-command
            :message-id message-id
            :payload (list (cons "nested" nested)
                           (cons "items" items))))
         (event (pending-event :now clock :command command)))
    (runtime-journal-append journal event)
    (setf (char message-id 0) #\X
          (char clock 0) #\X
          (char nested 0) #\X
          (char (aref items 0) 0) #\X)
    (setf (aref items 1) "replacement")
    (let ((stored (first (runtime-journal-replay journal))))
      (check (string= "command-1"
                      (getf (getf stored :command) :message-id))
             "Journal append retained caller-owned message-id string.")
      (check (string= "1970-01-01T00:00:00Z"
                      (getf stored :dispatcher-now))
             "Journal append retained caller-owned clock string.")
      (check (string= "alpha" (nested-payload-string stored))
             "Journal append retained a nested caller-owned payload string.")
      (check (equalp #("first" "second") (payload-vector stored))
             "Journal append retained caller-owned vector state."))))

(defun test-memory-journal-replay-returns-owned-mutable-leaves ()
  (let* ((journal (make-memory-runtime-journal-port))
         (command
           (test-command
            :message-id (copy-seq "command-1")
            :payload
            (list (cons "nested" (copy-seq "alpha"))
                  (cons "items"
                        (vector (copy-seq "first")
                                (copy-seq "second"))))))
         (event
           (pending-event
            :now (copy-seq "1970-01-01T00:00:00Z")
            :command command)))
    (runtime-journal-append journal event)
    (let ((first (first (runtime-journal-replay journal))))
      (setf (char (getf (getf first :command) :message-id) 0) #\X
            (char (getf first :dispatcher-now) 0) #\X
            (char (nested-payload-string first) 0) #\X
            (char (aref (payload-vector first) 0) 0) #\X)
      (setf (aref (payload-vector first) 1) "replacement"))
    (let ((second (first (runtime-journal-replay journal))))
      (check (string= "command-1"
                      (getf (getf second :command) :message-id))
             "Mutating one replay changed later message-id replay.")
      (check (string= "1970-01-01T00:00:00Z"
                      (getf second :dispatcher-now))
             "Mutating one replay changed later clock replay.")
      (check (string= "alpha" (nested-payload-string second))
             "Mutating one replay changed later nested payload replay.")
      (check (equalp #("first" "second") (payload-vector second))
             "Mutating one replay changed later vector replay."))))

(defun test-custom-backend-boundary-owns-values ()
  (let ((stored '()))
    (let* ((journal
             (make-runtime-journal-port
              :append
              (lambda (event)
                (setf stored (list event))
                :appended)
              :replay (lambda () stored)))
           (message-id (copy-seq "custom-command"))
           (event
             (pending-event
              :command (test-command :message-id message-id))))
      (runtime-journal-append journal event)
      (setf (char message-id 0) #\X)
      (check (string= "custom-command"
                      (getf (getf (first stored) :command) :message-id))
             "Journal passed caller-owned mutable data into custom append backend.")
      (let ((replay (runtime-journal-replay journal)))
        (setf (char (getf (getf (first replay) :command) :message-id) 0)
              #\Y))
      (check (string= "custom-command"
                      (getf (getf (first stored) :command) :message-id))
             "Journal exposed custom backend-owned mutable data through replay."))))

(defun test-file-journal-round-trip ()
  (let* ((path #p"/tmp/star-journal-final-test.sexp")
         (event (pending-event)))
    (unwind-protect
         (progn
           (when (probe-file path)
             (delete-file path))
           (let ((journal (make-file-runtime-journal-port path)))
             (check (eq :appended (runtime-journal-append journal event))
                    "File journal append did not report success.")
             (check (equal (list event) (runtime-journal-replay journal))
                    "File journal did not preserve the existing readable event format.")))
      (when (probe-file path)
        (delete-file path)))))

(defun test-event-shape-validation ()
  (let ((journal (make-memory-runtime-journal-port)))
    (check
     (signals-p
      'star-journal-error
      (lambda ()
        (runtime-journal-append
         journal
         (append (pending-event)
                 (list :result (list :outcome :retry))))))
     "Pending event accepted a result.")
    (check
     (signals-p
      'star-journal-error
      (lambda ()
        (runtime-journal-append
         journal
         (list :kind :route-result
               :dispatcher-sequence 1
               :dispatcher-now "1970-01-01T00:00:00Z"
               :command (test-command)))))
     "Settled event accepted a missing result.")
    (check
     (signals-p
      'star-journal-error
      (lambda ()
        (runtime-journal-append journal (settled-event :outcome :defer))))
     "Settled event accepted a deferred outcome.")
    (check
     (signals-p
      'star-journal-error
      (lambda ()
        (let ((event (pending-event)))
          (setf (getf (getf event :command) :kind) :event)
          (runtime-journal-append journal event))))
     "Journal accepted a non-command lifecycle envelope.")
    (check
     (signals-p
      'star-journal-error
      (lambda ()
        (runtime-journal-append
         journal
         (pending-event :sequence -1))))
     "Journal accepted a negative dispatcher sequence.")))

(defun test-replay-order-validation ()
  (let ((sequence-port
          (make-runtime-journal-port
           :append (lambda (event)
                     (declare (ignore event))
                     :appended)
           :replay
           (lambda ()
             (list (pending-event :sequence 2)
                   (pending-event :sequence 1)))))
        (clock-port
          (make-runtime-journal-port
           :append (lambda (event)
                     (declare (ignore event))
                     :appended)
           :replay
           (lambda ()
             (list
              (pending-event :sequence 1 :now "1970-01-01T00:00:02Z")
              (pending-event :sequence 1 :now "1970-01-01T00:00:01Z"))))))
    (check
     (signals-p 'star-journal-error
                (lambda () (runtime-journal-replay sequence-port)))
     "Journal accepted backward dispatcher sequence ordering.")
    (check
     (signals-p 'star-journal-error
                (lambda () (runtime-journal-replay clock-port)))
     "Journal accepted backward dispatcher clock ordering.")))

(defun test-backend-errors-are-typed ()
  (let ((journal
          (make-runtime-journal-port
           :append (lambda (event)
                     (declare (ignore event))
                     (error "append boom"))
           :replay (lambda () (error "replay boom")))))
    (check
     (signals-p 'star-journal-error
                (lambda ()
                  (runtime-journal-append journal (pending-event))))
     "Journal did not type a backend append failure.")
    (check
     (signals-p 'star-journal-error
                (lambda () (runtime-journal-replay journal)))
     "Journal did not type a backend replay failure.")))

(defun test-final-system-is-prototype-independent ()
  (check
   (null (find-package "STAR-LANG.CORE-SURFACE.PROTOTYPE"))
   "star-journal loaded the prototype package transitively."))

(defun run-tests ()
  (test-memory-journal-round-trip-and-copying)
  (test-memory-journal-owns-mutable-leaves-on-append)
  (test-memory-journal-replay-returns-owned-mutable-leaves)
  (test-custom-backend-boundary-owns-values)
  (test-file-journal-round-trip)
  (test-event-shape-validation)
  (test-replay-order-validation)
  (test-backend-errors-are-typed)
  (test-final-system-is-prototype-independent)
  (format t "~&star-journal tests passed~%")
  t)
