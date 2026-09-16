(defpackage :starjournal-boundary-tests
  (:use :cl)
  (:import-from :starjournal
                #:star-journal-error
                #:make-runtime-journal-port
                #:make-memory-runtime-journal-port
                #:runtime-journal-append
                #:runtime-journal-replay)
  (:export #:run-tests))

(in-package :starjournal-boundary-tests)

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

(defun command-with-payload (payload)
  (staractorprotocol:make-command-envelope
   :message-id "journal-boundary-command"
   :message-type "test/journal@1/command"
   :actor "journal-test"
   :idempotency-key "journal-boundary-key"
   :payload payload))

(defun event-with-payload (payload &key (sequence 1))
  (list :kind :pending
        :dispatcher-sequence sequence
        :dispatcher-now "1970-01-01T00:00:00Z"
        :command (command-with-payload payload)))

(defun nested-value (depth)
  (let ((value "leaf"))
    (dotimes (index depth value)
      (declare (ignore index))
      (setf value (list value)))))

(defun test-invalid-snapshot-never-enters-backend ()
  (let ((append-calls 0)
        (stored '()))
    (let ((journal
            (make-runtime-journal-port
             :append
             (lambda (event)
               (incf append-calls)
               (setf stored (append stored (list event)))
               :appended)
             :replay (lambda () stored))))
      (runtime-journal-append journal (event-with-payload '("good")))
      (let ((cycle (list "cycle")))
        (setf (cdr cycle) cycle)
        (check
         (signals-p 'star-journal-error
                    (lambda ()
                      (runtime-journal-append
                       journal (event-with-payload cycle :sequence 2))))
         "Journal accepted a circular payload."))
      (check (= 1 append-calls)
             "Rejected journal value reached the backend append callback.")
      (check (= 1 (length (runtime-journal-replay journal)))
             "Rejected append changed prior journal history."))))

(defun test-journal-rejects-excessive-depth-and-size ()
  (let ((journal (make-memory-runtime-journal-port)))
    (check
     (signals-p 'star-journal-error
                (lambda ()
                  (runtime-journal-append
                   journal
                   (event-with-payload (nested-value 70)))))
     "Journal accepted a payload beyond the portable snapshot depth bound.")
    (check
     (signals-p 'star-journal-error
                (lambda ()
                  (runtime-journal-append
                   journal
                   (event-with-payload (make-array 65537
                                                   :initial-element 0)))))
     "Journal accepted a vector beyond the portable snapshot size bound.")
    (check (null (runtime-journal-replay journal))
           "Rejected bounded values changed an empty journal.")))

(defun test-replay-rejects-backend-owned-cycle ()
  (let* ((cycle (list "cycle"))
         (event (event-with-payload cycle))
         (journal
           (make-runtime-journal-port
            :append (lambda (value)
                      (declare (ignore value))
                      :appended)
            :replay (lambda () (list event)))))
    (setf (cdr cycle) cycle)
    (check
     (signals-p 'star-journal-error
                (lambda () (runtime-journal-replay journal)))
     "Journal replay accepted circular backend-owned data.")))

(defun run-tests ()
  (test-invalid-snapshot-never-enters-backend)
  (test-journal-rejects-excessive-depth-and-size)
  (test-replay-rejects-backend-owned-cycle)
  (format t "~&star-journal boundary tests passed~%")
  t)
