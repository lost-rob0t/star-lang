(actor gov-harvester
  (:runtime external
   :service-uri "star://starintel:beast:gov-harvester"
   :protocol a2a-v1
   :endpoint "env:STARINTEL_A2A_GOV_HARVESTER_URL"
   :accepts (org.starintel/source-catalog@1 org.starintel/harvest-checkpoint@1)
   :produces (org.starintel/raw-document@1 org.starintel/harvest-checkpoint@1)
   :restart permanent
   :mailbox (bounded 8192)
   :capabilities (a2a-v1 bulk-export incremental-fetch partitioned-fetch resumable-fetch)
   :metadata ((domain "starintel") (program "beast-100m") (role "collector"))))
