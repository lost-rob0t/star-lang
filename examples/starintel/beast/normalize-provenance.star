(actor normalize-provenance
  (:runtime external
   :service-uri "star://starintel:beast:normalize-provenance"
   :protocol a2a-v1
   :endpoint "env:STARINTEL_A2A_NORMALIZE_PROVENANCE_URL"
   :accepts (org.starintel/raw-document@1)
   :produces (org.starintel/document@1 org.starintel/provenance-record@1)
   :restart permanent
   :mailbox (bounded 8192)
   :capabilities (a2a-v1 normalization canonical-hash provenance schema-validation)
   :metadata ((domain "starintel") (program "beast-100m") (role "normalizer"))))
