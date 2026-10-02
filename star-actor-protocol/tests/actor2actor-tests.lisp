(defpackage :staractorprotocol-actor2actor-tests
  (:use :cl)
  (:import-from :staractorprotocol
                #:+actor2actor-semantic-profile+
                #:invalid-actor2actor-task-error
                #:make-command-envelope
                #:make-ack-envelope
                #:make-error-envelope
                #:make-reply-envelope
                #:make-actor2actor-task
                #:validate-actor2actor-task
                #:actor2actor-task-status
                #:actor2actor-task-terminal-p
                #:actor2actor-task-sequence
                #:actor2actor-task-last-message-id
                #:actor2actor-status-for-envelope
                #:actor2actor-advance-task
                #:make-actor2actor-stream-frame
                #:validate-actor2actor-stream-frame
                #:actor2actor-stream-frame-sequence)
  (:export #:run-tests))

(in-package :staractorprotocol-actor2actor-tests)

(defun assert-test (condition label)
  (unless condition
    (error "Actor2Actor protocol test failed: ~A" label)))

(defun assert-equal (expected actual label)
  (assert-test (equal expected actual)
               (format nil "~A expected ~S got ~S"
                       label expected actual)))

(defun signals-a2a-error-p (thunk)
  (handler-case
      (progn (funcall thunk) nil)
    (invalid-actor2actor-task-error () t)))

(defun command ()
  (make-command-envelope
   :message-id "cmd-1"
   :message-type "test/run@1"
   :actor "worker"
   :sender "caller"
   :payload '(:value 1)
   :idempotency-key "idem-1"
   :correlation-id "corr-1"))

(defun test-semantic-profile-is-versioned ()
  (assert-equal "star.actor2actor/1"
                +actor2actor-semantic-profile+
                "semantic profile"))

(defun test-task-advances-through-terminal-state ()
  (let* ((task
           (make-actor2actor-task
            :task-id "task-1"
            :actor "worker"
            :correlation-id "corr-1"
            :status :accepted))
         (ack
           (make-ack-envelope
            (command)
            :message-id "ack-1"
            :actor "worker"
            :status :completed))
         (done (actor2actor-advance-task task ack)))
    (assert-test (validate-actor2actor-task done)
                 "terminal task validates")
    (assert-equal :completed
                  (actor2actor-task-status done)
                  "completed status")
    (assert-test (actor2actor-task-terminal-p done)
                 "completed is terminal")
    (assert-equal 1 (actor2actor-task-sequence done)
                  "task sequence increments")
    (assert-equal "ack-1"
                  (actor2actor-task-last-message-id done)
                  "last message recorded")
    (assert-test
     (signals-a2a-error-p
      (lambda () (actor2actor-advance-task done ack)))
     "first terminal outcome wins")))

(defun test-error-status-mapping ()
  (let* ((source (command))
         (deadline
           (make-error-envelope
            source
            :message-id "err-deadline"
            :actor "worker"
            :code "star.deadline-exceeded"
            :message "late"
            :retryable nil))
         (unknown
           (make-error-envelope
            source
            :message-id "err-unknown"
            :actor "worker"
            :code "star.outcome-unknown"
            :message "unknown"
            :retryable nil))
         (fault
           (make-error-envelope
            source
            :message-id "err-fault"
            :actor "worker"
            :code "star.backend-fault"
            :message "boom"
            :retryable nil)))
    (assert-equal :deadline-exceeded
                  (actor2actor-status-for-envelope deadline)
                  "deadline maps")
    (assert-equal :outcome-unknown
                  (actor2actor-status-for-envelope unknown)
                  "unknown maps")
    (assert-equal :failed
                  (actor2actor-status-for-envelope fault)
                  "fault maps")))

(defun test-correlation-mismatch-is-rejected ()
  (let* ((task
           (make-actor2actor-task
            :task-id "task-1"
            :actor "worker"
            :correlation-id "other"
            :status :accepted))
         (reply
           (make-reply-envelope
            (command)
            :message-id "reply-1"
            :message-type "test/result@1"
            :actor "worker"
            :payload '(:value 1))))
    (assert-test
     (signals-a2a-error-p
      (lambda () (actor2actor-advance-task task reply)))
     "mismatched correlation rejected")))

(defun test-stream-frame-is-bounded-identity-unit ()
  (let* ((reply
           (make-reply-envelope
            (command)
            :message-id "reply-1"
            :message-type "test/result@1"
            :actor "worker"
            :payload '(:value 1)))
         (frame
           (make-actor2actor-stream-frame
            :task-id "task-1"
            :correlation-id "corr-1"
            :sequence 1
            :envelope reply
            :terminal-p nil)))
    (assert-test (validate-actor2actor-stream-frame frame)
                 "stream frame validates")
    (assert-equal 1
                  (actor2actor-stream-frame-sequence frame)
                  "stream sequence")
    (assert-test
     (signals-a2a-error-p
      (lambda ()
        (make-actor2actor-stream-frame
         :task-id "task-1"
         :correlation-id "corr-1"
         :sequence 0
         :envelope reply)))
     "zero stream sequence rejected")))

(defun run-tests ()
  (test-semantic-profile-is-versioned)
  (test-task-advances-through-terminal-state)
  (test-error-status-mapping)
  (test-correlation-mismatch-is-rejected)
  (test-stream-frame-is-bounded-identity-unit)
  (format t "Actor2Actor protocol tests passed.~%")
  t)
