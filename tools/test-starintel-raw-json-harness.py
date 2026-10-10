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

    def check_fixture(self, cases, contract="starintel.raw-json-unique-keys/1", adapters=()):
        self.fixture.write_text(json.dumps({"contract": contract, "cases": cases}), encoding="utf-8")
        with patch.object(harness, "FIXTURE", self.fixture), patch.object(harness, "READER", self.reader), \
                patch.object(sys, "argv", ["test-starintel-raw-json.py"] +
                             [f"--adapter={entry}" for entry in adapters]), \
                contextlib.redirect_stdout(io.StringIO()):
            harness.main()

    def test_valid_cases_still_run(self):
        self.check_fixture([
            {"name": "valid", "wire": "{}", "valid": True},
            {"name": "duplicate", "wire": "duplicate", "valid": False},
        ])

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

    def test_rejects_duplicate_adapter_names_before_process_execution(self):
        cases = [{"name": "valid", "wire": "{}", "valid": True},
                 {"name": "duplicate", "wire": "duplicate", "valid": False}]
        for entries in (("shared=unused", "shared=unused"),
                        ("shared=unused", "other=unused", "shared=unused")):
            with self.subTest(entries=entries):
                with patch.object(harness.subprocess, "run",
                                  side_effect=AssertionError("adapter started before validation")) as run:
                    with contextlib.redirect_stderr(io.StringIO()) as stderr:
                        with self.assertRaises(SystemExit) as rejected:
                            self.check_fixture(cases, adapters=entries)
                    self.assertEqual(rejected.exception.code, 2)
                    self.assertIn("duplicate --adapter name: shared", stderr.getvalue())
                    run.assert_not_called()

    def test_distinct_adapter_names_preserve_commands(self):
        self.assertEqual(harness.adapter_commands(
            ["first=cmd --flag=a=b", "second=cmd --flag=c"]),
            [("first", "cmd --flag=a=b"), ("second", "cmd --flag=c")])

    def test_invalid_adapter_after_valid_adapter_rejects_before_launch(self):
        cases = [{"name": "valid", "wire": "{}", "valid": True},
                 {"name": "duplicate", "wire": "duplicate", "valid": False}]
        with patch.object(harness.subprocess, "run",
                          side_effect=AssertionError("preflight did not run")) as run:
            with contextlib.redirect_stderr(io.StringIO()) as stderr:
                with self.assertRaises(SystemExit) as rejected:
                    self.check_fixture(cases, adapters=("valid=unused", "bad"))
            self.assertEqual(rejected.exception.code, 2)
            self.assertIn("NAME=COMMAND", stderr.getvalue())
            run.assert_not_called()


if __name__ == "__main__":
    unittest.main()
