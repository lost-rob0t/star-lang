(actor corroborate-verify
  (:runtime external
   :service-uri "star://starintel:beast:corroborate-verify"
   :protocol a2a-v1
   :endpoint "env:STARINTEL_A2A_CORROBORATE_VERIFY_URL"
   :accepts (org.starintel/document@1 org.starintel/provenance-record@1)
   :produces (org.starintel/evidence-assessment@1 org.starintel/research-review@1)
   :restart permanent
   :mailbox (bounded 4096)
   :capabilities (a2a-v1 cross-source-corroboration contradiction-detection confidence lineage)
   :metadata ((domain "starintel") (program "beast-100m") (role "verification"))))
