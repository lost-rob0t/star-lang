#!/usr/bin/env python3
"""Real IPC fault peer. Replaces external effects, never actor runtime evidence."""
import json
import os
import sys
import time

import zmq


def main() -> None:
    endpoint, identity, actor, generation_text = sys.argv[1:]
    generation = int(generation_text)
    context = zmq.Context()
    socket = context.socket(zmq.DEALER)
    socket.linger = 100
    socket.rcvtimeo = 5000
    socket.sndtimeo = 5000
    socket.identity = (identity + (":wrong" if actor == "wrongRoute" else "")).encode()
    socket.connect(endpoint)
    try:
        if actor == "noReady":
            time.sleep(10)
            return
        if actor == "logFlood":
            for descriptor in (1, 2):
                for _ in range(2048):
                    os.write(descriptor, b"x" * 1024)
        socket.send_json({"starVersion": 1, "kind": "event", "messageId": "ready",
                          "messageType": "star.zmq/ready@1", "actor": actor,
                          "sender": actor, "correlationId": "ready", "attempt": 1,
                          "payload": {"generation": generation - (actor == "staleGeneration")}})
        command = socket.recv_json()
        if actor == "dieOnCommand":
            raise SystemExit(7)
        if actor == "stallOnCommand":
            time.sleep(10)
            return
        if actor == "malformed":
            socket.send(b"{")
            time.sleep(10)
            return
        reply = {"starVersion": 1, "kind": "reply", "messageId": "reply",
                 "messageType": command["messageType"], "actor": command["replyTo"],
                 "sender": actor, "correlationId": command["correlationId"],
                 "causationId": command["messageId"], "attempt": 1,
                 "payload": command["payload"]}
        if "dataset" in command:
            reply["dataset"] = command["dataset"]
        if actor == "wrongCorrelation":
            reply["correlationId"] = "stale"
        socket.send(json.dumps(reply).encode())
        time.sleep(10)
    finally:
        socket.close()
        context.term()


if __name__ == "__main__":
    main()
