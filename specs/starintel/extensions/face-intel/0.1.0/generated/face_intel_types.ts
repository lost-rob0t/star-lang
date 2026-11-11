// Generated from StarLang portable manifest. DO NOT EDIT.

export interface StarReference {
  schema: string;
  id: string;
}

export type DocumentId = string;

export type UnixTime = number;

export type ConfidenceScore = string;

export type Uri = string;

export type Sensitivity = "public" | "internal" | "confidential" | "restricted" | "secret" | "unknown";

export type Visibility = "public" | "private" | "shared" | "inherited" | "unknown";

export type CollectionStatus = "raw" | "normalized" | "enriched" | "verified" | "disputed" | "stale" | "deleted" | "unknown";

export type SourceKind = "api" | "web" | "file" | "database" | "message" | "human" | "sensor" | "inference" | "import" | "export" | "unknown";

export type HashAlgorithm = "sha256" | "sha512" | "blake2b" | "blake3" | "md5" | "unknown";

export type RelationDirection = "directed" | "symmetric" | "inverse" | "unknown";

export interface Document {
  "id": DocumentId;
  "rev"?: string;
  "dataset": string;
  "dtype": string;
  "schemaVersion": string;
  "externalIds"?: Record<string, unknown>;
  "aliases"?: Array<string>;
  "sources"?: Array<StarReference>;
  "sourceUrls"?: Array<Uri>;
  "sourceRecordIds"?: Array<string>;
  "sourceKinds"?: Array<SourceKind>;
  "sourceLicense"?: string;
  "sourceTerms"?: Uri;
  "sourceRetrievedAt"?: UnixTime;
  "collectedAt"?: UnixTime;
  "observedAt"?: UnixTime;
  "firstSeenAt"?: UnixTime;
  "lastSeenAt"?: UnixTime;
  "createdAt"?: UnixTime;
  "updatedAt"?: UnixTime;
  "validFrom"?: UnixTime;
  "validUntil"?: UnixTime;
  "expiresAt"?: UnixTime;
  "collector"?: string;
  "collectorVersion"?: string;
  "collectionMethod"?: string;
  "collectionStatus"?: CollectionStatus;
  "runId"?: string;
  "correlationId"?: string;
  "causationId"?: string;
  "parentId"?: DocumentId;
  "rootId"?: DocumentId;
  "confidence"?: ConfidenceScore;
  "confidenceBasis"?: string;
  "qualityScore"?: ConfidenceScore;
  "completenessScore"?: ConfidenceScore;
  "verificationStatus"?: string;
  "verifiedAt"?: UnixTime;
  "verifiedBy"?: string;
  "provenance"?: Record<string, unknown>;
  "chainOfCustody"?: Array<Record<string, unknown>>;
  "transformHistory"?: Array<Record<string, unknown>>;
  "labels"?: Array<string>;
  "tags"?: Array<string>;
  "topics"?: Array<string>;
  "language"?: string;
  "jurisdiction"?: string;
  "countryCode"?: string;
  "regionCode"?: string;
  "timezone"?: string;
  "sensitivity"?: Sensitivity;
  "visibility"?: Visibility;
  "owner"?: string;
  "accessControl"?: Record<string, unknown>;
  "legalBasis"?: string;
  "retentionPolicy"?: string;
  "contentType"?: string;
  "encoding"?: string;
  "sizeBytes"?: number;
  "contentHash"?: string;
  "hashAlgorithm"?: HashAlgorithm;
  "normalizedHash"?: string;
  "raw"?: Record<string, unknown>;
  "rawContent"?: string;
  "notes"?: string;
  "deleted"?: boolean;
  "tombstoneReason"?: string;
  "extensions"?: Record<string, unknown>;
}

export interface Person extends Document {
  "fname"?: string;
  "mname"?: string;
  "lname"?: string;
  "fullName"?: string;
  "displayName"?: string;
  "prefix"?: string;
  "suffix"?: string;
  "pronouns"?: string;
  "bio"?: string;
  "dob"?: string;
  "dateOfDeath"?: string;
  "age"?: number;
  "gender"?: string;
  "nationality"?: Array<string>;
  "citizenship"?: Array<string>;
  "occupation"?: Array<string>;
  "employer"?: Array<StarReference>;
  "education"?: Array<Record<string, unknown>>;
  "skills"?: Array<string>;
  "interests"?: Array<string>;
  "region"?: string;
  "addresses"?: Array<StarReference>;
  "emails"?: Array<StarReference>;
  "phones"?: Array<StarReference>;
  "accounts"?: Array<StarReference>;
  "images"?: Array<StarReference>;
  "identifiers"?: Array<StarReference>;
  "misc"?: Array<Record<string, unknown>>;
  "etype"?: string;
  "eid"?: string;
}

export interface Relation extends Document {
  "source": StarReference;
  "destination": StarReference;
  "predicate": string;
  "direction"?: RelationDirection;
  "inversePredicate"?: string;
  "note"?: string;
  "evidence"?: Array<StarReference>;
  "weight"?: string;
  "validAt"?: UnixTime;
  "endedAt"?: UnixTime;
}

export type PixelOffset = number;

export type PixelLength = number;

export type AnnotationBasis = string;

export type CandidateOnly = "candidate";

export interface FaceObservation extends Document {
  "picture": StarReference;
  "x": PixelOffset;
  "y": PixelOffset;
  "width": PixelLength;
  "height": PixelLength;
  "annotationBasis": AnnotationBasis;
}

export interface CandidatePerson extends Person {
  "candidateStatus": CandidateOnly;
  "annotationBasis": AnnotationBasis;
  "evidenceReferences"?: Array<StarReference>;
}

export interface FacePersonCandidate extends Relation {
  "candidateStatus": CandidateOnly;
  "annotationBasis": AnnotationBasis;
  "evidenceReferences"?: Array<StarReference>;
}

export interface StoreFaceObservation {
  "document": StarReference;
}

export interface StoreCandidatePerson {
  "document": StarReference;
}

export interface AnnotateFacePerson {
  "face": StarReference;
  "person": StarReference;
  "annotationBasis": AnnotationBasis;
}

export interface GetFaceObservation {
  "face": StarReference;
}

export const actorContracts = {
} as const;
