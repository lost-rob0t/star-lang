(defpackage :stardatabaseprotocol
  (:use :cl)
  (:nicknames :star-database-protocol)
  (:export
   #:+database-read-capability+
   #:+database-write-capability+
   #:+database-transaction-capability+
   #:+database-subscribe-capability+
   #:+database-admin-capability+
   #:+database-read-request-type+
   #:+database-write-request-type+
   #:+database-transaction-request-type+
   #:+database-subscribe-request-type+
   #:+database-result-type+
   #:+database-write-result-type+
   #:+database-error-type+
   #:database-contract-error
   #:database-contract-error-code
   #:database-access-capability
   #:database-message-access
   #:database-actor-capability-p
   #:validate-database-actor-access
   #:database-read-only-actor-p))
