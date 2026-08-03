(spec-library "org.starintel/bbp@1"
  (:version "1.0.0"
   :digest "sha256:bbp-domain-v1-research-fixture")

  (import "org.starintel/core@1"
    :version "1.0.0"
    :digest "sha256:core-v1-research-fixture")

  (scalar program-id
    (:base string
     :pattern "^[a-z0-9][a-z0-9._:-]{2,127}$"))

  (scalar run-id
    (:base string
     :pattern "^[a-z0-9][a-z0-9._:-]{2,127}$"))

  (scalar domain-name
    (:base string
     :pattern "^[A-Za-z0-9.-]+$"))

  (enum tool-name
    (subfinder httpx katana nmap))

  (enum tool-run-status
    (queued running completed failed cancelled))

  (document program
    (:persistence persistent)
    (programId program-id :required)
    (name string :required)
    (scope (list string) :required)
    (raw map :required))

  (document target
    (:persistence persistent)
    (programId program-id :required)
    (value string :required)
    (kind symbol :required)
    (inScope boolean :required)
    (raw map :required))

  (document tool-run
    (:persistence persistent)
    (runId run-id :required)
    (programId program-id :required)
    (tool tool-name :required)
    (target string :required)
    (argv (list string) :required)
    (status tool-run-status :required)
    (exitCode integer :optional)
    (stdout string :optional)
    (stderr string :optional)
    (raw map :required))

  (document tool-observation
    (:persistence persistent)
    (runId run-id :required)
    (programId program-id :required)
    (tool tool-name :required)
    (target string :required)
    (value string :required)
    (raw map :required))

  (message register-program
    (:fields
     ((programId program-id :required)
      (name string :required)
      (scope (list string) :required))))

  (message program-registered
    (:fields
     ((programId program-id :required)
      (scope (list string) :required))))

  (message run-tool
    (:fields
     ((programId program-id :required)
      (runId run-id :required)
      (tool tool-name :required)
      (target string :required)
      (options map :optional))))

  (message tool-run-completed
    (:fields
     ((programId program-id :required)
      (runId run-id :required)
      (tool tool-name :required)
      (target string :required)
      (argv (list string) :required)
      (exitCode integer :required)
      (stdout string :required)
      (stderr string :required))))

  (message get-program-state
    (:fields
     ((programId program-id :required))))

  (message program-state
    (:fields
     ((programId program-id :required)
      (scope (list string) :required)
      (runs integer :required)))))
