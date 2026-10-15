%% Generated from StarLang portable manifest. DO NOT EDIT.

star_reference_type(star_reference).
star_scalar('org.starintel/core@1/document-id', 'string').
star_scalar('org.starintel/core@1/unix-time', 'integer').
star_scalar('org.starintel/core@1/confidence-score', 'decimal').
star_scalar('org.starintel/core@1/uri', 'string').
star_enum('org.starintel/core@1/sensitivity').
star_enum_value('org.starintel/core@1/sensitivity', 'public').
star_enum_value('org.starintel/core@1/sensitivity', 'internal').
star_enum_value('org.starintel/core@1/sensitivity', 'confidential').
star_enum_value('org.starintel/core@1/sensitivity', 'restricted').
star_enum_value('org.starintel/core@1/sensitivity', 'secret').
star_enum_value('org.starintel/core@1/sensitivity', 'unknown').
star_enum('org.starintel/core@1/visibility').
star_enum_value('org.starintel/core@1/visibility', 'public').
star_enum_value('org.starintel/core@1/visibility', 'private').
star_enum_value('org.starintel/core@1/visibility', 'shared').
star_enum_value('org.starintel/core@1/visibility', 'inherited').
star_enum_value('org.starintel/core@1/visibility', 'unknown').
star_enum('org.starintel/core@1/collection-status').
star_enum_value('org.starintel/core@1/collection-status', 'raw').
star_enum_value('org.starintel/core@1/collection-status', 'normalized').
star_enum_value('org.starintel/core@1/collection-status', 'enriched').
star_enum_value('org.starintel/core@1/collection-status', 'verified').
star_enum_value('org.starintel/core@1/collection-status', 'disputed').
star_enum_value('org.starintel/core@1/collection-status', 'stale').
star_enum_value('org.starintel/core@1/collection-status', 'deleted').
star_enum_value('org.starintel/core@1/collection-status', 'unknown').
star_enum('org.starintel/core@1/source-kind').
star_enum_value('org.starintel/core@1/source-kind', 'api').
star_enum_value('org.starintel/core@1/source-kind', 'web').
star_enum_value('org.starintel/core@1/source-kind', 'file').
star_enum_value('org.starintel/core@1/source-kind', 'database').
star_enum_value('org.starintel/core@1/source-kind', 'message').
star_enum_value('org.starintel/core@1/source-kind', 'human').
star_enum_value('org.starintel/core@1/source-kind', 'sensor').
star_enum_value('org.starintel/core@1/source-kind', 'inference').
star_enum_value('org.starintel/core@1/source-kind', 'import').
star_enum_value('org.starintel/core@1/source-kind', 'export').
star_enum_value('org.starintel/core@1/source-kind', 'unknown').
star_enum('org.starintel/core@1/hash-algorithm').
star_enum_value('org.starintel/core@1/hash-algorithm', 'sha256').
star_enum_value('org.starintel/core@1/hash-algorithm', 'sha512').
star_enum_value('org.starintel/core@1/hash-algorithm', 'blake2b').
star_enum_value('org.starintel/core@1/hash-algorithm', 'blake3').
star_enum_value('org.starintel/core@1/hash-algorithm', 'md5').
star_enum_value('org.starintel/core@1/hash-algorithm', 'unknown').
star_enum('org.starintel/core@1/relation-direction').
star_enum_value('org.starintel/core@1/relation-direction', 'directed').
star_enum_value('org.starintel/core@1/relation-direction', 'symmetric').
star_enum_value('org.starintel/core@1/relation-direction', 'inverse').
star_enum_value('org.starintel/core@1/relation-direction', 'unknown').
star_document('org.starintel/core@1/document').
star_field('org.starintel/core@1/document', 'id', 'org.starintel/core@1/document-id', required).
star_field('org.starintel/core@1/document', 'rev', 'string', optional).
star_field('org.starintel/core@1/document', 'dataset', 'string', required).
star_field('org.starintel/core@1/document', 'dtype', 'string', required).
star_field('org.starintel/core@1/document', 'schemaVersion', 'string', required).
star_field('org.starintel/core@1/document', 'externalIds', 'map', optional).
star_field('org.starintel/core@1/document', 'aliases', list('string'), optional).
star_field('org.starintel/core@1/document', 'sources', list('reference'), optional).
star_field('org.starintel/core@1/document', 'sourceUrls', list('org.starintel/core@1/uri'), optional).
star_field('org.starintel/core@1/document', 'sourceRecordIds', list('string'), optional).
star_field('org.starintel/core@1/document', 'sourceKinds', list('org.starintel/core@1/source-kind'), optional).
star_field('org.starintel/core@1/document', 'sourceLicense', 'string', optional).
star_field('org.starintel/core@1/document', 'sourceTerms', 'org.starintel/core@1/uri', optional).
star_field('org.starintel/core@1/document', 'sourceRetrievedAt', 'org.starintel/core@1/unix-time', optional).
star_field('org.starintel/core@1/document', 'collectedAt', 'org.starintel/core@1/unix-time', optional).
star_field('org.starintel/core@1/document', 'observedAt', 'org.starintel/core@1/unix-time', optional).
star_field('org.starintel/core@1/document', 'firstSeenAt', 'org.starintel/core@1/unix-time', optional).
star_field('org.starintel/core@1/document', 'lastSeenAt', 'org.starintel/core@1/unix-time', optional).
star_field('org.starintel/core@1/document', 'createdAt', 'org.starintel/core@1/unix-time', optional).
star_field('org.starintel/core@1/document', 'updatedAt', 'org.starintel/core@1/unix-time', optional).
star_field('org.starintel/core@1/document', 'validFrom', 'org.starintel/core@1/unix-time', optional).
star_field('org.starintel/core@1/document', 'validUntil', 'org.starintel/core@1/unix-time', optional).
star_field('org.starintel/core@1/document', 'expiresAt', 'org.starintel/core@1/unix-time', optional).
star_field('org.starintel/core@1/document', 'collector', 'string', optional).
star_field('org.starintel/core@1/document', 'collectorVersion', 'string', optional).
star_field('org.starintel/core@1/document', 'collectionMethod', 'string', optional).
star_field('org.starintel/core@1/document', 'collectionStatus', 'org.starintel/core@1/collection-status', optional).
star_field('org.starintel/core@1/document', 'runId', 'string', optional).
star_field('org.starintel/core@1/document', 'correlationId', 'string', optional).
star_field('org.starintel/core@1/document', 'causationId', 'string', optional).
star_field('org.starintel/core@1/document', 'parentId', 'org.starintel/core@1/document-id', optional).
star_field('org.starintel/core@1/document', 'rootId', 'org.starintel/core@1/document-id', optional).
star_field('org.starintel/core@1/document', 'confidence', 'org.starintel/core@1/confidence-score', optional).
star_field('org.starintel/core@1/document', 'confidenceBasis', 'string', optional).
star_field('org.starintel/core@1/document', 'qualityScore', 'org.starintel/core@1/confidence-score', optional).
star_field('org.starintel/core@1/document', 'completenessScore', 'org.starintel/core@1/confidence-score', optional).
star_field('org.starintel/core@1/document', 'verificationStatus', 'string', optional).
star_field('org.starintel/core@1/document', 'verifiedAt', 'org.starintel/core@1/unix-time', optional).
star_field('org.starintel/core@1/document', 'verifiedBy', 'string', optional).
star_field('org.starintel/core@1/document', 'provenance', 'map', optional).
star_field('org.starintel/core@1/document', 'chainOfCustody', list('map'), optional).
star_field('org.starintel/core@1/document', 'transformHistory', list('map'), optional).
star_field('org.starintel/core@1/document', 'labels', list('string'), optional).
star_field('org.starintel/core@1/document', 'tags', list('string'), optional).
star_field('org.starintel/core@1/document', 'topics', list('string'), optional).
star_field('org.starintel/core@1/document', 'language', 'string', optional).
star_field('org.starintel/core@1/document', 'jurisdiction', 'string', optional).
star_field('org.starintel/core@1/document', 'countryCode', 'string', optional).
star_field('org.starintel/core@1/document', 'regionCode', 'string', optional).
star_field('org.starintel/core@1/document', 'timezone', 'string', optional).
star_field('org.starintel/core@1/document', 'sensitivity', 'org.starintel/core@1/sensitivity', optional).
star_field('org.starintel/core@1/document', 'visibility', 'org.starintel/core@1/visibility', optional).
star_field('org.starintel/core@1/document', 'owner', 'string', optional).
star_field('org.starintel/core@1/document', 'accessControl', 'map', optional).
star_field('org.starintel/core@1/document', 'legalBasis', 'string', optional).
star_field('org.starintel/core@1/document', 'retentionPolicy', 'string', optional).
star_field('org.starintel/core@1/document', 'contentType', 'string', optional).
star_field('org.starintel/core@1/document', 'encoding', 'string', optional).
star_field('org.starintel/core@1/document', 'sizeBytes', 'integer', optional).
star_field('org.starintel/core@1/document', 'contentHash', 'string', optional).
star_field('org.starintel/core@1/document', 'hashAlgorithm', 'org.starintel/core@1/hash-algorithm', optional).
star_field('org.starintel/core@1/document', 'normalizedHash', 'string', optional).
star_field('org.starintel/core@1/document', 'raw', 'map', optional).
star_field('org.starintel/core@1/document', 'rawContent', 'string', optional).
star_field('org.starintel/core@1/document', 'notes', 'string', optional).
star_field('org.starintel/core@1/document', 'deleted', 'boolean', optional).
star_field('org.starintel/core@1/document', 'tombstoneReason', 'string', optional).
star_field('org.starintel/core@1/document', 'extensions', 'map', optional).
star_document('org.starintel/core@1/person').
star_extends('org.starintel/core@1/person', 'org.starintel/core@1/document').
star_field('org.starintel/core@1/person', 'id', 'org.starintel/core@1/document-id', required).
star_field('org.starintel/core@1/person', 'rev', 'string', optional).
star_field('org.starintel/core@1/person', 'dataset', 'string', required).
star_field('org.starintel/core@1/person', 'dtype', 'string', required).
star_field('org.starintel/core@1/person', 'schemaVersion', 'string', required).
star_field('org.starintel/core@1/person', 'externalIds', 'map', optional).
star_field('org.starintel/core@1/person', 'aliases', list('string'), optional).
star_field('org.starintel/core@1/person', 'sources', list('reference'), optional).
star_field('org.starintel/core@1/person', 'sourceUrls', list('org.starintel/core@1/uri'), optional).
star_field('org.starintel/core@1/person', 'sourceRecordIds', list('string'), optional).
star_field('org.starintel/core@1/person', 'sourceKinds', list('org.starintel/core@1/source-kind'), optional).
star_field('org.starintel/core@1/person', 'sourceLicense', 'string', optional).
star_field('org.starintel/core@1/person', 'sourceTerms', 'org.starintel/core@1/uri', optional).
star_field('org.starintel/core@1/person', 'sourceRetrievedAt', 'org.starintel/core@1/unix-time', optional).
star_field('org.starintel/core@1/person', 'collectedAt', 'org.starintel/core@1/unix-time', optional).
star_field('org.starintel/core@1/person', 'observedAt', 'org.starintel/core@1/unix-time', optional).
star_field('org.starintel/core@1/person', 'firstSeenAt', 'org.starintel/core@1/unix-time', optional).
star_field('org.starintel/core@1/person', 'lastSeenAt', 'org.starintel/core@1/unix-time', optional).
star_field('org.starintel/core@1/person', 'createdAt', 'org.starintel/core@1/unix-time', optional).
star_field('org.starintel/core@1/person', 'updatedAt', 'org.starintel/core@1/unix-time', optional).
star_field('org.starintel/core@1/person', 'validFrom', 'org.starintel/core@1/unix-time', optional).
star_field('org.starintel/core@1/person', 'validUntil', 'org.starintel/core@1/unix-time', optional).
star_field('org.starintel/core@1/person', 'expiresAt', 'org.starintel/core@1/unix-time', optional).
star_field('org.starintel/core@1/person', 'collector', 'string', optional).
star_field('org.starintel/core@1/person', 'collectorVersion', 'string', optional).
star_field('org.starintel/core@1/person', 'collectionMethod', 'string', optional).
star_field('org.starintel/core@1/person', 'collectionStatus', 'org.starintel/core@1/collection-status', optional).
star_field('org.starintel/core@1/person', 'runId', 'string', optional).
star_field('org.starintel/core@1/person', 'correlationId', 'string', optional).
star_field('org.starintel/core@1/person', 'causationId', 'string', optional).
star_field('org.starintel/core@1/person', 'parentId', 'org.starintel/core@1/document-id', optional).
star_field('org.starintel/core@1/person', 'rootId', 'org.starintel/core@1/document-id', optional).
star_field('org.starintel/core@1/person', 'confidence', 'org.starintel/core@1/confidence-score', optional).
star_field('org.starintel/core@1/person', 'confidenceBasis', 'string', optional).
star_field('org.starintel/core@1/person', 'qualityScore', 'org.starintel/core@1/confidence-score', optional).
star_field('org.starintel/core@1/person', 'completenessScore', 'org.starintel/core@1/confidence-score', optional).
star_field('org.starintel/core@1/person', 'verificationStatus', 'string', optional).
star_field('org.starintel/core@1/person', 'verifiedAt', 'org.starintel/core@1/unix-time', optional).
star_field('org.starintel/core@1/person', 'verifiedBy', 'string', optional).
star_field('org.starintel/core@1/person', 'provenance', 'map', optional).
star_field('org.starintel/core@1/person', 'chainOfCustody', list('map'), optional).
star_field('org.starintel/core@1/person', 'transformHistory', list('map'), optional).
star_field('org.starintel/core@1/person', 'labels', list('string'), optional).
star_field('org.starintel/core@1/person', 'tags', list('string'), optional).
star_field('org.starintel/core@1/person', 'topics', list('string'), optional).
star_field('org.starintel/core@1/person', 'language', 'string', optional).
star_field('org.starintel/core@1/person', 'jurisdiction', 'string', optional).
star_field('org.starintel/core@1/person', 'countryCode', 'string', optional).
star_field('org.starintel/core@1/person', 'regionCode', 'string', optional).
star_field('org.starintel/core@1/person', 'timezone', 'string', optional).
star_field('org.starintel/core@1/person', 'sensitivity', 'org.starintel/core@1/sensitivity', optional).
star_field('org.starintel/core@1/person', 'visibility', 'org.starintel/core@1/visibility', optional).
star_field('org.starintel/core@1/person', 'owner', 'string', optional).
star_field('org.starintel/core@1/person', 'accessControl', 'map', optional).
star_field('org.starintel/core@1/person', 'legalBasis', 'string', optional).
star_field('org.starintel/core@1/person', 'retentionPolicy', 'string', optional).
star_field('org.starintel/core@1/person', 'contentType', 'string', optional).
star_field('org.starintel/core@1/person', 'encoding', 'string', optional).
star_field('org.starintel/core@1/person', 'sizeBytes', 'integer', optional).
star_field('org.starintel/core@1/person', 'contentHash', 'string', optional).
star_field('org.starintel/core@1/person', 'hashAlgorithm', 'org.starintel/core@1/hash-algorithm', optional).
star_field('org.starintel/core@1/person', 'normalizedHash', 'string', optional).
star_field('org.starintel/core@1/person', 'raw', 'map', optional).
star_field('org.starintel/core@1/person', 'rawContent', 'string', optional).
star_field('org.starintel/core@1/person', 'notes', 'string', optional).
star_field('org.starintel/core@1/person', 'deleted', 'boolean', optional).
star_field('org.starintel/core@1/person', 'tombstoneReason', 'string', optional).
star_field('org.starintel/core@1/person', 'extensions', 'map', optional).
star_field('org.starintel/core@1/person', 'fname', 'string', optional).
star_field('org.starintel/core@1/person', 'mname', 'string', optional).
star_field('org.starintel/core@1/person', 'lname', 'string', optional).
star_field('org.starintel/core@1/person', 'fullName', 'string', optional).
star_field('org.starintel/core@1/person', 'displayName', 'string', optional).
star_field('org.starintel/core@1/person', 'prefix', 'string', optional).
star_field('org.starintel/core@1/person', 'suffix', 'string', optional).
star_field('org.starintel/core@1/person', 'pronouns', 'string', optional).
star_field('org.starintel/core@1/person', 'bio', 'string', optional).
star_field('org.starintel/core@1/person', 'dob', 'iso-date', optional).
star_field('org.starintel/core@1/person', 'dateOfDeath', 'iso-date', optional).
star_field('org.starintel/core@1/person', 'age', 'integer', optional).
star_field('org.starintel/core@1/person', 'gender', 'string', optional).
star_field('org.starintel/core@1/person', 'nationality', list('string'), optional).
star_field('org.starintel/core@1/person', 'citizenship', list('string'), optional).
star_field('org.starintel/core@1/person', 'occupation', list('string'), optional).
star_field('org.starintel/core@1/person', 'employer', list('reference'), optional).
star_field('org.starintel/core@1/person', 'education', list('map'), optional).
star_field('org.starintel/core@1/person', 'skills', list('string'), optional).
star_field('org.starintel/core@1/person', 'interests', list('string'), optional).
star_field('org.starintel/core@1/person', 'region', 'string', optional).
star_field('org.starintel/core@1/person', 'addresses', list('reference'), optional).
star_field('org.starintel/core@1/person', 'emails', list('reference'), optional).
star_field('org.starintel/core@1/person', 'phones', list('reference'), optional).
star_field('org.starintel/core@1/person', 'accounts', list('reference'), optional).
star_field('org.starintel/core@1/person', 'images', list('reference'), optional).
star_field('org.starintel/core@1/person', 'identifiers', list('reference'), optional).
star_field('org.starintel/core@1/person', 'misc', list('map'), optional).
star_field('org.starintel/core@1/person', 'etype', 'string', optional).
star_field('org.starintel/core@1/person', 'eid', 'string', optional).
star_document('org.starintel/core@1/relation').
star_extends('org.starintel/core@1/relation', 'org.starintel/core@1/document').
star_field('org.starintel/core@1/relation', 'id', 'org.starintel/core@1/document-id', required).
star_field('org.starintel/core@1/relation', 'rev', 'string', optional).
star_field('org.starintel/core@1/relation', 'dataset', 'string', required).
star_field('org.starintel/core@1/relation', 'dtype', 'string', required).
star_field('org.starintel/core@1/relation', 'schemaVersion', 'string', required).
star_field('org.starintel/core@1/relation', 'externalIds', 'map', optional).
star_field('org.starintel/core@1/relation', 'aliases', list('string'), optional).
star_field('org.starintel/core@1/relation', 'sources', list('reference'), optional).
star_field('org.starintel/core@1/relation', 'sourceUrls', list('org.starintel/core@1/uri'), optional).
star_field('org.starintel/core@1/relation', 'sourceRecordIds', list('string'), optional).
star_field('org.starintel/core@1/relation', 'sourceKinds', list('org.starintel/core@1/source-kind'), optional).
star_field('org.starintel/core@1/relation', 'sourceLicense', 'string', optional).
star_field('org.starintel/core@1/relation', 'sourceTerms', 'org.starintel/core@1/uri', optional).
star_field('org.starintel/core@1/relation', 'sourceRetrievedAt', 'org.starintel/core@1/unix-time', optional).
star_field('org.starintel/core@1/relation', 'collectedAt', 'org.starintel/core@1/unix-time', optional).
star_field('org.starintel/core@1/relation', 'observedAt', 'org.starintel/core@1/unix-time', optional).
star_field('org.starintel/core@1/relation', 'firstSeenAt', 'org.starintel/core@1/unix-time', optional).
star_field('org.starintel/core@1/relation', 'lastSeenAt', 'org.starintel/core@1/unix-time', optional).
star_field('org.starintel/core@1/relation', 'createdAt', 'org.starintel/core@1/unix-time', optional).
star_field('org.starintel/core@1/relation', 'updatedAt', 'org.starintel/core@1/unix-time', optional).
star_field('org.starintel/core@1/relation', 'validFrom', 'org.starintel/core@1/unix-time', optional).
star_field('org.starintel/core@1/relation', 'validUntil', 'org.starintel/core@1/unix-time', optional).
star_field('org.starintel/core@1/relation', 'expiresAt', 'org.starintel/core@1/unix-time', optional).
star_field('org.starintel/core@1/relation', 'collector', 'string', optional).
star_field('org.starintel/core@1/relation', 'collectorVersion', 'string', optional).
star_field('org.starintel/core@1/relation', 'collectionMethod', 'string', optional).
star_field('org.starintel/core@1/relation', 'collectionStatus', 'org.starintel/core@1/collection-status', optional).
star_field('org.starintel/core@1/relation', 'runId', 'string', optional).
star_field('org.starintel/core@1/relation', 'correlationId', 'string', optional).
star_field('org.starintel/core@1/relation', 'causationId', 'string', optional).
star_field('org.starintel/core@1/relation', 'parentId', 'org.starintel/core@1/document-id', optional).
star_field('org.starintel/core@1/relation', 'rootId', 'org.starintel/core@1/document-id', optional).
star_field('org.starintel/core@1/relation', 'confidence', 'org.starintel/core@1/confidence-score', optional).
star_field('org.starintel/core@1/relation', 'confidenceBasis', 'string', optional).
star_field('org.starintel/core@1/relation', 'qualityScore', 'org.starintel/core@1/confidence-score', optional).
star_field('org.starintel/core@1/relation', 'completenessScore', 'org.starintel/core@1/confidence-score', optional).
star_field('org.starintel/core@1/relation', 'verificationStatus', 'string', optional).
star_field('org.starintel/core@1/relation', 'verifiedAt', 'org.starintel/core@1/unix-time', optional).
star_field('org.starintel/core@1/relation', 'verifiedBy', 'string', optional).
star_field('org.starintel/core@1/relation', 'provenance', 'map', optional).
star_field('org.starintel/core@1/relation', 'chainOfCustody', list('map'), optional).
star_field('org.starintel/core@1/relation', 'transformHistory', list('map'), optional).
star_field('org.starintel/core@1/relation', 'labels', list('string'), optional).
star_field('org.starintel/core@1/relation', 'tags', list('string'), optional).
star_field('org.starintel/core@1/relation', 'topics', list('string'), optional).
star_field('org.starintel/core@1/relation', 'language', 'string', optional).
star_field('org.starintel/core@1/relation', 'jurisdiction', 'string', optional).
star_field('org.starintel/core@1/relation', 'countryCode', 'string', optional).
star_field('org.starintel/core@1/relation', 'regionCode', 'string', optional).
star_field('org.starintel/core@1/relation', 'timezone', 'string', optional).
star_field('org.starintel/core@1/relation', 'sensitivity', 'org.starintel/core@1/sensitivity', optional).
star_field('org.starintel/core@1/relation', 'visibility', 'org.starintel/core@1/visibility', optional).
star_field('org.starintel/core@1/relation', 'owner', 'string', optional).
star_field('org.starintel/core@1/relation', 'accessControl', 'map', optional).
star_field('org.starintel/core@1/relation', 'legalBasis', 'string', optional).
star_field('org.starintel/core@1/relation', 'retentionPolicy', 'string', optional).
star_field('org.starintel/core@1/relation', 'contentType', 'string', optional).
star_field('org.starintel/core@1/relation', 'encoding', 'string', optional).
star_field('org.starintel/core@1/relation', 'sizeBytes', 'integer', optional).
star_field('org.starintel/core@1/relation', 'contentHash', 'string', optional).
star_field('org.starintel/core@1/relation', 'hashAlgorithm', 'org.starintel/core@1/hash-algorithm', optional).
star_field('org.starintel/core@1/relation', 'normalizedHash', 'string', optional).
star_field('org.starintel/core@1/relation', 'raw', 'map', optional).
star_field('org.starintel/core@1/relation', 'rawContent', 'string', optional).
star_field('org.starintel/core@1/relation', 'notes', 'string', optional).
star_field('org.starintel/core@1/relation', 'deleted', 'boolean', optional).
star_field('org.starintel/core@1/relation', 'tombstoneReason', 'string', optional).
star_field('org.starintel/core@1/relation', 'extensions', 'map', optional).
star_field('org.starintel/core@1/relation', 'source', 'reference', required).
star_field('org.starintel/core@1/relation', 'destination', 'reference', required).
star_field('org.starintel/core@1/relation', 'predicate', 'string', required).
star_field('org.starintel/core@1/relation', 'direction', 'org.starintel/core@1/relation-direction', optional).
star_field('org.starintel/core@1/relation', 'inversePredicate', 'string', optional).
star_field('org.starintel/core@1/relation', 'note', 'string', optional).
star_field('org.starintel/core@1/relation', 'evidence', list('reference'), optional).
star_field('org.starintel/core@1/relation', 'weight', 'decimal', optional).
star_field('org.starintel/core@1/relation', 'validAt', 'org.starintel/core@1/unix-time', optional).
star_field('org.starintel/core@1/relation', 'endedAt', 'org.starintel/core@1/unix-time', optional).
star_scalar('org.starintel/face-intel@1/pixel-offset', 'integer').
star_scalar('org.starintel/face-intel@1/pixel-length', 'integer').
star_scalar('org.starintel/face-intel@1/annotation-basis', 'string').
star_enum('org.starintel/face-intel@1/candidate-only').
star_enum_value('org.starintel/face-intel@1/candidate-only', 'candidate').
star_document('org.starintel/face-intel@1/face-observation').
star_extends('org.starintel/face-intel@1/face-observation', 'org.starintel/core@1/document').
star_field('org.starintel/face-intel@1/face-observation', 'id', 'org.starintel/core@1/document-id', required).
star_field('org.starintel/face-intel@1/face-observation', 'rev', 'string', optional).
star_field('org.starintel/face-intel@1/face-observation', 'dataset', 'string', required).
star_field('org.starintel/face-intel@1/face-observation', 'dtype', 'string', required).
star_field('org.starintel/face-intel@1/face-observation', 'schemaVersion', 'string', required).
star_field('org.starintel/face-intel@1/face-observation', 'externalIds', 'map', optional).
star_field('org.starintel/face-intel@1/face-observation', 'aliases', list('string'), optional).
star_field('org.starintel/face-intel@1/face-observation', 'sources', list('reference'), optional).
star_field('org.starintel/face-intel@1/face-observation', 'sourceUrls', list('org.starintel/core@1/uri'), optional).
star_field('org.starintel/face-intel@1/face-observation', 'sourceRecordIds', list('string'), optional).
star_field('org.starintel/face-intel@1/face-observation', 'sourceKinds', list('org.starintel/core@1/source-kind'), optional).
star_field('org.starintel/face-intel@1/face-observation', 'sourceLicense', 'string', optional).
star_field('org.starintel/face-intel@1/face-observation', 'sourceTerms', 'org.starintel/core@1/uri', optional).
star_field('org.starintel/face-intel@1/face-observation', 'sourceRetrievedAt', 'org.starintel/core@1/unix-time', optional).
star_field('org.starintel/face-intel@1/face-observation', 'collectedAt', 'org.starintel/core@1/unix-time', optional).
star_field('org.starintel/face-intel@1/face-observation', 'observedAt', 'org.starintel/core@1/unix-time', optional).
star_field('org.starintel/face-intel@1/face-observation', 'firstSeenAt', 'org.starintel/core@1/unix-time', optional).
star_field('org.starintel/face-intel@1/face-observation', 'lastSeenAt', 'org.starintel/core@1/unix-time', optional).
star_field('org.starintel/face-intel@1/face-observation', 'createdAt', 'org.starintel/core@1/unix-time', optional).
star_field('org.starintel/face-intel@1/face-observation', 'updatedAt', 'org.starintel/core@1/unix-time', optional).
star_field('org.starintel/face-intel@1/face-observation', 'validFrom', 'org.starintel/core@1/unix-time', optional).
star_field('org.starintel/face-intel@1/face-observation', 'validUntil', 'org.starintel/core@1/unix-time', optional).
star_field('org.starintel/face-intel@1/face-observation', 'expiresAt', 'org.starintel/core@1/unix-time', optional).
star_field('org.starintel/face-intel@1/face-observation', 'collector', 'string', optional).
star_field('org.starintel/face-intel@1/face-observation', 'collectorVersion', 'string', optional).
star_field('org.starintel/face-intel@1/face-observation', 'collectionMethod', 'string', optional).
star_field('org.starintel/face-intel@1/face-observation', 'collectionStatus', 'org.starintel/core@1/collection-status', optional).
star_field('org.starintel/face-intel@1/face-observation', 'runId', 'string', optional).
star_field('org.starintel/face-intel@1/face-observation', 'correlationId', 'string', optional).
star_field('org.starintel/face-intel@1/face-observation', 'causationId', 'string', optional).
star_field('org.starintel/face-intel@1/face-observation', 'parentId', 'org.starintel/core@1/document-id', optional).
star_field('org.starintel/face-intel@1/face-observation', 'rootId', 'org.starintel/core@1/document-id', optional).
star_field('org.starintel/face-intel@1/face-observation', 'confidence', 'org.starintel/core@1/confidence-score', optional).
star_field('org.starintel/face-intel@1/face-observation', 'confidenceBasis', 'string', optional).
star_field('org.starintel/face-intel@1/face-observation', 'qualityScore', 'org.starintel/core@1/confidence-score', optional).
star_field('org.starintel/face-intel@1/face-observation', 'completenessScore', 'org.starintel/core@1/confidence-score', optional).
star_field('org.starintel/face-intel@1/face-observation', 'verificationStatus', 'string', optional).
star_field('org.starintel/face-intel@1/face-observation', 'verifiedAt', 'org.starintel/core@1/unix-time', optional).
star_field('org.starintel/face-intel@1/face-observation', 'verifiedBy', 'string', optional).
star_field('org.starintel/face-intel@1/face-observation', 'provenance', 'map', optional).
star_field('org.starintel/face-intel@1/face-observation', 'chainOfCustody', list('map'), optional).
star_field('org.starintel/face-intel@1/face-observation', 'transformHistory', list('map'), optional).
star_field('org.starintel/face-intel@1/face-observation', 'labels', list('string'), optional).
star_field('org.starintel/face-intel@1/face-observation', 'tags', list('string'), optional).
star_field('org.starintel/face-intel@1/face-observation', 'topics', list('string'), optional).
star_field('org.starintel/face-intel@1/face-observation', 'language', 'string', optional).
star_field('org.starintel/face-intel@1/face-observation', 'jurisdiction', 'string', optional).
star_field('org.starintel/face-intel@1/face-observation', 'countryCode', 'string', optional).
star_field('org.starintel/face-intel@1/face-observation', 'regionCode', 'string', optional).
star_field('org.starintel/face-intel@1/face-observation', 'timezone', 'string', optional).
star_field('org.starintel/face-intel@1/face-observation', 'sensitivity', 'org.starintel/core@1/sensitivity', optional).
star_field('org.starintel/face-intel@1/face-observation', 'visibility', 'org.starintel/core@1/visibility', optional).
star_field('org.starintel/face-intel@1/face-observation', 'owner', 'string', optional).
star_field('org.starintel/face-intel@1/face-observation', 'accessControl', 'map', optional).
star_field('org.starintel/face-intel@1/face-observation', 'legalBasis', 'string', optional).
star_field('org.starintel/face-intel@1/face-observation', 'retentionPolicy', 'string', optional).
star_field('org.starintel/face-intel@1/face-observation', 'contentType', 'string', optional).
star_field('org.starintel/face-intel@1/face-observation', 'encoding', 'string', optional).
star_field('org.starintel/face-intel@1/face-observation', 'sizeBytes', 'integer', optional).
star_field('org.starintel/face-intel@1/face-observation', 'contentHash', 'string', optional).
star_field('org.starintel/face-intel@1/face-observation', 'hashAlgorithm', 'org.starintel/core@1/hash-algorithm', optional).
star_field('org.starintel/face-intel@1/face-observation', 'normalizedHash', 'string', optional).
star_field('org.starintel/face-intel@1/face-observation', 'raw', 'map', optional).
star_field('org.starintel/face-intel@1/face-observation', 'rawContent', 'string', optional).
star_field('org.starintel/face-intel@1/face-observation', 'notes', 'string', optional).
star_field('org.starintel/face-intel@1/face-observation', 'deleted', 'boolean', optional).
star_field('org.starintel/face-intel@1/face-observation', 'tombstoneReason', 'string', optional).
star_field('org.starintel/face-intel@1/face-observation', 'extensions', 'map', optional).
star_field('org.starintel/face-intel@1/face-observation', 'picture', 'reference', required).
star_field('org.starintel/face-intel@1/face-observation', 'x', 'org.starintel/face-intel@1/pixel-offset', required).
star_field('org.starintel/face-intel@1/face-observation', 'y', 'org.starintel/face-intel@1/pixel-offset', required).
star_field('org.starintel/face-intel@1/face-observation', 'width', 'org.starintel/face-intel@1/pixel-length', required).
star_field('org.starintel/face-intel@1/face-observation', 'height', 'org.starintel/face-intel@1/pixel-length', required).
star_field('org.starintel/face-intel@1/face-observation', 'annotationBasis', 'org.starintel/face-intel@1/annotation-basis', required).
star_document('org.starintel/face-intel@1/candidate-person').
star_extends('org.starintel/face-intel@1/candidate-person', 'org.starintel/core@1/person').
star_field('org.starintel/face-intel@1/candidate-person', 'id', 'org.starintel/core@1/document-id', required).
star_field('org.starintel/face-intel@1/candidate-person', 'rev', 'string', optional).
star_field('org.starintel/face-intel@1/candidate-person', 'dataset', 'string', required).
star_field('org.starintel/face-intel@1/candidate-person', 'dtype', 'string', required).
star_field('org.starintel/face-intel@1/candidate-person', 'schemaVersion', 'string', required).
star_field('org.starintel/face-intel@1/candidate-person', 'externalIds', 'map', optional).
star_field('org.starintel/face-intel@1/candidate-person', 'aliases', list('string'), optional).
star_field('org.starintel/face-intel@1/candidate-person', 'sources', list('reference'), optional).
star_field('org.starintel/face-intel@1/candidate-person', 'sourceUrls', list('org.starintel/core@1/uri'), optional).
star_field('org.starintel/face-intel@1/candidate-person', 'sourceRecordIds', list('string'), optional).
star_field('org.starintel/face-intel@1/candidate-person', 'sourceKinds', list('org.starintel/core@1/source-kind'), optional).
star_field('org.starintel/face-intel@1/candidate-person', 'sourceLicense', 'string', optional).
star_field('org.starintel/face-intel@1/candidate-person', 'sourceTerms', 'org.starintel/core@1/uri', optional).
star_field('org.starintel/face-intel@1/candidate-person', 'sourceRetrievedAt', 'org.starintel/core@1/unix-time', optional).
star_field('org.starintel/face-intel@1/candidate-person', 'collectedAt', 'org.starintel/core@1/unix-time', optional).
star_field('org.starintel/face-intel@1/candidate-person', 'observedAt', 'org.starintel/core@1/unix-time', optional).
star_field('org.starintel/face-intel@1/candidate-person', 'firstSeenAt', 'org.starintel/core@1/unix-time', optional).
star_field('org.starintel/face-intel@1/candidate-person', 'lastSeenAt', 'org.starintel/core@1/unix-time', optional).
star_field('org.starintel/face-intel@1/candidate-person', 'createdAt', 'org.starintel/core@1/unix-time', optional).
star_field('org.starintel/face-intel@1/candidate-person', 'updatedAt', 'org.starintel/core@1/unix-time', optional).
star_field('org.starintel/face-intel@1/candidate-person', 'validFrom', 'org.starintel/core@1/unix-time', optional).
star_field('org.starintel/face-intel@1/candidate-person', 'validUntil', 'org.starintel/core@1/unix-time', optional).
star_field('org.starintel/face-intel@1/candidate-person', 'expiresAt', 'org.starintel/core@1/unix-time', optional).
star_field('org.starintel/face-intel@1/candidate-person', 'collector', 'string', optional).
star_field('org.starintel/face-intel@1/candidate-person', 'collectorVersion', 'string', optional).
star_field('org.starintel/face-intel@1/candidate-person', 'collectionMethod', 'string', optional).
star_field('org.starintel/face-intel@1/candidate-person', 'collectionStatus', 'org.starintel/core@1/collection-status', optional).
star_field('org.starintel/face-intel@1/candidate-person', 'runId', 'string', optional).
star_field('org.starintel/face-intel@1/candidate-person', 'correlationId', 'string', optional).
star_field('org.starintel/face-intel@1/candidate-person', 'causationId', 'string', optional).
star_field('org.starintel/face-intel@1/candidate-person', 'parentId', 'org.starintel/core@1/document-id', optional).
star_field('org.starintel/face-intel@1/candidate-person', 'rootId', 'org.starintel/core@1/document-id', optional).
star_field('org.starintel/face-intel@1/candidate-person', 'confidence', 'org.starintel/core@1/confidence-score', optional).
star_field('org.starintel/face-intel@1/candidate-person', 'confidenceBasis', 'string', optional).
star_field('org.starintel/face-intel@1/candidate-person', 'qualityScore', 'org.starintel/core@1/confidence-score', optional).
star_field('org.starintel/face-intel@1/candidate-person', 'completenessScore', 'org.starintel/core@1/confidence-score', optional).
star_field('org.starintel/face-intel@1/candidate-person', 'verificationStatus', 'string', optional).
star_field('org.starintel/face-intel@1/candidate-person', 'verifiedAt', 'org.starintel/core@1/unix-time', optional).
star_field('org.starintel/face-intel@1/candidate-person', 'verifiedBy', 'string', optional).
star_field('org.starintel/face-intel@1/candidate-person', 'provenance', 'map', optional).
star_field('org.starintel/face-intel@1/candidate-person', 'chainOfCustody', list('map'), optional).
star_field('org.starintel/face-intel@1/candidate-person', 'transformHistory', list('map'), optional).
star_field('org.starintel/face-intel@1/candidate-person', 'labels', list('string'), optional).
star_field('org.starintel/face-intel@1/candidate-person', 'tags', list('string'), optional).
star_field('org.starintel/face-intel@1/candidate-person', 'topics', list('string'), optional).
star_field('org.starintel/face-intel@1/candidate-person', 'language', 'string', optional).
star_field('org.starintel/face-intel@1/candidate-person', 'jurisdiction', 'string', optional).
star_field('org.starintel/face-intel@1/candidate-person', 'countryCode', 'string', optional).
star_field('org.starintel/face-intel@1/candidate-person', 'regionCode', 'string', optional).
star_field('org.starintel/face-intel@1/candidate-person', 'timezone', 'string', optional).
star_field('org.starintel/face-intel@1/candidate-person', 'sensitivity', 'org.starintel/core@1/sensitivity', optional).
star_field('org.starintel/face-intel@1/candidate-person', 'visibility', 'org.starintel/core@1/visibility', optional).
star_field('org.starintel/face-intel@1/candidate-person', 'owner', 'string', optional).
star_field('org.starintel/face-intel@1/candidate-person', 'accessControl', 'map', optional).
star_field('org.starintel/face-intel@1/candidate-person', 'legalBasis', 'string', optional).
star_field('org.starintel/face-intel@1/candidate-person', 'retentionPolicy', 'string', optional).
star_field('org.starintel/face-intel@1/candidate-person', 'contentType', 'string', optional).
star_field('org.starintel/face-intel@1/candidate-person', 'encoding', 'string', optional).
star_field('org.starintel/face-intel@1/candidate-person', 'sizeBytes', 'integer', optional).
star_field('org.starintel/face-intel@1/candidate-person', 'contentHash', 'string', optional).
star_field('org.starintel/face-intel@1/candidate-person', 'hashAlgorithm', 'org.starintel/core@1/hash-algorithm', optional).
star_field('org.starintel/face-intel@1/candidate-person', 'normalizedHash', 'string', optional).
star_field('org.starintel/face-intel@1/candidate-person', 'raw', 'map', optional).
star_field('org.starintel/face-intel@1/candidate-person', 'rawContent', 'string', optional).
star_field('org.starintel/face-intel@1/candidate-person', 'notes', 'string', optional).
star_field('org.starintel/face-intel@1/candidate-person', 'deleted', 'boolean', optional).
star_field('org.starintel/face-intel@1/candidate-person', 'tombstoneReason', 'string', optional).
star_field('org.starintel/face-intel@1/candidate-person', 'extensions', 'map', optional).
star_field('org.starintel/face-intel@1/candidate-person', 'fname', 'string', optional).
star_field('org.starintel/face-intel@1/candidate-person', 'mname', 'string', optional).
star_field('org.starintel/face-intel@1/candidate-person', 'lname', 'string', optional).
star_field('org.starintel/face-intel@1/candidate-person', 'fullName', 'string', optional).
star_field('org.starintel/face-intel@1/candidate-person', 'displayName', 'string', optional).
star_field('org.starintel/face-intel@1/candidate-person', 'prefix', 'string', optional).
star_field('org.starintel/face-intel@1/candidate-person', 'suffix', 'string', optional).
star_field('org.starintel/face-intel@1/candidate-person', 'pronouns', 'string', optional).
star_field('org.starintel/face-intel@1/candidate-person', 'bio', 'string', optional).
star_field('org.starintel/face-intel@1/candidate-person', 'dob', 'iso-date', optional).
star_field('org.starintel/face-intel@1/candidate-person', 'dateOfDeath', 'iso-date', optional).
star_field('org.starintel/face-intel@1/candidate-person', 'age', 'integer', optional).
star_field('org.starintel/face-intel@1/candidate-person', 'gender', 'string', optional).
star_field('org.starintel/face-intel@1/candidate-person', 'nationality', list('string'), optional).
star_field('org.starintel/face-intel@1/candidate-person', 'citizenship', list('string'), optional).
star_field('org.starintel/face-intel@1/candidate-person', 'occupation', list('string'), optional).
star_field('org.starintel/face-intel@1/candidate-person', 'employer', list('reference'), optional).
star_field('org.starintel/face-intel@1/candidate-person', 'education', list('map'), optional).
star_field('org.starintel/face-intel@1/candidate-person', 'skills', list('string'), optional).
star_field('org.starintel/face-intel@1/candidate-person', 'interests', list('string'), optional).
star_field('org.starintel/face-intel@1/candidate-person', 'region', 'string', optional).
star_field('org.starintel/face-intel@1/candidate-person', 'addresses', list('reference'), optional).
star_field('org.starintel/face-intel@1/candidate-person', 'emails', list('reference'), optional).
star_field('org.starintel/face-intel@1/candidate-person', 'phones', list('reference'), optional).
star_field('org.starintel/face-intel@1/candidate-person', 'accounts', list('reference'), optional).
star_field('org.starintel/face-intel@1/candidate-person', 'images', list('reference'), optional).
star_field('org.starintel/face-intel@1/candidate-person', 'identifiers', list('reference'), optional).
star_field('org.starintel/face-intel@1/candidate-person', 'misc', list('map'), optional).
star_field('org.starintel/face-intel@1/candidate-person', 'etype', 'string', optional).
star_field('org.starintel/face-intel@1/candidate-person', 'eid', 'string', optional).
star_field('org.starintel/face-intel@1/candidate-person', 'candidateStatus', 'org.starintel/face-intel@1/candidate-only', required).
star_field('org.starintel/face-intel@1/candidate-person', 'annotationBasis', 'org.starintel/face-intel@1/annotation-basis', required).
star_field('org.starintel/face-intel@1/candidate-person', 'evidenceReferences', list('reference'), optional).
star_document('org.starintel/face-intel@1/face-person-candidate').
star_extends('org.starintel/face-intel@1/face-person-candidate', 'org.starintel/core@1/relation').
star_field('org.starintel/face-intel@1/face-person-candidate', 'id', 'org.starintel/core@1/document-id', required).
star_field('org.starintel/face-intel@1/face-person-candidate', 'rev', 'string', optional).
star_field('org.starintel/face-intel@1/face-person-candidate', 'dataset', 'string', required).
star_field('org.starintel/face-intel@1/face-person-candidate', 'dtype', 'string', required).
star_field('org.starintel/face-intel@1/face-person-candidate', 'schemaVersion', 'string', required).
star_field('org.starintel/face-intel@1/face-person-candidate', 'externalIds', 'map', optional).
star_field('org.starintel/face-intel@1/face-person-candidate', 'aliases', list('string'), optional).
star_field('org.starintel/face-intel@1/face-person-candidate', 'sources', list('reference'), optional).
star_field('org.starintel/face-intel@1/face-person-candidate', 'sourceUrls', list('org.starintel/core@1/uri'), optional).
star_field('org.starintel/face-intel@1/face-person-candidate', 'sourceRecordIds', list('string'), optional).
star_field('org.starintel/face-intel@1/face-person-candidate', 'sourceKinds', list('org.starintel/core@1/source-kind'), optional).
star_field('org.starintel/face-intel@1/face-person-candidate', 'sourceLicense', 'string', optional).
star_field('org.starintel/face-intel@1/face-person-candidate', 'sourceTerms', 'org.starintel/core@1/uri', optional).
star_field('org.starintel/face-intel@1/face-person-candidate', 'sourceRetrievedAt', 'org.starintel/core@1/unix-time', optional).
star_field('org.starintel/face-intel@1/face-person-candidate', 'collectedAt', 'org.starintel/core@1/unix-time', optional).
star_field('org.starintel/face-intel@1/face-person-candidate', 'observedAt', 'org.starintel/core@1/unix-time', optional).
star_field('org.starintel/face-intel@1/face-person-candidate', 'firstSeenAt', 'org.starintel/core@1/unix-time', optional).
star_field('org.starintel/face-intel@1/face-person-candidate', 'lastSeenAt', 'org.starintel/core@1/unix-time', optional).
star_field('org.starintel/face-intel@1/face-person-candidate', 'createdAt', 'org.starintel/core@1/unix-time', optional).
star_field('org.starintel/face-intel@1/face-person-candidate', 'updatedAt', 'org.starintel/core@1/unix-time', optional).
star_field('org.starintel/face-intel@1/face-person-candidate', 'validFrom', 'org.starintel/core@1/unix-time', optional).
star_field('org.starintel/face-intel@1/face-person-candidate', 'validUntil', 'org.starintel/core@1/unix-time', optional).
star_field('org.starintel/face-intel@1/face-person-candidate', 'expiresAt', 'org.starintel/core@1/unix-time', optional).
star_field('org.starintel/face-intel@1/face-person-candidate', 'collector', 'string', optional).
star_field('org.starintel/face-intel@1/face-person-candidate', 'collectorVersion', 'string', optional).
star_field('org.starintel/face-intel@1/face-person-candidate', 'collectionMethod', 'string', optional).
star_field('org.starintel/face-intel@1/face-person-candidate', 'collectionStatus', 'org.starintel/core@1/collection-status', optional).
star_field('org.starintel/face-intel@1/face-person-candidate', 'runId', 'string', optional).
star_field('org.starintel/face-intel@1/face-person-candidate', 'correlationId', 'string', optional).
star_field('org.starintel/face-intel@1/face-person-candidate', 'causationId', 'string', optional).
star_field('org.starintel/face-intel@1/face-person-candidate', 'parentId', 'org.starintel/core@1/document-id', optional).
star_field('org.starintel/face-intel@1/face-person-candidate', 'rootId', 'org.starintel/core@1/document-id', optional).
star_field('org.starintel/face-intel@1/face-person-candidate', 'confidence', 'org.starintel/core@1/confidence-score', optional).
star_field('org.starintel/face-intel@1/face-person-candidate', 'confidenceBasis', 'string', optional).
star_field('org.starintel/face-intel@1/face-person-candidate', 'qualityScore', 'org.starintel/core@1/confidence-score', optional).
star_field('org.starintel/face-intel@1/face-person-candidate', 'completenessScore', 'org.starintel/core@1/confidence-score', optional).
star_field('org.starintel/face-intel@1/face-person-candidate', 'verificationStatus', 'string', optional).
star_field('org.starintel/face-intel@1/face-person-candidate', 'verifiedAt', 'org.starintel/core@1/unix-time', optional).
star_field('org.starintel/face-intel@1/face-person-candidate', 'verifiedBy', 'string', optional).
star_field('org.starintel/face-intel@1/face-person-candidate', 'provenance', 'map', optional).
star_field('org.starintel/face-intel@1/face-person-candidate', 'chainOfCustody', list('map'), optional).
star_field('org.starintel/face-intel@1/face-person-candidate', 'transformHistory', list('map'), optional).
star_field('org.starintel/face-intel@1/face-person-candidate', 'labels', list('string'), optional).
star_field('org.starintel/face-intel@1/face-person-candidate', 'tags', list('string'), optional).
star_field('org.starintel/face-intel@1/face-person-candidate', 'topics', list('string'), optional).
star_field('org.starintel/face-intel@1/face-person-candidate', 'language', 'string', optional).
star_field('org.starintel/face-intel@1/face-person-candidate', 'jurisdiction', 'string', optional).
star_field('org.starintel/face-intel@1/face-person-candidate', 'countryCode', 'string', optional).
star_field('org.starintel/face-intel@1/face-person-candidate', 'regionCode', 'string', optional).
star_field('org.starintel/face-intel@1/face-person-candidate', 'timezone', 'string', optional).
star_field('org.starintel/face-intel@1/face-person-candidate', 'sensitivity', 'org.starintel/core@1/sensitivity', optional).
star_field('org.starintel/face-intel@1/face-person-candidate', 'visibility', 'org.starintel/core@1/visibility', optional).
star_field('org.starintel/face-intel@1/face-person-candidate', 'owner', 'string', optional).
star_field('org.starintel/face-intel@1/face-person-candidate', 'accessControl', 'map', optional).
star_field('org.starintel/face-intel@1/face-person-candidate', 'legalBasis', 'string', optional).
star_field('org.starintel/face-intel@1/face-person-candidate', 'retentionPolicy', 'string', optional).
star_field('org.starintel/face-intel@1/face-person-candidate', 'contentType', 'string', optional).
star_field('org.starintel/face-intel@1/face-person-candidate', 'encoding', 'string', optional).
star_field('org.starintel/face-intel@1/face-person-candidate', 'sizeBytes', 'integer', optional).
star_field('org.starintel/face-intel@1/face-person-candidate', 'contentHash', 'string', optional).
star_field('org.starintel/face-intel@1/face-person-candidate', 'hashAlgorithm', 'org.starintel/core@1/hash-algorithm', optional).
star_field('org.starintel/face-intel@1/face-person-candidate', 'normalizedHash', 'string', optional).
star_field('org.starintel/face-intel@1/face-person-candidate', 'raw', 'map', optional).
star_field('org.starintel/face-intel@1/face-person-candidate', 'rawContent', 'string', optional).
star_field('org.starintel/face-intel@1/face-person-candidate', 'notes', 'string', optional).
star_field('org.starintel/face-intel@1/face-person-candidate', 'deleted', 'boolean', optional).
star_field('org.starintel/face-intel@1/face-person-candidate', 'tombstoneReason', 'string', optional).
star_field('org.starintel/face-intel@1/face-person-candidate', 'extensions', 'map', optional).
star_field('org.starintel/face-intel@1/face-person-candidate', 'source', 'reference', required).
star_field('org.starintel/face-intel@1/face-person-candidate', 'destination', 'reference', required).
star_field('org.starintel/face-intel@1/face-person-candidate', 'predicate', 'string', required).
star_field('org.starintel/face-intel@1/face-person-candidate', 'direction', 'org.starintel/core@1/relation-direction', optional).
star_field('org.starintel/face-intel@1/face-person-candidate', 'inversePredicate', 'string', optional).
star_field('org.starintel/face-intel@1/face-person-candidate', 'note', 'string', optional).
star_field('org.starintel/face-intel@1/face-person-candidate', 'evidence', list('reference'), optional).
star_field('org.starintel/face-intel@1/face-person-candidate', 'weight', 'decimal', optional).
star_field('org.starintel/face-intel@1/face-person-candidate', 'validAt', 'org.starintel/core@1/unix-time', optional).
star_field('org.starintel/face-intel@1/face-person-candidate', 'endedAt', 'org.starintel/core@1/unix-time', optional).
star_field('org.starintel/face-intel@1/face-person-candidate', 'candidateStatus', 'org.starintel/face-intel@1/candidate-only', required).
star_field('org.starintel/face-intel@1/face-person-candidate', 'annotationBasis', 'org.starintel/face-intel@1/annotation-basis', required).
star_field('org.starintel/face-intel@1/face-person-candidate', 'evidenceReferences', list('reference'), optional).
star_message('org.starintel/face-intel@1/store-face-observation').
star_field('org.starintel/face-intel@1/store-face-observation', 'document', 'reference', required).
star_message('org.starintel/face-intel@1/store-candidate-person').
star_field('org.starintel/face-intel@1/store-candidate-person', 'document', 'reference', required).
star_message('org.starintel/face-intel@1/annotate-face-person').
star_field('org.starintel/face-intel@1/annotate-face-person', 'face', 'reference', required).
star_field('org.starintel/face-intel@1/annotate-face-person', 'person', 'reference', required).
star_field('org.starintel/face-intel@1/annotate-face-person', 'annotationBasis', 'org.starintel/face-intel@1/annotation-basis', required).
star_message('org.starintel/face-intel@1/get-face-observation').
star_field('org.starintel/face-intel@1/get-face-observation', 'face', 'reference', required).
