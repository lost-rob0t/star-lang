"""Real libzmq tests for the Python client; NOT evidence of Lisp/Nim execution."""
import pathlib
import sys
import threading
import unittest

import zmq

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1] / "python"))
from star_zmq import Dealer, SocketOwnerError, TransportLimitError, local_endpoint


class TransportTests(unittest.TestCase):
    def setUp(self):
        self.context = zmq.Context()
        self.router = self.context.socket(zmq.ROUTER)
        self.router.setsockopt(zmq.LINGER, 0)
        self.router.setsockopt(zmq.ROUTER_MANDATORY, 1)
        self.router.setsockopt(zmq.RCVTIMEO, 1000)
        self.router.setsockopt(zmq.SNDTIMEO, 1000)
        self.router.bind("inproc://test")
        self.dealer = Dealer(self.context, "inproc://test", b"peer", timeout_ms=50, payload_limit=255)

    def tearDown(self):
        self.dealer.close()
        self.router.close()
        self.context.term()

    def establish(self):
        self.dealer.send(b"ready")
        self.assertEqual(self.router.recv_multipart(), [b"peer", b"ready"])

    def test_binary_round_trip(self):
        body = bytes(range(255))
        self.dealer.send(body)
        self.assertEqual(self.router.recv_multipart(), [b"peer", body])
        self.router.send_multipart([b"peer", body])
        self.assertEqual(self.dealer.receive(), body)

    def test_empty_payload(self):
        self.dealer.send(b"")
        self.assertEqual(self.router.recv_multipart(), [b"peer", b""])

    def test_utf8_json_bytes_unchanged(self):
        body = '{"payload":{"text":"snowman ☃"},"starVersion":1}'.encode()
        self.dealer.send(body)
        self.assertEqual(self.router.recv_multipart(), [b"peer", body])

    def test_unroutable_is_not_silently_dropped(self):
        with self.assertRaises(zmq.ZMQError):
            self.router.send_multipart([b"unknown", b"payload"], flags=zmq.DONTWAIT)

    def test_oversized_send_rejected_before_io(self):
        with self.assertRaises(TransportLimitError):
            self.dealer.send(b"x" * 256)
        self.establish()

    def test_timeout_keeps_socket_usable(self):
        with self.assertRaises(zmq.Again):
            self.dealer.receive()
        self.establish()

    def test_extra_parts_close_socket(self):
        self.establish()
        self.router.send_multipart([b"peer", b"first", b"extra"])
        with self.assertRaises(TransportLimitError):
            self.dealer.receive()
        with self.assertRaises(RuntimeError):
            self.dealer.send(b"must fail")

    def test_oversized_receive_closes_socket(self):
        self.establish()
        # Inproc permits exercising the receive guard independently of TCP MAXMSGSIZE.
        self.router.send_multipart([b"peer", b"x" * 256])
        with self.assertRaises(TransportLimitError):
            self.dealer.receive()
        with self.assertRaises(RuntimeError):
            self.dealer.send(b"must fail")

    def test_wrong_thread_rejected(self):
        results = []
        def misuse():
            try:
                self.dealer.send(b"bad")
            except SocketOwnerError:
                results.append("rejected")
        thread = threading.Thread(target=misuse)
        thread.start()
        thread.join(timeout=2)
        self.assertFalse(thread.is_alive())
        self.assertEqual(results, ["rejected"])
        self.establish()

    def test_endpoint_allowlist(self):
        for endpoint in ["tcp://0.0.0.0:5555", "tcp://*:5555", "tcp://localhost:5555",
                         "tcp://127.0.0.1:0", "tcp://127.0.0.1:65536", "tcp://127.0.0.1:5\0evil",
                         "tcp://127.0.0.1:12/other", "tcp://127.0.0.1:１２", "ipc://", "inproc://"]:
            with self.subTest(endpoint=endpoint):
                self.assertFalse(local_endpoint(endpoint))
        for endpoint in ["ipc:///tmp/test.sock", "inproc://a", "tcp://127.0.0.1:5555", "tcp://[::1]:1"]:
            self.assertTrue(local_endpoint(endpoint))

    def test_two_explicit_peers(self):
        self.establish()
        with Dealer(self.context, "inproc://test", b"second") as second:
            second.send(b"hello")
            self.assertEqual(self.router.recv_multipart(), [b"second", b"hello"])
            self.router.send_multipart([b"second", b"for second"])
            self.assertEqual(second.receive(), b"for second")
            with self.assertRaises(zmq.Again):
                self.dealer.receive()

    def test_loopback_tcp(self):
        router = self.context.socket(zmq.ROUTER)
        router.setsockopt(zmq.LINGER, 0)
        router.setsockopt(zmq.RCVTIMEO, 1000)
        router.setsockopt(zmq.SNDTIMEO, 1000)
        port = router.bind_to_random_port("tcp://127.0.0.1")
        try:
            with Dealer(self.context, f"tcp://127.0.0.1:{port}", b"tcp") as peer:
                peer.send(b"hello")
                packet = router.recv_multipart()
                self.assertEqual(packet, [b"tcp", b"hello"])
                router.send_multipart(packet)
                self.assertEqual(peer.receive(), b"hello")
        finally:
            router.close()


if __name__ == "__main__":
    unittest.main()
