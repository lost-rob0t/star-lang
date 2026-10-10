#!/usr/bin/env python3
"""Executable canonical SL05 fixtures: generated structure then semantics."""

from __future__ import annotations

import copy
import json
from pathlib import Path
import sys
import unittest

from jsonschema import Draft202012Validator

ROOT = Path(__file__).resolve().parents[1]
RELEASE = ROOT / "specs/starintel/0.10.1"
sys.path.insert(0, str(RELEASE))
from media_semantics import validate_media_evidence_semantics  # noqa: E402

SCHEMA = json.loads((RELEASE / "generated/schema.json").read_text(encoding="utf-8"))
NAMES = {
    "video-frame": "VideoFrame",
    "picture": "Picture",
    "audio-segment": "AudioSegment",
    "speech-segment": "SpeechSegment",
    "speaker-observation": "SpeakerObservation",
    "speaker-turn": "SpeakerTurn",
    "transcript": "Transcript",
    "audio": "Audio",
    "video": "Video",
    "image": "Image",
    "media": "Media",
    "source": "Source",
    "evidence-record": "EvidenceRecord",
}


class MediaEvidenceContractTests(unittest.TestCase):
    def test_source_owned_fixture_gate(self):
        cases = json.loads(
            (RELEASE / "media-evidence-fixtures.json").read_text(encoding="utf-8")
        )
        self.assertEqual(cases["fixtureVersion"], 1)
        self.assertEqual(cases["authority"], "org.starintel/core@1")
        self.assertGreaterEqual(len(cases["cases"]), 35)
        for case in cases["cases"]:
            with self.subTest(case=case["id"]):
                document = copy.deepcopy(case["document"])
                dtype = document["dtype"]
                self.assertIn(dtype, NAMES)
                validator = Draft202012Validator(
                    {**SCHEMA, "$ref": "#/$defs/" + NAMES[dtype]}
                )
                # Every fixture is structurally valid: prove that the current
                # generator alone cannot reject impossible timing/provenance.
                validator.validate(document)
                untouched = copy.deepcopy(document)
                if case["valid"]:
                    validate_media_evidence_semantics(document)
                else:
                    with self.assertRaisesRegex(ValueError, case["error"]):
                        validate_media_evidence_semantics(document)
                self.assertEqual(document, untouched)

    def test_authority_and_generator_are_separate(self):
        source = (RELEASE / "core.star").read_text(encoding="utf-8")
        self.assertIn("SL05 media timeline invariant", source)
        self.assertIn("SL05 payload integrity invariant", source)
        self.assertIn("SL05 inherited image pixel dimensions", source)
        manifest = json.loads(
            (RELEASE / "generated/portable-manifest.json").read_text(encoding="utf-8")
        )
        self.assertEqual(manifest["library"]["name"], "org.starintel/core@1")
        self.assertEqual(manifest["library"]["version"], "0.10.1")
        lock = json.loads((RELEASE / "release-lock.json").read_text(encoding="utf-8"))
        for name in ("core.star", "media_semantics.py", "media-evidence-fixtures.json"):
            self.assertIn(name, lock["sources"])

    def test_confidence_does_not_become_verification(self):
        record = {
            "id": "sl05:source", "dataset": "test", "dtype": "source",
            "schemaVersion": "0.10.1", "credibility": "0.25",
            "payloadContentHash": "aa", "payloadHashAlgorithm": "sha256",
        }
        validate_media_evidence_semantics(record)
        self.assertEqual(record["credibility"], "0.25")
        self.assertNotIn("verificationStatus", record)
        self.assertNotIn("confidence", record)


if __name__ == "__main__":
    unittest.main()

