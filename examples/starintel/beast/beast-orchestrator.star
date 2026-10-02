(actor beast-orchestrator
  (:runtime external
   :service-uri "star://starintel:beast:beast-orchestrator"
   :protocol a2a-v1
   :endpoint "env:STARINTEL_A2A_BEAST_ORCHESTRATOR_URL"
   :accepts (org.starintel/research-request@1 org.starintel/workflow-event@1)
   :produces (org.starintel/work-assignment@1 org.starintel/workflow-run@1)
   :restart permanent
   :mailbox (bounded 4096)
   :capabilities (a2a-v1 delegated-work bounded-backpressure resumable-workflows)
   :metadata ((domain "starintel") (program "beast-100m") (role "orchestrator"))))
