(spec-library "org.starintel/fec@1"
  (:version "1.0.0"
   :digest "sha256:fec-core-v1-research-fixture")

  (import "org.starintel/core@1"
    :version "1.0.0"
    :digest "sha256:core-v1-research-fixture")

  (scalar candidate-id
    (:base string
     :pattern "^[HSP][A-Z0-9]{8}$"))

  (scalar committee-id
    (:base string
     :pattern "^C[0-9]{8}$"))

  (scalar file-number
    (:base integer
     :minimum 1))

  (scalar fec-money
    (:base decimal
     :scale 2))

  (scalar state-code
    (:base string
     :pattern "^[A-Z]{2}$"))

  (enum office
    (president senate house))

  (enum amendment-status
    (new amendment termination unknown))

  (enum support-oppose
    (support oppose unknown))

  (document entity
    (:persistence persistent)
    (fecId string :optional)
    (name string :required)
    (street1 string :optional)
    (street2 string :optional)
    (city string :optional)
    (state state-code :optional)
    (zipCode string :optional)
    (employer string :optional)
    (occupation string :optional)
    (raw map :required))

  (document candidate
    (:extends entity
     :persistence persistent)
    (candidateId candidate-id :required)
    (partyCode string :optional)
    (partyName string :optional)
    (office office :required)
    (officeState state-code :optional)
    (officeDistrict string :optional)
    (electionYears (list integer) :required))

  (document committee
    (:extends entity
     :persistence persistent)
    (committeeId committee-id :required)
    (committeeTypeCode string :optional)
    (designationCode string :optional)
    (connectedOrganizationName string :optional)
    (treasurerName string :optional)
    (candidateIds (list candidate-id) :optional))

  (document filing
    (:persistence persistent)
    (fileNumber file-number :required)
    (committeeId committee-id :required)
    (formType string :required)
    (reportType string :optional)
    (amendmentStatus amendment-status :required)
    (previousFileNumber file-number :optional)
    (coverageStartDate iso-date :optional)
    (coverageEndDate iso-date :optional)
    (receiptDate iso-date :optional)
    (imageNumber string :optional)
    (mostRecent boolean :required)
    (raw map :required))

  (document receipt
    (:persistence persistent)
    (committeeId committee-id :required)
    (contributor reference :required)
    (transactionDate iso-date :required)
    (amount fec-money :required)
    (aggregateAmount fec-money :optional)
    (fileNumber file-number :optional)
    (transactionId string :optional)
    (subId string :optional)
    (amendmentStatus amendment-status :required)
    (memoText string :optional)
    (raw map :required))

  (document disbursement
    (:persistence persistent)
    (committeeId committee-id :required)
    (payee reference :required)
    (transactionDate iso-date :required)
    (amount fec-money :required)
    (purpose string :optional)
    (fileNumber file-number :optional)
    (transactionId string :optional)
    (subId string :optional)
    (amendmentStatus amendment-status :required)
    (raw map :required))

  (document independent-expenditure
    (:persistence persistent)
    (committeeId committee-id :required)
    (candidateId candidate-id :required)
    (supportOppose support-oppose :required)
    (expenditureDate iso-date :required)
    (amount fec-money :required)
    (payee reference :optional)
    (purpose string :optional)
    (fileNumber file-number :optional)
    (transactionId string :optional)
    (subId string :optional)
    (amendmentStatus amendment-status :required)
    (raw map :required))

  (predicate candidate-committee
    (:source candidate
     :destination committee))

  (predicate contributed-to
    (:source entity
     :destination committee))

  (predicate paid-to
    (:source committee
     :destination entity))

  (predicate independent-expenditure-about
    (:source committee
     :destination candidate))

  (predicate filed
    (:source committee
     :destination filing))

  (message ingest-page
    (:fields
     ((endpoint string :required)
      (cycle integer :optional)
      (page integer :required)
      (results (list map) :required)
      (retrievedAt iso-datetime :required))))

  (message resolve-amendments
    (:fields
     ((committeeId committee-id :required)
      (cycle integer :required)
      (records (list reference) :required))))

  (message index-fec-record
    (:fields
     ((document reference :required)
      (sourceEndpoint string :required)
      (cycle integer :optional)))))
