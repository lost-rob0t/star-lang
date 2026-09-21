(actor challenge-broker
  (:runtime external
   :service-uri "star://starintel:beast:challenge-broker"
   :protocol a2a-v1
   :endpoint "env:STARINTEL_A2A_CHALLENGE_BROKER_URL"
   :accepts (org.starintel/fetch-challenge@1)
   :produces (org.starintel/challenge-resolution@1 org.starintel/research-review@1)
   :restart permanent
   :mailbox (bounded 512)
   :capabilities (a2a-v1 human-in-loop authorized-challenge-provider audited-resolution)
   :metadata ((domain "starintel") (program "beast-100m") (role "challenge-broker") (policy "no-protection-bypass"))))
