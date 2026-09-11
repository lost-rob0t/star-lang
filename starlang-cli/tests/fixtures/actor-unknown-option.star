(actor enrichment-worker
  (:runtime native
   :mystery 1
   :accepts (org.starintel/person@1)
   :produces (org.starintel/person@1)
   :handler enrichment-worker-handler
   :restart permanent
   :mailbox (bounded 128)))
