(spec-library "org.starintel/database@1"
  (:version "1.0.0")

  (scalar logical-database-id
    (:base string
     :pattern "^[A-Za-z0-9._-]{1,128}$"))

  (scalar database-operation-id
    (:base string
     :pattern "^[A-Za-z0-9._/-]{1,256}$"))

  (enum database-access
    (read write transaction subscribe admin))

  (enum database-result-kind
    (document row graph fact acknowledgement stream-page))

  (enum database-error-kind
    (invalid-request unauthorized capability-denied database-unavailable
     operation-unavailable timeout cancelled conflict precondition-failed
     transaction-aborted result-limit-exceeded malformed-backend-result
     backend-fault outcome-unknown))

  (message db-read-request
    (:fields
     ((requestId string :required)
      (database logical-database-id :required)
      (operation database-operation-id :required)
      (bindings map :required)
      (deadlineMs integer :optional)
      (resultLimit integer :optional))))

  (message db-write-request
    (:fields
     ((requestId string :required)
      (database logical-database-id :required)
      (operation database-operation-id :required)
      (bindings map :required)
      (idempotencyKey string :required)
      (precondition map :optional)
      (deadlineMs integer :optional))))

  (message db-transaction-request
    (:fields
     ((requestId string :required)
      (database logical-database-id :required)
      (operations (list map) :required)
      (isolation string :required)
      (idempotencyKey string :required)
      (deadlineMs integer :optional))))

  (message db-subscribe-request
    (:fields
     ((requestId string :required)
      (database logical-database-id :required)
      (operation database-operation-id :required)
      (bindings map :required)
      (checkpoint string :optional)
      (deadlineMs integer :optional))))

  (message db-result
    (:fields
     ((requestId string :required)
      (database logical-database-id :required)
      (operation database-operation-id :required)
      (kind database-result-kind :required)
      (items (list map) :required)
      (checkpoint string :optional)
      (terminal boolean :required))))

  (message db-write-result
    (:fields
     ((requestId string :required)
      (database logical-database-id :required)
      (operation database-operation-id :required)
      (affected integer :required)
      (revision string :optional)
      (terminal boolean :required))))

  (message db-error
    (:fields
     ((requestId string :required)
      (database logical-database-id :required)
      (operation database-operation-id :required)
      (kind database-error-kind :required)
      (retryable boolean :required)
      (message string :required)))))
