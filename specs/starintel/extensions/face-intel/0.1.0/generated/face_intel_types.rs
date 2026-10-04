// Generated from StarLang portable manifest. DO NOT EDIT.
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct StarReference { pub schema: String, pub id: String }

pub type DocumentId = String;

pub type UnixTime = i64;

pub type ConfidenceScore = String;

pub type Uri = String;

#[derive(Clone, Debug, Serialize, Deserialize)]
pub enum Sensitivity {
    #[serde(rename = "public")] Public,
    #[serde(rename = "internal")] Internal,
    #[serde(rename = "confidential")] Confidential,
    #[serde(rename = "restricted")] Restricted,
    #[serde(rename = "secret")] Secret,
    #[serde(rename = "unknown")] Unknown,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub enum Visibility {
    #[serde(rename = "public")] Public,
    #[serde(rename = "private")] Private,
    #[serde(rename = "shared")] Shared,
    #[serde(rename = "inherited")] Inherited,
    #[serde(rename = "unknown")] Unknown,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub enum CollectionStatus {
    #[serde(rename = "raw")] Raw,
    #[serde(rename = "normalized")] Normalized,
    #[serde(rename = "enriched")] Enriched,
    #[serde(rename = "verified")] Verified,
    #[serde(rename = "disputed")] Disputed,
    #[serde(rename = "stale")] Stale,
    #[serde(rename = "deleted")] Deleted,
    #[serde(rename = "unknown")] Unknown,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub enum SourceKind {
    #[serde(rename = "api")] Api,
    #[serde(rename = "web")] Web,
    #[serde(rename = "file")] File,
    #[serde(rename = "database")] Database,
    #[serde(rename = "message")] Message,
    #[serde(rename = "human")] Human,
    #[serde(rename = "sensor")] Sensor,
    #[serde(rename = "inference")] Inference,
    #[serde(rename = "import")] Import,
    #[serde(rename = "export")] Export,
    #[serde(rename = "unknown")] Unknown,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub enum HashAlgorithm {
    #[serde(rename = "sha256")] Sha256,
    #[serde(rename = "sha512")] Sha512,
    #[serde(rename = "blake2b")] Blake2b,
    #[serde(rename = "blake3")] Blake3,
    #[serde(rename = "md5")] Md5,
    #[serde(rename = "unknown")] Unknown,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub enum RelationDirection {
    #[serde(rename = "directed")] Directed,
    #[serde(rename = "symmetric")] Symmetric,
    #[serde(rename = "inverse")] Inverse,
    #[serde(rename = "unknown")] Unknown,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Document {
    #[serde(rename = "id")]
    pub id: DocumentId,
    #[serde(rename = "rev", skip_serializing_if = "Option::is_none")]
    pub rev: Option<String>,
    #[serde(rename = "dataset")]
    pub dataset: String,
    #[serde(rename = "dtype")]
    pub dtype: String,
    #[serde(rename = "schemaVersion")]
    pub schemaversion: String,
    #[serde(rename = "externalIds", skip_serializing_if = "Option::is_none")]
    pub externalids: Option<BTreeMap<String, serde_json::Value>>,
    #[serde(rename = "aliases", skip_serializing_if = "Option::is_none")]
    pub aliases: Option<Vec<String>>,
    #[serde(rename = "sources", skip_serializing_if = "Option::is_none")]
    pub sources: Option<Vec<StarReference>>,
    #[serde(rename = "sourceUrls", skip_serializing_if = "Option::is_none")]
    pub sourceurls: Option<Vec<Uri>>,
    #[serde(rename = "sourceRecordIds", skip_serializing_if = "Option::is_none")]
    pub sourcerecordids: Option<Vec<String>>,
    #[serde(rename = "sourceKinds", skip_serializing_if = "Option::is_none")]
    pub sourcekinds: Option<Vec<SourceKind>>,
    #[serde(rename = "sourceLicense", skip_serializing_if = "Option::is_none")]
    pub sourcelicense: Option<String>,
    #[serde(rename = "sourceTerms", skip_serializing_if = "Option::is_none")]
    pub sourceterms: Option<Uri>,
    #[serde(rename = "sourceRetrievedAt", skip_serializing_if = "Option::is_none")]
    pub sourceretrievedat: Option<UnixTime>,
    #[serde(rename = "collectedAt", skip_serializing_if = "Option::is_none")]
    pub collectedat: Option<UnixTime>,
    #[serde(rename = "observedAt", skip_serializing_if = "Option::is_none")]
    pub observedat: Option<UnixTime>,
    #[serde(rename = "firstSeenAt", skip_serializing_if = "Option::is_none")]
    pub firstseenat: Option<UnixTime>,
    #[serde(rename = "lastSeenAt", skip_serializing_if = "Option::is_none")]
    pub lastseenat: Option<UnixTime>,
    #[serde(rename = "createdAt", skip_serializing_if = "Option::is_none")]
    pub createdat: Option<UnixTime>,
    #[serde(rename = "updatedAt", skip_serializing_if = "Option::is_none")]
    pub updatedat: Option<UnixTime>,
    #[serde(rename = "validFrom", skip_serializing_if = "Option::is_none")]
    pub validfrom: Option<UnixTime>,
    #[serde(rename = "validUntil", skip_serializing_if = "Option::is_none")]
    pub validuntil: Option<UnixTime>,
    #[serde(rename = "expiresAt", skip_serializing_if = "Option::is_none")]
    pub expiresat: Option<UnixTime>,
    #[serde(rename = "collector", skip_serializing_if = "Option::is_none")]
    pub collector: Option<String>,
    #[serde(rename = "collectorVersion", skip_serializing_if = "Option::is_none")]
    pub collectorversion: Option<String>,
    #[serde(rename = "collectionMethod", skip_serializing_if = "Option::is_none")]
    pub collectionmethod: Option<String>,
    #[serde(rename = "collectionStatus", skip_serializing_if = "Option::is_none")]
    pub collectionstatus: Option<CollectionStatus>,
    #[serde(rename = "runId", skip_serializing_if = "Option::is_none")]
    pub runid: Option<String>,
    #[serde(rename = "correlationId", skip_serializing_if = "Option::is_none")]
    pub correlationid: Option<String>,
    #[serde(rename = "causationId", skip_serializing_if = "Option::is_none")]
    pub causationid: Option<String>,
    #[serde(rename = "parentId", skip_serializing_if = "Option::is_none")]
    pub parentid: Option<DocumentId>,
    #[serde(rename = "rootId", skip_serializing_if = "Option::is_none")]
    pub rootid: Option<DocumentId>,
    #[serde(rename = "confidence", skip_serializing_if = "Option::is_none")]
    pub confidence: Option<ConfidenceScore>,
    #[serde(rename = "confidenceBasis", skip_serializing_if = "Option::is_none")]
    pub confidencebasis: Option<String>,
    #[serde(rename = "qualityScore", skip_serializing_if = "Option::is_none")]
    pub qualityscore: Option<ConfidenceScore>,
    #[serde(rename = "completenessScore", skip_serializing_if = "Option::is_none")]
    pub completenessscore: Option<ConfidenceScore>,
    #[serde(rename = "verificationStatus", skip_serializing_if = "Option::is_none")]
    pub verificationstatus: Option<String>,
    #[serde(rename = "verifiedAt", skip_serializing_if = "Option::is_none")]
    pub verifiedat: Option<UnixTime>,
    #[serde(rename = "verifiedBy", skip_serializing_if = "Option::is_none")]
    pub verifiedby: Option<String>,
    #[serde(rename = "provenance", skip_serializing_if = "Option::is_none")]
    pub provenance: Option<BTreeMap<String, serde_json::Value>>,
    #[serde(rename = "chainOfCustody", skip_serializing_if = "Option::is_none")]
    pub chainofcustody: Option<Vec<BTreeMap<String, serde_json::Value>>>,
    #[serde(rename = "transformHistory", skip_serializing_if = "Option::is_none")]
    pub transformhistory: Option<Vec<BTreeMap<String, serde_json::Value>>>,
    #[serde(rename = "labels", skip_serializing_if = "Option::is_none")]
    pub labels: Option<Vec<String>>,
    #[serde(rename = "tags", skip_serializing_if = "Option::is_none")]
    pub tags: Option<Vec<String>>,
    #[serde(rename = "topics", skip_serializing_if = "Option::is_none")]
    pub topics: Option<Vec<String>>,
    #[serde(rename = "language", skip_serializing_if = "Option::is_none")]
    pub language: Option<String>,
    #[serde(rename = "jurisdiction", skip_serializing_if = "Option::is_none")]
    pub jurisdiction: Option<String>,
    #[serde(rename = "countryCode", skip_serializing_if = "Option::is_none")]
    pub countrycode: Option<String>,
    #[serde(rename = "regionCode", skip_serializing_if = "Option::is_none")]
    pub regioncode: Option<String>,
    #[serde(rename = "timezone", skip_serializing_if = "Option::is_none")]
    pub timezone: Option<String>,
    #[serde(rename = "sensitivity", skip_serializing_if = "Option::is_none")]
    pub sensitivity: Option<Sensitivity>,
    #[serde(rename = "visibility", skip_serializing_if = "Option::is_none")]
    pub visibility: Option<Visibility>,
    #[serde(rename = "owner", skip_serializing_if = "Option::is_none")]
    pub owner: Option<String>,
    #[serde(rename = "accessControl", skip_serializing_if = "Option::is_none")]
    pub accesscontrol: Option<BTreeMap<String, serde_json::Value>>,
    #[serde(rename = "legalBasis", skip_serializing_if = "Option::is_none")]
    pub legalbasis: Option<String>,
    #[serde(rename = "retentionPolicy", skip_serializing_if = "Option::is_none")]
    pub retentionpolicy: Option<String>,
    #[serde(rename = "contentType", skip_serializing_if = "Option::is_none")]
    pub contenttype: Option<String>,
    #[serde(rename = "encoding", skip_serializing_if = "Option::is_none")]
    pub encoding: Option<String>,
    #[serde(rename = "sizeBytes", skip_serializing_if = "Option::is_none")]
    pub sizebytes: Option<i64>,
    #[serde(rename = "contentHash", skip_serializing_if = "Option::is_none")]
    pub contenthash: Option<String>,
    #[serde(rename = "hashAlgorithm", skip_serializing_if = "Option::is_none")]
    pub hashalgorithm: Option<HashAlgorithm>,
    #[serde(rename = "normalizedHash", skip_serializing_if = "Option::is_none")]
    pub normalizedhash: Option<String>,
    #[serde(rename = "raw", skip_serializing_if = "Option::is_none")]
    pub raw: Option<BTreeMap<String, serde_json::Value>>,
    #[serde(rename = "rawContent", skip_serializing_if = "Option::is_none")]
    pub rawcontent: Option<String>,
    #[serde(rename = "notes", skip_serializing_if = "Option::is_none")]
    pub notes: Option<String>,
    #[serde(rename = "deleted", skip_serializing_if = "Option::is_none")]
    pub deleted: Option<bool>,
    #[serde(rename = "tombstoneReason", skip_serializing_if = "Option::is_none")]
    pub tombstonereason: Option<String>,
    #[serde(rename = "extensions", skip_serializing_if = "Option::is_none")]
    pub extensions: Option<BTreeMap<String, serde_json::Value>>,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Person {
    #[serde(rename = "id")]
    pub id: DocumentId,
    #[serde(rename = "rev", skip_serializing_if = "Option::is_none")]
    pub rev: Option<String>,
    #[serde(rename = "dataset")]
    pub dataset: String,
    #[serde(rename = "dtype")]
    pub dtype: String,
    #[serde(rename = "schemaVersion")]
    pub schemaversion: String,
    #[serde(rename = "externalIds", skip_serializing_if = "Option::is_none")]
    pub externalids: Option<BTreeMap<String, serde_json::Value>>,
    #[serde(rename = "aliases", skip_serializing_if = "Option::is_none")]
    pub aliases: Option<Vec<String>>,
    #[serde(rename = "sources", skip_serializing_if = "Option::is_none")]
    pub sources: Option<Vec<StarReference>>,
    #[serde(rename = "sourceUrls", skip_serializing_if = "Option::is_none")]
    pub sourceurls: Option<Vec<Uri>>,
    #[serde(rename = "sourceRecordIds", skip_serializing_if = "Option::is_none")]
    pub sourcerecordids: Option<Vec<String>>,
    #[serde(rename = "sourceKinds", skip_serializing_if = "Option::is_none")]
    pub sourcekinds: Option<Vec<SourceKind>>,
    #[serde(rename = "sourceLicense", skip_serializing_if = "Option::is_none")]
    pub sourcelicense: Option<String>,
    #[serde(rename = "sourceTerms", skip_serializing_if = "Option::is_none")]
    pub sourceterms: Option<Uri>,
    #[serde(rename = "sourceRetrievedAt", skip_serializing_if = "Option::is_none")]
    pub sourceretrievedat: Option<UnixTime>,
    #[serde(rename = "collectedAt", skip_serializing_if = "Option::is_none")]
    pub collectedat: Option<UnixTime>,
    #[serde(rename = "observedAt", skip_serializing_if = "Option::is_none")]
    pub observedat: Option<UnixTime>,
    #[serde(rename = "firstSeenAt", skip_serializing_if = "Option::is_none")]
    pub firstseenat: Option<UnixTime>,
    #[serde(rename = "lastSeenAt", skip_serializing_if = "Option::is_none")]
    pub lastseenat: Option<UnixTime>,
    #[serde(rename = "createdAt", skip_serializing_if = "Option::is_none")]
    pub createdat: Option<UnixTime>,
    #[serde(rename = "updatedAt", skip_serializing_if = "Option::is_none")]
    pub updatedat: Option<UnixTime>,
    #[serde(rename = "validFrom", skip_serializing_if = "Option::is_none")]
    pub validfrom: Option<UnixTime>,
    #[serde(rename = "validUntil", skip_serializing_if = "Option::is_none")]
    pub validuntil: Option<UnixTime>,
    #[serde(rename = "expiresAt", skip_serializing_if = "Option::is_none")]
    pub expiresat: Option<UnixTime>,
    #[serde(rename = "collector", skip_serializing_if = "Option::is_none")]
    pub collector: Option<String>,
    #[serde(rename = "collectorVersion", skip_serializing_if = "Option::is_none")]
    pub collectorversion: Option<String>,
    #[serde(rename = "collectionMethod", skip_serializing_if = "Option::is_none")]
    pub collectionmethod: Option<String>,
    #[serde(rename = "collectionStatus", skip_serializing_if = "Option::is_none")]
    pub collectionstatus: Option<CollectionStatus>,
    #[serde(rename = "runId", skip_serializing_if = "Option::is_none")]
    pub runid: Option<String>,
    #[serde(rename = "correlationId", skip_serializing_if = "Option::is_none")]
    pub correlationid: Option<String>,
    #[serde(rename = "causationId", skip_serializing_if = "Option::is_none")]
    pub causationid: Option<String>,
    #[serde(rename = "parentId", skip_serializing_if = "Option::is_none")]
    pub parentid: Option<DocumentId>,
    #[serde(rename = "rootId", skip_serializing_if = "Option::is_none")]
    pub rootid: Option<DocumentId>,
    #[serde(rename = "confidence", skip_serializing_if = "Option::is_none")]
    pub confidence: Option<ConfidenceScore>,
    #[serde(rename = "confidenceBasis", skip_serializing_if = "Option::is_none")]
    pub confidencebasis: Option<String>,
    #[serde(rename = "qualityScore", skip_serializing_if = "Option::is_none")]
    pub qualityscore: Option<ConfidenceScore>,
    #[serde(rename = "completenessScore", skip_serializing_if = "Option::is_none")]
    pub completenessscore: Option<ConfidenceScore>,
    #[serde(rename = "verificationStatus", skip_serializing_if = "Option::is_none")]
    pub verificationstatus: Option<String>,
    #[serde(rename = "verifiedAt", skip_serializing_if = "Option::is_none")]
    pub verifiedat: Option<UnixTime>,
    #[serde(rename = "verifiedBy", skip_serializing_if = "Option::is_none")]
    pub verifiedby: Option<String>,
    #[serde(rename = "provenance", skip_serializing_if = "Option::is_none")]
    pub provenance: Option<BTreeMap<String, serde_json::Value>>,
    #[serde(rename = "chainOfCustody", skip_serializing_if = "Option::is_none")]
    pub chainofcustody: Option<Vec<BTreeMap<String, serde_json::Value>>>,
    #[serde(rename = "transformHistory", skip_serializing_if = "Option::is_none")]
    pub transformhistory: Option<Vec<BTreeMap<String, serde_json::Value>>>,
    #[serde(rename = "labels", skip_serializing_if = "Option::is_none")]
    pub labels: Option<Vec<String>>,
    #[serde(rename = "tags", skip_serializing_if = "Option::is_none")]
    pub tags: Option<Vec<String>>,
    #[serde(rename = "topics", skip_serializing_if = "Option::is_none")]
    pub topics: Option<Vec<String>>,
    #[serde(rename = "language", skip_serializing_if = "Option::is_none")]
    pub language: Option<String>,
    #[serde(rename = "jurisdiction", skip_serializing_if = "Option::is_none")]
    pub jurisdiction: Option<String>,
    #[serde(rename = "countryCode", skip_serializing_if = "Option::is_none")]
    pub countrycode: Option<String>,
    #[serde(rename = "regionCode", skip_serializing_if = "Option::is_none")]
    pub regioncode: Option<String>,
    #[serde(rename = "timezone", skip_serializing_if = "Option::is_none")]
    pub timezone: Option<String>,
    #[serde(rename = "sensitivity", skip_serializing_if = "Option::is_none")]
    pub sensitivity: Option<Sensitivity>,
    #[serde(rename = "visibility", skip_serializing_if = "Option::is_none")]
    pub visibility: Option<Visibility>,
    #[serde(rename = "owner", skip_serializing_if = "Option::is_none")]
    pub owner: Option<String>,
    #[serde(rename = "accessControl", skip_serializing_if = "Option::is_none")]
    pub accesscontrol: Option<BTreeMap<String, serde_json::Value>>,
    #[serde(rename = "legalBasis", skip_serializing_if = "Option::is_none")]
    pub legalbasis: Option<String>,
    #[serde(rename = "retentionPolicy", skip_serializing_if = "Option::is_none")]
    pub retentionpolicy: Option<String>,
    #[serde(rename = "contentType", skip_serializing_if = "Option::is_none")]
    pub contenttype: Option<String>,
    #[serde(rename = "encoding", skip_serializing_if = "Option::is_none")]
    pub encoding: Option<String>,
    #[serde(rename = "sizeBytes", skip_serializing_if = "Option::is_none")]
    pub sizebytes: Option<i64>,
    #[serde(rename = "contentHash", skip_serializing_if = "Option::is_none")]
    pub contenthash: Option<String>,
    #[serde(rename = "hashAlgorithm", skip_serializing_if = "Option::is_none")]
    pub hashalgorithm: Option<HashAlgorithm>,
    #[serde(rename = "normalizedHash", skip_serializing_if = "Option::is_none")]
    pub normalizedhash: Option<String>,
    #[serde(rename = "raw", skip_serializing_if = "Option::is_none")]
    pub raw: Option<BTreeMap<String, serde_json::Value>>,
    #[serde(rename = "rawContent", skip_serializing_if = "Option::is_none")]
    pub rawcontent: Option<String>,
    #[serde(rename = "notes", skip_serializing_if = "Option::is_none")]
    pub notes: Option<String>,
    #[serde(rename = "deleted", skip_serializing_if = "Option::is_none")]
    pub deleted: Option<bool>,
    #[serde(rename = "tombstoneReason", skip_serializing_if = "Option::is_none")]
    pub tombstonereason: Option<String>,
    #[serde(rename = "extensions", skip_serializing_if = "Option::is_none")]
    pub extensions: Option<BTreeMap<String, serde_json::Value>>,
    #[serde(rename = "fname", skip_serializing_if = "Option::is_none")]
    pub fname: Option<String>,
    #[serde(rename = "mname", skip_serializing_if = "Option::is_none")]
    pub mname: Option<String>,
    #[serde(rename = "lname", skip_serializing_if = "Option::is_none")]
    pub lname: Option<String>,
    #[serde(rename = "fullName", skip_serializing_if = "Option::is_none")]
    pub fullname: Option<String>,
    #[serde(rename = "displayName", skip_serializing_if = "Option::is_none")]
    pub displayname: Option<String>,
    #[serde(rename = "prefix", skip_serializing_if = "Option::is_none")]
    pub prefix: Option<String>,
    #[serde(rename = "suffix", skip_serializing_if = "Option::is_none")]
    pub suffix: Option<String>,
    #[serde(rename = "pronouns", skip_serializing_if = "Option::is_none")]
    pub pronouns: Option<String>,
    #[serde(rename = "bio", skip_serializing_if = "Option::is_none")]
    pub bio: Option<String>,
    #[serde(rename = "dob", skip_serializing_if = "Option::is_none")]
    pub dob: Option<String>,
    #[serde(rename = "dateOfDeath", skip_serializing_if = "Option::is_none")]
    pub dateofdeath: Option<String>,
    #[serde(rename = "age", skip_serializing_if = "Option::is_none")]
    pub age: Option<i64>,
    #[serde(rename = "gender", skip_serializing_if = "Option::is_none")]
    pub gender: Option<String>,
    #[serde(rename = "nationality", skip_serializing_if = "Option::is_none")]
    pub nationality: Option<Vec<String>>,
    #[serde(rename = "citizenship", skip_serializing_if = "Option::is_none")]
    pub citizenship: Option<Vec<String>>,
    #[serde(rename = "occupation", skip_serializing_if = "Option::is_none")]
    pub occupation: Option<Vec<String>>,
    #[serde(rename = "employer", skip_serializing_if = "Option::is_none")]
    pub employer: Option<Vec<StarReference>>,
    #[serde(rename = "education", skip_serializing_if = "Option::is_none")]
    pub education: Option<Vec<BTreeMap<String, serde_json::Value>>>,
    #[serde(rename = "skills", skip_serializing_if = "Option::is_none")]
    pub skills: Option<Vec<String>>,
    #[serde(rename = "interests", skip_serializing_if = "Option::is_none")]
    pub interests: Option<Vec<String>>,
    #[serde(rename = "region", skip_serializing_if = "Option::is_none")]
    pub region: Option<String>,
    #[serde(rename = "addresses", skip_serializing_if = "Option::is_none")]
    pub addresses: Option<Vec<StarReference>>,
    #[serde(rename = "emails", skip_serializing_if = "Option::is_none")]
    pub emails: Option<Vec<StarReference>>,
    #[serde(rename = "phones", skip_serializing_if = "Option::is_none")]
    pub phones: Option<Vec<StarReference>>,
    #[serde(rename = "accounts", skip_serializing_if = "Option::is_none")]
    pub accounts: Option<Vec<StarReference>>,
    #[serde(rename = "images", skip_serializing_if = "Option::is_none")]
    pub images: Option<Vec<StarReference>>,
    #[serde(rename = "identifiers", skip_serializing_if = "Option::is_none")]
    pub identifiers: Option<Vec<StarReference>>,
    #[serde(rename = "misc", skip_serializing_if = "Option::is_none")]
    pub misc: Option<Vec<BTreeMap<String, serde_json::Value>>>,
    #[serde(rename = "etype", skip_serializing_if = "Option::is_none")]
    pub etype: Option<String>,
    #[serde(rename = "eid", skip_serializing_if = "Option::is_none")]
    pub eid: Option<String>,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Relation {
    #[serde(rename = "id")]
    pub id: DocumentId,
    #[serde(rename = "rev", skip_serializing_if = "Option::is_none")]
    pub rev: Option<String>,
    #[serde(rename = "dataset")]
    pub dataset: String,
    #[serde(rename = "dtype")]
    pub dtype: String,
    #[serde(rename = "schemaVersion")]
    pub schemaversion: String,
    #[serde(rename = "externalIds", skip_serializing_if = "Option::is_none")]
    pub externalids: Option<BTreeMap<String, serde_json::Value>>,
    #[serde(rename = "aliases", skip_serializing_if = "Option::is_none")]
    pub aliases: Option<Vec<String>>,
    #[serde(rename = "sources", skip_serializing_if = "Option::is_none")]
    pub sources: Option<Vec<StarReference>>,
    #[serde(rename = "sourceUrls", skip_serializing_if = "Option::is_none")]
    pub sourceurls: Option<Vec<Uri>>,
    #[serde(rename = "sourceRecordIds", skip_serializing_if = "Option::is_none")]
    pub sourcerecordids: Option<Vec<String>>,
    #[serde(rename = "sourceKinds", skip_serializing_if = "Option::is_none")]
    pub sourcekinds: Option<Vec<SourceKind>>,
    #[serde(rename = "sourceLicense", skip_serializing_if = "Option::is_none")]
    pub sourcelicense: Option<String>,
    #[serde(rename = "sourceTerms", skip_serializing_if = "Option::is_none")]
    pub sourceterms: Option<Uri>,
    #[serde(rename = "sourceRetrievedAt", skip_serializing_if = "Option::is_none")]
    pub sourceretrievedat: Option<UnixTime>,
    #[serde(rename = "collectedAt", skip_serializing_if = "Option::is_none")]
    pub collectedat: Option<UnixTime>,
    #[serde(rename = "observedAt", skip_serializing_if = "Option::is_none")]
    pub observedat: Option<UnixTime>,
    #[serde(rename = "firstSeenAt", skip_serializing_if = "Option::is_none")]
    pub firstseenat: Option<UnixTime>,
    #[serde(rename = "lastSeenAt", skip_serializing_if = "Option::is_none")]
    pub lastseenat: Option<UnixTime>,
    #[serde(rename = "createdAt", skip_serializing_if = "Option::is_none")]
    pub createdat: Option<UnixTime>,
    #[serde(rename = "updatedAt", skip_serializing_if = "Option::is_none")]
    pub updatedat: Option<UnixTime>,
    #[serde(rename = "validFrom", skip_serializing_if = "Option::is_none")]
    pub validfrom: Option<UnixTime>,
    #[serde(rename = "validUntil", skip_serializing_if = "Option::is_none")]
    pub validuntil: Option<UnixTime>,
    #[serde(rename = "expiresAt", skip_serializing_if = "Option::is_none")]
    pub expiresat: Option<UnixTime>,
    #[serde(rename = "collector", skip_serializing_if = "Option::is_none")]
    pub collector: Option<String>,
    #[serde(rename = "collectorVersion", skip_serializing_if = "Option::is_none")]
    pub collectorversion: Option<String>,
    #[serde(rename = "collectionMethod", skip_serializing_if = "Option::is_none")]
    pub collectionmethod: Option<String>,
    #[serde(rename = "collectionStatus", skip_serializing_if = "Option::is_none")]
    pub collectionstatus: Option<CollectionStatus>,
    #[serde(rename = "runId", skip_serializing_if = "Option::is_none")]
    pub runid: Option<String>,
    #[serde(rename = "correlationId", skip_serializing_if = "Option::is_none")]
    pub correlationid: Option<String>,
    #[serde(rename = "causationId", skip_serializing_if = "Option::is_none")]
    pub causationid: Option<String>,
    #[serde(rename = "parentId", skip_serializing_if = "Option::is_none")]
    pub parentid: Option<DocumentId>,
    #[serde(rename = "rootId", skip_serializing_if = "Option::is_none")]
    pub rootid: Option<DocumentId>,
    #[serde(rename = "confidence", skip_serializing_if = "Option::is_none")]
    pub confidence: Option<ConfidenceScore>,
    #[serde(rename = "confidenceBasis", skip_serializing_if = "Option::is_none")]
    pub confidencebasis: Option<String>,
    #[serde(rename = "qualityScore", skip_serializing_if = "Option::is_none")]
    pub qualityscore: Option<ConfidenceScore>,
    #[serde(rename = "completenessScore", skip_serializing_if = "Option::is_none")]
    pub completenessscore: Option<ConfidenceScore>,
    #[serde(rename = "verificationStatus", skip_serializing_if = "Option::is_none")]
    pub verificationstatus: Option<String>,
    #[serde(rename = "verifiedAt", skip_serializing_if = "Option::is_none")]
    pub verifiedat: Option<UnixTime>,
    #[serde(rename = "verifiedBy", skip_serializing_if = "Option::is_none")]
    pub verifiedby: Option<String>,
    #[serde(rename = "provenance", skip_serializing_if = "Option::is_none")]
    pub provenance: Option<BTreeMap<String, serde_json::Value>>,
    #[serde(rename = "chainOfCustody", skip_serializing_if = "Option::is_none")]
    pub chainofcustody: Option<Vec<BTreeMap<String, serde_json::Value>>>,
    #[serde(rename = "transformHistory", skip_serializing_if = "Option::is_none")]
    pub transformhistory: Option<Vec<BTreeMap<String, serde_json::Value>>>,
    #[serde(rename = "labels", skip_serializing_if = "Option::is_none")]
    pub labels: Option<Vec<String>>,
    #[serde(rename = "tags", skip_serializing_if = "Option::is_none")]
    pub tags: Option<Vec<String>>,
    #[serde(rename = "topics", skip_serializing_if = "Option::is_none")]
    pub topics: Option<Vec<String>>,
    #[serde(rename = "language", skip_serializing_if = "Option::is_none")]
    pub language: Option<String>,
    #[serde(rename = "jurisdiction", skip_serializing_if = "Option::is_none")]
    pub jurisdiction: Option<String>,
    #[serde(rename = "countryCode", skip_serializing_if = "Option::is_none")]
    pub countrycode: Option<String>,
    #[serde(rename = "regionCode", skip_serializing_if = "Option::is_none")]
    pub regioncode: Option<String>,
    #[serde(rename = "timezone", skip_serializing_if = "Option::is_none")]
    pub timezone: Option<String>,
    #[serde(rename = "sensitivity", skip_serializing_if = "Option::is_none")]
    pub sensitivity: Option<Sensitivity>,
    #[serde(rename = "visibility", skip_serializing_if = "Option::is_none")]
    pub visibility: Option<Visibility>,
    #[serde(rename = "owner", skip_serializing_if = "Option::is_none")]
    pub owner: Option<String>,
    #[serde(rename = "accessControl", skip_serializing_if = "Option::is_none")]
    pub accesscontrol: Option<BTreeMap<String, serde_json::Value>>,
    #[serde(rename = "legalBasis", skip_serializing_if = "Option::is_none")]
    pub legalbasis: Option<String>,
    #[serde(rename = "retentionPolicy", skip_serializing_if = "Option::is_none")]
    pub retentionpolicy: Option<String>,
    #[serde(rename = "contentType", skip_serializing_if = "Option::is_none")]
    pub contenttype: Option<String>,
    #[serde(rename = "encoding", skip_serializing_if = "Option::is_none")]
    pub encoding: Option<String>,
    #[serde(rename = "sizeBytes", skip_serializing_if = "Option::is_none")]
    pub sizebytes: Option<i64>,
    #[serde(rename = "contentHash", skip_serializing_if = "Option::is_none")]
    pub contenthash: Option<String>,
    #[serde(rename = "hashAlgorithm", skip_serializing_if = "Option::is_none")]
    pub hashalgorithm: Option<HashAlgorithm>,
    #[serde(rename = "normalizedHash", skip_serializing_if = "Option::is_none")]
    pub normalizedhash: Option<String>,
    #[serde(rename = "raw", skip_serializing_if = "Option::is_none")]
    pub raw: Option<BTreeMap<String, serde_json::Value>>,
    #[serde(rename = "rawContent", skip_serializing_if = "Option::is_none")]
    pub rawcontent: Option<String>,
    #[serde(rename = "notes", skip_serializing_if = "Option::is_none")]
    pub notes: Option<String>,
    #[serde(rename = "deleted", skip_serializing_if = "Option::is_none")]
    pub deleted: Option<bool>,
    #[serde(rename = "tombstoneReason", skip_serializing_if = "Option::is_none")]
    pub tombstonereason: Option<String>,
    #[serde(rename = "extensions", skip_serializing_if = "Option::is_none")]
    pub extensions: Option<BTreeMap<String, serde_json::Value>>,
    #[serde(rename = "source")]
    pub source: StarReference,
    #[serde(rename = "destination")]
    pub destination: StarReference,
    #[serde(rename = "predicate")]
    pub predicate: String,
    #[serde(rename = "direction", skip_serializing_if = "Option::is_none")]
    pub direction: Option<RelationDirection>,
    #[serde(rename = "inversePredicate", skip_serializing_if = "Option::is_none")]
    pub inversepredicate: Option<String>,
    #[serde(rename = "note", skip_serializing_if = "Option::is_none")]
    pub note: Option<String>,
    #[serde(rename = "evidence", skip_serializing_if = "Option::is_none")]
    pub evidence: Option<Vec<StarReference>>,
    #[serde(rename = "weight", skip_serializing_if = "Option::is_none")]
    pub weight: Option<String>,
    #[serde(rename = "validAt", skip_serializing_if = "Option::is_none")]
    pub validat: Option<UnixTime>,
    #[serde(rename = "endedAt", skip_serializing_if = "Option::is_none")]
    pub endedat: Option<UnixTime>,
}

pub type PixelOffset = i64;

pub type PixelLength = i64;

pub type AnnotationBasis = String;

#[derive(Clone, Debug, Serialize, Deserialize)]
pub enum CandidateOnly {
    #[serde(rename = "candidate")] Candidate,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct FaceObservation {
    #[serde(rename = "id")]
    pub id: DocumentId,
    #[serde(rename = "rev", skip_serializing_if = "Option::is_none")]
    pub rev: Option<String>,
    #[serde(rename = "dataset")]
    pub dataset: String,
    #[serde(rename = "dtype")]
    pub dtype: String,
    #[serde(rename = "schemaVersion")]
    pub schemaversion: String,
    #[serde(rename = "externalIds", skip_serializing_if = "Option::is_none")]
    pub externalids: Option<BTreeMap<String, serde_json::Value>>,
    #[serde(rename = "aliases", skip_serializing_if = "Option::is_none")]
    pub aliases: Option<Vec<String>>,
    #[serde(rename = "sources", skip_serializing_if = "Option::is_none")]
    pub sources: Option<Vec<StarReference>>,
    #[serde(rename = "sourceUrls", skip_serializing_if = "Option::is_none")]
    pub sourceurls: Option<Vec<Uri>>,
    #[serde(rename = "sourceRecordIds", skip_serializing_if = "Option::is_none")]
    pub sourcerecordids: Option<Vec<String>>,
    #[serde(rename = "sourceKinds", skip_serializing_if = "Option::is_none")]
    pub sourcekinds: Option<Vec<SourceKind>>,
    #[serde(rename = "sourceLicense", skip_serializing_if = "Option::is_none")]
    pub sourcelicense: Option<String>,
    #[serde(rename = "sourceTerms", skip_serializing_if = "Option::is_none")]
    pub sourceterms: Option<Uri>,
    #[serde(rename = "sourceRetrievedAt", skip_serializing_if = "Option::is_none")]
    pub sourceretrievedat: Option<UnixTime>,
    #[serde(rename = "collectedAt", skip_serializing_if = "Option::is_none")]
    pub collectedat: Option<UnixTime>,
    #[serde(rename = "observedAt", skip_serializing_if = "Option::is_none")]
    pub observedat: Option<UnixTime>,
    #[serde(rename = "firstSeenAt", skip_serializing_if = "Option::is_none")]
    pub firstseenat: Option<UnixTime>,
    #[serde(rename = "lastSeenAt", skip_serializing_if = "Option::is_none")]
    pub lastseenat: Option<UnixTime>,
    #[serde(rename = "createdAt", skip_serializing_if = "Option::is_none")]
    pub createdat: Option<UnixTime>,
    #[serde(rename = "updatedAt", skip_serializing_if = "Option::is_none")]
    pub updatedat: Option<UnixTime>,
    #[serde(rename = "validFrom", skip_serializing_if = "Option::is_none")]
    pub validfrom: Option<UnixTime>,
    #[serde(rename = "validUntil", skip_serializing_if = "Option::is_none")]
    pub validuntil: Option<UnixTime>,
    #[serde(rename = "expiresAt", skip_serializing_if = "Option::is_none")]
    pub expiresat: Option<UnixTime>,
    #[serde(rename = "collector", skip_serializing_if = "Option::is_none")]
    pub collector: Option<String>,
    #[serde(rename = "collectorVersion", skip_serializing_if = "Option::is_none")]
    pub collectorversion: Option<String>,
    #[serde(rename = "collectionMethod", skip_serializing_if = "Option::is_none")]
    pub collectionmethod: Option<String>,
    #[serde(rename = "collectionStatus", skip_serializing_if = "Option::is_none")]
    pub collectionstatus: Option<CollectionStatus>,
    #[serde(rename = "runId", skip_serializing_if = "Option::is_none")]
    pub runid: Option<String>,
    #[serde(rename = "correlationId", skip_serializing_if = "Option::is_none")]
    pub correlationid: Option<String>,
    #[serde(rename = "causationId", skip_serializing_if = "Option::is_none")]
    pub causationid: Option<String>,
    #[serde(rename = "parentId", skip_serializing_if = "Option::is_none")]
    pub parentid: Option<DocumentId>,
    #[serde(rename = "rootId", skip_serializing_if = "Option::is_none")]
    pub rootid: Option<DocumentId>,
    #[serde(rename = "confidence", skip_serializing_if = "Option::is_none")]
    pub confidence: Option<ConfidenceScore>,
    #[serde(rename = "confidenceBasis", skip_serializing_if = "Option::is_none")]
    pub confidencebasis: Option<String>,
    #[serde(rename = "qualityScore", skip_serializing_if = "Option::is_none")]
    pub qualityscore: Option<ConfidenceScore>,
    #[serde(rename = "completenessScore", skip_serializing_if = "Option::is_none")]
    pub completenessscore: Option<ConfidenceScore>,
    #[serde(rename = "verificationStatus", skip_serializing_if = "Option::is_none")]
    pub verificationstatus: Option<String>,
    #[serde(rename = "verifiedAt", skip_serializing_if = "Option::is_none")]
    pub verifiedat: Option<UnixTime>,
    #[serde(rename = "verifiedBy", skip_serializing_if = "Option::is_none")]
    pub verifiedby: Option<String>,
    #[serde(rename = "provenance", skip_serializing_if = "Option::is_none")]
    pub provenance: Option<BTreeMap<String, serde_json::Value>>,
    #[serde(rename = "chainOfCustody", skip_serializing_if = "Option::is_none")]
    pub chainofcustody: Option<Vec<BTreeMap<String, serde_json::Value>>>,
    #[serde(rename = "transformHistory", skip_serializing_if = "Option::is_none")]
    pub transformhistory: Option<Vec<BTreeMap<String, serde_json::Value>>>,
    #[serde(rename = "labels", skip_serializing_if = "Option::is_none")]
    pub labels: Option<Vec<String>>,
    #[serde(rename = "tags", skip_serializing_if = "Option::is_none")]
    pub tags: Option<Vec<String>>,
    #[serde(rename = "topics", skip_serializing_if = "Option::is_none")]
    pub topics: Option<Vec<String>>,
    #[serde(rename = "language", skip_serializing_if = "Option::is_none")]
    pub language: Option<String>,
    #[serde(rename = "jurisdiction", skip_serializing_if = "Option::is_none")]
    pub jurisdiction: Option<String>,
    #[serde(rename = "countryCode", skip_serializing_if = "Option::is_none")]
    pub countrycode: Option<String>,
    #[serde(rename = "regionCode", skip_serializing_if = "Option::is_none")]
    pub regioncode: Option<String>,
    #[serde(rename = "timezone", skip_serializing_if = "Option::is_none")]
    pub timezone: Option<String>,
    #[serde(rename = "sensitivity", skip_serializing_if = "Option::is_none")]
    pub sensitivity: Option<Sensitivity>,
    #[serde(rename = "visibility", skip_serializing_if = "Option::is_none")]
    pub visibility: Option<Visibility>,
    #[serde(rename = "owner", skip_serializing_if = "Option::is_none")]
    pub owner: Option<String>,
    #[serde(rename = "accessControl", skip_serializing_if = "Option::is_none")]
    pub accesscontrol: Option<BTreeMap<String, serde_json::Value>>,
    #[serde(rename = "legalBasis", skip_serializing_if = "Option::is_none")]
    pub legalbasis: Option<String>,
    #[serde(rename = "retentionPolicy", skip_serializing_if = "Option::is_none")]
    pub retentionpolicy: Option<String>,
    #[serde(rename = "contentType", skip_serializing_if = "Option::is_none")]
    pub contenttype: Option<String>,
    #[serde(rename = "encoding", skip_serializing_if = "Option::is_none")]
    pub encoding: Option<String>,
    #[serde(rename = "sizeBytes", skip_serializing_if = "Option::is_none")]
    pub sizebytes: Option<i64>,
    #[serde(rename = "contentHash", skip_serializing_if = "Option::is_none")]
    pub contenthash: Option<String>,
    #[serde(rename = "hashAlgorithm", skip_serializing_if = "Option::is_none")]
    pub hashalgorithm: Option<HashAlgorithm>,
    #[serde(rename = "normalizedHash", skip_serializing_if = "Option::is_none")]
    pub normalizedhash: Option<String>,
    #[serde(rename = "raw", skip_serializing_if = "Option::is_none")]
    pub raw: Option<BTreeMap<String, serde_json::Value>>,
    #[serde(rename = "rawContent", skip_serializing_if = "Option::is_none")]
    pub rawcontent: Option<String>,
    #[serde(rename = "notes", skip_serializing_if = "Option::is_none")]
    pub notes: Option<String>,
    #[serde(rename = "deleted", skip_serializing_if = "Option::is_none")]
    pub deleted: Option<bool>,
    #[serde(rename = "tombstoneReason", skip_serializing_if = "Option::is_none")]
    pub tombstonereason: Option<String>,
    #[serde(rename = "extensions", skip_serializing_if = "Option::is_none")]
    pub extensions: Option<BTreeMap<String, serde_json::Value>>,
    #[serde(rename = "picture")]
    pub picture: StarReference,
    #[serde(rename = "x")]
    pub x: PixelOffset,
    #[serde(rename = "y")]
    pub y: PixelOffset,
    #[serde(rename = "width")]
    pub width: PixelLength,
    #[serde(rename = "height")]
    pub height: PixelLength,
    #[serde(rename = "annotationBasis")]
    pub annotationbasis: AnnotationBasis,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct CandidatePerson {
    #[serde(rename = "id")]
    pub id: DocumentId,
    #[serde(rename = "rev", skip_serializing_if = "Option::is_none")]
    pub rev: Option<String>,
    #[serde(rename = "dataset")]
    pub dataset: String,
    #[serde(rename = "dtype")]
    pub dtype: String,
    #[serde(rename = "schemaVersion")]
    pub schemaversion: String,
    #[serde(rename = "externalIds", skip_serializing_if = "Option::is_none")]
    pub externalids: Option<BTreeMap<String, serde_json::Value>>,
    #[serde(rename = "aliases", skip_serializing_if = "Option::is_none")]
    pub aliases: Option<Vec<String>>,
    #[serde(rename = "sources", skip_serializing_if = "Option::is_none")]
    pub sources: Option<Vec<StarReference>>,
    #[serde(rename = "sourceUrls", skip_serializing_if = "Option::is_none")]
    pub sourceurls: Option<Vec<Uri>>,
    #[serde(rename = "sourceRecordIds", skip_serializing_if = "Option::is_none")]
    pub sourcerecordids: Option<Vec<String>>,
    #[serde(rename = "sourceKinds", skip_serializing_if = "Option::is_none")]
    pub sourcekinds: Option<Vec<SourceKind>>,
    #[serde(rename = "sourceLicense", skip_serializing_if = "Option::is_none")]
    pub sourcelicense: Option<String>,
    #[serde(rename = "sourceTerms", skip_serializing_if = "Option::is_none")]
    pub sourceterms: Option<Uri>,
    #[serde(rename = "sourceRetrievedAt", skip_serializing_if = "Option::is_none")]
    pub sourceretrievedat: Option<UnixTime>,
    #[serde(rename = "collectedAt", skip_serializing_if = "Option::is_none")]
    pub collectedat: Option<UnixTime>,
    #[serde(rename = "observedAt", skip_serializing_if = "Option::is_none")]
    pub observedat: Option<UnixTime>,
    #[serde(rename = "firstSeenAt", skip_serializing_if = "Option::is_none")]
    pub firstseenat: Option<UnixTime>,
    #[serde(rename = "lastSeenAt", skip_serializing_if = "Option::is_none")]
    pub lastseenat: Option<UnixTime>,
    #[serde(rename = "createdAt", skip_serializing_if = "Option::is_none")]
    pub createdat: Option<UnixTime>,
    #[serde(rename = "updatedAt", skip_serializing_if = "Option::is_none")]
    pub updatedat: Option<UnixTime>,
    #[serde(rename = "validFrom", skip_serializing_if = "Option::is_none")]
    pub validfrom: Option<UnixTime>,
    #[serde(rename = "validUntil", skip_serializing_if = "Option::is_none")]
    pub validuntil: Option<UnixTime>,
    #[serde(rename = "expiresAt", skip_serializing_if = "Option::is_none")]
    pub expiresat: Option<UnixTime>,
    #[serde(rename = "collector", skip_serializing_if = "Option::is_none")]
    pub collector: Option<String>,
    #[serde(rename = "collectorVersion", skip_serializing_if = "Option::is_none")]
    pub collectorversion: Option<String>,
    #[serde(rename = "collectionMethod", skip_serializing_if = "Option::is_none")]
    pub collectionmethod: Option<String>,
    #[serde(rename = "collectionStatus", skip_serializing_if = "Option::is_none")]
    pub collectionstatus: Option<CollectionStatus>,
    #[serde(rename = "runId", skip_serializing_if = "Option::is_none")]
    pub runid: Option<String>,
    #[serde(rename = "correlationId", skip_serializing_if = "Option::is_none")]
    pub correlationid: Option<String>,
    #[serde(rename = "causationId", skip_serializing_if = "Option::is_none")]
    pub causationid: Option<String>,
    #[serde(rename = "parentId", skip_serializing_if = "Option::is_none")]
    pub parentid: Option<DocumentId>,
    #[serde(rename = "rootId", skip_serializing_if = "Option::is_none")]
    pub rootid: Option<DocumentId>,
    #[serde(rename = "confidence", skip_serializing_if = "Option::is_none")]
    pub confidence: Option<ConfidenceScore>,
    #[serde(rename = "confidenceBasis", skip_serializing_if = "Option::is_none")]
    pub confidencebasis: Option<String>,
    #[serde(rename = "qualityScore", skip_serializing_if = "Option::is_none")]
    pub qualityscore: Option<ConfidenceScore>,
    #[serde(rename = "completenessScore", skip_serializing_if = "Option::is_none")]
    pub completenessscore: Option<ConfidenceScore>,
    #[serde(rename = "verificationStatus", skip_serializing_if = "Option::is_none")]
    pub verificationstatus: Option<String>,
    #[serde(rename = "verifiedAt", skip_serializing_if = "Option::is_none")]
    pub verifiedat: Option<UnixTime>,
    #[serde(rename = "verifiedBy", skip_serializing_if = "Option::is_none")]
    pub verifiedby: Option<String>,
    #[serde(rename = "provenance", skip_serializing_if = "Option::is_none")]
    pub provenance: Option<BTreeMap<String, serde_json::Value>>,
    #[serde(rename = "chainOfCustody", skip_serializing_if = "Option::is_none")]
    pub chainofcustody: Option<Vec<BTreeMap<String, serde_json::Value>>>,
    #[serde(rename = "transformHistory", skip_serializing_if = "Option::is_none")]
    pub transformhistory: Option<Vec<BTreeMap<String, serde_json::Value>>>,
    #[serde(rename = "labels", skip_serializing_if = "Option::is_none")]
    pub labels: Option<Vec<String>>,
    #[serde(rename = "tags", skip_serializing_if = "Option::is_none")]
    pub tags: Option<Vec<String>>,
    #[serde(rename = "topics", skip_serializing_if = "Option::is_none")]
    pub topics: Option<Vec<String>>,
    #[serde(rename = "language", skip_serializing_if = "Option::is_none")]
    pub language: Option<String>,
    #[serde(rename = "jurisdiction", skip_serializing_if = "Option::is_none")]
    pub jurisdiction: Option<String>,
    #[serde(rename = "countryCode", skip_serializing_if = "Option::is_none")]
    pub countrycode: Option<String>,
    #[serde(rename = "regionCode", skip_serializing_if = "Option::is_none")]
    pub regioncode: Option<String>,
    #[serde(rename = "timezone", skip_serializing_if = "Option::is_none")]
    pub timezone: Option<String>,
    #[serde(rename = "sensitivity", skip_serializing_if = "Option::is_none")]
    pub sensitivity: Option<Sensitivity>,
    #[serde(rename = "visibility", skip_serializing_if = "Option::is_none")]
    pub visibility: Option<Visibility>,
    #[serde(rename = "owner", skip_serializing_if = "Option::is_none")]
    pub owner: Option<String>,
    #[serde(rename = "accessControl", skip_serializing_if = "Option::is_none")]
    pub accesscontrol: Option<BTreeMap<String, serde_json::Value>>,
    #[serde(rename = "legalBasis", skip_serializing_if = "Option::is_none")]
    pub legalbasis: Option<String>,
    #[serde(rename = "retentionPolicy", skip_serializing_if = "Option::is_none")]
    pub retentionpolicy: Option<String>,
    #[serde(rename = "contentType", skip_serializing_if = "Option::is_none")]
    pub contenttype: Option<String>,
    #[serde(rename = "encoding", skip_serializing_if = "Option::is_none")]
    pub encoding: Option<String>,
    #[serde(rename = "sizeBytes", skip_serializing_if = "Option::is_none")]
    pub sizebytes: Option<i64>,
    #[serde(rename = "contentHash", skip_serializing_if = "Option::is_none")]
    pub contenthash: Option<String>,
    #[serde(rename = "hashAlgorithm", skip_serializing_if = "Option::is_none")]
    pub hashalgorithm: Option<HashAlgorithm>,
    #[serde(rename = "normalizedHash", skip_serializing_if = "Option::is_none")]
    pub normalizedhash: Option<String>,
    #[serde(rename = "raw", skip_serializing_if = "Option::is_none")]
    pub raw: Option<BTreeMap<String, serde_json::Value>>,
    #[serde(rename = "rawContent", skip_serializing_if = "Option::is_none")]
    pub rawcontent: Option<String>,
    #[serde(rename = "notes", skip_serializing_if = "Option::is_none")]
    pub notes: Option<String>,
    #[serde(rename = "deleted", skip_serializing_if = "Option::is_none")]
    pub deleted: Option<bool>,
    #[serde(rename = "tombstoneReason", skip_serializing_if = "Option::is_none")]
    pub tombstonereason: Option<String>,
    #[serde(rename = "extensions", skip_serializing_if = "Option::is_none")]
    pub extensions: Option<BTreeMap<String, serde_json::Value>>,
    #[serde(rename = "fname", skip_serializing_if = "Option::is_none")]
    pub fname: Option<String>,
    #[serde(rename = "mname", skip_serializing_if = "Option::is_none")]
    pub mname: Option<String>,
    #[serde(rename = "lname", skip_serializing_if = "Option::is_none")]
    pub lname: Option<String>,
    #[serde(rename = "fullName", skip_serializing_if = "Option::is_none")]
    pub fullname: Option<String>,
    #[serde(rename = "displayName", skip_serializing_if = "Option::is_none")]
    pub displayname: Option<String>,
    #[serde(rename = "prefix", skip_serializing_if = "Option::is_none")]
    pub prefix: Option<String>,
    #[serde(rename = "suffix", skip_serializing_if = "Option::is_none")]
    pub suffix: Option<String>,
    #[serde(rename = "pronouns", skip_serializing_if = "Option::is_none")]
    pub pronouns: Option<String>,
    #[serde(rename = "bio", skip_serializing_if = "Option::is_none")]
    pub bio: Option<String>,
    #[serde(rename = "dob", skip_serializing_if = "Option::is_none")]
    pub dob: Option<String>,
    #[serde(rename = "dateOfDeath", skip_serializing_if = "Option::is_none")]
    pub dateofdeath: Option<String>,
    #[serde(rename = "age", skip_serializing_if = "Option::is_none")]
    pub age: Option<i64>,
    #[serde(rename = "gender", skip_serializing_if = "Option::is_none")]
    pub gender: Option<String>,
    #[serde(rename = "nationality", skip_serializing_if = "Option::is_none")]
    pub nationality: Option<Vec<String>>,
    #[serde(rename = "citizenship", skip_serializing_if = "Option::is_none")]
    pub citizenship: Option<Vec<String>>,
    #[serde(rename = "occupation", skip_serializing_if = "Option::is_none")]
    pub occupation: Option<Vec<String>>,
    #[serde(rename = "employer", skip_serializing_if = "Option::is_none")]
    pub employer: Option<Vec<StarReference>>,
    #[serde(rename = "education", skip_serializing_if = "Option::is_none")]
    pub education: Option<Vec<BTreeMap<String, serde_json::Value>>>,
    #[serde(rename = "skills", skip_serializing_if = "Option::is_none")]
    pub skills: Option<Vec<String>>,
    #[serde(rename = "interests", skip_serializing_if = "Option::is_none")]
    pub interests: Option<Vec<String>>,
    #[serde(rename = "region", skip_serializing_if = "Option::is_none")]
    pub region: Option<String>,
    #[serde(rename = "addresses", skip_serializing_if = "Option::is_none")]
    pub addresses: Option<Vec<StarReference>>,
    #[serde(rename = "emails", skip_serializing_if = "Option::is_none")]
    pub emails: Option<Vec<StarReference>>,
    #[serde(rename = "phones", skip_serializing_if = "Option::is_none")]
    pub phones: Option<Vec<StarReference>>,
    #[serde(rename = "accounts", skip_serializing_if = "Option::is_none")]
    pub accounts: Option<Vec<StarReference>>,
    #[serde(rename = "images", skip_serializing_if = "Option::is_none")]
    pub images: Option<Vec<StarReference>>,
    #[serde(rename = "identifiers", skip_serializing_if = "Option::is_none")]
    pub identifiers: Option<Vec<StarReference>>,
    #[serde(rename = "misc", skip_serializing_if = "Option::is_none")]
    pub misc: Option<Vec<BTreeMap<String, serde_json::Value>>>,
    #[serde(rename = "etype", skip_serializing_if = "Option::is_none")]
    pub etype: Option<String>,
    #[serde(rename = "eid", skip_serializing_if = "Option::is_none")]
    pub eid: Option<String>,
    #[serde(rename = "candidateStatus")]
    pub candidatestatus: CandidateOnly,
    #[serde(rename = "annotationBasis")]
    pub annotationbasis: AnnotationBasis,
    #[serde(rename = "evidenceReferences", skip_serializing_if = "Option::is_none")]
    pub evidencereferences: Option<Vec<StarReference>>,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct FacePersonCandidate {
    #[serde(rename = "id")]
    pub id: DocumentId,
    #[serde(rename = "rev", skip_serializing_if = "Option::is_none")]
    pub rev: Option<String>,
    #[serde(rename = "dataset")]
    pub dataset: String,
    #[serde(rename = "dtype")]
    pub dtype: String,
    #[serde(rename = "schemaVersion")]
    pub schemaversion: String,
    #[serde(rename = "externalIds", skip_serializing_if = "Option::is_none")]
    pub externalids: Option<BTreeMap<String, serde_json::Value>>,
    #[serde(rename = "aliases", skip_serializing_if = "Option::is_none")]
    pub aliases: Option<Vec<String>>,
    #[serde(rename = "sources", skip_serializing_if = "Option::is_none")]
    pub sources: Option<Vec<StarReference>>,
    #[serde(rename = "sourceUrls", skip_serializing_if = "Option::is_none")]
    pub sourceurls: Option<Vec<Uri>>,
    #[serde(rename = "sourceRecordIds", skip_serializing_if = "Option::is_none")]
    pub sourcerecordids: Option<Vec<String>>,
    #[serde(rename = "sourceKinds", skip_serializing_if = "Option::is_none")]
    pub sourcekinds: Option<Vec<SourceKind>>,
    #[serde(rename = "sourceLicense", skip_serializing_if = "Option::is_none")]
    pub sourcelicense: Option<String>,
    #[serde(rename = "sourceTerms", skip_serializing_if = "Option::is_none")]
    pub sourceterms: Option<Uri>,
    #[serde(rename = "sourceRetrievedAt", skip_serializing_if = "Option::is_none")]
    pub sourceretrievedat: Option<UnixTime>,
    #[serde(rename = "collectedAt", skip_serializing_if = "Option::is_none")]
    pub collectedat: Option<UnixTime>,
    #[serde(rename = "observedAt", skip_serializing_if = "Option::is_none")]
    pub observedat: Option<UnixTime>,
    #[serde(rename = "firstSeenAt", skip_serializing_if = "Option::is_none")]
    pub firstseenat: Option<UnixTime>,
    #[serde(rename = "lastSeenAt", skip_serializing_if = "Option::is_none")]
    pub lastseenat: Option<UnixTime>,
    #[serde(rename = "createdAt", skip_serializing_if = "Option::is_none")]
    pub createdat: Option<UnixTime>,
    #[serde(rename = "updatedAt", skip_serializing_if = "Option::is_none")]
    pub updatedat: Option<UnixTime>,
    #[serde(rename = "validFrom", skip_serializing_if = "Option::is_none")]
    pub validfrom: Option<UnixTime>,
    #[serde(rename = "validUntil", skip_serializing_if = "Option::is_none")]
    pub validuntil: Option<UnixTime>,
    #[serde(rename = "expiresAt", skip_serializing_if = "Option::is_none")]
    pub expiresat: Option<UnixTime>,
    #[serde(rename = "collector", skip_serializing_if = "Option::is_none")]
    pub collector: Option<String>,
    #[serde(rename = "collectorVersion", skip_serializing_if = "Option::is_none")]
    pub collectorversion: Option<String>,
    #[serde(rename = "collectionMethod", skip_serializing_if = "Option::is_none")]
    pub collectionmethod: Option<String>,
    #[serde(rename = "collectionStatus", skip_serializing_if = "Option::is_none")]
    pub collectionstatus: Option<CollectionStatus>,
    #[serde(rename = "runId", skip_serializing_if = "Option::is_none")]
    pub runid: Option<String>,
    #[serde(rename = "correlationId", skip_serializing_if = "Option::is_none")]
    pub correlationid: Option<String>,
    #[serde(rename = "causationId", skip_serializing_if = "Option::is_none")]
    pub causationid: Option<String>,
    #[serde(rename = "parentId", skip_serializing_if = "Option::is_none")]
    pub parentid: Option<DocumentId>,
    #[serde(rename = "rootId", skip_serializing_if = "Option::is_none")]
    pub rootid: Option<DocumentId>,
    #[serde(rename = "confidence", skip_serializing_if = "Option::is_none")]
    pub confidence: Option<ConfidenceScore>,
    #[serde(rename = "confidenceBasis", skip_serializing_if = "Option::is_none")]
    pub confidencebasis: Option<String>,
    #[serde(rename = "qualityScore", skip_serializing_if = "Option::is_none")]
    pub qualityscore: Option<ConfidenceScore>,
    #[serde(rename = "completenessScore", skip_serializing_if = "Option::is_none")]
    pub completenessscore: Option<ConfidenceScore>,
    #[serde(rename = "verificationStatus", skip_serializing_if = "Option::is_none")]
    pub verificationstatus: Option<String>,
    #[serde(rename = "verifiedAt", skip_serializing_if = "Option::is_none")]
    pub verifiedat: Option<UnixTime>,
    #[serde(rename = "verifiedBy", skip_serializing_if = "Option::is_none")]
    pub verifiedby: Option<String>,
    #[serde(rename = "provenance", skip_serializing_if = "Option::is_none")]
    pub provenance: Option<BTreeMap<String, serde_json::Value>>,
    #[serde(rename = "chainOfCustody", skip_serializing_if = "Option::is_none")]
    pub chainofcustody: Option<Vec<BTreeMap<String, serde_json::Value>>>,
    #[serde(rename = "transformHistory", skip_serializing_if = "Option::is_none")]
    pub transformhistory: Option<Vec<BTreeMap<String, serde_json::Value>>>,
    #[serde(rename = "labels", skip_serializing_if = "Option::is_none")]
    pub labels: Option<Vec<String>>,
    #[serde(rename = "tags", skip_serializing_if = "Option::is_none")]
    pub tags: Option<Vec<String>>,
    #[serde(rename = "topics", skip_serializing_if = "Option::is_none")]
    pub topics: Option<Vec<String>>,
    #[serde(rename = "language", skip_serializing_if = "Option::is_none")]
    pub language: Option<String>,
    #[serde(rename = "jurisdiction", skip_serializing_if = "Option::is_none")]
    pub jurisdiction: Option<String>,
    #[serde(rename = "countryCode", skip_serializing_if = "Option::is_none")]
    pub countrycode: Option<String>,
    #[serde(rename = "regionCode", skip_serializing_if = "Option::is_none")]
    pub regioncode: Option<String>,
    #[serde(rename = "timezone", skip_serializing_if = "Option::is_none")]
    pub timezone: Option<String>,
    #[serde(rename = "sensitivity", skip_serializing_if = "Option::is_none")]
    pub sensitivity: Option<Sensitivity>,
    #[serde(rename = "visibility", skip_serializing_if = "Option::is_none")]
    pub visibility: Option<Visibility>,
    #[serde(rename = "owner", skip_serializing_if = "Option::is_none")]
    pub owner: Option<String>,
    #[serde(rename = "accessControl", skip_serializing_if = "Option::is_none")]
    pub accesscontrol: Option<BTreeMap<String, serde_json::Value>>,
    #[serde(rename = "legalBasis", skip_serializing_if = "Option::is_none")]
    pub legalbasis: Option<String>,
    #[serde(rename = "retentionPolicy", skip_serializing_if = "Option::is_none")]
    pub retentionpolicy: Option<String>,
    #[serde(rename = "contentType", skip_serializing_if = "Option::is_none")]
    pub contenttype: Option<String>,
    #[serde(rename = "encoding", skip_serializing_if = "Option::is_none")]
    pub encoding: Option<String>,
    #[serde(rename = "sizeBytes", skip_serializing_if = "Option::is_none")]
    pub sizebytes: Option<i64>,
    #[serde(rename = "contentHash", skip_serializing_if = "Option::is_none")]
    pub contenthash: Option<String>,
    #[serde(rename = "hashAlgorithm", skip_serializing_if = "Option::is_none")]
    pub hashalgorithm: Option<HashAlgorithm>,
    #[serde(rename = "normalizedHash", skip_serializing_if = "Option::is_none")]
    pub normalizedhash: Option<String>,
    #[serde(rename = "raw", skip_serializing_if = "Option::is_none")]
    pub raw: Option<BTreeMap<String, serde_json::Value>>,
    #[serde(rename = "rawContent", skip_serializing_if = "Option::is_none")]
    pub rawcontent: Option<String>,
    #[serde(rename = "notes", skip_serializing_if = "Option::is_none")]
    pub notes: Option<String>,
    #[serde(rename = "deleted", skip_serializing_if = "Option::is_none")]
    pub deleted: Option<bool>,
    #[serde(rename = "tombstoneReason", skip_serializing_if = "Option::is_none")]
    pub tombstonereason: Option<String>,
    #[serde(rename = "extensions", skip_serializing_if = "Option::is_none")]
    pub extensions: Option<BTreeMap<String, serde_json::Value>>,
    #[serde(rename = "source")]
    pub source: StarReference,
    #[serde(rename = "destination")]
    pub destination: StarReference,
    #[serde(rename = "predicate")]
    pub predicate: String,
    #[serde(rename = "direction", skip_serializing_if = "Option::is_none")]
    pub direction: Option<RelationDirection>,
    #[serde(rename = "inversePredicate", skip_serializing_if = "Option::is_none")]
    pub inversepredicate: Option<String>,
    #[serde(rename = "note", skip_serializing_if = "Option::is_none")]
    pub note: Option<String>,
    #[serde(rename = "evidence", skip_serializing_if = "Option::is_none")]
    pub evidence: Option<Vec<StarReference>>,
    #[serde(rename = "weight", skip_serializing_if = "Option::is_none")]
    pub weight: Option<String>,
    #[serde(rename = "validAt", skip_serializing_if = "Option::is_none")]
    pub validat: Option<UnixTime>,
    #[serde(rename = "endedAt", skip_serializing_if = "Option::is_none")]
    pub endedat: Option<UnixTime>,
    #[serde(rename = "candidateStatus")]
    pub candidatestatus: CandidateOnly,
    #[serde(rename = "annotationBasis")]
    pub annotationbasis: AnnotationBasis,
    #[serde(rename = "evidenceReferences", skip_serializing_if = "Option::is_none")]
    pub evidencereferences: Option<Vec<StarReference>>,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct StoreFaceObservation {
    #[serde(rename = "document")]
    pub document: StarReference,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct StoreCandidatePerson {
    #[serde(rename = "document")]
    pub document: StarReference,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct AnnotateFacePerson {
    #[serde(rename = "face")]
    pub face: StarReference,
    #[serde(rename = "person")]
    pub person: StarReference,
    #[serde(rename = "annotationBasis")]
    pub annotationbasis: AnnotationBasis,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct GetFaceObservation {
    #[serde(rename = "face")]
    pub face: StarReference,
}
