from __future__ import annotations

import unittest

from star_a2a.settlement import (
    DeliveryAction,
    Outcome,
    RequiredSettlement,
    deterministic_result_id,
    provenance_record,
    settle_required_outputs,
)


class SettlementTests(unittest.TestCase):
    def test_all_required_success_acks(self) -> None:
        decision = settle_required_outputs(
            [
                RequiredSettlement("document", Outcome.SUCCESS),
                RequiredSettlement("relation", Outcome.SUCCESS),
            ],
            redelivered=False,
        )
        self.assertEqual(decision.action, DeliveryAction.ACK)

    def test_transient_failure_requeues_once(self) -> None:
        output = [RequiredSettlement("document", Outcome.TRANSIENT)]
        first = settle_required_outputs(output, redelivered=False)
        second = settle_required_outputs(output, redelivered=True)
        self.assertEqual(first.action, DeliveryAction.NACK_REQUEUE)
        self.assertEqual(second.action, DeliveryAction.NACK_DROP)

    def test_permanent_failure_never_requeues(self) -> None:
        decision = settle_required_outputs(
            [RequiredSettlement("document", Outcome.PERMANENT)],
            redelivered=False,
        )
        self.assertEqual(decision.action, DeliveryAction.NACK_DROP)

    def test_result_identity_is_replay_stable(self) -> None:
        one = deterministic_result_id(
            worker_id="recon-domain",
            target_id="target-1",
            kind="observation",
            payload={"b": 2, "a": 1},
        )
        two = deterministic_result_id(
            worker_id="recon-domain",
            target_id="target-1",
            kind="observation",
            payload={"a": 1, "b": 2},
        )
        self.assertEqual(one, two)

    def test_provenance_keeps_correlation_and_causation(self) -> None:
        record = provenance_record(
            worker_id="gov-harvester",
            target_id="target-2",
            source_uri="https://data.example.gov/resource/abcd-1234.json",
            payload={"id": 1},
            correlation_id="corr-1",
            causation_id="cause-1",
        )
        self.assertEqual(record["correlation_id"], "corr-1")
        self.assertEqual(record["causation_id"], "cause-1")
        self.assertEqual(len(record["content_sha256"]), 64)


if __name__ == "__main__":
    unittest.main()
