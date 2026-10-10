#!/usr/bin/env python3
"""Guard shared raw-JSON validation even when Python assertions are optimized away."""
import contextlib
import importlib.util
import io
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("raw_json_harness", HERE / "test-starintel-raw-json.py")
harness = importlib.util.module_from_spec(spec)
spec.loader.exec_module(harness)


class HarnessPreflightTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.fixture = self.root / "raw-cases.json"
        self.reader = self.root / "fixture_reader.py"
        self.reader.write_text(
            "import json\n"
            "def parse(wire):\n"
            "    if wire == 'malformed':\n"
            "        raise ValueError('unexpected decoder failure')\n"
            "    if wire == 'duplicate':\n"
            "        raise ValueError('duplicate JSON key: x')\n"
            "    return json.loads(wire)\n",
            encoding="utf-8",
        )

    def check_fixture(self, cases, contract="starintel.raw-json-unique-keys/1"):
        self.fixture.write_text(json.dumps({"contract": contract, "cases": cases}), encoding="utf-8")
        with patch.object(harness, "FIXTURE", self.fixture), patch.object(harness, "READER", self.reader), \
                patch.object(sys, "argv", ["test-starintel-raw-json.py"]), \
                contextlib.redirect_stdout(io.StringIO()):
            harness.main()

    def test_valid_cases_still_run(self):
        self.check_fixture([
            {"name": "valid", "wire": "{}", "valid": True},
            {"name": "duplicate", "wire": "duplicate", "valid": False},
        ])

    def test_rejects_empty_fixture_without_false_green(self):
        with self.assertRaisesRegex(ValueError, 'accepted and rejected cases'):
            self.check_fixture([])

    def test_rejects_positive_only_fixture_without_duplicate_coverage(self):
        with self.assertRaisesRegex(ValueError, 'accepted and rejected cases'):
            self.check_fixture([{'name': 'valid', 'wire': '{}', 'valid': True}])

    def test_rejects_negative_only_fixture_without_positive_control(self):
        with self.assertRaisesRegex(ValueError, 'accepted and rejected cases'):
            self.check_fixture([{'name': 'duplicate', 'wire': 'duplicate', 'valid': False}])

    def test_rejects_unrecognized_contract_when_optimized(self):
        with self.assertRaisesRegex(ValueError, "fixture contract"):
            self.check_fixture([], contract="unrecognized/0")

    def test_rejects_duplicate_case_names_when_optimized(self):
        cases = [{"name": "same", "wire": "{}", "valid": True}] * 2
        with self.assertRaisesRegex(ValueError, "duplicate raw JSON fixture case"):
            self.check_fixture(cases)

    def test_rejects_authority_acceptance_mismatch_when_optimized(self):
        with self.assertRaisesRegex(ValueError, "authority raw JSON case mismatch"):
            self.check_fixture([{"name": "wrong", "wire": "{}", "valid": False}])

    def test_rejects_unexpected_parser_failure_when_optimized(self):
        with self.assertRaisesRegex(ValueError, "unexpected reference rejection"):
            self.check_fixture([{"name": "broken", "wire": "malformed", "valid": False}])

    def test_rejects_nonboolean_expected_validity(self):
        with self.assertRaisesRegex(ValueError, "boolean"):
            self.check_fixture([{"name": "wrong-bool", "wire": "{}", "valid": 1}])


if __name__ == "__main__":
    unittest.main()
