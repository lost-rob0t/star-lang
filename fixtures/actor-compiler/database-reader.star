(actor database-reader
  (:runtime native
   :service-uri "star://database:localhost:database-reader"
   :accepts (org.starintel/database@1/db-read-request
             org.starintel/database@1/db-subscribe-request)
   :produces (org.starintel/database@1/db-result
              org.starintel/database@1/db-error)
   :handler database-reader-handler
   :restart permanent
   :mailbox (bounded 256)
   :capabilities (databaseRead databaseSubscribe)
   :metadata ((domain "database") (role "reader"))))
