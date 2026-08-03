(spec-library "org.starintel/core@1"
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

  (scalar email-address
    (:base string
     :pattern "^[^[:space:]@]+@[^[:space:]@]+$"))

  (scalar phone-number
    (:base string
     :pattern "^\\+?[0-9(). -]{3,32}$"))

  (enum sensitivity
    (public internal confidential restricted secret unknown))

  (enum visibility
    (public private shared inherited unknown))

  (enum collection-status
    (raw normalized enriched verified disputed stale deleted unknown))

  (enum source-kind
    (api web file database message human sensor inference import export unknown))

  (enum hash-algorithm
    (sha256 sha512 blake2b blake3 md5 unknown))

  (enum relation-direction
    (directed symmetric inverse unknown))

  (enum target-state
    (pending scheduled running completed failed cancelled paused unknown))

  (document document
    (:persistence persistent)
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
    (sourceKinds (list source-kind) :optional)
    (sourceLicense string :optional)
    (sourceTerms uri :optional)
    (sourceRetrievedAt unix-time :optional)
    (collectedAt unix-time :optional)
    (observedAt unix-time :optional)
    (firstSeenAt unix-time :optional)
    (lastSeenAt unix-time :optional)
    (createdAt unix-time :optional)
    (updatedAt unix-time :optional)
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
    (hashAlgorithm hash-algorithm :optional)
    (normalizedHash string :optional)
    (raw map :optional)
    (rawContent string :optional)
    (notes string :optional)
    (deleted boolean :optional)
    (tombstoneReason string :optional)
    (extensions map :optional))

  (document person
    (:extends document
     :persistence persistent)
    (fname string :optional)
    (mname string :optional)
    (lname string :optional)
    (fullName string :optional)
    (displayName string :optional)
    (prefix string :optional)
    (suffix string :optional)
    (pronouns string :optional)
    (bio string :optional)
    (dob iso-date :optional)
    (dateOfDeath iso-date :optional)
    (age integer :optional)
    (gender string :optional)
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
     :persistence persistent)
    (reg string :optional)
    (registrationNumbers map :optional)
    (name string :required)
    (legalName string :optional)
    (alternateNames (list string) :optional)
    (bio string :optional)
    (description string :optional)
    (organizationType string :optional)
    (industry (list string) :optional)
    (foundedDate iso-date :optional)
    (dissolvedDate iso-date :optional)
    (status string :optional)
    (country string :optional)
    (jurisdictions (list string) :optional)
    (headquarters reference :optional)
    (addresses (list reference) :optional)
    (website uri :optional)
    (domains (list reference) :optional)
    (emails (list reference) :optional)
    (phones (list reference) :optional)
    (parentOrg reference :optional)
    (subsidiaries (list reference) :optional)
    (officers (list reference) :optional)
    (employees (list reference) :optional)
    (owners (list reference) :optional)
    (beneficialOwners (list reference) :optional)
    (identifiers map :optional)
    (etype string :optional)
    (eid string :optional))

  (document relation
    (:extends document
     :persistence persistent)
    (source reference :required)
    (destination reference :required)
    (predicate string :required)
    (direction relation-direction :optional)
    (inversePredicate string :optional)
    (note string :optional)
    (evidence (list reference) :optional)
    (weight decimal :optional)
    (validAt unix-time :optional)
    (endedAt unix-time :optional))

  (document domain
    (:extends document
     :persistence persistent)
    (name string :required)
    (unicodeName string :optional)
    (punycodeName string :optional)
    (recordType string :optional)
    (record string :optional)
    (resolvedAddresses (list reference) :optional)
    (dnsRecords (list map) :optional)
    (nameservers (list string) :optional)
    (mxRecords (list map) :optional)
    (txtRecords (list string) :optional)
    (registrar string :optional)
    (registrant reference :optional)
    (whois map :optional)
    (registeredAt unix-time :optional)
    (renewedAt unix-time :optional)
    (registryExpiresAt unix-time :optional)
    (dnssec boolean :optional)
    (statusCodes (list string) :optional))

  (document service
    (:extends document
     :persistence persistent)
    (host reference :required)
    (port port-number :required)
    (transport string :optional)
    (name string :optional)
    (product string :optional)
    (vendor string :optional)
    (version string :optional)
    (protocol string :optional)
    (scheme string :optional)
    (banner string :optional)
    (state string :optional)
    (tls boolean :optional)
    (tlsCertificate reference :optional)
    (cpe (list string) :optional)
    (fingerprints map :optional)
    (firstOpenAt unix-time :optional)
    (lastOpenAt unix-time :optional))

  (document port
    (:extends document
     :persistence persistent)
    (number port-number :required)
    (transport string :optional)
    (protocol string :optional)
    (service reference :optional)
    (state string :optional)
    (reason string :optional)
    (banner string :optional)
    (host reference :optional)
    (firstOpenAt unix-time :optional)
    (lastOpenAt unix-time :optional))

  (document network
    (:extends document
     :persistence persistent)
    (org reference :optional)
    (subnet string :required)
    (asn asn-number :optional)
    (asnName string :optional)
    (rir string :optional)
    (country string :optional)
    (netname string :optional)
    (description string :optional)
    (announcedPrefixes (list string) :optional)
    (upstreams (list asn-number) :optional)
    (peers (list asn-number) :optional))

  (document asn
    (:extends document
     :persistence persistent)
    (number asn-number :required)
    (name string :optional)
    (org reference :optional)
    (country string :optional)
    (rir string :optional)
    (registry string :optional)
    (prefixes (list string) :optional)
    (upstreams (list asn-number) :optional)
    (peers (list asn-number) :optional))

  (document host
    (:extends document
     :persistence persistent)
    (hostname string :optional)
    (hostnames (list string) :optional)
    (ip string :required)
    (ipVersion integer :optional)
    (mac string :optional)
    (os string :optional)
    (osVersion string :optional)
    (deviceType string :optional)
    (vendor string :optional)
    (network reference :optional)
    (asn asn-number :optional)
    (geo reference :optional)
    (ports (list reference) :optional)
    (services (list reference) :optional)
    (domains (list reference) :optional)
    (certificates (list reference) :optional)
    (cloud map :optional)
    (virtualization string :optional)
    (alive boolean :optional)
    (lastProbedAt unix-time :optional))

  (document url
    (:extends document
     :persistence persistent)
    (url uri :required)
    (scheme string :optional)
    (username string :optional)
    (host string :optional)
    (port port-number :optional)
    (path string :optional)
    (query string :optional)
    (fragment string :optional)
    (canonicalUrl uri :optional)
    (finalUrl uri :optional)
    (statusCode integer :optional)
    (method string :optional)
    (requestHeaders map :optional)
    (responseHeaders map :optional)
    (content string :optional)
    (contentTitle string :optional)
    (contentLength integer :optional)
    (technologies (list string) :optional)
    (redirectChain (list uri) :optional)
    (screenshot reference :optional)
    (fetchedAt unix-time :optional))

  (document breach
    (:extends document
     :persistence persistent)
    (name string :optional)
    (total integer :optional)
    (description string :optional)
    (url uri :optional)
    (breachedAt unix-time :optional)
    (publishedAt unix-time :optional)
    (dataClasses (list string) :optional)
    (affectedOrganizations (list reference) :optional)
    (affectedIdentifiers (list string) :optional)
    (verified boolean :optional)
    (sensitive boolean :optional))

  (document email
    (:extends document
     :persistence persistent)
    (address email-address :required)
    (user string :optional)
    (domain string :optional)
    (displayName string :optional)
    (password string :optional)
    (passwordHash string :optional)
    (hashType string :optional)
    (breaches (list reference) :optional)
    (deliverable boolean :optional)
    (disposable boolean :optional)
    (roleAccount boolean :optional)
    (catchAll boolean :optional)
    (mxValid boolean :optional)
    (provider string :optional)
    (lastVerifiedAt unix-time :optional))

  (document email-message
    (:extends document
     :persistence persistent)
    (messageId string :optional)
    (threadId string :optional)
    (subject string :optional)
    (body string :optional)
    (bodyHtml string :optional)
    (to (list email-address) :optional)
    (from email-address :optional)
    (replyTo email-address :optional)
    (cc (list email-address) :optional)
    (bcc (list email-address) :optional)
    (headers map :optional)
    (attachments (list reference) :optional)
    (sentAt unix-time :optional)
    (receivedAt unix-time :optional)
    (inReplyTo string :optional)
    (references (list string) :optional)
    (mailbox string :optional)
    (flags (list string) :optional))

  (document user
    (:extends document
     :persistence persistent)
    (url uri :optional)
    (username string :required)
    (displayName string :optional)
    (name string :optional)
    (platform string :required)
    (platformUserId string :optional)
    (bio string :optional)
    (avatar reference :optional)
    (banner reference :optional)
    (createdOnPlatformAt unix-time :optional)
    (followersCount integer :optional)
    (followingCount integer :optional)
    (postCount integer :optional)
    (verified boolean :optional)
    (private boolean :optional)
    (suspended boolean :optional)
    (location string :optional)
    (website uri :optional)
    (emails (list reference) :optional)
    (phones (list reference) :optional)
    (misc (list map) :optional))

  (document phone
    (:extends document
     :persistence persistent)
    (number phone-number :required)
    (e164 string :optional)
    (nationalNumber string :optional)
    (extension string :optional)
    (carrier string :optional)
    (status string :optional)
    (phoneType string :optional)
    (lineType string :optional)
    (valid boolean :optional)
    (reachable boolean :optional)
    (ported boolean :optional)
    (location string :optional)
    (lastVerifiedAt unix-time :optional))

  (document geo
    (:extends document
     :persistence persistent)
    (lat latitude :required)
    (long longitude :required)
    (alt decimal :optional)
    (accuracyMeters decimal :optional)
    (geohash string :optional)
    (coordinateSystem string :optional)
    (placeName string :optional)
    (placeKind string :optional))

  (document address
    (:extends geo
     :persistence persistent)
    (formatted string :optional)
    (street string :optional)
    (street2 string :optional)
    (unit string :optional)
    (city string :optional)
    (county string :optional)
    (state string :optional)
    (postal string :optional)
    (country string :optional)
    (addressType string :optional)
    (poBox string :optional)
    (building string :optional)
    (floor string :optional)
    (deliveryPoint string :optional)
    (validated boolean :optional)
    (validationProvider string :optional))

  (document message
    (:extends document
     :persistence persistent)
    (message string :required)
    (platform string :required)
    (user reference :optional)
    (isReply boolean :optional)
    (media (list reference) :optional)
    (messageId string :optional)
    (replyTo reference :optional)
    (threadId string :optional)
    (group string :optional)
    (channel string :optional)
    (mentions (list reference) :optional)
    (reactions map :optional)
    (edited boolean :optional)
    (editedAt unix-time :optional)
    (sentAt unix-time :optional)
    (deletedAt unix-time :optional))

  (document socialmpost
    (:extends document
     :persistence persistent)
    (content string :required)
    (user reference :optional)
    (platform string :optional)
    (platformPostId string :optional)
    (replies (list reference) :optional)
    (media (list reference) :optional)
    (replyCount integer :optional)
    (repostCount integer :optional)
    (likeCount integer :optional)
    (viewCount integer :optional)
    (quoteCount integer :optional)
    (bookmarkCount integer :optional)
    (url uri :optional)
    (links (list uri) :optional)
    (hashtags (list string) :optional)
    (mentions (list reference) :optional)
    (title string :optional)
    (group string :optional)
    (replyTo reference :optional)
    (conversationId string :optional)
    (publishedAt unix-time :optional)
    (editedAt unix-time :optional)
    (sensitive boolean :optional))

  (document target
    (:extends document
     :persistence persistent)
    (actor string :required)
    (target string :required)
    (targetType string :optional)
    (scope reference :optional)
    (delay integer :optional)
    (recurring boolean :optional)
    (schedule string :optional)
    (options map :optional)
    (state target-state :optional)
    (priority integer :optional)
    (notBefore unix-time :optional)
    (deadline unix-time :optional)
    (lastRunAt unix-time :optional)
    (nextRunAt unix-time :optional)
    (attempts integer :optional)
    (maximumAttempts integer :optional)
    (lastError map :optional))

  (document actor-manifest
    (:extends document
     :persistence persistent)
    (actor string :required)
    (actorVersion string :optional)
    (consumerPaths (list string) :optional)
    (targetOptions map :optional)
    (accepts (list string) :optional)
    (produces (list string) :optional)
    (capabilities (list string) :optional)
    (runtime string :optional)
    (endpoint string :optional)
    (mailbox map :optional)
    (restartPolicy string :optional)
    (healthEndpoint uri :optional)
    (heartbeatSeconds integer :optional)
    (metadata map :optional))

  (document artifact
    (:extends document
     :persistence persistent)
    (name string :optional)
    (filename string :optional)
    (mediaType string :optional)
    (uri uri :optional)
    (storageUri uri :optional)
    (bytesHash string :optional)
    (size integer :optional)
    (extractedText string :optional)
    (ocrText string :optional)
    (metadata map :optional)
    (attachments (list reference) :optional))

  (document finding
    (:extends document
     :persistence persistent)
    (title string :required)
    (description string :optional)
    (findingType string :optional)
    (severity string :optional)
    (status string :optional)
    (asset reference :optional)
    (evidence (list reference) :optional)
    (recommendation string :optional)
    (discoveredAt unix-time :optional)
    (resolvedAt unix-time :optional)
    (cve (list string) :optional)
    (cwe (list string) :optional)
    (cvss map :optional))

  (document scope
    (:extends document
     :persistence persistent)
    (name string :required)
    (program string :optional)
    (inScope (list string) :optional)
    (outOfScope (list string) :optional)
    (rules string :optional)
    (startsAt unix-time :optional)
    (endsAt unix-time :optional)
    (rateLimits map :optional)
    (allowedTools (list string) :optional)
    (prohibitedActions (list string) :optional))

  (predicate related-to
    (:source document
     :destination document))

  (predicate same-as
    (:source document
     :destination document))

  (predicate member-of
    (:source person
     :destination org))

  (predicate employed-by
    (:source person
     :destination org))

  (predicate owns
    (:source document
     :destination document))

  (predicate located-at
    (:source document
     :destination geo))

  (predicate links-to
    (:source url
     :destination url))

  (predicate resolves-to
    (:source domain
     :destination host))

  (predicate hosts-service
    (:source host
     :destination service))

  (predicate belongs-to-asn
    (:source host
     :destination network))

  (predicate leaked-in
    (:source document
     :destination breach))

  (predicate collected-from
    (:source document
     :destination document))

  (predicate derived-from
    (:source document
     :destination document))

  (predicate evidence-of
    (:source artifact
     :destination finding))

  (predicate in-scope-of
    (:source document
     :destination scope))

  (predicate has-finding
    (:source document
     :destination finding))

  (message upsert-document
    (:fields
     ((document reference :required)
      (dataset string :required)
      (runId string :optional))))

  (message query-documents
    (:fields
     ((dataset string :required)
      (dtype string :optional)
      (filters map :optional)
      (limit integer :optional)
      (cursor string :optional))))

  (message schedule-target
    (:fields
     ((target reference :required)
      (requestedBy string :optional))))

  (message actor-manifest-announcement
    (:fields
     ((manifest reference :required)
      (announcedAt unix-time :required)))))
