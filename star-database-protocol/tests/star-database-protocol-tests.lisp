(defpackage :stardatabaseprotocol-tests
  (:use :cl)
  (:import-from :stardatabaseprotocol
                #:+database-read-request-type+
                #:+database-write-request-type+
                #:+database-result-type+
                #:database-contract-error
                #:database-message-access
                #:database-actor-capability-p
                #:validate-database-actor-access
                #:database-read-only-actor-p)
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
    (check (= 7 (length messages))
           "Expected seven canonical database messages, got ~D."
           (length messages))
    (dolist (expected
             '("db-read-request" "db-write-request"
               "db-transaction-request" "db-subscribe-request"
               "db-result" "db-write-result" "db-error"))
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

(defun run-tests ()
  (test-message-access-vocabulary)
  (test-read-and-write-capabilities-are-not-interchangeable)
  (test-database-vocabulary-compiles-with-lower-camel-fields)
  (format t "Star database protocol tests passed.~%")
  t)
