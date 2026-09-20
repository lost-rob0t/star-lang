(actor database-a2a-reader
  (:runtime external
   :service-uri "star://database:remote:database-a2a-reader"
   :protocol a2a-v1
   :endpoint "https://example.invalid/a2a"
   :accepts (org.starintel/database@1/db-read-request)
   :produces (org.starintel/database@1/db-result
              org.starintel/database@1/db-error)
   :restart transient
   :mailbox (bounded 128)
   :capabilities (databaseRead)
   :metadata ((domain "database") (transport "a2a"))))
