// Code generated from StarLang portable manifest. DO NOT EDIT.
package starintel

type StarReference struct {
    Schema string `json:"schema"`
    ID string `json:"id"`
}

type DocumentId string

type UnixTime int64

type ConfidenceScore string

type Uri string

type Sensitivity string

const (
    SensitivityPublic Sensitivity = "public"
    SensitivityInternal Sensitivity = "internal"
    SensitivityConfidential Sensitivity = "confidential"
    SensitivityRestricted Sensitivity = "restricted"
    SensitivitySecret Sensitivity = "secret"
    SensitivityUnknown Sensitivity = "unknown"
)

type Visibility string

const (
    VisibilityPublic Visibility = "public"
    VisibilityPrivate Visibility = "private"
    VisibilityShared Visibility = "shared"
    VisibilityInherited Visibility = "inherited"
    VisibilityUnknown Visibility = "unknown"
)

type CollectionStatus string

const (
    CollectionStatusRaw CollectionStatus = "raw"
    CollectionStatusNormalized CollectionStatus = "normalized"
    CollectionStatusEnriched CollectionStatus = "enriched"
    CollectionStatusVerified CollectionStatus = "verified"
    CollectionStatusDisputed CollectionStatus = "disputed"
    CollectionStatusStale CollectionStatus = "stale"
    CollectionStatusDeleted CollectionStatus = "deleted"
    CollectionStatusUnknown CollectionStatus = "unknown"
)

type SourceKind string

const (
    SourceKindApi SourceKind = "api"
    SourceKindWeb SourceKind = "web"
    SourceKindFile SourceKind = "file"
    SourceKindDatabase SourceKind = "database"
    SourceKindMessage SourceKind = "message"
    SourceKindHuman SourceKind = "human"
    SourceKindSensor SourceKind = "sensor"
    SourceKindInference SourceKind = "inference"
    SourceKindImport SourceKind = "import"
    SourceKindExport SourceKind = "export"
    SourceKindUnknown SourceKind = "unknown"
)

type HashAlgorithm string

const (
    HashAlgorithmSha256 HashAlgorithm = "sha256"
    HashAlgorithmSha512 HashAlgorithm = "sha512"
    HashAlgorithmBlake2b HashAlgorithm = "blake2b"
    HashAlgorithmBlake3 HashAlgorithm = "blake3"
    HashAlgorithmMd5 HashAlgorithm = "md5"
    HashAlgorithmUnknown HashAlgorithm = "unknown"
)

type RelationDirection string

const (
    RelationDirectionDirected RelationDirection = "directed"
    RelationDirectionSymmetric RelationDirection = "symmetric"
    RelationDirectionInverse RelationDirection = "inverse"
    RelationDirectionUnknown RelationDirection = "unknown"
)

type Document struct {
    Id DocumentId `json:"id"`
    Rev *string `json:"rev,omitempty"`
    Dataset string `json:"dataset"`
    Dtype string `json:"dtype"`
    Schemaversion string `json:"schemaVersion"`
    Externalids *map[string]any `json:"externalIds,omitempty"`
    Aliases *[]string `json:"aliases,omitempty"`
    Sources *[]StarReference `json:"sources,omitempty"`
    Sourceurls *[]Uri `json:"sourceUrls,omitempty"`
    Sourcerecordids *[]string `json:"sourceRecordIds,omitempty"`
    Sourcekinds *[]SourceKind `json:"sourceKinds,omitempty"`
    Sourcelicense *string `json:"sourceLicense,omitempty"`
    Sourceterms *Uri `json:"sourceTerms,omitempty"`
    Sourceretrievedat *UnixTime `json:"sourceRetrievedAt,omitempty"`
    Collectedat *UnixTime `json:"collectedAt,omitempty"`
    Observedat *UnixTime `json:"observedAt,omitempty"`
    Firstseenat *UnixTime `json:"firstSeenAt,omitempty"`
    Lastseenat *UnixTime `json:"lastSeenAt,omitempty"`
    Createdat *UnixTime `json:"createdAt,omitempty"`
    Updatedat *UnixTime `json:"updatedAt,omitempty"`
    Validfrom *UnixTime `json:"validFrom,omitempty"`
    Validuntil *UnixTime `json:"validUntil,omitempty"`
    Expiresat *UnixTime `json:"expiresAt,omitempty"`
    Collector *string `json:"collector,omitempty"`
    Collectorversion *string `json:"collectorVersion,omitempty"`
    Collectionmethod *string `json:"collectionMethod,omitempty"`
    Collectionstatus *CollectionStatus `json:"collectionStatus,omitempty"`
    Runid *string `json:"runId,omitempty"`
    Correlationid *string `json:"correlationId,omitempty"`
    Causationid *string `json:"causationId,omitempty"`
    Parentid *DocumentId `json:"parentId,omitempty"`
    Rootid *DocumentId `json:"rootId,omitempty"`
    Confidence *ConfidenceScore `json:"confidence,omitempty"`
    Confidencebasis *string `json:"confidenceBasis,omitempty"`
    Qualityscore *ConfidenceScore `json:"qualityScore,omitempty"`
    Completenessscore *ConfidenceScore `json:"completenessScore,omitempty"`
    Verificationstatus *string `json:"verificationStatus,omitempty"`
    Verifiedat *UnixTime `json:"verifiedAt,omitempty"`
    Verifiedby *string `json:"verifiedBy,omitempty"`
    Provenance *map[string]any `json:"provenance,omitempty"`
    Chainofcustody *[]map[string]any `json:"chainOfCustody,omitempty"`
    Transformhistory *[]map[string]any `json:"transformHistory,omitempty"`
    Labels *[]string `json:"labels,omitempty"`
    Tags *[]string `json:"tags,omitempty"`
    Topics *[]string `json:"topics,omitempty"`
    Language *string `json:"language,omitempty"`
    Jurisdiction *string `json:"jurisdiction,omitempty"`
    Countrycode *string `json:"countryCode,omitempty"`
    Regioncode *string `json:"regionCode,omitempty"`
    Timezone *string `json:"timezone,omitempty"`
    Sensitivity *Sensitivity `json:"sensitivity,omitempty"`
    Visibility *Visibility `json:"visibility,omitempty"`
    Owner *string `json:"owner,omitempty"`
    Accesscontrol *map[string]any `json:"accessControl,omitempty"`
    Legalbasis *string `json:"legalBasis,omitempty"`
    Retentionpolicy *string `json:"retentionPolicy,omitempty"`
    Contenttype *string `json:"contentType,omitempty"`
    Encoding *string `json:"encoding,omitempty"`
    Sizebytes *int64 `json:"sizeBytes,omitempty"`
    Contenthash *string `json:"contentHash,omitempty"`
    Hashalgorithm *HashAlgorithm `json:"hashAlgorithm,omitempty"`
    Normalizedhash *string `json:"normalizedHash,omitempty"`
    Raw *map[string]any `json:"raw,omitempty"`
    Rawcontent *string `json:"rawContent,omitempty"`
    Notes *string `json:"notes,omitempty"`
    Deleted *bool `json:"deleted,omitempty"`
    Tombstonereason *string `json:"tombstoneReason,omitempty"`
    Extensions *map[string]any `json:"extensions,omitempty"`
}

type Person struct {
    Id DocumentId `json:"id"`
    Rev *string `json:"rev,omitempty"`
    Dataset string `json:"dataset"`
    Dtype string `json:"dtype"`
    Schemaversion string `json:"schemaVersion"`
    Externalids *map[string]any `json:"externalIds,omitempty"`
    Aliases *[]string `json:"aliases,omitempty"`
    Sources *[]StarReference `json:"sources,omitempty"`
    Sourceurls *[]Uri `json:"sourceUrls,omitempty"`
    Sourcerecordids *[]string `json:"sourceRecordIds,omitempty"`
    Sourcekinds *[]SourceKind `json:"sourceKinds,omitempty"`
    Sourcelicense *string `json:"sourceLicense,omitempty"`
    Sourceterms *Uri `json:"sourceTerms,omitempty"`
    Sourceretrievedat *UnixTime `json:"sourceRetrievedAt,omitempty"`
    Collectedat *UnixTime `json:"collectedAt,omitempty"`
    Observedat *UnixTime `json:"observedAt,omitempty"`
    Firstseenat *UnixTime `json:"firstSeenAt,omitempty"`
    Lastseenat *UnixTime `json:"lastSeenAt,omitempty"`
    Createdat *UnixTime `json:"createdAt,omitempty"`
    Updatedat *UnixTime `json:"updatedAt,omitempty"`
    Validfrom *UnixTime `json:"validFrom,omitempty"`
    Validuntil *UnixTime `json:"validUntil,omitempty"`
    Expiresat *UnixTime `json:"expiresAt,omitempty"`
    Collector *string `json:"collector,omitempty"`
    Collectorversion *string `json:"collectorVersion,omitempty"`
    Collectionmethod *string `json:"collectionMethod,omitempty"`
    Collectionstatus *CollectionStatus `json:"collectionStatus,omitempty"`
    Runid *string `json:"runId,omitempty"`
    Correlationid *string `json:"correlationId,omitempty"`
    Causationid *string `json:"causationId,omitempty"`
    Parentid *DocumentId `json:"parentId,omitempty"`
    Rootid *DocumentId `json:"rootId,omitempty"`
    Confidence *ConfidenceScore `json:"confidence,omitempty"`
    Confidencebasis *string `json:"confidenceBasis,omitempty"`
    Qualityscore *ConfidenceScore `json:"qualityScore,omitempty"`
    Completenessscore *ConfidenceScore `json:"completenessScore,omitempty"`
    Verificationstatus *string `json:"verificationStatus,omitempty"`
    Verifiedat *UnixTime `json:"verifiedAt,omitempty"`
    Verifiedby *string `json:"verifiedBy,omitempty"`
    Provenance *map[string]any `json:"provenance,omitempty"`
    Chainofcustody *[]map[string]any `json:"chainOfCustody,omitempty"`
    Transformhistory *[]map[string]any `json:"transformHistory,omitempty"`
    Labels *[]string `json:"labels,omitempty"`
    Tags *[]string `json:"tags,omitempty"`
    Topics *[]string `json:"topics,omitempty"`
    Language *string `json:"language,omitempty"`
    Jurisdiction *string `json:"jurisdiction,omitempty"`
    Countrycode *string `json:"countryCode,omitempty"`
    Regioncode *string `json:"regionCode,omitempty"`
    Timezone *string `json:"timezone,omitempty"`
    Sensitivity *Sensitivity `json:"sensitivity,omitempty"`
    Visibility *Visibility `json:"visibility,omitempty"`
    Owner *string `json:"owner,omitempty"`
    Accesscontrol *map[string]any `json:"accessControl,omitempty"`
    Legalbasis *string `json:"legalBasis,omitempty"`
    Retentionpolicy *string `json:"retentionPolicy,omitempty"`
    Contenttype *string `json:"contentType,omitempty"`
    Encoding *string `json:"encoding,omitempty"`
    Sizebytes *int64 `json:"sizeBytes,omitempty"`
    Contenthash *string `json:"contentHash,omitempty"`
    Hashalgorithm *HashAlgorithm `json:"hashAlgorithm,omitempty"`
    Normalizedhash *string `json:"normalizedHash,omitempty"`
    Raw *map[string]any `json:"raw,omitempty"`
    Rawcontent *string `json:"rawContent,omitempty"`
    Notes *string `json:"notes,omitempty"`
    Deleted *bool `json:"deleted,omitempty"`
    Tombstonereason *string `json:"tombstoneReason,omitempty"`
    Extensions *map[string]any `json:"extensions,omitempty"`
    Fname *string `json:"fname,omitempty"`
    Mname *string `json:"mname,omitempty"`
    Lname *string `json:"lname,omitempty"`
    Fullname *string `json:"fullName,omitempty"`
    Displayname *string `json:"displayName,omitempty"`
    Prefix *string `json:"prefix,omitempty"`
    Suffix *string `json:"suffix,omitempty"`
    Pronouns *string `json:"pronouns,omitempty"`
    Bio *string `json:"bio,omitempty"`
    Dob *string `json:"dob,omitempty"`
    Dateofdeath *string `json:"dateOfDeath,omitempty"`
    Age *int64 `json:"age,omitempty"`
    Gender *string `json:"gender,omitempty"`
    Nationality *[]string `json:"nationality,omitempty"`
    Citizenship *[]string `json:"citizenship,omitempty"`
    Occupation *[]string `json:"occupation,omitempty"`
    Employer *[]StarReference `json:"employer,omitempty"`
    Education *[]map[string]any `json:"education,omitempty"`
    Skills *[]string `json:"skills,omitempty"`
    Interests *[]string `json:"interests,omitempty"`
    Region *string `json:"region,omitempty"`
    Addresses *[]StarReference `json:"addresses,omitempty"`
    Emails *[]StarReference `json:"emails,omitempty"`
    Phones *[]StarReference `json:"phones,omitempty"`
    Accounts *[]StarReference `json:"accounts,omitempty"`
    Images *[]StarReference `json:"images,omitempty"`
    Identifiers *[]StarReference `json:"identifiers,omitempty"`
    Misc *[]map[string]any `json:"misc,omitempty"`
    Etype *string `json:"etype,omitempty"`
    Eid *string `json:"eid,omitempty"`
}

type Relation struct {
    Id DocumentId `json:"id"`
    Rev *string `json:"rev,omitempty"`
    Dataset string `json:"dataset"`
    Dtype string `json:"dtype"`
    Schemaversion string `json:"schemaVersion"`
    Externalids *map[string]any `json:"externalIds,omitempty"`
    Aliases *[]string `json:"aliases,omitempty"`
    Sources *[]StarReference `json:"sources,omitempty"`
    Sourceurls *[]Uri `json:"sourceUrls,omitempty"`
    Sourcerecordids *[]string `json:"sourceRecordIds,omitempty"`
    Sourcekinds *[]SourceKind `json:"sourceKinds,omitempty"`
    Sourcelicense *string `json:"sourceLicense,omitempty"`
    Sourceterms *Uri `json:"sourceTerms,omitempty"`
    Sourceretrievedat *UnixTime `json:"sourceRetrievedAt,omitempty"`
    Collectedat *UnixTime `json:"collectedAt,omitempty"`
    Observedat *UnixTime `json:"observedAt,omitempty"`
    Firstseenat *UnixTime `json:"firstSeenAt,omitempty"`
    Lastseenat *UnixTime `json:"lastSeenAt,omitempty"`
    Createdat *UnixTime `json:"createdAt,omitempty"`
    Updatedat *UnixTime `json:"updatedAt,omitempty"`
    Validfrom *UnixTime `json:"validFrom,omitempty"`
    Validuntil *UnixTime `json:"validUntil,omitempty"`
    Expiresat *UnixTime `json:"expiresAt,omitempty"`
    Collector *string `json:"collector,omitempty"`
    Collectorversion *string `json:"collectorVersion,omitempty"`
    Collectionmethod *string `json:"collectionMethod,omitempty"`
    Collectionstatus *CollectionStatus `json:"collectionStatus,omitempty"`
    Runid *string `json:"runId,omitempty"`
    Correlationid *string `json:"correlationId,omitempty"`
    Causationid *string `json:"causationId,omitempty"`
    Parentid *DocumentId `json:"parentId,omitempty"`
    Rootid *DocumentId `json:"rootId,omitempty"`
    Confidence *ConfidenceScore `json:"confidence,omitempty"`
    Confidencebasis *string `json:"confidenceBasis,omitempty"`
    Qualityscore *ConfidenceScore `json:"qualityScore,omitempty"`
    Completenessscore *ConfidenceScore `json:"completenessScore,omitempty"`
    Verificationstatus *string `json:"verificationStatus,omitempty"`
    Verifiedat *UnixTime `json:"verifiedAt,omitempty"`
    Verifiedby *string `json:"verifiedBy,omitempty"`
    Provenance *map[string]any `json:"provenance,omitempty"`
    Chainofcustody *[]map[string]any `json:"chainOfCustody,omitempty"`
    Transformhistory *[]map[string]any `json:"transformHistory,omitempty"`
    Labels *[]string `json:"labels,omitempty"`
    Tags *[]string `json:"tags,omitempty"`
    Topics *[]string `json:"topics,omitempty"`
    Language *string `json:"language,omitempty"`
    Jurisdiction *string `json:"jurisdiction,omitempty"`
    Countrycode *string `json:"countryCode,omitempty"`
    Regioncode *string `json:"regionCode,omitempty"`
    Timezone *string `json:"timezone,omitempty"`
    Sensitivity *Sensitivity `json:"sensitivity,omitempty"`
    Visibility *Visibility `json:"visibility,omitempty"`
    Owner *string `json:"owner,omitempty"`
    Accesscontrol *map[string]any `json:"accessControl,omitempty"`
    Legalbasis *string `json:"legalBasis,omitempty"`
    Retentionpolicy *string `json:"retentionPolicy,omitempty"`
    Contenttype *string `json:"contentType,omitempty"`
    Encoding *string `json:"encoding,omitempty"`
    Sizebytes *int64 `json:"sizeBytes,omitempty"`
    Contenthash *string `json:"contentHash,omitempty"`
    Hashalgorithm *HashAlgorithm `json:"hashAlgorithm,omitempty"`
    Normalizedhash *string `json:"normalizedHash,omitempty"`
    Raw *map[string]any `json:"raw,omitempty"`
    Rawcontent *string `json:"rawContent,omitempty"`
    Notes *string `json:"notes,omitempty"`
    Deleted *bool `json:"deleted,omitempty"`
    Tombstonereason *string `json:"tombstoneReason,omitempty"`
    Extensions *map[string]any `json:"extensions,omitempty"`
    Source StarReference `json:"source"`
    Destination StarReference `json:"destination"`
    Predicate string `json:"predicate"`
    Direction *RelationDirection `json:"direction,omitempty"`
    Inversepredicate *string `json:"inversePredicate,omitempty"`
    Note *string `json:"note,omitempty"`
    Evidence *[]StarReference `json:"evidence,omitempty"`
    Weight *string `json:"weight,omitempty"`
    Validat *UnixTime `json:"validAt,omitempty"`
    Endedat *UnixTime `json:"endedAt,omitempty"`
}

type PixelOffset int64

type PixelLength int64

type AnnotationBasis string

type CandidateOnly string

const (
    CandidateOnlyCandidate CandidateOnly = "candidate"
)

type FaceObservation struct {
    Id DocumentId `json:"id"`
    Rev *string `json:"rev,omitempty"`
    Dataset string `json:"dataset"`
    Dtype string `json:"dtype"`
    Schemaversion string `json:"schemaVersion"`
    Externalids *map[string]any `json:"externalIds,omitempty"`
    Aliases *[]string `json:"aliases,omitempty"`
    Sources *[]StarReference `json:"sources,omitempty"`
    Sourceurls *[]Uri `json:"sourceUrls,omitempty"`
    Sourcerecordids *[]string `json:"sourceRecordIds,omitempty"`
    Sourcekinds *[]SourceKind `json:"sourceKinds,omitempty"`
    Sourcelicense *string `json:"sourceLicense,omitempty"`
    Sourceterms *Uri `json:"sourceTerms,omitempty"`
    Sourceretrievedat *UnixTime `json:"sourceRetrievedAt,omitempty"`
    Collectedat *UnixTime `json:"collectedAt,omitempty"`
    Observedat *UnixTime `json:"observedAt,omitempty"`
    Firstseenat *UnixTime `json:"firstSeenAt,omitempty"`
    Lastseenat *UnixTime `json:"lastSeenAt,omitempty"`
    Createdat *UnixTime `json:"createdAt,omitempty"`
    Updatedat *UnixTime `json:"updatedAt,omitempty"`
    Validfrom *UnixTime `json:"validFrom,omitempty"`
    Validuntil *UnixTime `json:"validUntil,omitempty"`
    Expiresat *UnixTime `json:"expiresAt,omitempty"`
    Collector *string `json:"collector,omitempty"`
    Collectorversion *string `json:"collectorVersion,omitempty"`
    Collectionmethod *string `json:"collectionMethod,omitempty"`
    Collectionstatus *CollectionStatus `json:"collectionStatus,omitempty"`
    Runid *string `json:"runId,omitempty"`
    Correlationid *string `json:"correlationId,omitempty"`
    Causationid *string `json:"causationId,omitempty"`
    Parentid *DocumentId `json:"parentId,omitempty"`
    Rootid *DocumentId `json:"rootId,omitempty"`
    Confidence *ConfidenceScore `json:"confidence,omitempty"`
    Confidencebasis *string `json:"confidenceBasis,omitempty"`
    Qualityscore *ConfidenceScore `json:"qualityScore,omitempty"`
    Completenessscore *ConfidenceScore `json:"completenessScore,omitempty"`
    Verificationstatus *string `json:"verificationStatus,omitempty"`
    Verifiedat *UnixTime `json:"verifiedAt,omitempty"`
    Verifiedby *string `json:"verifiedBy,omitempty"`
    Provenance *map[string]any `json:"provenance,omitempty"`
    Chainofcustody *[]map[string]any `json:"chainOfCustody,omitempty"`
    Transformhistory *[]map[string]any `json:"transformHistory,omitempty"`
    Labels *[]string `json:"labels,omitempty"`
    Tags *[]string `json:"tags,omitempty"`
    Topics *[]string `json:"topics,omitempty"`
    Language *string `json:"language,omitempty"`
    Jurisdiction *string `json:"jurisdiction,omitempty"`
    Countrycode *string `json:"countryCode,omitempty"`
    Regioncode *string `json:"regionCode,omitempty"`
    Timezone *string `json:"timezone,omitempty"`
    Sensitivity *Sensitivity `json:"sensitivity,omitempty"`
    Visibility *Visibility `json:"visibility,omitempty"`
    Owner *string `json:"owner,omitempty"`
    Accesscontrol *map[string]any `json:"accessControl,omitempty"`
    Legalbasis *string `json:"legalBasis,omitempty"`
    Retentionpolicy *string `json:"retentionPolicy,omitempty"`
    Contenttype *string `json:"contentType,omitempty"`
    Encoding *string `json:"encoding,omitempty"`
    Sizebytes *int64 `json:"sizeBytes,omitempty"`
    Contenthash *string `json:"contentHash,omitempty"`
    Hashalgorithm *HashAlgorithm `json:"hashAlgorithm,omitempty"`
    Normalizedhash *string `json:"normalizedHash,omitempty"`
    Raw *map[string]any `json:"raw,omitempty"`
    Rawcontent *string `json:"rawContent,omitempty"`
    Notes *string `json:"notes,omitempty"`
    Deleted *bool `json:"deleted,omitempty"`
    Tombstonereason *string `json:"tombstoneReason,omitempty"`
    Extensions *map[string]any `json:"extensions,omitempty"`
    Picture StarReference `json:"picture"`
    X PixelOffset `json:"x"`
    Y PixelOffset `json:"y"`
    Width PixelLength `json:"width"`
    Height PixelLength `json:"height"`
    Annotationbasis AnnotationBasis `json:"annotationBasis"`
}

type CandidatePerson struct {
    Id DocumentId `json:"id"`
    Rev *string `json:"rev,omitempty"`
    Dataset string `json:"dataset"`
    Dtype string `json:"dtype"`
    Schemaversion string `json:"schemaVersion"`
    Externalids *map[string]any `json:"externalIds,omitempty"`
    Aliases *[]string `json:"aliases,omitempty"`
    Sources *[]StarReference `json:"sources,omitempty"`
    Sourceurls *[]Uri `json:"sourceUrls,omitempty"`
    Sourcerecordids *[]string `json:"sourceRecordIds,omitempty"`
    Sourcekinds *[]SourceKind `json:"sourceKinds,omitempty"`
    Sourcelicense *string `json:"sourceLicense,omitempty"`
    Sourceterms *Uri `json:"sourceTerms,omitempty"`
    Sourceretrievedat *UnixTime `json:"sourceRetrievedAt,omitempty"`
    Collectedat *UnixTime `json:"collectedAt,omitempty"`
    Observedat *UnixTime `json:"observedAt,omitempty"`
    Firstseenat *UnixTime `json:"firstSeenAt,omitempty"`
    Lastseenat *UnixTime `json:"lastSeenAt,omitempty"`
    Createdat *UnixTime `json:"createdAt,omitempty"`
    Updatedat *UnixTime `json:"updatedAt,omitempty"`
    Validfrom *UnixTime `json:"validFrom,omitempty"`
    Validuntil *UnixTime `json:"validUntil,omitempty"`
    Expiresat *UnixTime `json:"expiresAt,omitempty"`
    Collector *string `json:"collector,omitempty"`
    Collectorversion *string `json:"collectorVersion,omitempty"`
    Collectionmethod *string `json:"collectionMethod,omitempty"`
    Collectionstatus *CollectionStatus `json:"collectionStatus,omitempty"`
    Runid *string `json:"runId,omitempty"`
    Correlationid *string `json:"correlationId,omitempty"`
    Causationid *string `json:"causationId,omitempty"`
    Parentid *DocumentId `json:"parentId,omitempty"`
    Rootid *DocumentId `json:"rootId,omitempty"`
    Confidence *ConfidenceScore `json:"confidence,omitempty"`
    Confidencebasis *string `json:"confidenceBasis,omitempty"`
    Qualityscore *ConfidenceScore `json:"qualityScore,omitempty"`
    Completenessscore *ConfidenceScore `json:"completenessScore,omitempty"`
    Verificationstatus *string `json:"verificationStatus,omitempty"`
    Verifiedat *UnixTime `json:"verifiedAt,omitempty"`
    Verifiedby *string `json:"verifiedBy,omitempty"`
    Provenance *map[string]any `json:"provenance,omitempty"`
    Chainofcustody *[]map[string]any `json:"chainOfCustody,omitempty"`
    Transformhistory *[]map[string]any `json:"transformHistory,omitempty"`
    Labels *[]string `json:"labels,omitempty"`
    Tags *[]string `json:"tags,omitempty"`
    Topics *[]string `json:"topics,omitempty"`
    Language *string `json:"language,omitempty"`
    Jurisdiction *string `json:"jurisdiction,omitempty"`
    Countrycode *string `json:"countryCode,omitempty"`
    Regioncode *string `json:"regionCode,omitempty"`
    Timezone *string `json:"timezone,omitempty"`
    Sensitivity *Sensitivity `json:"sensitivity,omitempty"`
    Visibility *Visibility `json:"visibility,omitempty"`
    Owner *string `json:"owner,omitempty"`
    Accesscontrol *map[string]any `json:"accessControl,omitempty"`
    Legalbasis *string `json:"legalBasis,omitempty"`
    Retentionpolicy *string `json:"retentionPolicy,omitempty"`
    Contenttype *string `json:"contentType,omitempty"`
    Encoding *string `json:"encoding,omitempty"`
    Sizebytes *int64 `json:"sizeBytes,omitempty"`
    Contenthash *string `json:"contentHash,omitempty"`
    Hashalgorithm *HashAlgorithm `json:"hashAlgorithm,omitempty"`
    Normalizedhash *string `json:"normalizedHash,omitempty"`
    Raw *map[string]any `json:"raw,omitempty"`
    Rawcontent *string `json:"rawContent,omitempty"`
    Notes *string `json:"notes,omitempty"`
    Deleted *bool `json:"deleted,omitempty"`
    Tombstonereason *string `json:"tombstoneReason,omitempty"`
    Extensions *map[string]any `json:"extensions,omitempty"`
    Fname *string `json:"fname,omitempty"`
    Mname *string `json:"mname,omitempty"`
    Lname *string `json:"lname,omitempty"`
    Fullname *string `json:"fullName,omitempty"`
    Displayname *string `json:"displayName,omitempty"`
    Prefix *string `json:"prefix,omitempty"`
    Suffix *string `json:"suffix,omitempty"`
    Pronouns *string `json:"pronouns,omitempty"`
    Bio *string `json:"bio,omitempty"`
    Dob *string `json:"dob,omitempty"`
    Dateofdeath *string `json:"dateOfDeath,omitempty"`
    Age *int64 `json:"age,omitempty"`
    Gender *string `json:"gender,omitempty"`
    Nationality *[]string `json:"nationality,omitempty"`
    Citizenship *[]string `json:"citizenship,omitempty"`
    Occupation *[]string `json:"occupation,omitempty"`
    Employer *[]StarReference `json:"employer,omitempty"`
    Education *[]map[string]any `json:"education,omitempty"`
    Skills *[]string `json:"skills,omitempty"`
    Interests *[]string `json:"interests,omitempty"`
    Region *string `json:"region,omitempty"`
    Addresses *[]StarReference `json:"addresses,omitempty"`
    Emails *[]StarReference `json:"emails,omitempty"`
    Phones *[]StarReference `json:"phones,omitempty"`
    Accounts *[]StarReference `json:"accounts,omitempty"`
    Images *[]StarReference `json:"images,omitempty"`
    Identifiers *[]StarReference `json:"identifiers,omitempty"`
    Misc *[]map[string]any `json:"misc,omitempty"`
    Etype *string `json:"etype,omitempty"`
    Eid *string `json:"eid,omitempty"`
    Candidatestatus CandidateOnly `json:"candidateStatus"`
    Annotationbasis AnnotationBasis `json:"annotationBasis"`
    Evidencereferences *[]StarReference `json:"evidenceReferences,omitempty"`
}

type FacePersonCandidate struct {
    Id DocumentId `json:"id"`
    Rev *string `json:"rev,omitempty"`
    Dataset string `json:"dataset"`
    Dtype string `json:"dtype"`
    Schemaversion string `json:"schemaVersion"`
    Externalids *map[string]any `json:"externalIds,omitempty"`
    Aliases *[]string `json:"aliases,omitempty"`
    Sources *[]StarReference `json:"sources,omitempty"`
    Sourceurls *[]Uri `json:"sourceUrls,omitempty"`
    Sourcerecordids *[]string `json:"sourceRecordIds,omitempty"`
    Sourcekinds *[]SourceKind `json:"sourceKinds,omitempty"`
    Sourcelicense *string `json:"sourceLicense,omitempty"`
    Sourceterms *Uri `json:"sourceTerms,omitempty"`
    Sourceretrievedat *UnixTime `json:"sourceRetrievedAt,omitempty"`
    Collectedat *UnixTime `json:"collectedAt,omitempty"`
    Observedat *UnixTime `json:"observedAt,omitempty"`
    Firstseenat *UnixTime `json:"firstSeenAt,omitempty"`
    Lastseenat *UnixTime `json:"lastSeenAt,omitempty"`
    Createdat *UnixTime `json:"createdAt,omitempty"`
    Updatedat *UnixTime `json:"updatedAt,omitempty"`
    Validfrom *UnixTime `json:"validFrom,omitempty"`
    Validuntil *UnixTime `json:"validUntil,omitempty"`
    Expiresat *UnixTime `json:"expiresAt,omitempty"`
    Collector *string `json:"collector,omitempty"`
    Collectorversion *string `json:"collectorVersion,omitempty"`
    Collectionmethod *string `json:"collectionMethod,omitempty"`
    Collectionstatus *CollectionStatus `json:"collectionStatus,omitempty"`
    Runid *string `json:"runId,omitempty"`
    Correlationid *string `json:"correlationId,omitempty"`
    Causationid *string `json:"causationId,omitempty"`
    Parentid *DocumentId `json:"parentId,omitempty"`
    Rootid *DocumentId `json:"rootId,omitempty"`
    Confidence *ConfidenceScore `json:"confidence,omitempty"`
    Confidencebasis *string `json:"confidenceBasis,omitempty"`
    Qualityscore *ConfidenceScore `json:"qualityScore,omitempty"`
    Completenessscore *ConfidenceScore `json:"completenessScore,omitempty"`
    Verificationstatus *string `json:"verificationStatus,omitempty"`
    Verifiedat *UnixTime `json:"verifiedAt,omitempty"`
    Verifiedby *string `json:"verifiedBy,omitempty"`
    Provenance *map[string]any `json:"provenance,omitempty"`
    Chainofcustody *[]map[string]any `json:"chainOfCustody,omitempty"`
    Transformhistory *[]map[string]any `json:"transformHistory,omitempty"`
    Labels *[]string `json:"labels,omitempty"`
    Tags *[]string `json:"tags,omitempty"`
    Topics *[]string `json:"topics,omitempty"`
    Language *string `json:"language,omitempty"`
    Jurisdiction *string `json:"jurisdiction,omitempty"`
    Countrycode *string `json:"countryCode,omitempty"`
    Regioncode *string `json:"regionCode,omitempty"`
    Timezone *string `json:"timezone,omitempty"`
    Sensitivity *Sensitivity `json:"sensitivity,omitempty"`
    Visibility *Visibility `json:"visibility,omitempty"`
    Owner *string `json:"owner,omitempty"`
    Accesscontrol *map[string]any `json:"accessControl,omitempty"`
    Legalbasis *string `json:"legalBasis,omitempty"`
    Retentionpolicy *string `json:"retentionPolicy,omitempty"`
    Contenttype *string `json:"contentType,omitempty"`
    Encoding *string `json:"encoding,omitempty"`
    Sizebytes *int64 `json:"sizeBytes,omitempty"`
    Contenthash *string `json:"contentHash,omitempty"`
    Hashalgorithm *HashAlgorithm `json:"hashAlgorithm,omitempty"`
    Normalizedhash *string `json:"normalizedHash,omitempty"`
    Raw *map[string]any `json:"raw,omitempty"`
    Rawcontent *string `json:"rawContent,omitempty"`
    Notes *string `json:"notes,omitempty"`
    Deleted *bool `json:"deleted,omitempty"`
    Tombstonereason *string `json:"tombstoneReason,omitempty"`
    Extensions *map[string]any `json:"extensions,omitempty"`
    Source StarReference `json:"source"`
    Destination StarReference `json:"destination"`
    Predicate string `json:"predicate"`
    Direction *RelationDirection `json:"direction,omitempty"`
    Inversepredicate *string `json:"inversePredicate,omitempty"`
    Note *string `json:"note,omitempty"`
    Evidence *[]StarReference `json:"evidence,omitempty"`
    Weight *string `json:"weight,omitempty"`
    Validat *UnixTime `json:"validAt,omitempty"`
    Endedat *UnixTime `json:"endedAt,omitempty"`
    Candidatestatus CandidateOnly `json:"candidateStatus"`
    Annotationbasis AnnotationBasis `json:"annotationBasis"`
    Evidencereferences *[]StarReference `json:"evidenceReferences,omitempty"`
}

type StoreFaceObservation struct {
    Document StarReference `json:"document"`
}

type StoreCandidatePerson struct {
    Document StarReference `json:"document"`
}

type AnnotateFacePerson struct {
    Face StarReference `json:"face"`
    Person StarReference `json:"person"`
    Annotationbasis AnnotationBasis `json:"annotationBasis"`
}

type GetFaceObservation struct {
    Face StarReference `json:"face"`
}
