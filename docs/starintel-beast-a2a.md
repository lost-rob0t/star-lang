# StarIntel Beast: A2A worker architecture

## Goal

Build a resumable StarIntel collection and verification fabric capable of growing to
100,000,000 documents without making any one worker, queue, or database the global
serialization point.

The public StarLang repository owns portable worker contracts. `starintel-biz` owns
commercial policy, entitlements, tenant budgets, and runtime enablement.
`starintel-infra` owns deployment. Quasar owns user-facing workflow composition.
StarIntel Server remains document/target/auth authority.

## Inter-agent protocol

The public worker catalog targets Agent2Agent (A2A) protocol 1.0.0. Deployment must
materialize a valid Agent Card for each worker from its StarLang manifest plus its
configured HTTPS endpoint and authentication policy. Star `star://` service URIs are
stable logical identities; deployment URLs are not committed to this repository.

A2A tasks carry only bounded work descriptors, document references, checkpoints, and
artifacts. Large payloads move through the StarIntel document/object-storage plane.
Workers must not smuggle credentials in task metadata or artifacts.

Required behavior:

- capability discovery from Agent Cards;
- authenticated task creation;
- streaming status for long jobs where available;
- resumable checkpoints and idempotency keys;
- correlation/causation identifiers preserved across A2A and Star message envelopes;
- bounded retries with dead-letter/review outcomes rather than infinite replay;
- cancellation and deadline propagation;
- tenant/dataset identity never inferred from user-controlled payload fields.

## Ten workers

1. `beast-orchestrator` partitions work, delegates tasks, applies backpressure and
   resumes from durable checkpoints.
2. `gov-catalog` discovers public local-government catalogs and datasets. First-class
   adapters target Socrata/SODA, CKAN Action API, ArcGIS data services and direct
   government bulk feeds.
3. `gov-harvester` performs bulk and incremental reads, partitions large datasets and
   emits raw document records plus checkpoints.
4. `challenge-broker` handles access challenges through human review or explicitly
   authorized challenge providers. It is not a protection-bypass service.
5. `proxy-egress` centralizes tenant-isolated egress, rate policy, health and cost
   accounting. Proxy rotation must not be used to evade source rate limits or blocks.
6. `recon-domain` ports the useful Star-BBP domain-program model to public network
   metadata collection: DNS, RDAP, certificate transparency and HTTP metadata.
7. `normalize-provenance` converts source records to canonical StarIntel documents,
   stores source URLs/identifiers, timestamps and hashes, and rejects invalid schema.
8. `archive-preserve` preserves originals and derived archival metadata, including
   hashes, timestamps and chain-of-custody records.
9. `corroborate-verify` compares independent sources, records contradictions and
   confidence evidence, and routes weak/ambiguous results to review.
10. `graph-index-publisher` performs graph/search projection, dataset accounting and
    final publish checkpoints after authoritative document acceptance.

## Default OSINT workflow

The default workflow follows a collection-plan -> acquire -> preserve -> normalize ->
corroborate -> publish loop. Discovery and collection are separate so source inventory
can be reviewed before expensive harvesting. Preservation happens before enrichment so
later analysis can always point back to original material. Corroboration records both
supporting and contradictory evidence; confidence is data, not a permission grant.

Every result should retain enough provenance for another researcher to independently
reproduce how it was obtained. Online material that may change should be archived as
early as practical. Deduplication never deletes provenance: multiple source records may
resolve to one canonical entity/document while retaining independent lineage edges.

## Scale model

100M is a corpus objective, not one transaction. The orchestrator partitions by
`tenant/dataset/source/jurisdiction/time-window/shard`, and each partition has a durable
checkpoint. Collection uses bounded queues and backpressure. Bulk APIs are preferred
over page scraping when an official machine-readable export exists.

At 100 documents/second sustained, 100M documents is about 11.6 days of pure ingest; at
1,000 documents/second it is about 27.8 hours. Real wall-clock time will be dominated by
source limits, transforms, persistence, indexing, verification and retries, so capacity
planning must measure each stage independently rather than treating the ingest endpoint
as the only bottleneck.

The release gate must prove restart/resume, duplicate replay, source throttling, queue
saturation, storage pressure and partial worker failure before increasing concurrency.

## Quasar bundle

Quasar should ship three editable starter graphs once its Morrison-style FBP runtime has
actor/A2A nodes:

- **Local Government Mirror**: jurisdiction -> catalog -> harvester -> preserve ->
  normalize -> verify -> publish.
- **Domain Recon**: domain target -> recon-domain -> normalize -> verify -> graph/index.
- **Auto-Dig Research**: research request -> orchestrator -> fan-out collectors/recon ->
  preserve -> normalize -> corroborate -> publish, with explicit researcher review
  gates for ambiguous findings.

Graph definitions request capabilities; they never grant them. Biz/host policy remains
authoritative for which workers, source families, proxy routes and external spend are
available to a tenant.

## E2E acceptance

A release candidate is not called end-to-end until CI launches StarIntel Server,
Quasar, at least two real A2A worker processes and the persistence dependencies, then
proves:

1. Agent Card discovery and authenticated A2A task creation.
2. A government fixture catalog is discovered and partitioned.
3. Harvest emits documents through the real StarIntel ingest path.
4. A restart between partitions resumes without duplicate accepted documents.
5. Provenance and archive records survive through final publish.
6. A challenge is routed to review/authorized resolution rather than silently bypassed.
7. Proxy policy rejects a request that would violate configured source/tenant limits.
8. Recon output traverses the same normalization/verification/publish path.
9. Correlation and idempotency identifiers survive A2A -> StarIntel -> storage.
10. Quasar shows the workflow/run state and can cancel a running task.

## References

- A2A Protocol 1.0.0 specification: https://a2a-protocol.org/latest/specification
- Socrata developer documentation: https://dev.socrata.com/docs/endpoints
- CKAN Action API: https://docs.ckan.org/en/latest/api/
- Bellingcat guidance on reproducible sourcing and archiving:
  https://www.bellingcat.com/resources/2024/04/25/oshit-seven-deadly-sins-of-bad-open-source-research/
- Bellingcat Auto Archiver architecture and preservation practices:
  https://www.bellingcat.com/resources/2025/08/13/the-open-source-tool-that-has-preserved-150000-pieces-of-online-evidence/
