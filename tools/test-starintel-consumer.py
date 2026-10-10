"""Integration tests for release pinning, tampering, and consumer drift."""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
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

    def test_noncanonical_paths_rejected(self):
        for path in ("", ".", "./schema.json", "schema//file.json", "schema/./file.json",
                     "/schema.json", "../schema.json", "schema/../file.json",
                     "schema\\file.json", "schema\u0000.json", "schema\nfile.json"):
            with self.subTest(path=path):
                with self.assertRaisesRegex(ValueError, "unsafe"):
                    consumer.safe_path(path)

    def test_sync_rejects_symlink_destination_before_writes(self):
        root = self.lock.parent.parent
        root.mkdir(parents=True)
        outside = self.root / "outside"
        outside.mkdir()
        (root / "escape").symlink_to(outside, target_is_directory=True)
        with self.assertRaisesRegex(ValueError, "unsafe"):
            consumer.sync(self.lock, self.commit, self.source, "escape/release")
        self.assertEqual(list(outside.iterdir()), [])
        self.assertFalse(self.lock.exists())

    def test_check_rejects_duplicate_sources_online_and_offline(self):
        self.sync()
        lock = json.loads(self.lock.read_text())
        local, entry = next(iter(lock["vendored_files"].items()))
        duplicate = self.lock.parent.parent / "duplicate.json"
        duplicate.write_bytes((self.lock.parent.parent / local).read_bytes())
        lock["vendored_files"]["duplicate.json"] = entry
        self.lock.write_text(json.dumps(lock))
        for offline in (False, True):
            with self.subTest(offline=offline):
                with self.assertRaisesRegex(ValueError, "duplicate canonical source"):
                    consumer.check(self.lock, None if offline else self.source, offline=offline)

    def test_check_rejects_symlinked_vendored_file(self):
        self.sync()
        lock = json.loads(self.lock.read_text())
        local = next(iter(lock["vendored_files"]))
        target = self.lock.parent.parent / local
        outside = self.root / "outside.json"
        outside.write_bytes(target.read_bytes())
        target.unlink()
        target.symlink_to(outside)
        for offline in (False, True):
            with self.subTest(offline=offline):
                with self.assertRaisesRegex(ValueError, "unsafe"):
                    consumer.check(self.lock, None if offline else self.source, offline=offline)

    def bundle_source(self):
        before = (self.source / consumer.RELEASE / "release-lock.json").read_bytes()
        subprocess.run([sys.executable, str(self.source / "tools/finalize-starintel-release.py"),
                        "--bundle"], check=True, cwd=self.source)
        self.assertEqual(before, (self.source / consumer.RELEASE / "release-lock.json").read_bytes())
        subprocess.run(["git", "-C", str(self.source), "add", "."], check=True)
        subprocess.run(["git", "-C", str(self.source), "-c", "user.name=Test",
                        "-c", "user.email=test@example.test", "commit", "--quiet",
                        "--allow-empty", "-m", "generate test bundle"], check=True)
        return subprocess.check_output(["git", "-C", str(self.source), "rev-parse", "HEAD"],
                                       text=True).strip()

    def test_complete_bundle_relocates_real_reader_offline(self):
        commit = self.bundle_source()
        consumer.sync(self.lock, commit, self.source, "vendor/starintel", bundle=True, release="0.10.1")
        with patch.object(consumer, "read_source", side_effect=AssertionError("offline network")):
            lock = consumer.check(self.lock, None, offline=True)
        root = self.lock.parent.parent / "vendor/starintel"
        reader = root / "compatibility/versioned_reader.py"
        old = b' \n{"_id":"fixture:alert","dataset":"test","dtype":"alert","schema_version":"0.9.0","version":1,"date_added":"2026-10-04T00:00:00Z","date_updated":"2026-10-04T00:00:00Z","sources":[],"evidence":[],"data":{},"extensions":{"flag":false,"n":1e3}}\n'
        def run(*args, raw=old):
            return subprocess.run([sys.executable, "-I", "-B", str(reader), *args], input=raw,
                                  capture_output=True, cwd=self.root, check=True).stdout
        self.assertEqual(run("read"), old)
        report = json.loads(run("migrate", "--dry-run"))
        self.assertIn("status", report)
        current = run("migrate")
        self.assertEqual(run("read", raw=current), current)
        self.assertEqual(run("restore", raw=current), old)
        self.assertEqual(json.loads(run("migrate", raw=current)), json.loads(current))
        self.assertEqual(lock["bundle_format"], "starintel-consumer-bundle/1")
        self.assertIn("vendor/starintel/compatibility/registry.json", lock["vendored_files"])
        self.assertIn("vendor/starintel/0.10.1/release-lock.json", lock["vendored_files"])

    def test_bundle_missing_tampered_and_duplicate_mapping_fail_closed(self):
        commit = self.bundle_source()
        consumer.sync(self.lock, commit, self.source, "vendor/starintel", bundle=True)
        original = self.lock.read_bytes()
        lock = json.loads(original)
        local = "vendor/starintel/compatibility/versioned_reader.py"
        target = self.lock.parent.parent / local
        data = target.read_bytes()
        target.write_bytes(data + b"\n# tampered\n")
        with self.assertRaisesRegex(ValueError, "hash mismatch"):
            consumer.check(self.lock, None, offline=True)
        target.write_bytes(data)
        del lock["vendored_files"][local]
        self.lock.write_text(json.dumps(lock))
        with self.assertRaisesRegex(ValueError, "complete locked"):
            consumer.check(self.lock, None, offline=True)
        self.lock.write_bytes(original)
        lock = json.loads(original)
        lock["vendored_files"]["duplicate.py"] = lock["vendored_files"][local]
        self.lock.write_text(json.dumps(lock))
        with self.assertRaisesRegex(ValueError, "duplicate canonical source"):
            consumer.check(self.lock, self.source)

    def test_bundle_rejects_wrong_release_format_and_floating_ref(self):
        commit = self.bundle_source()
        with self.assertRaisesRegex(ValueError, "unsupported release"):
            consumer.sync(self.lock, commit, self.source, "vendor/starintel", bundle=True, release="0.9.0")
        with self.assertRaisesRegex(ValueError, "immutable"):
            consumer.sync(self.lock, "main", self.source, "vendor/starintel", bundle=True)
        consumer.sync(self.lock, commit, self.source, "vendor/starintel", bundle=True)
        lock = json.loads(self.lock.read_text())
        lock["bundle_format"] = "unknown"
        self.lock.write_text(json.dumps(lock))
        with self.assertRaisesRegex(ValueError, "bundle format"):
            consumer.check(self.lock, None, offline=True)

    def test_bundle_interruption_keeps_lock_and_fails_verification(self):
        commit = self.bundle_source()
        consumer.sync(self.lock, commit, self.source, "vendor/starintel", bundle=True)
        original = self.lock.read_bytes()
        real_write = Path.write_bytes
        count = 0
        def interrupted(path, data):
            nonlocal count
            count += 1
            if count == 2:
                real_write(path, b"interrupted")
                raise OSError("injected write interruption")
            return real_write(path, data)
        with patch.object(Path, "write_bytes", interrupted):
            with self.assertRaisesRegex(OSError, "interruption"):
                consumer.sync(self.lock, commit, self.source, "vendor/starintel", bundle=True)
        self.assertEqual(self.lock.read_bytes(), original)
        with self.assertRaisesRegex(ValueError, "hash mismatch"):
            consumer.check(self.lock, None, offline=True)

    def test_relocated_bundle_matrix_and_seeded_archival_properties(self):
        commit = self.bundle_source()
        consumer.sync(self.lock, commit, self.source, "vendor/starintel", bundle=True)
        root = self.lock.parent.parent / "vendor/starintel"
        script = r"""
import importlib.util, json, pathlib, random, sys
root = pathlib.Path(sys.argv[1])
spec = importlib.util.spec_from_file_location("isolated_reader", root / "compatibility/versioned_reader.py")
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
fixtures = json.loads((root / "compatibility/historical-reader-fixtures.json").read_text())
expected = json.loads((root / "compatibility/canonical-migration-fixtures.json").read_text())
matrix = json.loads((root / "compatibility/capabilities.json").read_text())
assert len(m.LEGACY["properties"]["dtype"]["enum"]) == matrix["profiles"][0]["schemaDtypes"]
assert len(fixtures) == matrix["profiles"][0]["pairedMigrationDtypes"] == 28
for fixture, canonical in zip(fixtures, expected, strict=True):
    raw = fixture["sourceUtf8"].encode()
    m.read(raw)
    current, report = m.migrate(raw)
    assert current == m.parse(json.dumps(canonical["document"]))
    wire = m.encode(current).encode()
    assert m.restore(wire) == raw
    assert m.migrate(wire)[1]["status"] == "unchanged"
rng = random.Random(204)
for index in range(64):
    doc = json.loads(fixtures[0]["sourceUtf8"])
    token = rng.choice(["-0", "1e3", "1.000", "1e999999999999999999999",
                        "1e-999999999999999999999", "9007199254740993"])
    doc["extensions"] = {"flag": bool(rng.randrange(2)), "nil": None,
                         "opaque_" + str(index): "numeric-token"}
    raw = (rng.choice(["", " ", "\n\t"]) + json.dumps(doc, sort_keys=bool(index % 2))
           .replace('"numeric-token"', token) + rng.choice(["", "\n", " "])).encode()
    m.read(raw)
    current, report = m.migrate(raw)
    assert m.restore(m.encode(current).encode()) == raw
    duplicate = raw.replace(b'"schema_version": "0.9.0"',
                            b'"schema_version":"0.9.0","schema_version":"0.9.0"')
    try:
        m.read(duplicate)
    except ValueError:
        pass
    else:
        raise AssertionError("duplicate-key mutation accepted")
print("28 relocated paired workflows; 64 seeded archival cases passed")
"""
        result = subprocess.run([sys.executable, "-I", "-B", "-c", script, str(root)],
                                capture_output=True, text=True, cwd=self.root, check=True)
        self.assertIn("64 seeded archival cases passed", result.stdout)

    def test_bundle_layout_and_explicit_cli_mode_fail_closed(self):
        commit = self.bundle_source()
        consumer.sync(self.lock, commit, self.source, "vendor/starintel", bundle=True)
        lock = json.loads(self.lock.read_text())
        old = "vendor/starintel/compatibility/versioned_reader.py"
        new = "flattened-reader.py"
        (self.lock.parent.parent / new).write_bytes((self.lock.parent.parent / old).read_bytes())
        lock["vendored_files"][new] = lock["vendored_files"].pop(old)
        self.lock.write_text(json.dumps(lock))
        with self.assertRaisesRegex(ValueError, "sibling layout"):
            consumer.check(self.lock, None, offline=True)
        self.sync()
        result = subprocess.run([sys.executable, str(ROOT / "tools/sync-starintel-consumer.py"),
                                 "--lock", str(self.lock), "--offline", "--bundle"],
                                capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("requires a bundle lock", result.stderr)

    def test_malformed_upstream_bundle_rejected_before_writes(self):
        commit = self.bundle_source()
        _, pristine = consumer.verify_bundle(commit, self.source)
        path = consumer.RELEASE + "/bundle-lock.json"
        for mode in ("missing-reader", "wrong-format", "wrong-version", "tampered-reader", "unsafe-path"):
            files = dict(pristine)
            bundle = json.loads(files[path])
            if mode == "missing-reader":
                bundle["files"].pop("compatibility/versioned_reader.py")
            elif mode == "wrong-format":
                bundle["bundleFormat"] = "unknown"
            elif mode == "wrong-version":
                bundle["schemaVersion"] = "0.9.0"
            elif mode == "tampered-reader":
                files[consumer.BUNDLE_ROOT + "/compatibility/versioned_reader.py"] += b"\n# corruption"
            else:
                bundle["files"]["../outside"] = "0" * 64
            files[path] = json.dumps(bundle).encode()
            with self.subTest(mode=mode):
                with patch.object(consumer, "read_source", side_effect=lambda sha, name, source: files[name]):
                    with self.assertRaises(ValueError):
                        consumer.sync(self.lock, commit, self.source, "vendor/starintel", bundle=True)
                self.assertFalse(self.lock.exists())
                self.assertFalse((self.lock.parent.parent / "vendor").exists())

    def test_bundle_rejects_unlisted_import_shadows_and_bytecode(self):
        commit = self.bundle_source()
        consumer.sync(self.lock, commit, self.source, "vendor/starintel", bundle=True)
        original_lock = self.lock.read_bytes()
        directory = self.lock.parent.parent / "vendor/starintel/compatibility"
        for name in ("operation_semantics.py", "raw_json_numbers.pyc",
                     "__pycache__/raw_json_numbers.cpython-312.pyc"):
            shadow = directory / name
            shadow.parent.mkdir(parents=True, exist_ok=True)
            shadow.write_bytes(b"# unpinned shadow")
            with self.subTest(name=name):
                for offline in (False, True):
                    with self.assertRaisesRegex(ValueError, "unlisted bundle file"):
                        consumer.check(self.lock, None if offline else self.source, offline=offline)
                with self.assertRaisesRegex(ValueError, "unlisted bundle file"):
                    consumer.sync(self.lock, commit, self.source, "vendor/starintel", bundle=True)
                self.assertEqual(self.lock.read_bytes(), original_lock)
            shadow.unlink()
        consumer.check(self.lock, None, offline=True)

    def test_bundle_rejects_lock_inside_destination_and_hardlinked_target(self):
        commit = self.bundle_source()
        with self.assertRaisesRegex(ValueError, "lock must stay outside"):
            consumer.sync(self.lock, commit, self.source, "schema", bundle=True)
        self.assertFalse(self.lock.exists())
        consumer.sync(self.lock, commit, self.source, "vendor/starintel", bundle=True)
        target = self.lock.parent.parent / "vendor/starintel/compatibility/raw_json_numbers.py"
        outside = self.root / "outside-helper.py"
        outside.write_bytes(target.read_bytes())
        original = outside.read_bytes()
        target.unlink()
        target.hardlink_to(outside)
        with self.assertRaisesRegex(ValueError, "hardlinked"):
            consumer.sync(self.lock, commit, self.source, "vendor/starintel", bundle=True)
        self.assertEqual(outside.read_bytes(), original)

    @unittest.skipUnless(hasattr(os, "mkfifo"), "FIFO test requires POSIX")
    def test_nonregular_bundle_target_rejects_without_blocking(self):
        commit = self.bundle_source()
        consumer.sync(self.lock, commit, self.source, "vendor/starintel", bundle=True)
        target = self.lock.parent.parent / "vendor/starintel/compatibility/raw_json_numbers.py"
        target.unlink()
        os.mkfifo(target)
        result = subprocess.run([sys.executable, str(ROOT / "tools/sync-starintel-consumer.py"),
                                 "--lock", str(self.lock), "--offline", "--bundle"],
                                capture_output=True, text=True, timeout=5)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("nonregular", result.stderr)
        with self.assertRaisesRegex(ValueError, "nonregular"):
            consumer.sync(self.lock, commit, self.source, "vendor/starintel", bundle=True)


if __name__ == "__main__":
    unittest.main()
