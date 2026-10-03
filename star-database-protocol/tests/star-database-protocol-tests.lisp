(defpackage :stardatabaseprotocol-tests
  (:use :cl)
  (:import-from :stardatabaseprotocol
                #:+database-read-request-type+
                #:+database-write-request-type+
                #:+database-result-type+
                #:+database-stream-page-type+
                #:database-contract-error
                #:database-message-access
                #:database-actor-capability-p
                #:validate-database-actor-access
                #:database-read-only-actor-p
                #:make-database-stream-state
                #:database-stream-state-checkpoint
                #:database-stream-state-committed-items
                #:reduce-database-stream-page)
  (:export #:run-tests))

(in-package :stardatabaseprotocol-tests)

(defun check (truth control &rest arguments)
  (unless truth
    (error (apply #'format nil control arguments))))

(defun signals-p (condition-type thunk)
  (handler-case
      (progn (funcall thunk) nil)
    (error (condition)
      (typep condition condition-type))))

(defun protocol-root ()
  (asdf:system-source-directory :star-database-protocol))

(defun fixture-path (relative)
  (merge-pathnames relative (protocol-root)))

(defun compile-actor-fixture (name)
  (starlangcompiler:compile-actor-file
   (fixture-path (format nil "../fixtures/actor-compiler/~A.star" name))))

(defun compile-database-library ()
  (let ((source
          (uiop:read-file-string
           (fixture-path "../fixtures/star-database-core.star"))))
    (starlangcompiler:compile-spec-library
     (starlangcompiler:read-star-syntax
      source :source-id "fixtures/star-database-core.star"))))

(defun test-message-access-vocabulary ()
  (check (eq :read
             (database-message-access +database-read-request-type+))
         "Read request did not map to :READ.")
  (check (eq :write
             (database-message-access +database-write-request-type+))
         "Write request did not map to :WRITE.")
  (check (null (database-message-access +database-result-type+))
         "Result type was treated as an operation request."))

(defun test-read-and-write-capabilities-are-not-interchangeable ()
  (let ((reader (compile-actor-fixture "database-reader"))
        (writer (compile-actor-fixture "database-writer")))
    (check (database-actor-capability-p reader :read)
           "Reader lacks databaseRead.")
    (check (database-read-only-actor-p reader)
           "Reader is not structurally read-only.")
    (check
     (signals-p
      'database-contract-error
      (lambda () (validate-database-actor-access reader :write)))
     "Reader was accepted for write access.")
    (check (database-actor-capability-p writer :write)
           "Writer lacks databaseWrite.")
    (check (database-actor-capability-p writer :transaction)
           "Writer lacks databaseTransaction.")
    (check (not (database-read-only-actor-p writer))
           "Writer was classified read-only.")))

(defun test-database-vocabulary-compiles-with-lower-camel-fields ()
  (let* ((library (compile-database-library))
         (messages
           (loop for item in (getf library :declarations)
                 when (eq (getf item :kind) :message)
                   collect item))
         (names (mapcar (lambda (item) (getf item :name)) messages)))
    (check (string= "1.1.0" (getf library :version))
           "Database portable library version was not advanced to 1.1.0.")
    (check (= 8 (length messages))
           "Expected eight canonical database messages, got ~D."
           (length messages))
    (dolist (expected
             '("db-read-request" "db-write-request"
               "db-transaction-request" "db-subscribe-request"
               "db-result" "db-stream-page" "db-write-result" "db-error"))
      (check (member expected names :test #'string=)
             "Missing database message ~A." expected))
    (dolist (message messages)
      (dolist (field (getf message :fields))
        (let ((name (getf field :name)))
          (check
           (and (stringp name)
                (not (find #\_ name))
                (not (find #\- name)))
           "Database field is not lowerCamelCase: ~S" name))))))

(defun stream-item (change-id &optional value)
  (list :change-id change-id :value value))

(defun test-stream-page-contract-is-first-class ()
  (check (null (database-message-access +database-stream-page-type+))
         "A stream page response was treated as an operation request.")
  (let* ((library (compile-database-library))
         (page
           (find "db-stream-page"
                 (getf library :declarations)
                 :key (lambda (item) (getf item :name))
                 :test #'string=))
         (fields (mapcar (lambda (field) (getf field :name))
                         (getf page :fields))))
    (check page "Missing first-class db-stream-page contract.")
    (dolist (field '("requestId" "database" "operation" "inputCheckpoint"
                     "outputCheckpoint" "items" "terminal"))
      (check (member field fields :test #'string=)
             "db-stream-page missing field ~A." field))))

(defun test-stream-reducer-commit-barrier ()
  (let* ((state (make-database-stream-state :checkpoint "10-a"))
         (seen (make-hash-table :test #'equal))
         (fail-once t)
         (items (list (stream-item "c11" "one")
                      (stream-item "c12" "two"))))
    (labels ((apply-change (item)
               (let ((id (getf item :change-id)))
                 (cond
                   ((gethash id seen) :duplicate)
                   ((and fail-once (string= id "c12"))
                    (setf fail-once nil)
                    :retry)
                   (t
                    (setf (gethash id seen) t)
                    :applied)))))
      (multiple-value-bind (first first-status)
          (reduce-database-stream-page
           state "10-a" "12-c" items #'apply-change)
        (check (eq :retry first-status) "Partial page did not retry.")
        (check (eq state first) "Retry replaced committed state.")
        (check (string= "10-a" (database-stream-state-checkpoint first))
               "Retry advanced checkpoint."))
      (multiple-value-bind (second second-status)
          (reduce-database-stream-page
           state "10-a" "12-c" items #'apply-change)
        (check (eq :committed second-status)
               "Replay did not commit after duplicate recognition.")
        (check (string= "12-c" (database-stream-state-checkpoint second))
               "Committed page did not advance checkpoint.")
        (check (= 2 (database-stream-state-committed-items second))
               "Committed item count is wrong.")))))

(defun test-stream-reducer-fails-closed ()
  (let ((state (make-database-stream-state :checkpoint "22-z"))
        (apply-fn (lambda (item) (declare (ignore item)) :applied)))
    (check
     (signals-p
      'database-contract-error
      (lambda ()
        (reduce-database-stream-page
         state "21-y" "23-a"
         (list (stream-item "c23"))
         apply-fn)))
     "Stale page was accepted.")
    (check
     (signals-p
      'database-contract-error
      (lambda ()
        (reduce-database-stream-page
         state "22-z" "23-a"
         (list (stream-item "same") (stream-item "same"))
         apply-fn)))
     "Duplicate change id was accepted.")
    (check
     (signals-p
      'database-contract-error
      (lambda ()
        (reduce-database-stream-page
         state "22-z" "22-z"
         (list (stream-item "c23"))
         apply-fn)))
     "Non-advancing page was accepted.")))

(defun test-opaque-checkpoint-preservation ()
  (let* ((token "3-g1AAAABXeJzLYWBgYMpgSmHgKy5JLCrJTq2MT8lPzkzJ")
         (next "4-g1AAAABXeJzLYWBgYMpgSmHgKy5JLCrJTq2MT8lPzkzJ")
         (state (make-database-stream-state :checkpoint token)))
    (multiple-value-bind (after status)
        (reduce-database-stream-page
         state token next
         (list (stream-item "opaque-1"))
         (lambda (item) (declare (ignore item)) :applied))
      (check (eq :committed status) "Opaque page did not commit.")
      (check (string= next (database-stream-state-checkpoint after))
             "Opaque checkpoint was transformed."))))

(defun run-tests ()
  (test-message-access-vocabulary)
  (test-read-and-write-capabilities-are-not-interchangeable)
  (test-database-vocabulary-compiles-with-lower-camel-fields)
  (test-stream-page-contract-is-first-class)
  (test-stream-reducer-commit-barrier)
  (test-stream-reducer-fails-closed)
  (test-opaque-checkpoint-preservation)
  (format t "Star database protocol tests passed.~%")
  t)
