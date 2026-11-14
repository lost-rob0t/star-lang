(spec-library "org.starintel/ingest@1"
  (:version "1.0.0")

  (scalar program-id
    (:base string
     :pattern "^[a-z0-9][a-z0-9-]{2,63}$"))

  (scalar source-id
    (:base string
     :pattern "^[A-Za-z0-9._~-]{1,255}$"))

  (document ingest/source
    (:persistence persistent
     :fields
     ((programId program-id :required)
      (sourceId source-id :required)
      (note string :optional))))

  (message ingest/record@1
    (:fields
     ((programId program-id :required)
      (sourceId source-id :required)
      (note string :required))))

  (message ingest/state@1
    (:fields
     ((programId program-id :required)
      (lastSource source-id :required)))))
