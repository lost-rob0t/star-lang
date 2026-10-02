(actor proxy-egress
  (:runtime external
   :service-uri "star://starintel:beast:proxy-egress"
   :protocol a2a-v1
   :endpoint "env:STARINTEL_A2A_PROXY_EGRESS_URL"
   :accepts (org.starintel/fetch-request@1)
   :produces (org.starintel/fetch-response@1 org.starintel/fetch-challenge@1)
   :restart permanent
   :mailbox (bounded 4096)
   :capabilities (a2a-v1 policy-routing tenant-isolation rate-limits egress-accounting)
   :metadata ((domain "starintel") (program "beast-100m") (role "egress") (policy "no-rate-limit-evasion"))))
