# star-a2a

Reference A2A v1 host for StarLang external actors.

It is deliberately thin: StarLang defines actor contracts and projects Agent Cards;
the host exposes those contracts through the official A2A Python SDK. Business policy,
credentials, tenant entitlements, and endpoint selection stay outside this package.

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

The reference executor is a transport proof, not a production collector. Real worker
backends plug into the same contracts and must retain StarIntel authorization,
provenance, idempotency, checkpointing, source rate policy, and tenant isolation.

## Verification

`tests/test_beast_e2e.py` mounts all ten workers through the official A2A v1 route
stack, discovers every Agent Card, sends a valid `SendMessage` request to each worker,
and proves a nested A2A delegation from `beast-orchestrator` to `gov-catalog`.

The full-system release gate remains stricter: Quasar, StarIntel Server, persistence,
and real worker processes must also be exercised before a deployment is called fully
end-to-end.

## Safety boundary

The public challenge broker supports human review or explicitly authorized challenge
providers. It is not an anti-bot bypass mechanism. Proxy egress centralizes approved
routing, health, tenant isolation, accounting, and source rate policy; it must not be
used to evade blocks or source throttles.
