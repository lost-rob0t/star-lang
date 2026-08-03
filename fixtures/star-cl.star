(spec-library "org.starintel/star-cl@1"
  (:version "1.0.0")

  (scalar document-id
    (:base string
     :pattern "^[A-Za-z0-9._~:/+-]{1,512}$"))

  (scalar unix-time
    (:base integer
     :minimum 0))

  (scalar confidence-score
    (:base decimal
     :minimum 0
     :maximum 1
     :scale 4))

  (scalar latitude
    (:base decimal
     :minimum -90
     :maximum 90
     :scale 8))

  (scalar longitude
    (:base decimal
     :minimum -180
     :maximum 180
     :scale 8))

  (scalar port-number
    (:base integer
     :minimum 0
     :maximum 65535))

  (scalar asn-number
    (:base integer
     :minimum 0
     :maximum 4294967295))

  (scalar uri
    (:base string
     :format uri))

  (enum id-kind
    (ulid uuidv4 digest supplied))

  (enum id-algorithm
    (md5 sha256))

  (enum collection-status
    (raw normalized enriched verified disputed stale deleted unknown))

  (enum sensitivity
    (public internal confidential restricted secret unknown))

  (enum visibility
    (public private shared inherited unknown))

  (document document
    (:persistence persistent
     :id-policy (:kind ulid))
    (id document-id :required)
    (rev string :optional)
    (dataset string :required)
    (dtype string :required)
    (schemaVersion string :required)
    (externalIds map :optional)
    (aliases (list string) :optional)
    (sources (list reference) :optional)
    (sourceUrls (list uri) :optional)
    (sourceRecordIds (list string) :optional)
    (sourceKinds (list string) :optional)
    (sourceLicense string :optional)
    (sourceTerms uri :optional)
    (sourceRetrievedAt unix-time :optional)
    (collectedAt unix-time :optional)
    (observedAt unix-time :optional)
    (firstSeenAt unix-time :optional)
    (lastSeenAt unix-time :optional)
    (createdAt unix-time :required)
    (updatedAt unix-time :required)
    (dateAdded unix-time :required)
    (dateUpdated unix-time :required)
    (validFrom unix-time :optional)
    (validUntil unix-time :optional)
    (expiresAt unix-time :optional)
    (collector string :optional)
    (collectorVersion string :optional)
    (collectionMethod string :optional)
    (collectionStatus collection-status :optional)
    (runId string :optional)
    (correlationId string :optional)
    (causationId string :optional)
    (parentId document-id :optional)
    (rootId document-id :optional)
    (confidence confidence-score :optional)
    (confidenceBasis string :optional)
    (qualityScore confidence-score :optional)
    (completenessScore confidence-score :optional)
    (verificationStatus string :optional)
    (verifiedAt unix-time :optional)
    (verifiedBy string :optional)
    (provenance map :optional)
    (chainOfCustody (list map) :optional)
    (transformHistory (list map) :optional)
    (labels (list string) :optional)
    (tags (list string) :optional)
    (topics (list string) :optional)
    (language string :optional)
    (jurisdiction string :optional)
    (countryCode string :optional)
    (regionCode string :optional)
    (timezone string :optional)
    (sensitivity sensitivity :optional)
    (visibility visibility :optional)
    (owner string :optional)
    (accessControl map :optional)
    (legalBasis string :optional)
    (retentionPolicy string :optional)
    (contentType string :optional)
    (encoding string :optional)
    (sizeBytes integer :optional)
    (contentHash string :optional)
    (hashAlgorithm id-algorithm :optional)
    (normalizedHash string :optional)
    (raw map :optional)
    (rawContent string :optional)
    (notes string :optional)
    (deleted boolean :optional)
    (tombstoneReason string :optional)
    (extensions map :optional))

  (document person
    (:extends document
     :persistence persistent
     :id-policy (:kind ulid))
    (fname string :optional)
    (mname string :optional)
    (lname string :optional)
    (fullName string :optional)
    (displayName string :optional)
    (prefix string :optional)
    (suffix string :optional)
    (bio string :optional)
    (dob iso-date :optional)
    (dateOfDeath iso-date :optional)
    (age integer :optional)
    (gender string :optional)
    (pronouns string :optional)
    (nationality (list string) :optional)
    (citizenship (list string) :optional)
    (occupation (list string) :optional)
    (employer (list reference) :optional)
    (education (list map) :optional)
    (skills (list string) :optional)
    (interests (list string) :optional)
    (region string :optional)
    (addresses (list reference) :optional)
    (emails (list reference) :optional)
    (phones (list reference) :optional)
    (accounts (list reference) :optional)
    (images (list reference) :optional)
    (misc (list map) :optional)
    (etype string :optional)
    (eid string :optional))

  (document org
    (:extends document
     :persistence persistent
     :id-policy (:kind digest
                 :algorithm md5
                 :fields (name reg country)))
    (reg string :optional)
    (name string :required)
    (legalName string :optional)
    (aliases (list string) :optional)
    (bio string :optional)
    (country string :optional)
    (jurisdiction string :optional)
    (website uri :optional)
    (registrationNumber string :optional)
    (taxId string :optional)
    (industry (list string) :optional)
    (foundedAt iso-date :optional)
    (dissolvedAt iso-date :optional)
    (status string :optional)
    (parentOrg reference :optional)
    (subsidiaries (list reference) :optional)
    (addresses (list reference) :optional)
    (phones (list reference) :optional)
    (emails (list reference) :optional)
    (accounts (list reference) :optional)
    (etype string :optional)
    (eid string :optional))

  (document relation
    (:extends document
     :persistence persistent
     :id-policy (:kind ulid))
    (source document-id :required)
    (target document-id :required)
    (predicate string :required)
    (note string :optional)
    (direction string :optional)
    (inversePredicate string :optional)
    (weight confidence-score :optional)
    (evidence (list reference) :optional)
    (assertedAt unix-time :optional)
    (assertedBy string :optional)
    (validFrom unix-time :optional)
    (validUntil unix-time :optional))

  (document domain
    (:extends document
     :persistence persistent
     :id-policy (:kind digest
                 :algorithm md5
                 :fields (record recordType)))
    (recordType string :optional)
    (record string :required)
    (fqdn string :optional)
    (registrableDomain string :optional)
    (subdomain string :optional)
    (tld string :optional)
    (unicodeName string :optional)
    (punycodeName string :optional)
    (resolvedAddresses (list string) :optional)
    (dnsRecords (list map) :optional)
    (nameservers (list string) :optional)
    (mxRecords (list map) :optional)
    (txtRecords (list string) :optional)
    (whois map :optional)
    (registrar string :optional)
    (registeredAt iso-datetime :optional)
    (expiresAt iso-datetime :optional))

  (document service
    (:extends document
     :persistence persistent
     :id-policy (:kind digest
                 :algorithm md5
                 :fields (host port transport name version)))
    (host reference :optional)
    (port port-number :required)
    (transport string :optional)
    (name string :optional)
    (product string :optional)
    (version string :optional)
    (banner string :optional)
    (protocol string :optional)
    (tls boolean :optional)
    (tlsCertificate reference :optional)
    (state string :optional)
    (fingerprints map :optional))

  (document port
    (:extends document
     :persistence persistent
     :id-policy (:kind digest
                 :algorithm md5
                 :fields (host port protocol)))
    (host reference :optional)
    (port port-number :required)
    (protocol string :optional)
    (state string :optional)
    (service reference :optional)
    (reason string :optional)
    (observedBy string :optional))

  (document network
    (:extends document
     :persistence persistent
     :id-policy (:kind digest
                 :algorithm md5
                 :fields (asn org subnet)))
    (org string :optional)
    (subnet string :required)
    (asn asn-number :optional)
    (cidr string :optional)
    (networkAddress string :optional)
    (broadcastAddress string :optional)
    (prefixLength integer :optional)
    (rir string :optional)
    (country string :optional)
    (description string :optional))

  (document asn
    (:extends document
     :persistence persistent
     :id-policy (:kind digest
                 :algorithm md5
                 :fields (number)))
    (number asn-number :required)
    (name string :optional)
    (organization string :optional)
    (country string :optional)
    (rir string :optional)
    (subnets (list string) :optional)
    (peers (list asn-number) :optional)
    (upstreams (list asn-number) :optional)
    (downstreams (list asn-number) :optional))

  (document host
    (:extends document
     :persistence persistent
     :id-policy (:kind digest
                 :algorithm md5
                 :fields (ip)))
    (hostname string :optional)
    (ip string :required)
    (ipVersion integer :optional)
    (reverseDns (list string) :optional)
    (os string :optional)
    (osVersion string :optional)
    (macAddress string :optional)
    (ports (list reference) :optional)
    (services (list reference) :optional)
    (network reference :optional)
    (asn reference :optional)
    (location reference :optional)
    (cloud map :optional)
    (virtualization string :optional))

  (document url
    (:extends document
     :persistence persistent
     :id-policy (:kind digest
                 :algorithm md5
                 :fields (url content)))
    (url uri :required)
    (scheme string :optional)
    (host string :optional)
    (port port-number :optional)
    (path string :optional)
    (query string :optional)
    (fragment string :optional)
    (content string :optional)
    (title string :optional)
    (statusCode integer :optional)
    (headers map :optional)
    (redirectChain (list uri) :optional)
    (canonicalUrl uri :optional)
    (technologies (list string) :optional)
    (forms (list map) :optional)
    (links (list uri) :optional)
    (screenshots (list reference) :optional))

  (document breach
    (:extends document
     :persistence persistent)
    (name string :optional)
    (total integer :optional)
    (description string :optional)
    (url uri :optional)
    (breachedAt iso-date :optional)
    (publishedAt iso-date :optional)
    (dataClasses (list string) :optional)
    (verified boolean :optional)
    (sensitive boolean :optional)
    (records (list reference) :optional))

  (document email
    (:extends document
     :persistence persistent
     :id-policy (:kind digest
                 :algorithm md5
                 :fields (user domain password)))
    (address string :optional)
    (user string :required)
    (domain string :required)
    (password string :optional)
    (displayName string :optional)
    (valid boolean :optional)
    (deliverable boolean :optional)
    (disposable boolean :optional)
    (roleAddress boolean :optional)
    (mxHosts (list string) :optional)
    (breaches (list reference) :optional)
    (credentials (list map) :optional))

  (document email-message
    (:extends document
     :persistence persistent
     :id-policy (:kind digest
                 :algorithm md5
                 :fields (body to from subject)))
    (body string :optional)
    (subject string :optional)
    (to (list string) :optional)
    (from string :optional)
    (replyTo string :optional)
    (headers map :optional)
    (cc (list string) :optional)
    (bcc (list string) :optional)
    (messageId string :optional)
    (inReplyTo string :optional)
    (references (list string) :optional)
    (sentAt iso-datetime :optional)
    (receivedAt iso-datetime :optional)
    (attachments (list reference) :optional))

  (document user
    (:extends document
     :persistence persistent
     :id-policy (:kind digest
                 :algorithm md5
                 :fields (name url platform)))
    (url uri :optional)
    (name string :required)
    (displayName string :optional)
    (platform string :required)
    (platformId string :optional)
    (bio string :optional)
    (misc (list map) :optional)
    (avatar reference :optional)
    (createdAtPlatform iso-datetime :optional)
    (followersCount integer :optional)
    (followingCount integer :optional)
    (postsCount integer :optional)
    (verified boolean :optional)
    (private boolean :optional)
    (status string :optional))

  (document phone
    (:extends document
     :persistence persistent
     :id-policy (:kind digest
                 :algorithm md5
                 :fields (number)))
    (number string :required)
    (e164 string :optional)
    (countryCode string :optional)
    (nationalNumber string :optional)
    (extension string :optional)
    (carrier string :optional)
    (status string :optional)
    (phoneType string :optional)
    (valid boolean :optional)
    (possible boolean :optional)
    (location string :optional)
    (timezone (list string) :optional))

  (document geo
    (:extends document
     :persistence persistent
     :id-policy (:kind digest
                 :algorithm md5
                 :fields (lat long alt)))
    (lat latitude :required)
    (long longitude :required)
    (alt decimal :optional)
    (accuracy decimal :optional)
    (geohash string :optional)
    (coordinateSystem string :optional))

  (document address
    (:extends geo
     :persistence persistent
     :id-policy (:kind digest
                 :algorithm md5
                 :fields (lat long alt city state postal country street street2)))
    (city string :optional)
    (state string :optional)
    (county string :optional)
    (postal string :optional)
    (country string :optional)
    (countryCode string :optional)
    (street string :optional)
    (street2 string :optional)
    (formatted string :optional)
    (building string :optional)
    (unit string :optional)
    (neighborhood string :optional))

  (document message
    (:extends document
     :persistence persistent
     :id-policy (:kind digest
                 :algorithm md5
                 :fields (content user channel group messageId platform)))
    (content string :required)
    (platform string :optional)
    (user reference :optional)
    (isReply boolean :optional)
    (media (list reference) :optional)
    (messageId string :optional)
    (replyTo reference :optional)
    (group string :optional)
    (channel string :optional)
    (mentions (list reference) :optional)
    (reactions map :optional)
    (sentAt iso-datetime :optional)
    (editedAt iso-datetime :optional)
    (deletedAt iso-datetime :optional))

  (document socialmpost
    (:extends document
     :persistence persistent
     :id-policy (:kind digest
                 :algorithm md5
                 :fields (content user url group)))
    (content string :required)
    (user reference :optional)
    (platform string :optional)
    (platformId string :optional)
    (replies (list reference) :optional)
    (media (list reference) :optional)
    (replyCount integer :optional)
    (repostCount integer :optional)
    (likeCount integer :optional)
    (viewCount integer :optional)
    (url uri :optional)
    (links (list uri) :optional)
    (tags (list string) :optional)
    (title string :optional)
    (group string :optional)
    (replyTo reference :optional)
    (publishedAt iso-datetime :optional)
    (editedAt iso-datetime :optional))

  (document target
    (:extends document
     :persistence persistent
     :id-policy (:kind digest
                 :algorithm md5
                 :fields (dataset target actor)))
    (actor string :required)
    (target string :required)
    (delay integer :optional)
    (recurring boolean :optional)
    (schedule string :optional)
    (options map :optional)
    (scope reference :optional)
    (priority integer :optional)
    (state string :optional)
    (nextRunAt unix-time :optional)
    (lastRunAt unix-time :optional))

  (document actor-manifest
    (:extends document
     :persistence persistent
     :id-policy (:kind digest
                 :algorithm md5
                 :fields (actor)))
    (actor string :required)
    (runtime string :optional)
    (version string :optional)
    (consumerPaths (list string) :optional)
    (targetOptions map :optional)
    (accepts (list string) :optional)
    (produces (list string) :optional)
    (capabilities (list string) :optional)
    (mailbox map :optional)
    (restartPolicy string :optional)
    (endpoint string :optional)
    (healthEndpoint string :optional))

  (document scope
    (:extends document
     :persistence persistent
     :id-policy (:kind digest
                 :algorithm md5
                 :fields (name in out)))
    (name string :required)
    (description string :optional)
    (in (list string) :optional)
    (out (list string) :optional)
    (constraints map :optional)
    (authorization map :optional)
    (startsAt unix-time :optional)
    (endsAt unix-time :optional))

  (document artifact
    (:extends document
     :persistence persistent
     :id-policy (:kind digest
                 :algorithm sha256
                 :fields (contentHash sourceUrl name)))
    (name string :optional)
    (artifactType string :optional)
    (sourceUrl uri :optional)
    (path string :optional)
    (contentHash string :required)
    (mimeType string :optional)
    (sizeBytes integer :optional)
    (createdBy string :optional)
    (tool string :optional)
    (toolVersion string :optional))

  (document finding
    (:extends document
     :persistence persistent
     :id-policy (:kind digest
                 :algorithm sha256
                 :fields (target title evidence)))
    (target reference :required)
    (title string :required)
    (description string :optional)
    (severity string :optional)
    (confidence confidence-score :optional)
    (status string :optional)
    (evidence (list reference) :optional)
    (remediation string :optional)
    (references (list uri) :optional))

  (document runtime-event
    (:extends document
     :persistence transient
     :id-policy (:kind uuidv4))
    (eventType string :required)
    (actor string :optional)
    (payload map :optional)
    (occurredAt unix-time :required))

  (message generate-id
    (:fields
     ((kind id-kind :required)
      (algorithm id-algorithm :optional)
      (value any :optional)
      (fields (list string) :optional)
      (prefix string :optional))))

  (message create-document
    (:fields
     ((documentType string :required)
      (dataset string :required)
      (values map :required))))

  (message encode-document
    (:fields
     ((document reference :required)
      (keyStyle string :optional)
      (couchdb boolean :optional))))

  (message decode-document
    (:fields
     ((documentType string :required)
      (encoded map :required)
      (dataset string :optional))))

  (message relate-documents
    (:fields
     ((source reference :required)
      (target reference :required)
      (predicate string :required)
      (note string :optional)))))
