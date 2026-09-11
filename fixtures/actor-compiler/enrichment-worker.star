(actor enrichment-worker
  (:runtime native
   :service-uri "star://starintel:localhost:enrichment-worker"
   :accepts (org.starintel/person@1)
   :produces (org.starintel/person@1)
   :handler enrichment-worker-handler
   :restart permanent
   :mailbox (bounded 128)
   :metadata ((domain "starintel") (team "enrichment"))))
