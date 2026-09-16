"""Local-only transport binding. Actor semantics and JSON validation live upstream."""
from __future__ import annotations

import re
import threading

import zmq

MAX_PAYLOAD = 1_048_576
_LOCAL_TCP = re.compile(r"tcp://(?:127\.0\.0\.1|\[::1\]):([0-9]{1,5})\Z", re.ASCII)


class TransportLimitError(ValueError):
    """An endpoint, frame count or payload bound was violated."""


class SocketOwnerError(RuntimeError):
    """A socket was used from another thread."""


def local_endpoint(endpoint: str) -> bool:
    if not isinstance(endpoint, str) or not 1 <= len(endpoint) <= 1024 or "\0" in endpoint:
        return False
    for prefix in ("ipc://", "inproc://"):
        if endpoint.startswith(prefix) and len(endpoint) > len(prefix):
            return True
    match = _LOCAL_TCP.fullmatch(endpoint)
    return match is not None and 1 <= int(match[1]) <= 65535


class Dealer:
    """One explicitly addressed peer. The caller owns the shared process context.

    A successful send only means queued to libzmq. This class does not retry,
    authorize identities, implement actors, serialize objects or promise delivery.
    """

    def __init__(
        self, context: zmq.Context, endpoint: str, identity: bytes, *,
        timeout_ms: int = 1000, payload_limit: int = MAX_PAYLOAD,
    ) -> None:
        if not local_endpoint(endpoint):
            raise TransportLimitError("Only IPC/inproc/literal loopback endpoints are allowed")
        if not isinstance(identity, bytes) or not 1 <= len(identity) <= 255 or identity[0] == 0:
            raise TransportLimitError("Identity must contain 1..255 bytes, without an initial NUL")
        if type(timeout_ms) is not int or not 1 <= timeout_ms <= 60_000:
            raise TransportLimitError("Timeout must be 1..60000 milliseconds")
        if type(payload_limit) is not int or not 1 <= payload_limit <= 16_777_216:
            raise TransportLimitError("Invalid payload limit")
        self._owner = threading.current_thread()
        self._limit = payload_limit
        self._socket: zmq.Socket | None = context.socket(zmq.DEALER)
        try:
            self._socket.setsockopt(zmq.LINGER, 0)
            self._socket.setsockopt(zmq.SNDHWM, 64)
            self._socket.setsockopt(zmq.RCVHWM, 64)
            self._socket.setsockopt(zmq.RCVTIMEO, timeout_ms)
            self._socket.setsockopt(zmq.SNDTIMEO, timeout_ms)
            self._socket.setsockopt(zmq.MAXMSGSIZE, max(255, payload_limit))
            self._socket.setsockopt(zmq.IMMEDIATE, 1)
            self._socket.setsockopt(zmq.ROUTING_ID, identity)
            self._socket.connect(endpoint)
        except BaseException:
            self.close()
            raise

    def _owned(self) -> zmq.Socket:
        if threading.current_thread() is not self._owner:
            raise SocketOwnerError("Socket belongs to its creating thread")
        if self._socket is None:
            raise RuntimeError("Socket is closed")
        return self._socket

    def send(self, payload: bytes) -> None:
        socket = self._owned()
        if not isinstance(payload, bytes) or len(payload) > self._limit:
            raise TransportLimitError("Expected bounded immutable bytes")
        socket.send(payload, copy=True)

    def receive(self) -> bytes:
        socket = self._owned()
        # recv_into reports the full native frame length without allocating that length.
        buffer = bytearray(self._limit)
        size = socket.recv_into(buffer)
        try:
            if size > self._limit or socket.getsockopt(zmq.RCVMORE):
                raise TransportLimitError("Oversized or unexpected multipart message")
            return bytes(buffer[:size])
        except BaseException:
            self.close()
            raise

    def close(self) -> None:
        if threading.current_thread() is not self._owner:
            raise SocketOwnerError("Close the socket on its owner thread")
        if self._socket is not None:
            self._socket.close(linger=0)
            self._socket = None

    def __enter__(self) -> Dealer:
        self._owned()
        return self

    def __exit__(self, *_: object) -> None:
        self.close()
