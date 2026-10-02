(actor archive-preserve
  (:runtime external
   :service-uri "star://starintel:beast:archive-preserve"
   :protocol a2a-v1
   :endpoint "env:STARINTEL_A2A_ARCHIVE_PRESERVE_URL"
   :accepts (org.starintel/document@1 org.starintel/provenance-record@1)
   :produces (org.starintel/archive-record@1)
   :restart permanent
   :mailbox (bounded 4096)
   :capabilities (a2a-v1 archival hashing timestamping chain-of-custody object-storage)
   :metadata ((domain "starintel") (program "beast-100m") (role "preservation"))))
