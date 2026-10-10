# StarLang Runtime Providers

Status: design for #151.

A runtime provider describes **where an actor executes**. It does not define a different actor model.

The existing actor semantic split remains:

```text
native
external
```

Provider placement is orthogonal.

## Why a provider layer

The same native StarLang actor should be able to execute:

- inside the host process;
- on another StarLang worker;
- on a Raspberry Pi/StarMesh node;
- in a container/VM;
- as an AWS Lambda function.

Application message contracts must not change because deployment changed.

## Proposed source direction

This is proposed grammar for #151 and is not accepted by the compiler yet.

```lisp
(runtime-provider burst
  (:class serverless
   :profile "burst-default"
   :architectures (arm64 x86-64)
   :streaming optional
   :cold-start-tolerance milliseconds-1000))

(actor enrichment-worker
  (:runtime native
   :provider burst
   :service-uri "star://enrichment:localhost:worker"
   :accepts (org.starintel/enrich@1)
   :produces (org.starintel/enriched@1)
   :restart transient
   :mailbox (bounded 64)
   :capabilities (network databaseRead)))
```

The final spelling must be implemented through the normal Star parser/validator/IR pipeline. Do not encode provider semantics in arbitrary metadata.

Portable source references a logical provider profile. Trusted deployment configuration maps that profile to AWS account/region/function/image/VPC/IAM details.

## Provider IR

A provider requirement should capture:

- logical profile id;
- execution class;
- architecture requirements;
- memory class;
- maximum duration;
- streaming requirement;
- concurrency characteristics;
- local ephemeral storage requirement;
- network/effect requirements;
- package/artifact digest;
- runtime build identity;
- cold-start tolerance;
- required capabilities.

It must not contain:

- AWS access keys;
- secret keys/session tokens;
- account credentials;
- private ARNs;
- VPC/subnet/security-group ids;
- secret values.

## Provider protocol

A provider implementation supports a generic lifecycle:

```text
prepare
health
admit
invoke
cancel
stream
settle
close
```

The payload is a canonical Star Actor2Actor invocation.

Provider output is a canonical Star reply/error/stream outcome.

## AWS Lambda provider

AWS Lambda is the first concrete serverless provider.

Target:

```text
provided.al2023
arm64 + x86_64
custom Common Lisp / StarLang runtime
Lambda Runtime API
```

The runtime bootstrap initializes immutable runtime/compiler/actor artifacts once per execution environment, then handles individual Actor2Actor invocations.

### Invocation loop

Conceptually:

```text
init StarLang runtime
  |
GET next Lambda invocation
  |
decode canonical Actor2Actor envelope
  |
install fresh request authority context
  |
dispatch to actor
  |
validate typed terminal result
  |
POST response/error
  |
clear request authority/state aliases
  |
next invocation
```

Warm execution environment reuse is an optimization only. Durable actor state must use Star journaling/storage; correctness cannot depend on Lambda process memory surviving.

### Response streaming

When the actor/provider contract requires streaming, the provider may use Lambda response streaming, but the Star stream sequence/order/backpressure contract remains authoritative.

### Timeouts

Effective deadline:

```text
min(
  Star message deadline,
  provider invocation deadline,
  configured actor operation deadline
)
```

Completion after the effective deadline cannot be published as successful.

### Retry and writes

AWS/provider retries must never bypass Star idempotency.

For write effects:

- keyed/idempotent operations may replay under the same identity;
- preconditioned operations re-check their precondition;
- unknown/non-replayable outcomes remain `outcomeUnknown` until reconciled.

### Isolation

Every invocation gets fresh:

- principal context;
- tenant context;
- correlation/trace context;
- per-invocation mutable actor transition state.

Warm invocation reuse must not leak any of those to a subsequent tenant/request.

## Other providers

The same contract should later support:

```text
local
remote-worker
star-mesh
container
vm
aws-lambda
other-serverless
```

Provider selection is runtime/deployment policy. Actor semantics stay StarLang.
