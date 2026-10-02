from __future__ import annotations

import hashlib
import json
from dataclasses import dataclass
from enum import StrEnum
from typing import Any, Iterable


class Outcome(StrEnum):
    SUCCESS = "success"
    TRANSIENT = "transient"
    PERMANENT = "permanent"


class DeliveryAction(StrEnum):
    ACK = "ack"
    NACK_REQUEUE = "nack-requeue"
    NACK_DROP = "nack-drop"


@dataclass(frozen=True, slots=True)
class RequiredSettlement:
    name: str
    outcome: Outcome
    detail: str | None = None


@dataclass(frozen=True, slots=True)
class DeliveryDecision:
    action: DeliveryAction
    required: tuple[RequiredSettlement, ...]
    reason: str


def settle_required_outputs(
    outputs: Iterable[RequiredSettlement], *, redelivered: bool
) -> DeliveryDecision:
    """Apply the public BBPD-style required-output settlement invariant.

    A target completes only after every required output settles successfully.
    Permanent failure never requeues. Transient failure gets at most one broker
    redelivery; a transient failure on redelivery is dropped/dead-lettered by the
    caller rather than creating an unbounded poison loop.
    """

    required = tuple(outputs)
    if not required:
        return DeliveryDecision(DeliveryAction.ACK, required, "no required outputs")

    permanent = [item for item in required if item.outcome is Outcome.PERMANENT]
    if permanent:
        return DeliveryDecision(
            DeliveryAction.NACK_DROP,
            required,
            f"permanent required-output failure: {permanent[0].name}",
        )

    transient = [item for item in required if item.outcome is Outcome.TRANSIENT]
    if transient:
        action = DeliveryAction.NACK_DROP if redelivered else DeliveryAction.NACK_REQUEUE
        reason = (
            "transient required-output failure on redelivery"
            if redelivered
            else "transient required-output failure; one retry allowed"
        )
        return DeliveryDecision(action, required, reason)

    return DeliveryDecision(DeliveryAction.ACK, required, "all required outputs settled")


def canonical_json(value: Any) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False)


def deterministic_result_id(
    *, worker_id: str, target_id: str, kind: str, payload: Any
) -> str:
    """Create a replay-stable identity without depending on process timing."""

    basis = canonical_json(
        {
            "worker": worker_id,
            "target": target_id,
            "kind": kind,
            "payload": payload,
        }
    )
    digest = hashlib.sha256(basis.encode("utf-8")).hexdigest()
    return f"beast:{worker_id}:{kind}:{digest}"


def provenance_record(
    *,
    worker_id: str,
    target_id: str,
    source_uri: str,
    payload: Any,
    correlation_id: str,
    causation_id: str | None,
) -> dict[str, Any]:
    """Build the transport-neutral provenance core every worker can preserve."""

    return {
        "worker": worker_id,
        "target_id": target_id,
        "source_uri": source_uri,
        "correlation_id": correlation_id,
        "causation_id": causation_id,
        "content_sha256": hashlib.sha256(canonical_json(payload).encode("utf-8")).hexdigest(),
    }
