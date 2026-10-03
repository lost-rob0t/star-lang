# StarIntel 0.10.1 network-capture migration

`specs/starintel/0.10.1/core.star` is the schema authority. The historical
`starintel-doc` 0.9.2 network-capture profile and the Python copy in
`starintel-gpt-auto-dig` are compatibility inputs, not independent 0.10.1
schema authorities.

## Canonical 0.10.1 records

The StarLang core owns first-class:

- `http-transaction`;
- `web-capture`;
- `pcap-capture`;
- `network-conversation`;
- `network-device`;
- `wireless-network`;
- `wireless-station`.

Canonical wire keys are lowerCamelCase. HTTP body bytes, DOM bytes, and
screenshot bytes remain artifact-backed; ordinary documents carry only
metadata, hashes, and artifact URIs.

Request/response header maps are permitted only after producer-side redaction.
Credentials, cookies, bearer/API tokens, proxy credentials, CAPTCHA answers,
and raw browser-session secrets must not be persisted in ordinary StarIntel
documents.

## Retired 0.9.2 profile

Legacy 0.9.2 network-capture documents used the 0.9.0 envelope, snake_case
keys, and nested `data`. The 0.10.1 compatibility contract already specifies:

1. snake_case to lowerCamelCase normalization;
2. nested `data` merge into the canonical document;
3. canonical 0.10.1 output only;
4. quarantine on ambiguous collisions or canonical-validation failure.

Capture-specific ISO-8601 timestamp strings (`startedAt`, `endedAt`, and
`capturedAt`) remain textual in these two contracts so existing evidence can
migrate without lossy timestamp coercion. New producers should additionally
populate the canonical envelope's `observedAt` when an epoch timestamp is
available.

## Downstream release gate

A downstream repository is not 0.10.1-ready merely because it changes a
version constant. It must:

1. pin an exact StarLang commit/release lock;
2. validate emitted documents against the generated StarLang schema;
3. emit lowerCamelCase canonical output;
4. keep an explicit legacy-input path where required;
5. reject or quarantine ambiguous legacy field collisions;
6. prove sensitive HTTP headers are redacted before persistence;
7. run exact-head CI against the pinned generated artifacts.

For `star-bbpd`, the current 0.9.2 `starintel-doc` dependency is therefore a
release blocker until its HTTP/browser capture boundary is migrated to this
generated contract. For `starintel-gpt-auto-dig`, the Python 0.10.1 schema
copy is a migration implementation only and must not supersede StarLang.
