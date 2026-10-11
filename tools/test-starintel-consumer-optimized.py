#!/usr/bin/env python3
"""Fail-closed optimized-mode tests for the vendored-reader conformance subprocess.

These tests exercise the actual embedded test program, not a duplicate checker.
The injected reader is an external-effect fixture, never canonical data authority.
"""
from __future__ import annotations

import ast
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

TEST_SOURCE = Path(__file__).with_name("test-starintel-consumer.py")

FAKE_READER = '''
import json, os
FAULT = os.environ.get("STARLANG_READER_TEST_FAULT", "")
LEGACY = {"properties": {"dtype": {"enum": list(range(27 if FAULT == "enum" else 28))}}}
class Envelope(dict):
    def __init__(self, body, raw):
        super().__init__(body)
        self.raw = raw
class Wire:
    def __init__(self, raw): self.raw = raw
    def encode(self): return self.raw
def read(raw):
    if raw.count(b'"schema_version"') > 1:
        raise ValueError("duplicate key")
    return json.loads(raw)
def migrate(raw):
    body = read(raw)
    if FAULT == "canonical": body["dtype"] = "wrong"
    return Envelope(body, raw), {"status": "changed" if FAULT == "status" else "unchanged"}
def parse(text): return json.loads(text)
def encode(doc): return Wire(doc.raw)
def restore(wire):
    if FAULT == "restore" or (FAULT == "seeded" and b"opaque_" in wire):
        return b"incorrect bytes"
    return wire
'''


def embedded_program():
    tree = ast.parse(TEST_SOURCE.read_text(encoding="utf-8"))
    programs = [node.value.value for node in ast.walk(tree)
                if isinstance(node, ast.Assign)
                and any(isinstance(target, ast.Name) and target.id == "script"
                        for target in node.targets)
                and isinstance(node.value, ast.Constant)
                and isinstance(node.value.value, str)]
    if len(programs) != 1:
        raise ValueError("expected exactly one vendored conformance subprocess")
    return programs[0]


class OptimizedReaderHarnessTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        root = Path(self.tmp.name) / "compatibility"
        root.mkdir()
        (root / "versioned_reader.py").write_text(FAKE_READER, encoding="utf-8")
        sample = {"schema_version": "0.9.0", "dtype": "alert", "extensions": {}}
        fixtures = [{"sourceUtf8": json.dumps(sample)} for _ in range(28)]
        expected = [{"document": sample} for _ in range(28)]
        (root / "historical-reader-fixtures.json").write_text(json.dumps(fixtures))
        (root / "canonical-migration-fixtures.json").write_text(json.dumps(expected))
        (root / "capabilities.json").write_text(json.dumps({
            "profiles": [{"schemaDtypes": 28, "pairedMigrationDtypes": 28}]}))

    def run_case(self, fault=""):
        env = os.environ.copy()
        env["STARLANG_READER_TEST_FAULT"] = fault
        return subprocess.run([sys.executable, "-O", "-I", "-B", "-c", embedded_program(),
                               self.tmp.name], text=True, capture_output=True, env=env,
                              timeout=15, check=False)

    def test_valid_reader_passes_under_optimized_python(self):
        result = self.run_case()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("64 seeded archival cases passed", result.stdout)

    def test_optimized_script_has_no_elided_assertions(self):
        self.assertFalse([node for node in ast.walk(ast.parse(embedded_program()))
                          if isinstance(node, ast.Assert)],
                         "-O would remove this reader conformance assertion")

    def test_dtype_coverage_error_still_rejected_with_optimization(self):
        self.assertNotEqual(self.run_case("enum").returncode, 0)

    def test_canonical_migration_error_still_rejected_with_optimization(self):
        self.assertNotEqual(self.run_case("canonical").returncode, 0)

    def test_lossless_restore_error_still_rejected_with_optimization(self):
        self.assertNotEqual(self.run_case("restore").returncode, 0)

    def test_unchanged_status_error_still_rejected_with_optimization(self):
        self.assertNotEqual(self.run_case("status").returncode, 0)

    def test_seeded_round_trip_error_still_rejected_with_optimization(self):
        self.assertNotEqual(self.run_case("seeded").returncode, 0)


if __name__ == "__main__":
    unittest.main()
