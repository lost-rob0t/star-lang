# star-a2a

Reference A2A v1 host for StarLang external actors.

StarLang defines actor contracts and projects Agent Cards; this package exposes those
contracts through the official A2A Python SDK. Each Beast endpoint is backed by its own
Pykka worker actor/mailbox. Business policy, credentials, tenant entitlements, and
endpoint selection stay outside this package.

## Beast reference host

From the StarLang repository root:

```sh
python -m pip install -e ./star-a2a
STAR_A2A_CATALOG=catalog/starintel/beast-workers.json \
  python -m star_a2a
```

Defaults bind to `127.0.0.1:9797`. Set `STAR_A2A_PUBLIC_URL` when the advertised
Agent Card URL differs from the bind address. Production deployment should advertise
HTTPS and apply authentication at the host/gateway according to Biz and Infra policy.

Each worker is mounted at `/a2a/<worker-id>` and publishes its Agent Card at
`/a2a/<worker-id>/.well-known/agent-card.json`.

The A2A reference executor proves transport, independent actor mailboxes, lifecycle,
and nested delegation. It is not the production StarIntel persistence plane. Production
worker backends plug into the same contracts and retain StarIntel authorization,
provenance, idempotency, checkpointing, source rate policy, and tenant isolation.

## Local-government adapters

`star_a2a.government` provides bounded request/page contracts for the first public-data
sources used by `gov-catalog` and `gov-harvester`:

- Socrata catalog discovery and SODA resource pages;
- CKAN `package_search` catalog pages;
- ArcGIS portal search and FeatureServer query pages.

The adapters require HTTPS, reject credentials in source URLs, bound page sizes, and
return explicit cursors for checkpointing. They only construct/parse source requests;
deployment-owned HTTP egress still enforces host allowlists, tenant policy, deadlines,
rate limits, byte limits, retries, proxy routing, and credentials.

## BBPD semantics port

`star_a2a.settlement` ports the useful runtime invariants from the earlier BBPD design
without copying its private scanner stack:

- a target succeeds only after every required output settles;
- permanent failures never requeue;
- transient required-output failure gets at most one redelivery;
- deterministic result identity is based on canonical content, not process timing;
- correlation/causation/source provenance survives retries.

The public default `recon-domain` contract is deliberately limited to DNS, RDAP,
certificate-transparency, and HTTP metadata. Higher-impact scanning belongs behind a
separate explicit authorization/capability boundary.

## Access policy primitives

`star_a2a.access_policy` keeps challenge and proxy behavior fail closed:

- tasks select only opaque, host-configured proxy route IDs; they cannot inject raw
  proxy endpoints;
- route policy binds tenant and source host and carries an explicit rate ceiling;
- challenge tasks cannot carry provider keys/site keys/tokens;
- only host-configured provider IDs can be selected; everything else becomes human
  review.

## Verification

`tests/test_beast_e2e.py` mounts all ten workers through the official A2A v1 route
stack, proves ten live Pykka actor refs, discovers every Agent Card, sends a valid
`SendMessage` request to each worker, and proves nested A2A delegation from
`beast-orchestrator` to `gov-catalog`.

Additional hermetic tests cover government adapter pagination/bounds, proxy/challenge
policy, BBPD-style settlement, deterministic identities, and provenance.

The full-system release gate remains stricter: Quasar, StarIntel Server, persistence,
and production worker processes must also be exercised before a deployment is called
fully end-to-end or a 100M corpus claim is made.

## Safety boundary

The public challenge broker supports human review or explicitly authorized challenge
providers. It is not an anti-bot bypass mechanism. Proxy egress centralizes approved
routing, health, tenant isolation, accounting, and source rate policy; it must not be
used to evade blocks or source throttles.
