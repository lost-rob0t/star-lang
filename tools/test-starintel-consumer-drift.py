#!/usr/bin/env python3
"""Deterministic offline diagnostics; no network, mutation, or schema authoring."""
from __future__ import annotations

import hashlib
import importlib.util
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("drift", HERE / "report-starintel-consumer-drift.py")
drift = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(drift)


def sha(data):
    return hashlib.sha256(data).hexdigest()


class DriftReportTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.authority = self.root / "authority"
        self.consumer = self.root / "consumer"
        self.lock = self.consumer / "schema/starintel-schema.lock.json"
        self.lock.parent.mkdir(parents=True)
        self.release = "specs/starintel/0.10.1"
        self.source = self.release + "/core.star"
        self.schema = self.release + "/generated/schema.json"
        self.payloads = {self.source: b"(spec-library fixture)\n", self.schema: b'{"$schema": "fixture"}\n'}
        for path, data in self.payloads.items():
            target = self.authority / path
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(data)
        metadata = {"authorityLibrary": "org.starintel/core@1", "releaseVersion": "0.10.1",
                    "schemaVersion": "0.10.1", "sources": {"core.star": sha(self.payloads[self.source])},
                    "artifacts": {"schema.json": sha(self.payloads[self.schema])}}
        target = self.authority / self.release / "release-lock.json"
        target.write_text(json.dumps(metadata), encoding="utf-8")
        self.payloads[self.release + "/release-lock.json"] = target.read_bytes()
        self.vendor = {}
        for canonical, data in self.payloads.items():
            local = "vendor/" + canonical.removeprefix(self.release + "/")
            path = self.consumer / local
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)
            self.vendor[local] = {"source": canonical, "sha256": sha(data)}
        self.write_lock()

    def write_lock(self):
        self.lock.write_text(json.dumps({"canonical_repository": "lost-rob0t/star-lang",
                                         "release_version": "0.10.1", "schema_version": "0.10.1",
                                         "vendored_files": self.vendor}), encoding="utf-8")

    def test_exact_closed_release_reports_clean(self):
        result = drift.audit(self.lock, self.authority)
        self.assertTrue(result["ok"], result["errors"])
        self.assertEqual(result["mode"], "release")

    def test_reports_all_corrupted_files_without_short_circuit(self):
        for local in list(self.vendor)[:2]:
            (self.consumer / local).write_bytes(b"corrupt")
        result = drift.audit(self.lock, self.authority)
        self.assertFalse(result["ok"])
        self.assertEqual(sum("vendored bytes drift" in x for x in result["errors"]), 2)
        self.assertEqual(result["errors"], sorted(result["errors"]))

    def test_duplicate_and_missing_sources_both_reported(self):
        local = sorted(self.vendor)[0]
        removed = sorted(self.vendor)[1]
        self.vendor["vendor/duplicate.star"] = dict(self.vendor[local])
        del self.vendor[removed]
        self.write_lock()
        result = drift.audit(self.lock, self.authority)
        self.assertFalse(result["ok"])
        self.assertTrue(any("duplicate source" in x for x in result["errors"]))
        self.assertTrue(any("missing source" in x for x in result["errors"]))

    def test_authority_drift_and_bad_pin_reported(self):
        (self.authority / self.schema).write_bytes(b"corrupted authority")
        local = sorted(self.vendor)[0]
        self.vendor[local]["sha256"] = "0" * 64
        self.write_lock()
        result = drift.audit(self.lock, self.authority)
        self.assertFalse(result["ok"])
        self.assertTrue(any("authority: committed file drift" in x for x in result["errors"]))
        self.assertTrue(any("consumer: stale lock hash" in x for x in result["errors"]))

    def bundle_source(self):
        compatibility = "specs/starintel/compatibility/versioned_reader.py"
        target = self.authority / compatibility
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(b"reader fixture\n")
        bundle = self.release + "/bundle-lock.json"
        closure = dict(self.payloads)
        closure[compatibility] = target.read_bytes()
        metadata = {"bundleFormat": "starintel-consumer-bundle/1",
                    "files": {p.removeprefix("specs/starintel/"): sha(data)
                              for p, data in closure.items()}}
        bundle_file = self.authority / bundle
        bundle_file.write_text(json.dumps(metadata), encoding="utf-8")
        closure[bundle] = bundle_file.read_bytes()
        self.vendor = {}
        for source, data in closure.items():
            local = "vendor/starintel/" + source.removeprefix("specs/starintel/")
            path = self.consumer / local
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)
            self.vendor[local] = {"source": source, "sha256": sha(data)}
        self.write_lock()
        lock = json.loads(self.lock.read_text())
        lock["bundle_format"] = "starintel-consumer-bundle/1"
        lock["bundle_lock_path"] = bundle
        self.lock.write_text(json.dumps(lock))
        return compatibility

    def test_bundle_closure_reports_clean(self):
        self.bundle_source()
        result = drift.audit(self.lock, self.authority)
        self.assertTrue(result["ok"], result["errors"])
        self.assertEqual(result["mode"], "bundle")

    def test_bundle_reports_release_hash_disagreement(self):
        self.bundle_source()
        path = self.authority / self.release / "bundle-lock.json"
        bundle = json.loads(path.read_text())
        bundle["files"]["0.10.1/core.star"] = "0" * 64
        path.write_text(json.dumps(bundle))
        result = drift.audit(self.lock, self.authority)
        self.assertFalse(result["ok"])
        self.assertTrue(any("release/bundle hash mismatch" in x for x in result["errors"]))


    def test_bundle_rejects_remapped_reader_with_identical_bytes(self):
        self.bundle_source()
        lock = json.loads(self.lock.read_text())
        old = "vendor/starintel/compatibility/versioned_reader.py"
        new = "safe-elsewhere/versioned_reader.py"
        target = self.consumer / new
        target.parent.mkdir()
        (self.consumer / old).rename(target)
        lock["vendored_files"][new] = lock["vendored_files"].pop(old)
        self.lock.write_text(json.dumps(lock))
        result = drift.audit(self.lock, self.authority)
        self.assertFalse(result["ok"], result)
        self.assertTrue(any("sibling layout" in x for x in result["errors"]))

    def test_bundle_rejects_invalid_lock_path_metadata(self):
        self.bundle_source()
        original = json.loads(self.lock.read_text())
        for value in (None, "specs/starintel/0.9.0/bundle-lock.json"):
            with self.subTest(value=value):
                lock = dict(original)
                lock["bundle_lock_path"] = value
                self.lock.write_text(json.dumps(lock))
                result = drift.audit(self.lock, self.authority)
                self.assertFalse(result["ok"], result)
                self.assertTrue(any("bundle lock path" in x for x in result["errors"]))

    def test_bundle_rejects_unlisted_import_shadows_and_bytecode(self):
        self.bundle_source()
        for name in ("operation_semantics.py", "raw_json_numbers.pyc",
                     "__pycache__/raw_json_numbers.cpython-312.pyc"):
            with self.subTest(name=name):
                path = self.consumer / "vendor/starintel/compatibility" / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(b"# unpinned shadow")
                before = self.lock.read_bytes()
                result = drift.audit(self.lock, self.authority)
                self.assertFalse(result["ok"], result)
                self.assertTrue(any("unlisted bundle file" in x for x in result["errors"]))
                self.assertEqual(self.lock.read_bytes(), before)
                self.assertEqual(path.read_bytes(), b"# unpinned shadow")
                path.unlink()
        self.assertTrue(drift.audit(self.lock, self.authority)["ok"])

    def test_bundle_layout_failure_keeps_other_diagnostics(self):
        self.bundle_source()
        lock = json.loads(self.lock.read_text())
        lock["bundle_lock_path"] = "wrong"
        self.lock.write_text(json.dumps(lock))
        (self.consumer / "vendor/starintel/0.10.1/core.star").write_bytes(b"corrupt")
        result = drift.audit(self.lock, self.authority)
        self.assertFalse(result["ok"], result)
        self.assertTrue(any("bundle lock path" in x for x in result["errors"]))
        self.assertTrue(any("vendored bytes drift" in x for x in result["errors"]))

    def assert_authority_lock_not_read(self, lock_path, *, bundle):
        """A rejected lock must not be opened before path validation."""
        original_read = Path.read_bytes
        forbidden_reads = []

        def guarded_read(path):
            if path == lock_path:
                forbidden_reads.append(str(path))
                raise AssertionError("untrusted authority lock was read before validation")
            return original_read(path)

        with patch.object(Path, "read_bytes", guarded_read):
            with self.assertRaisesRegex(ValueError, "unsafe"):
                drift.authority_closure(self.authority, bundle)
        self.assertEqual(forbidden_reads, [])

    def test_release_lock_symlink_outside_authority_is_never_read(self):
        path = self.authority / self.release / "release-lock.json"
        external = self.root / "untrusted-release.json"
        external.write_bytes(path.read_bytes())
        path.unlink()
        path.symlink_to(external)
        self.assert_authority_lock_not_read(path, bundle=False)

    def test_bundle_lock_symlink_inside_authority_is_never_read(self):
        self.bundle_source()
        path = self.authority / self.release / "bundle-lock.json"
        alternate = self.authority / self.release / "alternate-bundle.json"
        alternate.write_bytes(path.read_bytes())
        path.unlink()
        path.symlink_to(alternate)
        self.assert_authority_lock_not_read(path, bundle=True)

    def test_release_lock_hardlink_is_never_read(self):
        path = self.authority / self.release / "release-lock.json"
        other = self.root / "linked-release.json"
        os.link(path, other)
        self.assert_authority_lock_not_read(path, bundle=False)

    def test_symlink_vendor_is_not_followed(self):
        local = sorted(self.vendor)[0]
        target = self.consumer / local
        target.unlink()
        target.symlink_to(self.consumer / sorted(self.vendor)[1])
        result = drift.audit(self.lock, self.authority)
        self.assertFalse(result["ok"])
        self.assertTrue(any("unsafe symlink target" in x for x in result["errors"]))


if __name__ == "__main__":
    unittest.main()
