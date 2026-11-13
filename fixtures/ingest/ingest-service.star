(actor ingest-service
  (:runtime native
   :service-uri "star://starintel.dev/actor/ingest-service"
   :accepts (ingest/record@1)
   :produces (ingest/state@1)
   :restart permanent
   :mailbox (bounded 32)
   :metadata ((domain "starintel") (team "ingest") (transport "zmq-req-rep")))

  (state
    (lastSource string :initial "" :persistence journaled))

  (on ingest/record@1 (message context)
    (let ((source (field message sourceId)))
      (when source
        (set lastSource source)))
    (reply (construct ingest/state@1
                      (programId (field message programId))
                      (lastSource (state lastSource))))))
