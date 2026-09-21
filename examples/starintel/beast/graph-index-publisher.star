(actor graph-index-publisher
  (:runtime external
   :service-uri "star://starintel:beast:graph-index-publisher"
   :protocol a2a-v1
   :endpoint "env:STARINTEL_A2A_GRAPH_INDEX_PUBLISHER_URL"
   :accepts (org.starintel/document@1 org.starintel/evidence-assessment@1 org.starintel/archive-record@1)
   :produces (org.starintel/graph-update@1 org.starintel/index-update@1 org.starintel/dataset-stats@1)
   :restart permanent
   :mailbox (bounded 8192)
   :capabilities (a2a-v1 graph-upsert search-index dataset-accounting checkpoints)
   :metadata ((domain "starintel") (program "beast-100m") (role "publisher"))))
