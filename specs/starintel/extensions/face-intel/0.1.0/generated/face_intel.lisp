;;;; Generated from StarLang portable manifest. DO NOT EDIT. language=common-lisp

(defpackage #:org.starintel.core.v1
  (:use #:cl)
  (:export
    #:star-reference
    #:MAKE-star-reference
    #:COPY-star-reference
    #:star-reference-P
    #:+star-reference-WIRE-FIELDS+
    #:star-reference-schema
    #:star-reference-id
    #:document-id
    #:unix-time
    #:confidence-score
    #:uri
    #:sensitivity
    #:visibility
    #:collection-status
    #:source-kind
    #:hash-algorithm
    #:relation-direction
    #:document
    #:MAKE-document
    #:COPY-document
    #:document-P
    #:+document-WIRE-FIELDS+
    #:document-rev
    #:document-dataset
    #:document-dtype
    #:document-schemaversion
    #:document-externalids
    #:document-aliases
    #:document-sources
    #:document-sourceurls
    #:document-sourcerecordids
    #:document-sourcekinds
    #:document-sourcelicense
    #:document-sourceterms
    #:document-sourceretrievedat
    #:document-collectedat
    #:document-observedat
    #:document-firstseenat
    #:document-lastseenat
    #:document-createdat
    #:document-updatedat
    #:document-validfrom
    #:document-validuntil
    #:document-expiresat
    #:document-collector
    #:document-collectorversion
    #:document-collectionmethod
    #:document-collectionstatus
    #:document-runid
    #:document-correlationid
    #:document-causationid
    #:document-parentid
    #:document-rootid
    #:document-confidence
    #:document-confidencebasis
    #:document-qualityscore
    #:document-completenessscore
    #:document-verificationstatus
    #:document-verifiedat
    #:document-verifiedby
    #:document-provenance
    #:document-chainofcustody
    #:document-transformhistory
    #:document-labels
    #:document-tags
    #:document-topics
    #:document-language
    #:document-jurisdiction
    #:document-countrycode
    #:document-regioncode
    #:document-timezone
    #:document-sensitivity
    #:document-visibility
    #:document-owner
    #:document-accesscontrol
    #:document-legalbasis
    #:document-retentionpolicy
    #:document-contenttype
    #:document-encoding
    #:document-sizebytes
    #:document-contenthash
    #:document-hashalgorithm
    #:document-normalizedhash
    #:document-raw
    #:document-rawcontent
    #:document-notes
    #:document-deleted
    #:document-tombstonereason
    #:document-extensions
    #:person
    #:MAKE-person
    #:COPY-person
    #:person-P
    #:+person-WIRE-FIELDS+
    #:person-id
    #:person-rev
    #:person-dataset
    #:person-dtype
    #:person-schemaversion
    #:person-externalids
    #:person-aliases
    #:person-sources
    #:person-sourceurls
    #:person-sourcerecordids
    #:person-sourcekinds
    #:person-sourcelicense
    #:person-sourceterms
    #:person-sourceretrievedat
    #:person-collectedat
    #:person-observedat
    #:person-firstseenat
    #:person-lastseenat
    #:person-createdat
    #:person-updatedat
    #:person-validfrom
    #:person-validuntil
    #:person-expiresat
    #:person-collector
    #:person-collectorversion
    #:person-collectionmethod
    #:person-collectionstatus
    #:person-runid
    #:person-correlationid
    #:person-causationid
    #:person-parentid
    #:person-rootid
    #:person-confidence
    #:person-confidencebasis
    #:person-qualityscore
    #:person-completenessscore
    #:person-verificationstatus
    #:person-verifiedat
    #:person-verifiedby
    #:person-provenance
    #:person-chainofcustody
    #:person-transformhistory
    #:person-labels
    #:person-tags
    #:person-topics
    #:person-language
    #:person-jurisdiction
    #:person-countrycode
    #:person-regioncode
    #:person-timezone
    #:person-sensitivity
    #:person-visibility
    #:person-owner
    #:person-accesscontrol
    #:person-legalbasis
    #:person-retentionpolicy
    #:person-contenttype
    #:person-encoding
    #:person-sizebytes
    #:person-contenthash
    #:person-hashalgorithm
    #:person-normalizedhash
    #:person-raw
    #:person-rawcontent
    #:person-notes
    #:person-deleted
    #:person-tombstonereason
    #:person-extensions
    #:person-fname
    #:person-mname
    #:person-lname
    #:person-fullname
    #:person-displayname
    #:person-prefix
    #:person-suffix
    #:person-pronouns
    #:person-bio
    #:person-dob
    #:person-dateofdeath
    #:person-age
    #:person-gender
    #:person-nationality
    #:person-citizenship
    #:person-occupation
    #:person-employer
    #:person-education
    #:person-skills
    #:person-interests
    #:person-region
    #:person-addresses
    #:person-emails
    #:person-phones
    #:person-accounts
    #:person-images
    #:person-identifiers
    #:person-misc
    #:person-etype
    #:person-eid
    #:relation
    #:MAKE-relation
    #:COPY-relation
    #:relation-P
    #:+relation-WIRE-FIELDS+
    #:relation-id
    #:relation-rev
    #:relation-dataset
    #:relation-dtype
    #:relation-schemaversion
    #:relation-externalids
    #:relation-aliases
    #:relation-sources
    #:relation-sourceurls
    #:relation-sourcerecordids
    #:relation-sourcekinds
    #:relation-sourcelicense
    #:relation-sourceterms
    #:relation-sourceretrievedat
    #:relation-collectedat
    #:relation-observedat
    #:relation-firstseenat
    #:relation-lastseenat
    #:relation-createdat
    #:relation-updatedat
    #:relation-validfrom
    #:relation-validuntil
    #:relation-expiresat
    #:relation-collector
    #:relation-collectorversion
    #:relation-collectionmethod
    #:relation-collectionstatus
    #:relation-runid
    #:relation-correlationid
    #:relation-causationid
    #:relation-parentid
    #:relation-rootid
    #:relation-confidence
    #:relation-confidencebasis
    #:relation-qualityscore
    #:relation-completenessscore
    #:relation-verificationstatus
    #:relation-verifiedat
    #:relation-verifiedby
    #:relation-provenance
    #:relation-chainofcustody
    #:relation-transformhistory
    #:relation-labels
    #:relation-tags
    #:relation-topics
    #:relation-language
    #:relation-jurisdiction
    #:relation-countrycode
    #:relation-regioncode
    #:relation-timezone
    #:relation-sensitivity
    #:relation-visibility
    #:relation-owner
    #:relation-accesscontrol
    #:relation-legalbasis
    #:relation-retentionpolicy
    #:relation-contenttype
    #:relation-encoding
    #:relation-sizebytes
    #:relation-contenthash
    #:relation-hashalgorithm
    #:relation-normalizedhash
    #:relation-raw
    #:relation-rawcontent
    #:relation-notes
    #:relation-deleted
    #:relation-tombstonereason
    #:relation-extensions
    #:relation-source
    #:relation-destination
    #:relation-predicate
    #:relation-inversepredicate
    #:relation-note
    #:relation-evidence
    #:relation-weight
    #:relation-validat
    #:relation-endedat
    #:pixel-offset
    #:pixel-length
    #:annotation-basis
    #:candidate-only
    #:face-observation
    #:MAKE-face-observation
    #:COPY-face-observation
    #:face-observation-P
    #:+face-observation-WIRE-FIELDS+
    #:face-observation-id
    #:face-observation-rev
    #:face-observation-dataset
    #:face-observation-dtype
    #:face-observation-schemaversion
    #:face-observation-externalids
    #:face-observation-aliases
    #:face-observation-sources
    #:face-observation-sourceurls
    #:face-observation-sourcerecordids
    #:face-observation-sourcekinds
    #:face-observation-sourcelicense
    #:face-observation-sourceterms
    #:face-observation-sourceretrievedat
    #:face-observation-collectedat
    #:face-observation-observedat
    #:face-observation-firstseenat
    #:face-observation-lastseenat
    #:face-observation-createdat
    #:face-observation-updatedat
    #:face-observation-validfrom
    #:face-observation-validuntil
    #:face-observation-expiresat
    #:face-observation-collector
    #:face-observation-collectorversion
    #:face-observation-collectionmethod
    #:face-observation-collectionstatus
    #:face-observation-runid
    #:face-observation-correlationid
    #:face-observation-causationid
    #:face-observation-parentid
    #:face-observation-rootid
    #:face-observation-confidence
    #:face-observation-confidencebasis
    #:face-observation-qualityscore
    #:face-observation-completenessscore
    #:face-observation-verificationstatus
    #:face-observation-verifiedat
    #:face-observation-verifiedby
    #:face-observation-provenance
    #:face-observation-chainofcustody
    #:face-observation-transformhistory
    #:face-observation-labels
    #:face-observation-tags
    #:face-observation-topics
    #:face-observation-language
    #:face-observation-jurisdiction
    #:face-observation-countrycode
    #:face-observation-regioncode
    #:face-observation-timezone
    #:face-observation-sensitivity
    #:face-observation-visibility
    #:face-observation-owner
    #:face-observation-accesscontrol
    #:face-observation-legalbasis
    #:face-observation-retentionpolicy
    #:face-observation-contenttype
    #:face-observation-encoding
    #:face-observation-sizebytes
    #:face-observation-contenthash
    #:face-observation-hashalgorithm
    #:face-observation-normalizedhash
    #:face-observation-raw
    #:face-observation-rawcontent
    #:face-observation-notes
    #:face-observation-deleted
    #:face-observation-tombstonereason
    #:face-observation-extensions
    #:face-observation-picture
    #:face-observation-x
    #:face-observation-y
    #:face-observation-width
    #:face-observation-height
    #:face-observation-annotationbasis
    #:candidate-person
    #:MAKE-candidate-person
    #:COPY-candidate-person
    #:candidate-person-P
    #:+candidate-person-WIRE-FIELDS+
    #:candidate-person-id
    #:candidate-person-rev
    #:candidate-person-dataset
    #:candidate-person-dtype
    #:candidate-person-schemaversion
    #:candidate-person-externalids
    #:candidate-person-aliases
    #:candidate-person-sources
    #:candidate-person-sourceurls
    #:candidate-person-sourcerecordids
    #:candidate-person-sourcekinds
    #:candidate-person-sourcelicense
    #:candidate-person-sourceterms
    #:candidate-person-sourceretrievedat
    #:candidate-person-collectedat
    #:candidate-person-observedat
    #:candidate-person-firstseenat
    #:candidate-person-lastseenat
    #:candidate-person-createdat
    #:candidate-person-updatedat
    #:candidate-person-validfrom
    #:candidate-person-validuntil
    #:candidate-person-expiresat
    #:candidate-person-collector
    #:candidate-person-collectorversion
    #:candidate-person-collectionmethod
    #:candidate-person-collectionstatus
    #:candidate-person-runid
    #:candidate-person-correlationid
    #:candidate-person-causationid
    #:candidate-person-parentid
    #:candidate-person-rootid
    #:candidate-person-confidence
    #:candidate-person-confidencebasis
    #:candidate-person-qualityscore
    #:candidate-person-completenessscore
    #:candidate-person-verificationstatus
    #:candidate-person-verifiedat
    #:candidate-person-verifiedby
    #:candidate-person-provenance
    #:candidate-person-chainofcustody
    #:candidate-person-transformhistory
    #:candidate-person-labels
    #:candidate-person-tags
    #:candidate-person-topics
    #:candidate-person-language
    #:candidate-person-jurisdiction
    #:candidate-person-countrycode
    #:candidate-person-regioncode
    #:candidate-person-timezone
    #:candidate-person-sensitivity
    #:candidate-person-visibility
    #:candidate-person-owner
    #:candidate-person-accesscontrol
    #:candidate-person-legalbasis
    #:candidate-person-retentionpolicy
    #:candidate-person-contenttype
    #:candidate-person-encoding
    #:candidate-person-sizebytes
    #:candidate-person-contenthash
    #:candidate-person-hashalgorithm
    #:candidate-person-normalizedhash
    #:candidate-person-raw
    #:candidate-person-rawcontent
    #:candidate-person-notes
    #:candidate-person-deleted
    #:candidate-person-tombstonereason
    #:candidate-person-extensions
    #:candidate-person-fname
    #:candidate-person-mname
    #:candidate-person-lname
    #:candidate-person-fullname
    #:candidate-person-displayname
    #:candidate-person-prefix
    #:candidate-person-suffix
    #:candidate-person-pronouns
    #:candidate-person-bio
    #:candidate-person-dob
    #:candidate-person-dateofdeath
    #:candidate-person-age
    #:candidate-person-gender
    #:candidate-person-nationality
    #:candidate-person-citizenship
    #:candidate-person-occupation
    #:candidate-person-employer
    #:candidate-person-education
    #:candidate-person-skills
    #:candidate-person-interests
    #:candidate-person-region
    #:candidate-person-addresses
    #:candidate-person-emails
    #:candidate-person-phones
    #:candidate-person-accounts
    #:candidate-person-images
    #:candidate-person-identifiers
    #:candidate-person-misc
    #:candidate-person-etype
    #:candidate-person-eid
    #:candidate-person-candidatestatus
    #:candidate-person-annotationbasis
    #:candidate-person-evidencereferences
    #:face-person-candidate
    #:MAKE-face-person-candidate
    #:COPY-face-person-candidate
    #:face-person-candidate-P
    #:+face-person-candidate-WIRE-FIELDS+
    #:face-person-candidate-id
    #:face-person-candidate-rev
    #:face-person-candidate-dataset
    #:face-person-candidate-dtype
    #:face-person-candidate-schemaversion
    #:face-person-candidate-externalids
    #:face-person-candidate-aliases
    #:face-person-candidate-sources
    #:face-person-candidate-sourceurls
    #:face-person-candidate-sourcerecordids
    #:face-person-candidate-sourcekinds
    #:face-person-candidate-sourcelicense
    #:face-person-candidate-sourceterms
    #:face-person-candidate-sourceretrievedat
    #:face-person-candidate-collectedat
    #:face-person-candidate-observedat
    #:face-person-candidate-firstseenat
    #:face-person-candidate-lastseenat
    #:face-person-candidate-createdat
    #:face-person-candidate-updatedat
    #:face-person-candidate-validfrom
    #:face-person-candidate-validuntil
    #:face-person-candidate-expiresat
    #:face-person-candidate-collector
    #:face-person-candidate-collectorversion
    #:face-person-candidate-collectionmethod
    #:face-person-candidate-collectionstatus
    #:face-person-candidate-runid
    #:face-person-candidate-correlationid
    #:face-person-candidate-causationid
    #:face-person-candidate-parentid
    #:face-person-candidate-rootid
    #:face-person-candidate-confidence
    #:face-person-candidate-confidencebasis
    #:face-person-candidate-qualityscore
    #:face-person-candidate-completenessscore
    #:face-person-candidate-verificationstatus
    #:face-person-candidate-verifiedat
    #:face-person-candidate-verifiedby
    #:face-person-candidate-provenance
    #:face-person-candidate-chainofcustody
    #:face-person-candidate-transformhistory
    #:face-person-candidate-labels
    #:face-person-candidate-tags
    #:face-person-candidate-topics
    #:face-person-candidate-language
    #:face-person-candidate-jurisdiction
    #:face-person-candidate-countrycode
    #:face-person-candidate-regioncode
    #:face-person-candidate-timezone
    #:face-person-candidate-sensitivity
    #:face-person-candidate-visibility
    #:face-person-candidate-owner
    #:face-person-candidate-accesscontrol
    #:face-person-candidate-legalbasis
    #:face-person-candidate-retentionpolicy
    #:face-person-candidate-contenttype
    #:face-person-candidate-encoding
    #:face-person-candidate-sizebytes
    #:face-person-candidate-contenthash
    #:face-person-candidate-hashalgorithm
    #:face-person-candidate-normalizedhash
    #:face-person-candidate-raw
    #:face-person-candidate-rawcontent
    #:face-person-candidate-notes
    #:face-person-candidate-deleted
    #:face-person-candidate-tombstonereason
    #:face-person-candidate-extensions
    #:face-person-candidate-source
    #:face-person-candidate-destination
    #:face-person-candidate-predicate
    #:face-person-candidate-direction
    #:face-person-candidate-inversepredicate
    #:face-person-candidate-note
    #:face-person-candidate-evidence
    #:face-person-candidate-weight
    #:face-person-candidate-validat
    #:face-person-candidate-endedat
    #:face-person-candidate-candidatestatus
    #:face-person-candidate-annotationbasis
    #:face-person-candidate-evidencereferences
    #:store-face-observation
    #:MAKE-store-face-observation
    #:COPY-store-face-observation
    #:store-face-observation-P
    #:+store-face-observation-WIRE-FIELDS+
    #:store-face-observation-document
    #:store-candidate-person
    #:MAKE-store-candidate-person
    #:COPY-store-candidate-person
    #:store-candidate-person-P
    #:+store-candidate-person-WIRE-FIELDS+
    #:store-candidate-person-document
    #:annotate-face-person
    #:MAKE-annotate-face-person
    #:COPY-annotate-face-person
    #:annotate-face-person-P
    #:+annotate-face-person-WIRE-FIELDS+
    #:annotate-face-person-face
    #:annotate-face-person-person
    #:annotate-face-person-annotationbasis
    #:get-face-observation
    #:MAKE-get-face-observation
    #:COPY-get-face-observation
    #:get-face-observation-P
    #:+get-face-observation-WIRE-FIELDS+
    #:get-face-observation-face
  ))

(in-package #:org.starintel.core.v1)

(defstruct star-reference
  (schema nil)
  (id nil)
)
(defparameter +star-reference-wire-fields+
  '(
    ("schema" . schema)
    ("id" . id)
  ))

(deftype document-id () 'string)

(deftype unix-time () 'integer)

(deftype confidence-score () 'string)

(deftype uri () 'string)

(deftype sensitivity () '(member "public" "internal" "confidential" "restricted" "secret" "unknown"))

(deftype visibility () '(member "public" "private" "shared" "inherited" "unknown"))

(deftype collection-status () '(member "raw" "normalized" "enriched" "verified" "disputed" "stale" "deleted" "unknown"))

(deftype source-kind () '(member "api" "web" "file" "database" "message" "human" "sensor" "inference" "import" "export" "unknown"))

(deftype hash-algorithm () '(member "sha256" "sha512" "blake2b" "blake3" "md5" "unknown"))

(deftype relation-direction () '(member "directed" "symmetric" "inverse" "unknown"))

(defstruct document
  (id nil)
  (rev nil)
  (dataset nil)
  (dtype nil)
  (schemaversion nil)
  (externalids nil)
  (aliases nil)
  (sources nil)
  (sourceurls nil)
  (sourcerecordids nil)
  (sourcekinds nil)
  (sourcelicense nil)
  (sourceterms nil)
  (sourceretrievedat nil)
  (collectedat nil)
  (observedat nil)
  (firstseenat nil)
  (lastseenat nil)
  (createdat nil)
  (updatedat nil)
  (validfrom nil)
  (validuntil nil)
  (expiresat nil)
  (collector nil)
  (collectorversion nil)
  (collectionmethod nil)
  (collectionstatus nil)
  (runid nil)
  (correlationid nil)
  (causationid nil)
  (parentid nil)
  (rootid nil)
  (confidence nil)
  (confidencebasis nil)
  (qualityscore nil)
  (completenessscore nil)
  (verificationstatus nil)
  (verifiedat nil)
  (verifiedby nil)
  (provenance nil)
  (chainofcustody nil)
  (transformhistory nil)
  (labels nil)
  (tags nil)
  (topics nil)
  (language nil)
  (jurisdiction nil)
  (countrycode nil)
  (regioncode nil)
  (timezone nil)
  (sensitivity nil)
  (visibility nil)
  (owner nil)
  (accesscontrol nil)
  (legalbasis nil)
  (retentionpolicy nil)
  (contenttype nil)
  (encoding nil)
  (sizebytes nil)
  (contenthash nil)
  (hashalgorithm nil)
  (normalizedhash nil)
  (raw nil)
  (rawcontent nil)
  (notes nil)
  (deleted nil)
  (tombstonereason nil)
  (extensions nil)
)
(defparameter +document-wire-fields+
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

(defstruct person
  (id nil)
  (rev nil)
  (dataset nil)
  (dtype nil)
  (schemaversion nil)
  (externalids nil)
  (aliases nil)
  (sources nil)
  (sourceurls nil)
  (sourcerecordids nil)
  (sourcekinds nil)
  (sourcelicense nil)
  (sourceterms nil)
  (sourceretrievedat nil)
  (collectedat nil)
  (observedat nil)
  (firstseenat nil)
  (lastseenat nil)
  (createdat nil)
  (updatedat nil)
  (validfrom nil)
  (validuntil nil)
  (expiresat nil)
  (collector nil)
  (collectorversion nil)
  (collectionmethod nil)
  (collectionstatus nil)
  (runid nil)
  (correlationid nil)
  (causationid nil)
  (parentid nil)
  (rootid nil)
  (confidence nil)
  (confidencebasis nil)
  (qualityscore nil)
  (completenessscore nil)
  (verificationstatus nil)
  (verifiedat nil)
  (verifiedby nil)
  (provenance nil)
  (chainofcustody nil)
  (transformhistory nil)
  (labels nil)
  (tags nil)
  (topics nil)
  (language nil)
  (jurisdiction nil)
  (countrycode nil)
  (regioncode nil)
  (timezone nil)
  (sensitivity nil)
  (visibility nil)
  (owner nil)
  (accesscontrol nil)
  (legalbasis nil)
  (retentionpolicy nil)
  (contenttype nil)
  (encoding nil)
  (sizebytes nil)
  (contenthash nil)
  (hashalgorithm nil)
  (normalizedhash nil)
  (raw nil)
  (rawcontent nil)
  (notes nil)
  (deleted nil)
  (tombstonereason nil)
  (extensions nil)
  (fname nil)
  (mname nil)
  (lname nil)
  (fullname nil)
  (displayname nil)
  (prefix nil)
  (suffix nil)
  (pronouns nil)
  (bio nil)
  (dob nil)
  (dateofdeath nil)
  (age nil)
  (gender nil)
  (nationality nil)
  (citizenship nil)
  (occupation nil)
  (employer nil)
  (education nil)
  (skills nil)
  (interests nil)
  (region nil)
  (addresses nil)
  (emails nil)
  (phones nil)
  (accounts nil)
  (images nil)
  (identifiers nil)
  (misc nil)
  (etype nil)
  (eid nil)
)
(defparameter +person-wire-fields+
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

(defstruct relation
  (id nil)
  (rev nil)
  (dataset nil)
  (dtype nil)
  (schemaversion nil)
  (externalids nil)
  (aliases nil)
  (sources nil)
  (sourceurls nil)
  (sourcerecordids nil)
  (sourcekinds nil)
  (sourcelicense nil)
  (sourceterms nil)
  (sourceretrievedat nil)
  (collectedat nil)
  (observedat nil)
  (firstseenat nil)
  (lastseenat nil)
  (createdat nil)
  (updatedat nil)
  (validfrom nil)
  (validuntil nil)
  (expiresat nil)
  (collector nil)
  (collectorversion nil)
  (collectionmethod nil)
  (collectionstatus nil)
  (runid nil)
  (correlationid nil)
  (causationid nil)
  (parentid nil)
  (rootid nil)
  (confidence nil)
  (confidencebasis nil)
  (qualityscore nil)
  (completenessscore nil)
  (verificationstatus nil)
  (verifiedat nil)
  (verifiedby nil)
  (provenance nil)
  (chainofcustody nil)
  (transformhistory nil)
  (labels nil)
  (tags nil)
  (topics nil)
  (language nil)
  (jurisdiction nil)
  (countrycode nil)
  (regioncode nil)
  (timezone nil)
  (sensitivity nil)
  (visibility nil)
  (owner nil)
  (accesscontrol nil)
  (legalbasis nil)
  (retentionpolicy nil)
  (contenttype nil)
  (encoding nil)
  (sizebytes nil)
  (contenthash nil)
  (hashalgorithm nil)
  (normalizedhash nil)
  (raw nil)
  (rawcontent nil)
  (notes nil)
  (deleted nil)
  (tombstonereason nil)
  (extensions nil)
  (source nil)
  (destination nil)
  (predicate nil)
  (direction nil)
  (inversepredicate nil)
  (note nil)
  (evidence nil)
  (weight nil)
  (validat nil)
  (endedat nil)
)
(defparameter +relation-wire-fields+
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

(deftype pixel-offset () 'integer)

(deftype pixel-length () 'integer)

(deftype annotation-basis () 'string)

(deftype candidate-only () '(member "candidate"))

(defstruct face-observation
  (id nil)
  (rev nil)
  (dataset nil)
  (dtype nil)
  (schemaversion nil)
  (externalids nil)
  (aliases nil)
  (sources nil)
  (sourceurls nil)
  (sourcerecordids nil)
  (sourcekinds nil)
  (sourcelicense nil)
  (sourceterms nil)
  (sourceretrievedat nil)
  (collectedat nil)
  (observedat nil)
  (firstseenat nil)
  (lastseenat nil)
  (createdat nil)
  (updatedat nil)
  (validfrom nil)
  (validuntil nil)
  (expiresat nil)
  (collector nil)
  (collectorversion nil)
  (collectionmethod nil)
  (collectionstatus nil)
  (runid nil)
  (correlationid nil)
  (causationid nil)
  (parentid nil)
  (rootid nil)
  (confidence nil)
  (confidencebasis nil)
  (qualityscore nil)
  (completenessscore nil)
  (verificationstatus nil)
  (verifiedat nil)
  (verifiedby nil)
  (provenance nil)
  (chainofcustody nil)
  (transformhistory nil)
  (labels nil)
  (tags nil)
  (topics nil)
  (language nil)
  (jurisdiction nil)
  (countrycode nil)
  (regioncode nil)
  (timezone nil)
  (sensitivity nil)
  (visibility nil)
  (owner nil)
  (accesscontrol nil)
  (legalbasis nil)
  (retentionpolicy nil)
  (contenttype nil)
  (encoding nil)
  (sizebytes nil)
  (contenthash nil)
  (hashalgorithm nil)
  (normalizedhash nil)
  (raw nil)
  (rawcontent nil)
  (notes nil)
  (deleted nil)
  (tombstonereason nil)
  (extensions nil)
  (picture nil)
  (x nil)
  (y nil)
  (width nil)
  (height nil)
  (annotationbasis nil)
)
(defparameter +face-observation-wire-fields+
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

(defstruct candidate-person
  (id nil)
  (rev nil)
  (dataset nil)
  (dtype nil)
  (schemaversion nil)
  (externalids nil)
  (aliases nil)
  (sources nil)
  (sourceurls nil)
  (sourcerecordids nil)
  (sourcekinds nil)
  (sourcelicense nil)
  (sourceterms nil)
  (sourceretrievedat nil)
  (collectedat nil)
  (observedat nil)
  (firstseenat nil)
  (lastseenat nil)
  (createdat nil)
  (updatedat nil)
  (validfrom nil)
  (validuntil nil)
  (expiresat nil)
  (collector nil)
  (collectorversion nil)
  (collectionmethod nil)
  (collectionstatus nil)
  (runid nil)
  (correlationid nil)
  (causationid nil)
  (parentid nil)
  (rootid nil)
  (confidence nil)
  (confidencebasis nil)
  (qualityscore nil)
  (completenessscore nil)
  (verificationstatus nil)
  (verifiedat nil)
  (verifiedby nil)
  (provenance nil)
  (chainofcustody nil)
  (transformhistory nil)
  (labels nil)
  (tags nil)
  (topics nil)
  (language nil)
  (jurisdiction nil)
  (countrycode nil)
  (regioncode nil)
  (timezone nil)
  (sensitivity nil)
  (visibility nil)
  (owner nil)
  (accesscontrol nil)
  (legalbasis nil)
  (retentionpolicy nil)
  (contenttype nil)
  (encoding nil)
  (sizebytes nil)
  (contenthash nil)
  (hashalgorithm nil)
  (normalizedhash nil)
  (raw nil)
  (rawcontent nil)
  (notes nil)
  (deleted nil)
  (tombstonereason nil)
  (extensions nil)
  (fname nil)
  (mname nil)
  (lname nil)
  (fullname nil)
  (displayname nil)
  (prefix nil)
  (suffix nil)
  (pronouns nil)
  (bio nil)
  (dob nil)
  (dateofdeath nil)
  (age nil)
  (gender nil)
  (nationality nil)
  (citizenship nil)
  (occupation nil)
  (employer nil)
  (education nil)
  (skills nil)
  (interests nil)
  (region nil)
  (addresses nil)
  (emails nil)
  (phones nil)
  (accounts nil)
  (images nil)
  (identifiers nil)
  (misc nil)
  (etype nil)
  (eid nil)
  (candidatestatus nil)
  (annotationbasis nil)
  (evidencereferences nil)
)
(defparameter +candidate-person-wire-fields+
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

(defstruct face-person-candidate
  (id nil)
  (rev nil)
  (dataset nil)
  (dtype nil)
  (schemaversion nil)
  (externalids nil)
  (aliases nil)
  (sources nil)
  (sourceurls nil)
  (sourcerecordids nil)
  (sourcekinds nil)
  (sourcelicense nil)
  (sourceterms nil)
  (sourceretrievedat nil)
  (collectedat nil)
  (observedat nil)
  (firstseenat nil)
  (lastseenat nil)
  (createdat nil)
  (updatedat nil)
  (validfrom nil)
  (validuntil nil)
  (expiresat nil)
  (collector nil)
  (collectorversion nil)
  (collectionmethod nil)
  (collectionstatus nil)
  (runid nil)
  (correlationid nil)
  (causationid nil)
  (parentid nil)
  (rootid nil)
  (confidence nil)
  (confidencebasis nil)
  (qualityscore nil)
  (completenessscore nil)
  (verificationstatus nil)
  (verifiedat nil)
  (verifiedby nil)
  (provenance nil)
  (chainofcustody nil)
  (transformhistory nil)
  (labels nil)
  (tags nil)
  (topics nil)
  (language nil)
  (jurisdiction nil)
  (countrycode nil)
  (regioncode nil)
  (timezone nil)
  (sensitivity nil)
  (visibility nil)
  (owner nil)
  (accesscontrol nil)
  (legalbasis nil)
  (retentionpolicy nil)
  (contenttype nil)
  (encoding nil)
  (sizebytes nil)
  (contenthash nil)
  (hashalgorithm nil)
  (normalizedhash nil)
  (raw nil)
  (rawcontent nil)
  (notes nil)
  (deleted nil)
  (tombstonereason nil)
  (extensions nil)
  (source nil)
  (destination nil)
  (predicate nil)
  (direction nil)
  (inversepredicate nil)
  (note nil)
  (evidence nil)
  (weight nil)
  (validat nil)
  (endedat nil)
  (candidatestatus nil)
  (annotationbasis nil)
  (evidencereferences nil)
)
(defparameter +face-person-candidate-wire-fields+
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

(defstruct store-face-observation
  (document nil)
)
(defparameter +store-face-observation-wire-fields+
  '(
    ("document" . document)
  ))

(defstruct store-candidate-person
  (document nil)
)
(defparameter +store-candidate-person-wire-fields+
  '(
    ("document" . document)
  ))

(defstruct annotate-face-person
  (face nil)
  (person nil)
  (annotationbasis nil)
)
(defparameter +annotate-face-person-wire-fields+
  '(
    ("face" . face)
    ("person" . person)
    ("annotationBasis" . annotationbasis)
  ))

(defstruct get-face-observation
  (face nil)
)
(defparameter +get-face-observation-wire-fields+
  '(
    ("face" . face)
  ))
