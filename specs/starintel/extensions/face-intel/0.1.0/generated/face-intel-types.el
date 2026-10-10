;;; Generated from StarLang portable manifest. DO NOT EDIT. -*- lexical-binding: t; -*-

(require 'cl-lib)

(cl-defstruct (starintel-reference (:constructor starintel-reference-create)) schema id)

(defconst starintel-document-id-type "string")

(defconst starintel-unix-time-type "integer")

(defconst starintel-confidence-score-type "decimal")

(defconst starintel-uri-type "string")

(defconst starintel-sensitivity-values '("public" "internal" "confidential"
                                         "restricted" "secret" "unknown"))

(defconst starintel-visibility-values '("public" "private" "shared" "inherited"
                                        "unknown"))

(defconst starintel-collection-status-values '("raw" "normalized" "enriched"
                                               "verified" "disputed" "stale"
                                               "deleted" "unknown"))

(defconst starintel-source-kind-values '("api" "web" "file" "database"
                                         "message" "human" "sensor" "inference"
                                         "import" "export" "unknown"))

(defconst starintel-hash-algorithm-values '("sha256" "sha512" "blake2b"
                                            "blake3" "md5" "unknown"))

(defconst starintel-relation-direction-values '("directed" "symmetric"
                                                "inverse" "unknown"))

(cl-defstruct (starintel-document (:constructor starintel-document-create))
  id
  rev
  dataset
  dtype
  schemaversion
  externalids
  aliases
  sources
  sourceurls
  sourcerecordids
  sourcekinds
  sourcelicense
  sourceterms
  sourceretrievedat
  collectedat
  observedat
  firstseenat
  lastseenat
  createdat
  updatedat
  validfrom
  validuntil
  expiresat
  collector
  collectorversion
  collectionmethod
  collectionstatus
  runid
  correlationid
  causationid
  parentid
  rootid
  confidence
  confidencebasis
  qualityscore
  completenessscore
  verificationstatus
  verifiedat
  verifiedby
  provenance
  chainofcustody
  transformhistory
  labels
  tags
  topics
  language
  jurisdiction
  countrycode
  regioncode
  timezone
  sensitivity
  visibility
  owner
  accesscontrol
  legalbasis
  retentionpolicy
  contenttype
  encoding
  sizebytes
  contenthash
  hashalgorithm
  normalizedhash
  raw
  rawcontent
  notes
  deleted
  tombstonereason
  extensions
)
(defconst starintel-document-wire-fields
  '(
    ("id" . id)
    ("rev" . rev)
    ("dataset" . dataset)
    ("dtype" . dtype)
    ("schemaVersion" . schemaversion)
    ("externalIds" . externalids)
    ("aliases" . aliases)
    ("sources" . sources)
    ("sourceUrls" . sourceurls)
    ("sourceRecordIds" . sourcerecordids)
    ("sourceKinds" . sourcekinds)
    ("sourceLicense" . sourcelicense)
    ("sourceTerms" . sourceterms)
    ("sourceRetrievedAt" . sourceretrievedat)
    ("collectedAt" . collectedat)
    ("observedAt" . observedat)
    ("firstSeenAt" . firstseenat)
    ("lastSeenAt" . lastseenat)
    ("createdAt" . createdat)
    ("updatedAt" . updatedat)
    ("validFrom" . validfrom)
    ("validUntil" . validuntil)
    ("expiresAt" . expiresat)
    ("collector" . collector)
    ("collectorVersion" . collectorversion)
    ("collectionMethod" . collectionmethod)
    ("collectionStatus" . collectionstatus)
    ("runId" . runid)
    ("correlationId" . correlationid)
    ("causationId" . causationid)
    ("parentId" . parentid)
    ("rootId" . rootid)
    ("confidence" . confidence)
    ("confidenceBasis" . confidencebasis)
    ("qualityScore" . qualityscore)
    ("completenessScore" . completenessscore)
    ("verificationStatus" . verificationstatus)
    ("verifiedAt" . verifiedat)
    ("verifiedBy" . verifiedby)
    ("provenance" . provenance)
    ("chainOfCustody" . chainofcustody)
    ("transformHistory" . transformhistory)
    ("labels" . labels)
    ("tags" . tags)
    ("topics" . topics)
    ("language" . language)
    ("jurisdiction" . jurisdiction)
    ("countryCode" . countrycode)
    ("regionCode" . regioncode)
    ("timezone" . timezone)
    ("sensitivity" . sensitivity)
    ("visibility" . visibility)
    ("owner" . owner)
    ("accessControl" . accesscontrol)
    ("legalBasis" . legalbasis)
    ("retentionPolicy" . retentionpolicy)
    ("contentType" . contenttype)
    ("encoding" . encoding)
    ("sizeBytes" . sizebytes)
    ("contentHash" . contenthash)
    ("hashAlgorithm" . hashalgorithm)
    ("normalizedHash" . normalizedhash)
    ("raw" . raw)
    ("rawContent" . rawcontent)
    ("notes" . notes)
    ("deleted" . deleted)
    ("tombstoneReason" . tombstonereason)
    ("extensions" . extensions)
  ))

(cl-defstruct (starintel-person (:constructor starintel-person-create))
  id
  rev
  dataset
  dtype
  schemaversion
  externalids
  aliases
  sources
  sourceurls
  sourcerecordids
  sourcekinds
  sourcelicense
  sourceterms
  sourceretrievedat
  collectedat
  observedat
  firstseenat
  lastseenat
  createdat
  updatedat
  validfrom
  validuntil
  expiresat
  collector
  collectorversion
  collectionmethod
  collectionstatus
  runid
  correlationid
  causationid
  parentid
  rootid
  confidence
  confidencebasis
  qualityscore
  completenessscore
  verificationstatus
  verifiedat
  verifiedby
  provenance
  chainofcustody
  transformhistory
  labels
  tags
  topics
  language
  jurisdiction
  countrycode
  regioncode
  timezone
  sensitivity
  visibility
  owner
  accesscontrol
  legalbasis
  retentionpolicy
  contenttype
  encoding
  sizebytes
  contenthash
  hashalgorithm
  normalizedhash
  raw
  rawcontent
  notes
  deleted
  tombstonereason
  extensions
  fname
  mname
  lname
  fullname
  displayname
  prefix
  suffix
  pronouns
  bio
  dob
  dateofdeath
  age
  gender
  nationality
  citizenship
  occupation
  employer
  education
  skills
  interests
  region
  addresses
  emails
  phones
  accounts
  images
  identifiers
  misc
  etype
  eid
)
(defconst starintel-person-wire-fields
  '(
    ("id" . id)
    ("rev" . rev)
    ("dataset" . dataset)
    ("dtype" . dtype)
    ("schemaVersion" . schemaversion)
    ("externalIds" . externalids)
    ("aliases" . aliases)
    ("sources" . sources)
    ("sourceUrls" . sourceurls)
    ("sourceRecordIds" . sourcerecordids)
    ("sourceKinds" . sourcekinds)
    ("sourceLicense" . sourcelicense)
    ("sourceTerms" . sourceterms)
    ("sourceRetrievedAt" . sourceretrievedat)
    ("collectedAt" . collectedat)
    ("observedAt" . observedat)
    ("firstSeenAt" . firstseenat)
    ("lastSeenAt" . lastseenat)
    ("createdAt" . createdat)
    ("updatedAt" . updatedat)
    ("validFrom" . validfrom)
    ("validUntil" . validuntil)
    ("expiresAt" . expiresat)
    ("collector" . collector)
    ("collectorVersion" . collectorversion)
    ("collectionMethod" . collectionmethod)
    ("collectionStatus" . collectionstatus)
    ("runId" . runid)
    ("correlationId" . correlationid)
    ("causationId" . causationid)
    ("parentId" . parentid)
    ("rootId" . rootid)
    ("confidence" . confidence)
    ("confidenceBasis" . confidencebasis)
    ("qualityScore" . qualityscore)
    ("completenessScore" . completenessscore)
    ("verificationStatus" . verificationstatus)
    ("verifiedAt" . verifiedat)
    ("verifiedBy" . verifiedby)
    ("provenance" . provenance)
    ("chainOfCustody" . chainofcustody)
    ("transformHistory" . transformhistory)
    ("labels" . labels)
    ("tags" . tags)
    ("topics" . topics)
    ("language" . language)
    ("jurisdiction" . jurisdiction)
    ("countryCode" . countrycode)
    ("regionCode" . regioncode)
    ("timezone" . timezone)
    ("sensitivity" . sensitivity)
    ("visibility" . visibility)
    ("owner" . owner)
    ("accessControl" . accesscontrol)
    ("legalBasis" . legalbasis)
    ("retentionPolicy" . retentionpolicy)
    ("contentType" . contenttype)
    ("encoding" . encoding)
    ("sizeBytes" . sizebytes)
    ("contentHash" . contenthash)
    ("hashAlgorithm" . hashalgorithm)
    ("normalizedHash" . normalizedhash)
    ("raw" . raw)
    ("rawContent" . rawcontent)
    ("notes" . notes)
    ("deleted" . deleted)
    ("tombstoneReason" . tombstonereason)
    ("extensions" . extensions)
    ("fname" . fname)
    ("mname" . mname)
    ("lname" . lname)
    ("fullName" . fullname)
    ("displayName" . displayname)
    ("prefix" . prefix)
    ("suffix" . suffix)
    ("pronouns" . pronouns)
    ("bio" . bio)
    ("dob" . dob)
    ("dateOfDeath" . dateofdeath)
    ("age" . age)
    ("gender" . gender)
    ("nationality" . nationality)
    ("citizenship" . citizenship)
    ("occupation" . occupation)
    ("employer" . employer)
    ("education" . education)
    ("skills" . skills)
    ("interests" . interests)
    ("region" . region)
    ("addresses" . addresses)
    ("emails" . emails)
    ("phones" . phones)
    ("accounts" . accounts)
    ("images" . images)
    ("identifiers" . identifiers)
    ("misc" . misc)
    ("etype" . etype)
    ("eid" . eid)
  ))

(cl-defstruct (starintel-relation (:constructor starintel-relation-create))
  id
  rev
  dataset
  dtype
  schemaversion
  externalids
  aliases
  sources
  sourceurls
  sourcerecordids
  sourcekinds
  sourcelicense
  sourceterms
  sourceretrievedat
  collectedat
  observedat
  firstseenat
  lastseenat
  createdat
  updatedat
  validfrom
  validuntil
  expiresat
  collector
  collectorversion
  collectionmethod
  collectionstatus
  runid
  correlationid
  causationid
  parentid
  rootid
  confidence
  confidencebasis
  qualityscore
  completenessscore
  verificationstatus
  verifiedat
  verifiedby
  provenance
  chainofcustody
  transformhistory
  labels
  tags
  topics
  language
  jurisdiction
  countrycode
  regioncode
  timezone
  sensitivity
  visibility
  owner
  accesscontrol
  legalbasis
  retentionpolicy
  contenttype
  encoding
  sizebytes
  contenthash
  hashalgorithm
  normalizedhash
  raw
  rawcontent
  notes
  deleted
  tombstonereason
  extensions
  source
  destination
  predicate
  direction
  inversepredicate
  note
  evidence
  weight
  validat
  endedat
)
(defconst starintel-relation-wire-fields
  '(
    ("id" . id)
    ("rev" . rev)
    ("dataset" . dataset)
    ("dtype" . dtype)
    ("schemaVersion" . schemaversion)
    ("externalIds" . externalids)
    ("aliases" . aliases)
    ("sources" . sources)
    ("sourceUrls" . sourceurls)
    ("sourceRecordIds" . sourcerecordids)
    ("sourceKinds" . sourcekinds)
    ("sourceLicense" . sourcelicense)
    ("sourceTerms" . sourceterms)
    ("sourceRetrievedAt" . sourceretrievedat)
    ("collectedAt" . collectedat)
    ("observedAt" . observedat)
    ("firstSeenAt" . firstseenat)
    ("lastSeenAt" . lastseenat)
    ("createdAt" . createdat)
    ("updatedAt" . updatedat)
    ("validFrom" . validfrom)
    ("validUntil" . validuntil)
    ("expiresAt" . expiresat)
    ("collector" . collector)
    ("collectorVersion" . collectorversion)
    ("collectionMethod" . collectionmethod)
    ("collectionStatus" . collectionstatus)
    ("runId" . runid)
    ("correlationId" . correlationid)
    ("causationId" . causationid)
    ("parentId" . parentid)
    ("rootId" . rootid)
    ("confidence" . confidence)
    ("confidenceBasis" . confidencebasis)
    ("qualityScore" . qualityscore)
    ("completenessScore" . completenessscore)
    ("verificationStatus" . verificationstatus)
    ("verifiedAt" . verifiedat)
    ("verifiedBy" . verifiedby)
    ("provenance" . provenance)
    ("chainOfCustody" . chainofcustody)
    ("transformHistory" . transformhistory)
    ("labels" . labels)
    ("tags" . tags)
    ("topics" . topics)
    ("language" . language)
    ("jurisdiction" . jurisdiction)
    ("countryCode" . countrycode)
    ("regionCode" . regioncode)
    ("timezone" . timezone)
    ("sensitivity" . sensitivity)
    ("visibility" . visibility)
    ("owner" . owner)
    ("accessControl" . accesscontrol)
    ("legalBasis" . legalbasis)
    ("retentionPolicy" . retentionpolicy)
    ("contentType" . contenttype)
    ("encoding" . encoding)
    ("sizeBytes" . sizebytes)
    ("contentHash" . contenthash)
    ("hashAlgorithm" . hashalgorithm)
    ("normalizedHash" . normalizedhash)
    ("raw" . raw)
    ("rawContent" . rawcontent)
    ("notes" . notes)
    ("deleted" . deleted)
    ("tombstoneReason" . tombstonereason)
    ("extensions" . extensions)
    ("source" . source)
    ("destination" . destination)
    ("predicate" . predicate)
    ("direction" . direction)
    ("inversePredicate" . inversepredicate)
    ("note" . note)
    ("evidence" . evidence)
    ("weight" . weight)
    ("validAt" . validat)
    ("endedAt" . endedat)
  ))

(defconst starintel-pixel-offset-type "integer")

(defconst starintel-pixel-length-type "integer")

(defconst starintel-annotation-basis-type "string")

(defconst starintel-candidate-only-values '("candidate"))

(cl-defstruct (starintel-face-observation (:constructor starintel-face-observation-create))
  id
  rev
  dataset
  dtype
  schemaversion
  externalids
  aliases
  sources
  sourceurls
  sourcerecordids
  sourcekinds
  sourcelicense
  sourceterms
  sourceretrievedat
  collectedat
  observedat
  firstseenat
  lastseenat
  createdat
  updatedat
  validfrom
  validuntil
  expiresat
  collector
  collectorversion
  collectionmethod
  collectionstatus
  runid
  correlationid
  causationid
  parentid
  rootid
  confidence
  confidencebasis
  qualityscore
  completenessscore
  verificationstatus
  verifiedat
  verifiedby
  provenance
  chainofcustody
  transformhistory
  labels
  tags
  topics
  language
  jurisdiction
  countrycode
  regioncode
  timezone
  sensitivity
  visibility
  owner
  accesscontrol
  legalbasis
  retentionpolicy
  contenttype
  encoding
  sizebytes
  contenthash
  hashalgorithm
  normalizedhash
  raw
  rawcontent
  notes
  deleted
  tombstonereason
  extensions
  picture
  x
  y
  width
  height
  annotationbasis
)
(defconst starintel-face-observation-wire-fields
  '(
    ("id" . id)
    ("rev" . rev)
    ("dataset" . dataset)
    ("dtype" . dtype)
    ("schemaVersion" . schemaversion)
    ("externalIds" . externalids)
    ("aliases" . aliases)
    ("sources" . sources)
    ("sourceUrls" . sourceurls)
    ("sourceRecordIds" . sourcerecordids)
    ("sourceKinds" . sourcekinds)
    ("sourceLicense" . sourcelicense)
    ("sourceTerms" . sourceterms)
    ("sourceRetrievedAt" . sourceretrievedat)
    ("collectedAt" . collectedat)
    ("observedAt" . observedat)
    ("firstSeenAt" . firstseenat)
    ("lastSeenAt" . lastseenat)
    ("createdAt" . createdat)
    ("updatedAt" . updatedat)
    ("validFrom" . validfrom)
    ("validUntil" . validuntil)
    ("expiresAt" . expiresat)
    ("collector" . collector)
    ("collectorVersion" . collectorversion)
    ("collectionMethod" . collectionmethod)
    ("collectionStatus" . collectionstatus)
    ("runId" . runid)
    ("correlationId" . correlationid)
    ("causationId" . causationid)
    ("parentId" . parentid)
    ("rootId" . rootid)
    ("confidence" . confidence)
    ("confidenceBasis" . confidencebasis)
    ("qualityScore" . qualityscore)
    ("completenessScore" . completenessscore)
    ("verificationStatus" . verificationstatus)
    ("verifiedAt" . verifiedat)
    ("verifiedBy" . verifiedby)
    ("provenance" . provenance)
    ("chainOfCustody" . chainofcustody)
    ("transformHistory" . transformhistory)
    ("labels" . labels)
    ("tags" . tags)
    ("topics" . topics)
    ("language" . language)
    ("jurisdiction" . jurisdiction)
    ("countryCode" . countrycode)
    ("regionCode" . regioncode)
    ("timezone" . timezone)
    ("sensitivity" . sensitivity)
    ("visibility" . visibility)
    ("owner" . owner)
    ("accessControl" . accesscontrol)
    ("legalBasis" . legalbasis)
    ("retentionPolicy" . retentionpolicy)
    ("contentType" . contenttype)
    ("encoding" . encoding)
    ("sizeBytes" . sizebytes)
    ("contentHash" . contenthash)
    ("hashAlgorithm" . hashalgorithm)
    ("normalizedHash" . normalizedhash)
    ("raw" . raw)
    ("rawContent" . rawcontent)
    ("notes" . notes)
    ("deleted" . deleted)
    ("tombstoneReason" . tombstonereason)
    ("extensions" . extensions)
    ("picture" . picture)
    ("x" . x)
    ("y" . y)
    ("width" . width)
    ("height" . height)
    ("annotationBasis" . annotationbasis)
  ))

(cl-defstruct (starintel-candidate-person (:constructor starintel-candidate-person-create))
  id
  rev
  dataset
  dtype
  schemaversion
  externalids
  aliases
  sources
  sourceurls
  sourcerecordids
  sourcekinds
  sourcelicense
  sourceterms
  sourceretrievedat
  collectedat
  observedat
  firstseenat
  lastseenat
  createdat
  updatedat
  validfrom
  validuntil
  expiresat
  collector
  collectorversion
  collectionmethod
  collectionstatus
  runid
  correlationid
  causationid
  parentid
  rootid
  confidence
  confidencebasis
  qualityscore
  completenessscore
  verificationstatus
  verifiedat
  verifiedby
  provenance
  chainofcustody
  transformhistory
  labels
  tags
  topics
  language
  jurisdiction
  countrycode
  regioncode
  timezone
  sensitivity
  visibility
  owner
  accesscontrol
  legalbasis
  retentionpolicy
  contenttype
  encoding
  sizebytes
  contenthash
  hashalgorithm
  normalizedhash
  raw
  rawcontent
  notes
  deleted
  tombstonereason
  extensions
  fname
  mname
  lname
  fullname
  displayname
  prefix
  suffix
  pronouns
  bio
  dob
  dateofdeath
  age
  gender
  nationality
  citizenship
  occupation
  employer
  education
  skills
  interests
  region
  addresses
  emails
  phones
  accounts
  images
  identifiers
  misc
  etype
  eid
  candidatestatus
  annotationbasis
  evidencereferences
)
(defconst starintel-candidate-person-wire-fields
  '(
    ("id" . id)
    ("rev" . rev)
    ("dataset" . dataset)
    ("dtype" . dtype)
    ("schemaVersion" . schemaversion)
    ("externalIds" . externalids)
    ("aliases" . aliases)
    ("sources" . sources)
    ("sourceUrls" . sourceurls)
    ("sourceRecordIds" . sourcerecordids)
    ("sourceKinds" . sourcekinds)
    ("sourceLicense" . sourcelicense)
    ("sourceTerms" . sourceterms)
    ("sourceRetrievedAt" . sourceretrievedat)
    ("collectedAt" . collectedat)
    ("observedAt" . observedat)
    ("firstSeenAt" . firstseenat)
    ("lastSeenAt" . lastseenat)
    ("createdAt" . createdat)
    ("updatedAt" . updatedat)
    ("validFrom" . validfrom)
    ("validUntil" . validuntil)
    ("expiresAt" . expiresat)
    ("collector" . collector)
    ("collectorVersion" . collectorversion)
    ("collectionMethod" . collectionmethod)
    ("collectionStatus" . collectionstatus)
    ("runId" . runid)
    ("correlationId" . correlationid)
    ("causationId" . causationid)
    ("parentId" . parentid)
    ("rootId" . rootid)
    ("confidence" . confidence)
    ("confidenceBasis" . confidencebasis)
    ("qualityScore" . qualityscore)
    ("completenessScore" . completenessscore)
    ("verificationStatus" . verificationstatus)
    ("verifiedAt" . verifiedat)
    ("verifiedBy" . verifiedby)
    ("provenance" . provenance)
    ("chainOfCustody" . chainofcustody)
    ("transformHistory" . transformhistory)
    ("labels" . labels)
    ("tags" . tags)
    ("topics" . topics)
    ("language" . language)
    ("jurisdiction" . jurisdiction)
    ("countryCode" . countrycode)
    ("regionCode" . regioncode)
    ("timezone" . timezone)
    ("sensitivity" . sensitivity)
    ("visibility" . visibility)
    ("owner" . owner)
    ("accessControl" . accesscontrol)
    ("legalBasis" . legalbasis)
    ("retentionPolicy" . retentionpolicy)
    ("contentType" . contenttype)
    ("encoding" . encoding)
    ("sizeBytes" . sizebytes)
    ("contentHash" . contenthash)
    ("hashAlgorithm" . hashalgorithm)
    ("normalizedHash" . normalizedhash)
    ("raw" . raw)
    ("rawContent" . rawcontent)
    ("notes" . notes)
    ("deleted" . deleted)
    ("tombstoneReason" . tombstonereason)
    ("extensions" . extensions)
    ("fname" . fname)
    ("mname" . mname)
    ("lname" . lname)
    ("fullName" . fullname)
    ("displayName" . displayname)
    ("prefix" . prefix)
    ("suffix" . suffix)
    ("pronouns" . pronouns)
    ("bio" . bio)
    ("dob" . dob)
    ("dateOfDeath" . dateofdeath)
    ("age" . age)
    ("gender" . gender)
    ("nationality" . nationality)
    ("citizenship" . citizenship)
    ("occupation" . occupation)
    ("employer" . employer)
    ("education" . education)
    ("skills" . skills)
    ("interests" . interests)
    ("region" . region)
    ("addresses" . addresses)
    ("emails" . emails)
    ("phones" . phones)
    ("accounts" . accounts)
    ("images" . images)
    ("identifiers" . identifiers)
    ("misc" . misc)
    ("etype" . etype)
    ("eid" . eid)
    ("candidateStatus" . candidatestatus)
    ("annotationBasis" . annotationbasis)
    ("evidenceReferences" . evidencereferences)
  ))

(cl-defstruct (starintel-face-person-candidate (:constructor starintel-face-person-candidate-create))
  id
  rev
  dataset
  dtype
  schemaversion
  externalids
  aliases
  sources
  sourceurls
  sourcerecordids
  sourcekinds
  sourcelicense
  sourceterms
  sourceretrievedat
  collectedat
  observedat
  firstseenat
  lastseenat
  createdat
  updatedat
  validfrom
  validuntil
  expiresat
  collector
  collectorversion
  collectionmethod
  collectionstatus
  runid
  correlationid
  causationid
  parentid
  rootid
  confidence
  confidencebasis
  qualityscore
  completenessscore
  verificationstatus
  verifiedat
  verifiedby
  provenance
  chainofcustody
  transformhistory
  labels
  tags
  topics
  language
  jurisdiction
  countrycode
  regioncode
  timezone
  sensitivity
  visibility
  owner
  accesscontrol
  legalbasis
  retentionpolicy
  contenttype
  encoding
  sizebytes
  contenthash
  hashalgorithm
  normalizedhash
  raw
  rawcontent
  notes
  deleted
  tombstonereason
  extensions
  source
  destination
  predicate
  direction
  inversepredicate
  note
  evidence
  weight
  validat
  endedat
  candidatestatus
  annotationbasis
  evidencereferences
)
(defconst starintel-face-person-candidate-wire-fields
  '(
    ("id" . id)
    ("rev" . rev)
    ("dataset" . dataset)
    ("dtype" . dtype)
    ("schemaVersion" . schemaversion)
    ("externalIds" . externalids)
    ("aliases" . aliases)
    ("sources" . sources)
    ("sourceUrls" . sourceurls)
    ("sourceRecordIds" . sourcerecordids)
    ("sourceKinds" . sourcekinds)
    ("sourceLicense" . sourcelicense)
    ("sourceTerms" . sourceterms)
    ("sourceRetrievedAt" . sourceretrievedat)
    ("collectedAt" . collectedat)
    ("observedAt" . observedat)
    ("firstSeenAt" . firstseenat)
    ("lastSeenAt" . lastseenat)
    ("createdAt" . createdat)
    ("updatedAt" . updatedat)
    ("validFrom" . validfrom)
    ("validUntil" . validuntil)
    ("expiresAt" . expiresat)
    ("collector" . collector)
    ("collectorVersion" . collectorversion)
    ("collectionMethod" . collectionmethod)
    ("collectionStatus" . collectionstatus)
    ("runId" . runid)
    ("correlationId" . correlationid)
    ("causationId" . causationid)
    ("parentId" . parentid)
    ("rootId" . rootid)
    ("confidence" . confidence)
    ("confidenceBasis" . confidencebasis)
    ("qualityScore" . qualityscore)
    ("completenessScore" . completenessscore)
    ("verificationStatus" . verificationstatus)
    ("verifiedAt" . verifiedat)
    ("verifiedBy" . verifiedby)
    ("provenance" . provenance)
    ("chainOfCustody" . chainofcustody)
    ("transformHistory" . transformhistory)
    ("labels" . labels)
    ("tags" . tags)
    ("topics" . topics)
    ("language" . language)
    ("jurisdiction" . jurisdiction)
    ("countryCode" . countrycode)
    ("regionCode" . regioncode)
    ("timezone" . timezone)
    ("sensitivity" . sensitivity)
    ("visibility" . visibility)
    ("owner" . owner)
    ("accessControl" . accesscontrol)
    ("legalBasis" . legalbasis)
    ("retentionPolicy" . retentionpolicy)
    ("contentType" . contenttype)
    ("encoding" . encoding)
    ("sizeBytes" . sizebytes)
    ("contentHash" . contenthash)
    ("hashAlgorithm" . hashalgorithm)
    ("normalizedHash" . normalizedhash)
    ("raw" . raw)
    ("rawContent" . rawcontent)
    ("notes" . notes)
    ("deleted" . deleted)
    ("tombstoneReason" . tombstonereason)
    ("extensions" . extensions)
    ("source" . source)
    ("destination" . destination)
    ("predicate" . predicate)
    ("direction" . direction)
    ("inversePredicate" . inversepredicate)
    ("note" . note)
    ("evidence" . evidence)
    ("weight" . weight)
    ("validAt" . validat)
    ("endedAt" . endedat)
    ("candidateStatus" . candidatestatus)
    ("annotationBasis" . annotationbasis)
    ("evidenceReferences" . evidencereferences)
  ))

(cl-defstruct (starintel-store-face-observation (:constructor starintel-store-face-observation-create))
  document
)
(defconst starintel-store-face-observation-wire-fields
  '(
    ("document" . document)
  ))

(cl-defstruct (starintel-store-candidate-person (:constructor starintel-store-candidate-person-create))
  document
)
(defconst starintel-store-candidate-person-wire-fields
  '(
    ("document" . document)
  ))

(cl-defstruct (starintel-annotate-face-person (:constructor starintel-annotate-face-person-create))
  face
  person
  annotationbasis
)
(defconst starintel-annotate-face-person-wire-fields
  '(
    ("face" . face)
    ("person" . person)
    ("annotationBasis" . annotationbasis)
  ))

(cl-defstruct (starintel-get-face-observation (:constructor starintel-get-face-observation-create))
  face
)
(defconst starintel-get-face-observation-wire-fields
  '(
    ("face" . face)
  ))

(provide 'starintel-bindings)
