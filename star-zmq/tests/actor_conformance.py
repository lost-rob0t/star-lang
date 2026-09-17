"""Black-box tests for the real Nim executable, not actor-runtime proof.

Run explicitly with STAR_ZMQ_ACTOR set. Missing binaries fail, never skip.
"""
from __future__ import annotations

import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

import zmq


class NimActorTests(unittest.TestCase):
    executable: str

    @classmethod
    def setUpClass(cls) -> None:
        configured = os.environ.get("STAR_ZMQ_ACTOR")
        if not configured or not Path(configured).is_file():
            raise RuntimeError("STAR_ZMQ_ACTOR must name the compiled Nim executable")
        cls.executable = configured

    def setUp(self) -> None:
        self.context = zmq.Context()
        self.addCleanup(self.context.term)
        self.socket = self.context.socket(zmq.ROUTER)
        self.addCleanup(self.socket.close, linger=0)
        self.socket.rcvtimeo = 5000
        self.socket.sndtimeo = 5000
        self.socket.router_mandatory = 1
        self.directory = tempfile.TemporaryDirectory(prefix="star-zmq-", dir="/tmp")
        self.addCleanup(self.directory.cleanup)
        self.child: subprocess.Popen[bytes] | None = None
        # Registered last: reap the child before closing the socket/context.
        self.addCleanup(self.stop_child)

    def stop_child(self) -> None:
        if self.child is None:
            return
        if self.child.poll() is None:
            self.child.terminate()
            try:
                self.child.wait(timeout=2)
            except subprocess.TimeoutExpired:
                self.child.kill()
        self.child.wait(timeout=2)

    def start(self, *, tcp: bool = False) -> None:
        endpoint = (
            f"tcp://127.0.0.1:{self.socket.bind_to_random_port('tcp://127.0.0.1')}"
            if tcp else f"ipc://{self.directory.name}/actor.sock"
        )
        if not tcp:
            self.socket.bind(endpoint)
        self.child = subprocess.Popen(
            [self.executable, endpoint, "conformance/7", "nim.echo", "7"],
            stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        route, data = self.socket.recv_multipart()
        self.assertEqual(route, b"conformance/7")
        ready = json.loads(data)
        self.assertEqual(ready["kind"], "event")
        self.assertEqual(ready["messageType"], "star.zmq/ready@1")
        self.assertEqual(ready["payload"], {"generation": 7})
        self.assertEqual(ready["actor"], "nim.echo")
        self.assertEqual(ready["sender"], "nim.echo")

    @staticmethod
    def command(sequence: int = 1) -> dict[str, object]:
        return {
            "starVersion": 1, "kind": "command", "messageId": f"command/{sequence}",
            "messageType": "star.zmq/echo@1", "actor": "nim.echo", "sender": "caller",
            "replyTo": "caller", "correlationId": "shared-correlation", "attempt": 1,
            "idempotencyKey": f"idempotency/{sequence}", "dataset": "fixture",
            "payload": {"text": "snow ☃ / astral 🛰 / é / null\u0000"},
        }

    def request(self, command: dict[str, object]) -> dict[str, object]:
        self.socket.send_multipart([b"conformance/7", json.dumps(command).encode()])
        route, data = self.socket.recv_multipart()
        self.assertEqual(route, b"conformance/7")
        reply = json.loads(data)
        self.assertEqual(reply["actor"], "caller")
        self.assertEqual(reply["sender"], "nim.echo")
        self.assertEqual(reply["causationId"], command["messageId"])
        self.assertEqual(reply["correlationId"], command["correlationId"])
        self.assertEqual(reply["dataset"], command["dataset"])
        return reply

    def normal_session(self, *, tcp: bool) -> None:
        self.start(tcp=tcp)
        reply_ids: set[str] = set()
        for sequence in range(16):
            command = self.command(sequence)
            reply = self.request(command)
            self.assertEqual(reply["kind"], "reply")
            self.assertEqual(reply["messageType"], command["messageType"])
            self.assertEqual(reply["payload"], command["payload"])
            self.assertNotIn(reply["messageId"], reply_ids)
            reply_ids.add(reply["messageId"])
        unsupported = self.command(17)
        unsupported["messageType"] = "unhandled@1"
        unsupported["payload"] = {}
        error = self.request(unsupported)
        self.assertEqual(error["kind"], "error")
        self.assertEqual(error["messageType"], "star.protocol/error@1")
        self.assertIs(error["payload"]["retryable"], False)
        stop = self.command(18)
        stop.update(messageType="star.zmq/stop@1", payload={})
        self.assertEqual(self.request(stop)["kind"], "reply")
        assert self.child is not None
        self.assertEqual(self.child.wait(timeout=5), 0)

    def test_persistent_ipc_session(self) -> None:
        self.normal_session(tcp=False)

    def test_persistent_loopback_tcp_session(self) -> None:
        self.normal_session(tcp=True)

    def reject(self, data: bytes) -> None:
        self.start()
        self.socket.send_multipart([b"conformance/7", data])
        assert self.child is not None
        self.assertNotEqual(self.child.wait(timeout=5), 0)

    def test_duplicate_escaped_key(self) -> None:
        valid = json.dumps(self.command())
        self.reject(valid.replace('"attempt": 1', '"attempt": 1, "\\u0061ttempt": 2').encode())

    def test_wrong_actor(self) -> None:
        command = self.command()
        command["actor"] = "other.actor"
        self.reject(json.dumps(command).encode())

    def test_boolean_attempt(self) -> None:
        command = self.command()
        command["attempt"] = True
        self.reject(json.dumps(command).encode())

    def test_deadline_not_silently_ignored(self) -> None:
        command = self.command()
        command["deadline"] = "2000-01-01T00:00:00Z"
        self.reject(json.dumps(command).encode())

    def test_unknown_envelope_field(self) -> None:
        command = self.command()
        command["hostPermission"] = "admin"
        self.reject(json.dumps(command).encode())

    def test_trailing_input(self) -> None:
        self.reject(json.dumps(self.command()).encode() + b" {}")

    def test_malformed_utf8(self) -> None:
        self.reject(b'{"payload":"\xff"}')

    def test_nested_payload_depth_bound(self) -> None:
        command = self.command()
        nested: object = "text"
        for _ in range(40):
            nested = [nested]
        command["payload"] = {"text": nested}
        self.reject(json.dumps(command).encode())

    def test_extra_multipart_frame(self) -> None:
        self.start()
        self.socket.send_multipart([b"conformance/7", json.dumps(self.command()).encode(), b"extra"])
        assert self.child is not None
        self.assertNotEqual(self.child.wait(timeout=5), 0)


if __name__ == "__main__":
    unittest.main(verbosity=2)
