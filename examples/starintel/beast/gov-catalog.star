(actor gov-catalog
  (:runtime external
   :service-uri "star://starintel:beast:gov-catalog"
   :protocol a2a-v1
   :endpoint "env:STARINTEL_A2A_GOV_CATALOG_URL"
   :accepts (org.starintel/jurisdiction-target@1 org.starintel/source-seed@1)
   :produces (org.starintel/source-catalog@1)
   :restart permanent
   :mailbox (bounded 2048)
   :capabilities (a2a-v1 socrata ckan arcgis feed-discovery)
   :metadata ((domain "starintel") (program "beast-100m") (role "source-discovery"))))
