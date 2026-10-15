## Generated from StarLang portable manifest. DO NOT EDIT.
import std/[json, options]

type
  StarReference* = object
    schema*: string
    id*: string

  DocumentId* = distinct string
  UnixTime* = distinct int64
  ConfidenceScore* = distinct string
  Uri* = distinct string
  Sensitivity* = distinct string
  Visibility* = distinct string
  CollectionStatus* = distinct string
  SourceKind* = distinct string
  HashAlgorithm* = distinct string
  RelationDirection* = distinct string
  Document* = object
    `id`*: DocumentId
    `rev`*: Option[string]
    `dataset`*: string
    `dtype`*: string
    `schemaVersion`*: string
    `externalIds`*: Option[JsonNode]
    `aliases`*: Option[seq[string]]
    `sources`*: Option[seq[StarReference]]
    `sourceUrls`*: Option[seq[Uri]]
    `sourceRecordIds`*: Option[seq[string]]
    `sourceKinds`*: Option[seq[SourceKind]]
    `sourceLicense`*: Option[string]
    `sourceTerms`*: Option[Uri]
    `sourceRetrievedAt`*: Option[UnixTime]
    `collectedAt`*: Option[UnixTime]
    `observedAt`*: Option[UnixTime]
    `firstSeenAt`*: Option[UnixTime]
    `lastSeenAt`*: Option[UnixTime]
    `createdAt`*: Option[UnixTime]
    `updatedAt`*: Option[UnixTime]
    `validFrom`*: Option[UnixTime]
    `validUntil`*: Option[UnixTime]
    `expiresAt`*: Option[UnixTime]
    `collector`*: Option[string]
    `collectorVersion`*: Option[string]
    `collectionMethod`*: Option[string]
    `collectionStatus`*: Option[CollectionStatus]
    `runId`*: Option[string]
    `correlationId`*: Option[string]
    `causationId`*: Option[string]
    `parentId`*: Option[DocumentId]
    `rootId`*: Option[DocumentId]
    `confidence`*: Option[ConfidenceScore]
    `confidenceBasis`*: Option[string]
    `qualityScore`*: Option[ConfidenceScore]
    `completenessScore`*: Option[ConfidenceScore]
    `verificationStatus`*: Option[string]
    `verifiedAt`*: Option[UnixTime]
    `verifiedBy`*: Option[string]
    `provenance`*: Option[JsonNode]
    `chainOfCustody`*: Option[seq[JsonNode]]
    `transformHistory`*: Option[seq[JsonNode]]
    `labels`*: Option[seq[string]]
    `tags`*: Option[seq[string]]
    `topics`*: Option[seq[string]]
    `language`*: Option[string]
    `jurisdiction`*: Option[string]
    `countryCode`*: Option[string]
    `regionCode`*: Option[string]
    `timezone`*: Option[string]
    `sensitivity`*: Option[Sensitivity]
    `visibility`*: Option[Visibility]
    `owner`*: Option[string]
    `accessControl`*: Option[JsonNode]
    `legalBasis`*: Option[string]
    `retentionPolicy`*: Option[string]
    `contentType`*: Option[string]
    `encoding`*: Option[string]
    `sizeBytes`*: Option[int64]
    `contentHash`*: Option[string]
    `hashAlgorithm`*: Option[HashAlgorithm]
    `normalizedHash`*: Option[string]
    `raw`*: Option[JsonNode]
    `rawContent`*: Option[string]
    `notes`*: Option[string]
    `deleted`*: Option[bool]
    `tombstoneReason`*: Option[string]
    `extensions`*: Option[JsonNode]

  Person* = object
    `id`*: DocumentId
    `rev`*: Option[string]
    `dataset`*: string
    `dtype`*: string
    `schemaVersion`*: string
    `externalIds`*: Option[JsonNode]
    `aliases`*: Option[seq[string]]
    `sources`*: Option[seq[StarReference]]
    `sourceUrls`*: Option[seq[Uri]]
    `sourceRecordIds`*: Option[seq[string]]
    `sourceKinds`*: Option[seq[SourceKind]]
    `sourceLicense`*: Option[string]
    `sourceTerms`*: Option[Uri]
    `sourceRetrievedAt`*: Option[UnixTime]
    `collectedAt`*: Option[UnixTime]
    `observedAt`*: Option[UnixTime]
    `firstSeenAt`*: Option[UnixTime]
    `lastSeenAt`*: Option[UnixTime]
    `createdAt`*: Option[UnixTime]
    `updatedAt`*: Option[UnixTime]
    `validFrom`*: Option[UnixTime]
    `validUntil`*: Option[UnixTime]
    `expiresAt`*: Option[UnixTime]
    `collector`*: Option[string]
    `collectorVersion`*: Option[string]
    `collectionMethod`*: Option[string]
    `collectionStatus`*: Option[CollectionStatus]
    `runId`*: Option[string]
    `correlationId`*: Option[string]
    `causationId`*: Option[string]
    `parentId`*: Option[DocumentId]
    `rootId`*: Option[DocumentId]
    `confidence`*: Option[ConfidenceScore]
    `confidenceBasis`*: Option[string]
    `qualityScore`*: Option[ConfidenceScore]
    `completenessScore`*: Option[ConfidenceScore]
    `verificationStatus`*: Option[string]
    `verifiedAt`*: Option[UnixTime]
    `verifiedBy`*: Option[string]
    `provenance`*: Option[JsonNode]
    `chainOfCustody`*: Option[seq[JsonNode]]
    `transformHistory`*: Option[seq[JsonNode]]
    `labels`*: Option[seq[string]]
    `tags`*: Option[seq[string]]
    `topics`*: Option[seq[string]]
    `language`*: Option[string]
    `jurisdiction`*: Option[string]
    `countryCode`*: Option[string]
    `regionCode`*: Option[string]
    `timezone`*: Option[string]
    `sensitivity`*: Option[Sensitivity]
    `visibility`*: Option[Visibility]
    `owner`*: Option[string]
    `accessControl`*: Option[JsonNode]
    `legalBasis`*: Option[string]
    `retentionPolicy`*: Option[string]
    `contentType`*: Option[string]
    `encoding`*: Option[string]
    `sizeBytes`*: Option[int64]
    `contentHash`*: Option[string]
    `hashAlgorithm`*: Option[HashAlgorithm]
    `normalizedHash`*: Option[string]
    `raw`*: Option[JsonNode]
    `rawContent`*: Option[string]
    `notes`*: Option[string]
    `deleted`*: Option[bool]
    `tombstoneReason`*: Option[string]
    `extensions`*: Option[JsonNode]
    `fname`*: Option[string]
    `mname`*: Option[string]
    `lname`*: Option[string]
    `fullName`*: Option[string]
    `displayName`*: Option[string]
    `prefix`*: Option[string]
    `suffix`*: Option[string]
    `pronouns`*: Option[string]
    `bio`*: Option[string]
    `dob`*: Option[string]
    `dateOfDeath`*: Option[string]
    `age`*: Option[int64]
    `gender`*: Option[string]
    `nationality`*: Option[seq[string]]
    `citizenship`*: Option[seq[string]]
    `occupation`*: Option[seq[string]]
    `employer`*: Option[seq[StarReference]]
    `education`*: Option[seq[JsonNode]]
    `skills`*: Option[seq[string]]
    `interests`*: Option[seq[string]]
    `region`*: Option[string]
    `addresses`*: Option[seq[StarReference]]
    `emails`*: Option[seq[StarReference]]
    `phones`*: Option[seq[StarReference]]
    `accounts`*: Option[seq[StarReference]]
    `images`*: Option[seq[StarReference]]
    `identifiers`*: Option[seq[StarReference]]
    `misc`*: Option[seq[JsonNode]]
    `etype`*: Option[string]
    `eid`*: Option[string]

  Relation* = object
    `id`*: DocumentId
    `rev`*: Option[string]
    `dataset`*: string
    `dtype`*: string
    `schemaVersion`*: string
    `externalIds`*: Option[JsonNode]
    `aliases`*: Option[seq[string]]
    `sources`*: Option[seq[StarReference]]
    `sourceUrls`*: Option[seq[Uri]]
    `sourceRecordIds`*: Option[seq[string]]
    `sourceKinds`*: Option[seq[SourceKind]]
    `sourceLicense`*: Option[string]
    `sourceTerms`*: Option[Uri]
    `sourceRetrievedAt`*: Option[UnixTime]
    `collectedAt`*: Option[UnixTime]
    `observedAt`*: Option[UnixTime]
    `firstSeenAt`*: Option[UnixTime]
    `lastSeenAt`*: Option[UnixTime]
    `createdAt`*: Option[UnixTime]
    `updatedAt`*: Option[UnixTime]
    `validFrom`*: Option[UnixTime]
    `validUntil`*: Option[UnixTime]
    `expiresAt`*: Option[UnixTime]
    `collector`*: Option[string]
    `collectorVersion`*: Option[string]
    `collectionMethod`*: Option[string]
    `collectionStatus`*: Option[CollectionStatus]
    `runId`*: Option[string]
    `correlationId`*: Option[string]
    `causationId`*: Option[string]
    `parentId`*: Option[DocumentId]
    `rootId`*: Option[DocumentId]
    `confidence`*: Option[ConfidenceScore]
    `confidenceBasis`*: Option[string]
    `qualityScore`*: Option[ConfidenceScore]
    `completenessScore`*: Option[ConfidenceScore]
    `verificationStatus`*: Option[string]
    `verifiedAt`*: Option[UnixTime]
    `verifiedBy`*: Option[string]
    `provenance`*: Option[JsonNode]
    `chainOfCustody`*: Option[seq[JsonNode]]
    `transformHistory`*: Option[seq[JsonNode]]
    `labels`*: Option[seq[string]]
    `tags`*: Option[seq[string]]
    `topics`*: Option[seq[string]]
    `language`*: Option[string]
    `jurisdiction`*: Option[string]
    `countryCode`*: Option[string]
    `regionCode`*: Option[string]
    `timezone`*: Option[string]
    `sensitivity`*: Option[Sensitivity]
    `visibility`*: Option[Visibility]
    `owner`*: Option[string]
    `accessControl`*: Option[JsonNode]
    `legalBasis`*: Option[string]
    `retentionPolicy`*: Option[string]
    `contentType`*: Option[string]
    `encoding`*: Option[string]
    `sizeBytes`*: Option[int64]
    `contentHash`*: Option[string]
    `hashAlgorithm`*: Option[HashAlgorithm]
    `normalizedHash`*: Option[string]
    `raw`*: Option[JsonNode]
    `rawContent`*: Option[string]
    `notes`*: Option[string]
    `deleted`*: Option[bool]
    `tombstoneReason`*: Option[string]
    `extensions`*: Option[JsonNode]
    `source`*: StarReference
    `destination`*: StarReference
    `predicate`*: string
    `direction`*: Option[RelationDirection]
    `inversePredicate`*: Option[string]
    `note`*: Option[string]
    `evidence`*: Option[seq[StarReference]]
    `weight`*: Option[string]
    `validAt`*: Option[UnixTime]
    `endedAt`*: Option[UnixTime]

  PixelOffset* = distinct int64
  PixelLength* = distinct int64
  AnnotationBasis* = distinct string
  CandidateOnly* = distinct string
  FaceObservation* = object
    `id`*: DocumentId
    `rev`*: Option[string]
    `dataset`*: string
    `dtype`*: string
    `schemaVersion`*: string
    `externalIds`*: Option[JsonNode]
    `aliases`*: Option[seq[string]]
    `sources`*: Option[seq[StarReference]]
    `sourceUrls`*: Option[seq[Uri]]
    `sourceRecordIds`*: Option[seq[string]]
    `sourceKinds`*: Option[seq[SourceKind]]
    `sourceLicense`*: Option[string]
    `sourceTerms`*: Option[Uri]
    `sourceRetrievedAt`*: Option[UnixTime]
    `collectedAt`*: Option[UnixTime]
    `observedAt`*: Option[UnixTime]
    `firstSeenAt`*: Option[UnixTime]
    `lastSeenAt`*: Option[UnixTime]
    `createdAt`*: Option[UnixTime]
    `updatedAt`*: Option[UnixTime]
    `validFrom`*: Option[UnixTime]
    `validUntil`*: Option[UnixTime]
    `expiresAt`*: Option[UnixTime]
    `collector`*: Option[string]
    `collectorVersion`*: Option[string]
    `collectionMethod`*: Option[string]
    `collectionStatus`*: Option[CollectionStatus]
    `runId`*: Option[string]
    `correlationId`*: Option[string]
    `causationId`*: Option[string]
    `parentId`*: Option[DocumentId]
    `rootId`*: Option[DocumentId]
    `confidence`*: Option[ConfidenceScore]
    `confidenceBasis`*: Option[string]
    `qualityScore`*: Option[ConfidenceScore]
    `completenessScore`*: Option[ConfidenceScore]
    `verificationStatus`*: Option[string]
    `verifiedAt`*: Option[UnixTime]
    `verifiedBy`*: Option[string]
    `provenance`*: Option[JsonNode]
    `chainOfCustody`*: Option[seq[JsonNode]]
    `transformHistory`*: Option[seq[JsonNode]]
    `labels`*: Option[seq[string]]
    `tags`*: Option[seq[string]]
    `topics`*: Option[seq[string]]
    `language`*: Option[string]
    `jurisdiction`*: Option[string]
    `countryCode`*: Option[string]
    `regionCode`*: Option[string]
    `timezone`*: Option[string]
    `sensitivity`*: Option[Sensitivity]
    `visibility`*: Option[Visibility]
    `owner`*: Option[string]
    `accessControl`*: Option[JsonNode]
    `legalBasis`*: Option[string]
    `retentionPolicy`*: Option[string]
    `contentType`*: Option[string]
    `encoding`*: Option[string]
    `sizeBytes`*: Option[int64]
    `contentHash`*: Option[string]
    `hashAlgorithm`*: Option[HashAlgorithm]
    `normalizedHash`*: Option[string]
    `raw`*: Option[JsonNode]
    `rawContent`*: Option[string]
    `notes`*: Option[string]
    `deleted`*: Option[bool]
    `tombstoneReason`*: Option[string]
    `extensions`*: Option[JsonNode]
    `picture`*: StarReference
    `x`*: PixelOffset
    `y`*: PixelOffset
    `width`*: PixelLength
    `height`*: PixelLength
    `annotationBasis`*: AnnotationBasis

  CandidatePerson* = object
    `id`*: DocumentId
    `rev`*: Option[string]
    `dataset`*: string
    `dtype`*: string
    `schemaVersion`*: string
    `externalIds`*: Option[JsonNode]
    `aliases`*: Option[seq[string]]
    `sources`*: Option[seq[StarReference]]
    `sourceUrls`*: Option[seq[Uri]]
    `sourceRecordIds`*: Option[seq[string]]
    `sourceKinds`*: Option[seq[SourceKind]]
    `sourceLicense`*: Option[string]
    `sourceTerms`*: Option[Uri]
    `sourceRetrievedAt`*: Option[UnixTime]
    `collectedAt`*: Option[UnixTime]
    `observedAt`*: Option[UnixTime]
    `firstSeenAt`*: Option[UnixTime]
    `lastSeenAt`*: Option[UnixTime]
    `createdAt`*: Option[UnixTime]
    `updatedAt`*: Option[UnixTime]
    `validFrom`*: Option[UnixTime]
    `validUntil`*: Option[UnixTime]
    `expiresAt`*: Option[UnixTime]
    `collector`*: Option[string]
    `collectorVersion`*: Option[string]
    `collectionMethod`*: Option[string]
    `collectionStatus`*: Option[CollectionStatus]
    `runId`*: Option[string]
    `correlationId`*: Option[string]
    `causationId`*: Option[string]
    `parentId`*: Option[DocumentId]
    `rootId`*: Option[DocumentId]
    `confidence`*: Option[ConfidenceScore]
    `confidenceBasis`*: Option[string]
    `qualityScore`*: Option[ConfidenceScore]
    `completenessScore`*: Option[ConfidenceScore]
    `verificationStatus`*: Option[string]
    `verifiedAt`*: Option[UnixTime]
    `verifiedBy`*: Option[string]
    `provenance`*: Option[JsonNode]
    `chainOfCustody`*: Option[seq[JsonNode]]
    `transformHistory`*: Option[seq[JsonNode]]
    `labels`*: Option[seq[string]]
    `tags`*: Option[seq[string]]
    `topics`*: Option[seq[string]]
    `language`*: Option[string]
    `jurisdiction`*: Option[string]
    `countryCode`*: Option[string]
    `regionCode`*: Option[string]
    `timezone`*: Option[string]
    `sensitivity`*: Option[Sensitivity]
    `visibility`*: Option[Visibility]
    `owner`*: Option[string]
    `accessControl`*: Option[JsonNode]
    `legalBasis`*: Option[string]
    `retentionPolicy`*: Option[string]
    `contentType`*: Option[string]
    `encoding`*: Option[string]
    `sizeBytes`*: Option[int64]
    `contentHash`*: Option[string]
    `hashAlgorithm`*: Option[HashAlgorithm]
    `normalizedHash`*: Option[string]
    `raw`*: Option[JsonNode]
    `rawContent`*: Option[string]
    `notes`*: Option[string]
    `deleted`*: Option[bool]
    `tombstoneReason`*: Option[string]
    `extensions`*: Option[JsonNode]
    `fname`*: Option[string]
    `mname`*: Option[string]
    `lname`*: Option[string]
    `fullName`*: Option[string]
    `displayName`*: Option[string]
    `prefix`*: Option[string]
    `suffix`*: Option[string]
    `pronouns`*: Option[string]
    `bio`*: Option[string]
    `dob`*: Option[string]
    `dateOfDeath`*: Option[string]
    `age`*: Option[int64]
    `gender`*: Option[string]
    `nationality`*: Option[seq[string]]
    `citizenship`*: Option[seq[string]]
    `occupation`*: Option[seq[string]]
    `employer`*: Option[seq[StarReference]]
    `education`*: Option[seq[JsonNode]]
    `skills`*: Option[seq[string]]
    `interests`*: Option[seq[string]]
    `region`*: Option[string]
    `addresses`*: Option[seq[StarReference]]
    `emails`*: Option[seq[StarReference]]
    `phones`*: Option[seq[StarReference]]
    `accounts`*: Option[seq[StarReference]]
    `images`*: Option[seq[StarReference]]
    `identifiers`*: Option[seq[StarReference]]
    `misc`*: Option[seq[JsonNode]]
    `etype`*: Option[string]
    `eid`*: Option[string]
    `candidateStatus`*: CandidateOnly
    `annotationBasis`*: AnnotationBasis
    `evidenceReferences`*: Option[seq[StarReference]]

  FacePersonCandidate* = object
    `id`*: DocumentId
    `rev`*: Option[string]
    `dataset`*: string
    `dtype`*: string
    `schemaVersion`*: string
    `externalIds`*: Option[JsonNode]
    `aliases`*: Option[seq[string]]
    `sources`*: Option[seq[StarReference]]
    `sourceUrls`*: Option[seq[Uri]]
    `sourceRecordIds`*: Option[seq[string]]
    `sourceKinds`*: Option[seq[SourceKind]]
    `sourceLicense`*: Option[string]
    `sourceTerms`*: Option[Uri]
    `sourceRetrievedAt`*: Option[UnixTime]
    `collectedAt`*: Option[UnixTime]
    `observedAt`*: Option[UnixTime]
    `firstSeenAt`*: Option[UnixTime]
    `lastSeenAt`*: Option[UnixTime]
    `createdAt`*: Option[UnixTime]
    `updatedAt`*: Option[UnixTime]
    `validFrom`*: Option[UnixTime]
    `validUntil`*: Option[UnixTime]
    `expiresAt`*: Option[UnixTime]
    `collector`*: Option[string]
    `collectorVersion`*: Option[string]
    `collectionMethod`*: Option[string]
    `collectionStatus`*: Option[CollectionStatus]
    `runId`*: Option[string]
    `correlationId`*: Option[string]
    `causationId`*: Option[string]
    `parentId`*: Option[DocumentId]
    `rootId`*: Option[DocumentId]
    `confidence`*: Option[ConfidenceScore]
    `confidenceBasis`*: Option[string]
    `qualityScore`*: Option[ConfidenceScore]
    `completenessScore`*: Option[ConfidenceScore]
    `verificationStatus`*: Option[string]
    `verifiedAt`*: Option[UnixTime]
    `verifiedBy`*: Option[string]
    `provenance`*: Option[JsonNode]
    `chainOfCustody`*: Option[seq[JsonNode]]
    `transformHistory`*: Option[seq[JsonNode]]
    `labels`*: Option[seq[string]]
    `tags`*: Option[seq[string]]
    `topics`*: Option[seq[string]]
    `language`*: Option[string]
    `jurisdiction`*: Option[string]
    `countryCode`*: Option[string]
    `regionCode`*: Option[string]
    `timezone`*: Option[string]
    `sensitivity`*: Option[Sensitivity]
    `visibility`*: Option[Visibility]
    `owner`*: Option[string]
    `accessControl`*: Option[JsonNode]
    `legalBasis`*: Option[string]
    `retentionPolicy`*: Option[string]
    `contentType`*: Option[string]
    `encoding`*: Option[string]
    `sizeBytes`*: Option[int64]
    `contentHash`*: Option[string]
    `hashAlgorithm`*: Option[HashAlgorithm]
    `normalizedHash`*: Option[string]
    `raw`*: Option[JsonNode]
    `rawContent`*: Option[string]
    `notes`*: Option[string]
    `deleted`*: Option[bool]
    `tombstoneReason`*: Option[string]
    `extensions`*: Option[JsonNode]
    `source`*: StarReference
    `destination`*: StarReference
    `predicate`*: string
    `direction`*: Option[RelationDirection]
    `inversePredicate`*: Option[string]
    `note`*: Option[string]
    `evidence`*: Option[seq[StarReference]]
    `weight`*: Option[string]
    `validAt`*: Option[UnixTime]
    `endedAt`*: Option[UnixTime]
    `candidateStatus`*: CandidateOnly
    `annotationBasis`*: AnnotationBasis
    `evidenceReferences`*: Option[seq[StarReference]]


const SensitivityPublic* = Sensitivity("public")
const SensitivityInternal* = Sensitivity("internal")
const SensitivityConfidential* = Sensitivity("confidential")
const SensitivityRestricted* = Sensitivity("restricted")
const SensitivitySecret* = Sensitivity("secret")
const SensitivityUnknown* = Sensitivity("unknown")
const VisibilityPublic* = Visibility("public")
const VisibilityPrivate* = Visibility("private")
const VisibilityShared* = Visibility("shared")
const VisibilityInherited* = Visibility("inherited")
const VisibilityUnknown* = Visibility("unknown")
const CollectionStatusRaw* = CollectionStatus("raw")
const CollectionStatusNormalized* = CollectionStatus("normalized")
const CollectionStatusEnriched* = CollectionStatus("enriched")
const CollectionStatusVerified* = CollectionStatus("verified")
const CollectionStatusDisputed* = CollectionStatus("disputed")
const CollectionStatusStale* = CollectionStatus("stale")
const CollectionStatusDeleted* = CollectionStatus("deleted")
const CollectionStatusUnknown* = CollectionStatus("unknown")
const SourceKindApi* = SourceKind("api")
const SourceKindWeb* = SourceKind("web")
const SourceKindFile* = SourceKind("file")
const SourceKindDatabase* = SourceKind("database")
const SourceKindMessage* = SourceKind("message")
const SourceKindHuman* = SourceKind("human")
const SourceKindSensor* = SourceKind("sensor")
const SourceKindInference* = SourceKind("inference")
const SourceKindImport* = SourceKind("import")
const SourceKindExport* = SourceKind("export")
const SourceKindUnknown* = SourceKind("unknown")
const HashAlgorithmSha256* = HashAlgorithm("sha256")
const HashAlgorithmSha512* = HashAlgorithm("sha512")
const HashAlgorithmBlake2b* = HashAlgorithm("blake2b")
const HashAlgorithmBlake3* = HashAlgorithm("blake3")
const HashAlgorithmMd5* = HashAlgorithm("md5")
const HashAlgorithmUnknown* = HashAlgorithm("unknown")
const RelationDirectionDirected* = RelationDirection("directed")
const RelationDirectionSymmetric* = RelationDirection("symmetric")
const RelationDirectionInverse* = RelationDirection("inverse")
const RelationDirectionUnknown* = RelationDirection("unknown")
const CandidateOnlyCandidate* = CandidateOnly("candidate")

type
  StoreFaceObservation* = object
    `document`*: StarReference

type
  StoreCandidatePerson* = object
    `document`*: StarReference

type
  AnnotateFacePerson* = object
    `face`*: StarReference
    `person`*: StarReference
    `annotationBasis`*: AnnotationBasis

type
  GetFaceObservation* = object
    `face`*: StarReference
