(actor database-writer
  (:runtime native
   :service-uri "star://database:localhost:database-writer"
   :accepts (org.starintel/database@1/db-write-request
             org.starintel/database@1/db-transaction-request)
   :produces (org.starintel/database@1/db-write-result
              org.starintel/database@1/db-error)
   :handler database-writer-handler
   :restart permanent
   :mailbox (bounded 128)
   :capabilities (databaseWrite databaseTransaction)
   :metadata ((domain "database") (role "writer"))))
