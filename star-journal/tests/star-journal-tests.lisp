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
                       (idempotency-key "journal-key"))
  (staractorprotocol:make-command-envelope
   :message-id message-id
   :message-type "test/journal@1/command"
   :actor "journal-test"
   :idempotency-key idempotency-key
   :payload nil))

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
  (test-file-journal-round-trip)
  (test-event-shape-validation)
  (test-replay-order-validation)
  (test-backend-errors-are-typed)
  (test-final-system-is-prototype-independent)
  (format t "~&star-journal tests passed~%")
  t)
