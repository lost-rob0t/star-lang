# star-logic-adapter-swi

Final Common Lisp ownership for the SWI-Prolog MQI backend boundary.

This slice implements only worker ownership and transport trust: exact executable
identity, embedded MQI startup, UTF-8 byte framing, authentication, MQI version
validation, a repository-owned bootstrap handshake, process-isolated sessions,
health, and orderly shutdown/reaping.

It deliberately does **not** implement `star.logic.query/1`, portable query
operations, fact mutation, tabling, constraints, proofs, cancellation escalation,
or worker pooling/reset.

## Executable and build identity

`make-swi-backend` requires an explicit executable path. It never discovers
`swipl` through ambient `PATH`. The path is resolved to its exact file, the
version is obtained by launching that exact executable with `--version`, and
`backendBuildId` is the SHA-256 digest of the resolved executable bytes. Under
Nix, descriptor metadata also retains the exact store executable path.

Before every session open, the adapter rechecks path, version, and executable
digest. The worker itself then proves the expected version triplet through the
trusted bootstrap predicate. Any mismatch fails closed.

## MQI framing

Outbound commands are trusted adapter-owned Prolog messages encoded using MQI's
UTF-8 byte-count framing. Incoming responses use the same bounded frame header,
with heartbeat bytes handled before the header, but the counted response body is
parsed as JSON rather than reinterpreted as caller-controlled Prolog text.

The decoder accepts both the raw JSON response body emitted by the pinned SWI
runtime and the generic MQI dot/newline suffix when that suffix is present. Frame
length, UTF-8 decoding, and JSON parsing remain bounded and fail closed.

The real integration gate currently proves SWI-Prolog 10.0.2 negotiating MQI
protocol 1.0.

## Trusted bootstrap

`prolog/star_logic_bootstrap.pl` is part of this ASDF system. Its path is derived
internally from ASDF and cannot be supplied by a caller. Its SHA-256 digest is
recorded at backend construction and revalidated immediately before every worker
launch, before any subprocess is spawned. The adapter's private MQI grammar loads
only this file and invokes only its fixed handshake predicate.

There is no exported raw Prolog goal, predicate, consult, or file-loading API.
