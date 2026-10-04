"""Validate source-generated contracts, imports, and candidate-only fixtures."""
import importlib.util
import json
from pathlib import Path
import unittest

from jsonschema import Draft202012Validator

ROOT = Path(__file__).resolve().parents[1]
RELEASE = ROOT / "specs/starintel/extensions/face-intel/0.1.0"
CORE = ROOT / "specs/starintel/0.10.1"


class FaceExtensionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.schema = json.loads((RELEASE / "generated/schema.json").read_text())
        cls.manifest = json.loads((RELEASE / "generated/portable-manifest.json").read_text())

    def test_schema_and_fixtures(self):
        Draft202012Validator.check_schema(self.schema)
        fixtures = json.loads((RELEASE / "fixtures.json").read_text())
        self.assertGreaterEqual(len(fixtures), 8)
        for case in fixtures:
            with self.subTest(case=case["name"]):
                validator = Draft202012Validator({**self.schema, "$ref": case["type"]})
                self.assertEqual(validator.is_valid(case["document"]), case["valid"])

    def test_inherited_core_types_remain_unmodified(self):
        core = json.loads((CORE / "generated/schema.json").read_text())
        for name, definition in self.schema["$defs"].items():
            if name in core["$defs"]:
                self.assertEqual(definition, core["$defs"][name], name)

    def test_distinct_library_and_exact_core_dependency(self):
        self.assertEqual(self.manifest["library"], {
            "name": "org.starintel/face-intel@1", "version": "0.1.0",
        })
        self.assertEqual(len(self.manifest["imports"]), 1)
        self.assertEqual(self.manifest["imports"][0]["version"], "0.10.1")
        for entry in self.manifest["types"]:
            self.assertTrue(entry["name"].startswith("org.starintel/face-intel@1/"))
        self.assertEqual(self.schema["$defs"]["CandidateOnly"]["enum"], ["candidate"])

    def test_resolved_types_are_unique_and_only_reachable_dependencies(self):
        resolved = json.loads((RELEASE / "generated/resolved-manifest.json").read_text())
        names = [entry["name"] for entry in resolved["types"]]
        self.assertEqual(len(names), len(set(names)))
        self.assertIn("org.starintel/core@1/person", names)
        self.assertNotIn("org.starintel/core@1/mission", names)
        self.assertNotIn("org.starintel/core@1/target", names)

    def test_all_supported_languages_have_locked_outputs(self):
        lock = json.loads((RELEASE / "release-lock.json").read_text())
        for filename in (
            "face_intel.lisp", "face_intel_types.py", "face_intel_types.ts",
            "face_intel_types.nim", "FaceIntel.kt", "FaceIntel.java",
            "face_intel_types.go", "face_intel_types.rs", "face-intel-types.el",
            "face_intel_types.pl",
        ):
            self.assertIn(filename, lock["artifacts"])

    def test_release_lock_matches_source_and_artifacts(self):
        spec = importlib.util.spec_from_file_location(
            "face_lock", ROOT / "tools/finalize-face-intel-extension.py"
        )
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        self.assertEqual(
            json.loads((RELEASE / "release-lock.json").read_text()), module.release_lock()
        )


if __name__ == "__main__":
    unittest.main()
