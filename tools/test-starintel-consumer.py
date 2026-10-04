"""Integration tests for release pinning, tampering, and consumer drift."""
import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("consumer", ROOT / "tools/sync-starintel-consumer.py")
consumer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(consumer)


class ConsumerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.source = self.root / "source"
        subprocess.run(["git", "clone", "--quiet", "--shared", str(ROOT), str(self.source)], check=True)
        self.commit = subprocess.check_output(["git", "-C", str(ROOT), "rev-parse", "HEAD"], text=True).strip()
        self.lock = self.root / "consumer/schema/starintel-schema.lock.json"

    def sync(self):
        consumer.sync(self.lock, self.commit, self.source, "schemas/starintel-0.10.1")

    def test_complete_release_roundtrip_and_vendored_drift(self):
        self.sync()
        lock = consumer.check(self.lock, self.source)
        schema = self.lock.parent.parent / next(p for p in lock["vendored_files"] if p.endswith("generated/schema.json"))
        schema.write_text("{}")
        with self.assertRaisesRegex(ValueError, "drift"):
            consumer.check(self.lock, self.source)

    def test_metadata_and_missing_artifact_rejected(self):
        self.sync()
        lock = json.loads(self.lock.read_text())
        lock["schema_version"] = "0.9.0"
        self.lock.write_text(json.dumps(lock))
        with self.assertRaisesRegex(ValueError, "schema_version mismatch"):
            consumer.check(self.lock, self.source)
        self.sync()
        lock = json.loads(self.lock.read_text())
        lock["vendored_files"].pop(next(iter(lock["vendored_files"])))
        self.lock.write_text(json.dumps(lock))
        with self.assertRaisesRegex(ValueError, "complete locked release"):
            consumer.check(self.lock, self.source)

    def test_floating_ref_and_unsafe_paths_rejected(self):
        with self.assertRaisesRegex(ValueError, "immutable"):
            consumer.verify_release("main", self.source)
        with self.assertRaisesRegex(ValueError, "unsafe"):
            consumer.safe_path("../outside")

    def test_offline_complete_release_and_tampering_without_network(self):
        self.sync()
        with patch.object(consumer, "read_source", side_effect=AssertionError("offline check used network")):
            lock = consumer.check(self.lock, None, offline=True)
            schema = self.lock.parent.parent / next(p for p in lock["vendored_files"] if p.endswith("generated/schema.json"))
            schema.write_text("{}")
            with self.assertRaisesRegex(ValueError, "hash mismatch"):
                consumer.check(self.lock, None, offline=True)

    def test_stale_upstream_lock_rejected_before_writes(self):
        core = self.source / consumer.RELEASE / "core.star"
        core.write_text(core.read_text() + "\n; changed source\n")
        subprocess.run(["git", "-C", str(self.source), "add", "."], check=True)
        subprocess.run(["git", "-C", str(self.source), "-c", "user.name=Test", "-c", "user.email=test@example.test",
                        "commit", "--quiet", "-m", "stale release"], check=True)
        commit = subprocess.check_output(["git", "-C", str(self.source), "rev-parse", "HEAD"], text=True).strip()
        with self.assertRaisesRegex(ValueError, "upstream release hash mismatch"):
            consumer.sync(self.lock, commit, self.source, "schemas/starintel-0.10.1")
        self.assertFalse(self.lock.exists())


if __name__ == "__main__":
    unittest.main()
