(actor recon-domain
  (:runtime external
   :service-uri "star://starintel:beast:recon-domain"
   :protocol a2a-v1
   :endpoint "env:STARINTEL_A2A_RECON_DOMAIN_URL"
   :accepts (org.starintel/domain-target@1 org.starintel/recon-program@1)
   :produces (org.starintel/domain-observation@1 org.starintel/recon-result@1)
   :restart permanent
   :mailbox (bounded 2048)
   :capabilities (a2a-v1 dns rdap certificate-transparency http-metadata star-bbp-programs)
   :metadata ((domain "starintel") (program "beast-100m") (role "recon") (scope "public-network-metadata"))))
