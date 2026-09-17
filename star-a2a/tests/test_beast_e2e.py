from __future__ import annotations

import json
import unittest
import uuid
from pathlib import Path
from typing import Any

import httpx

from star_a2a.host import build_app, load_beast_catalog

ROOT = Path(__file__).resolve().parents[2]
CATALOG = ROOT / "catalog" / "starintel" / "beast-workers.json"


def message_request(worker_id: str, text: str) -> dict[str, Any]:
    return {
        "jsonrpc": "2.0",
        "id": f"rpc-{worker_id}-{uuid.uuid4()}",
        "method": "SendMessage",
        "params": {
            "message": {
                "messageId": f"msg-{worker_id}-{uuid.uuid4()}",
                "role": "ROLE_USER",
                "parts": [{"text": text}],
            }
        },
    }


class BeastA2AE2E(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self) -> None:
        self.catalog = load_beast_catalog(CATALOG)
        self.client_box: dict[str, httpx.AsyncClient] = {}

        async def delegate(worker_id: str, text: str) -> dict[str, Any]:
            client = self.client_box["client"]
            response = await client.post(
                f"/a2a/{worker_id}",
                headers={"A2A-Version": "1.0"},
                json=message_request(worker_id, text),
            )
            response.raise_for_status()
            payload = response.json()
            if "error" in payload:
                raise AssertionError(f"delegated A2A call failed: {payload['error']}")
            return {"worker": worker_id, "a2a": "ok"}

        self.app, self.state = build_app(
            self.catalog,
            public_url="http://testserver",
            delegate=delegate,
        )
        self.client = httpx.AsyncClient(
            transport=httpx.ASGITransport(app=self.app),
            base_url="http://testserver",
            timeout=10,
        )
        self.client_box["client"] = self.client

    async def asyncTearDown(self) -> None:
        await self.client.aclose()

    async def test_cards_and_send_message_for_all_ten_workers(self) -> None:
        worker_ids = [worker["id"] for worker in self.catalog["workers"]]
        self.assertEqual(len(worker_ids), 10)
        self.assertEqual(len(set(worker_ids)), 10)

        for worker_id in worker_ids:
            card_response = await self.client.get(
                f"/a2a/{worker_id}/.well-known/agent-card.json"
            )
            self.assertEqual(card_response.status_code, 200, worker_id)
            card = card_response.json()
            self.assertEqual(card["name"], worker_id)
            self.assertEqual(card["supportedInterfaces"][0]["protocolVersion"], "1.0")
            self.assertEqual(card["supportedInterfaces"][0]["protocolBinding"], "JSONRPC")
            self.assertGreaterEqual(len(card["skills"]), 1)

        for worker_id in worker_ids:
            response = await self.client.post(
                f"/a2a/{worker_id}",
                headers={"A2A-Version": "1.0"},
                json=message_request(worker_id, json.dumps({"target": "fixture.local"})),
            )
            self.assertEqual(response.status_code, 200, worker_id)
            payload = response.json()
            self.assertEqual(payload["jsonrpc"], "2.0")
            self.assertNotIn("error", payload)
            self.assertIn("result", payload)

        for worker_id in worker_ids:
            self.assertGreaterEqual(self.state.counts[worker_id], 1, worker_id)

        # The orchestrator performs a real nested A2A SendMessage to gov-catalog.
        self.assertGreaterEqual(self.state.counts["gov-catalog"], 2)
        self.assertEqual(self.state.counts["beast-orchestrator"], 1)

    async def test_v1_required_message_fields_are_present(self) -> None:
        request = message_request("gov-catalog", "fixture")
        self.assertEqual(request["method"], "SendMessage")
        message = request["params"]["message"]
        self.assertTrue(message["messageId"])
        self.assertEqual(message["role"], "ROLE_USER")
        self.assertTrue(message["parts"])


if __name__ == "__main__":
    unittest.main()
