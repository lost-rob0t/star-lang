#!/usr/bin/env python3
"""Portable graph association semantic fixtures against the generated 0.10.1 schema."""

import copy
import json
from pathlib import Path
import sys
import unittest

from jsonschema import Draft202012Validator, FormatChecker

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from starintel_graph_contracts import (
    IDENTITY_EQUIVALENCE_PREDICATES,
    validate_relation_assertion,
    validate_entity_association,
    validate_graph_association,
)

SCHEMA = json.loads((ROOT / "specs/starintel/0.10.1/generated/schema.json").read_text())
FIXTURES = json.loads((ROOT / "fixtures/starintel/graph-association-v1.json").read_text())
RELATION_SCHEMA_VALIDATOR = Draft202012Validator({**SCHEMA, "$ref": "#/$defs/Relation"}, format_checker=FormatChecker())
ENTITY_SCHEMA_VALIDATOR = Draft202012Validator({**SCHEMA, "$ref": "#/$defs/Entity"}, format_checker=FormatChecker())

def check_generated_schema(document):
    if document.get("dtype") == "relation":
        RELATION_SCHEMA_VALIDATOR.validate(document)
    elif document.get("dtype") == "entity":
        ENTITY_SCHEMA_VALIDATOR.validate(document)


def validate(document):
    check_generated_schema(document)
    return validate_graph_association(document)


class GraphAssociationTests(unittest.TestCase):
    def setUp(self):
        self.candidate = copy.deepcopy(FIXTURES["cases"][0]["document"])
        self.verified = copy.deepcopy(FIXTURES["cases"][2]["document"])
        self.entity_candidate = copy.deepcopy(FIXTURES["cases"][5]["document"])
        self.entity_verified = copy.deepcopy(FIXTURES["cases"][6]["document"])
        self.entity_proof = copy.deepcopy(FIXTURES["cases"][6]["verifiedRelations"][0])

    def test_goldens(self):
        self.assertEqual(FIXTURES["version"], "0.10.1")
        self.assertEqual(len(FIXTURES["cases"]), 27)
        for case in FIXTURES["cases"]:
            with self.subTest(case=case["name"]):
                # Both positive and semantic-negative fixtures must be
                # structurally valid under the actual generated schema.
                check_generated_schema(case["document"])
                for assertion in case.get("verifiedRelations", ()):
                    check_generated_schema(assertion)
                prove = case.get("verifiedRelations", ())
                if case["valid"]:
                    self.assertEqual(validate_graph_association(case["document"], prove), case["document"])
                else:
                    with self.assertRaises(ValueError):
                        validate_graph_association(case["document"], prove)

    def test_candidate_requires_evidence_provenance_and_confidence_basis(self):
        for field in ("confidence", "confidenceBasis", "evidence", "provenance"):
            doc = copy.deepcopy(self.candidate)
            del doc[field]
            with self.subTest(field=field), self.assertRaises(ValueError):
                validate(doc)
        for field, value in (("evidence", []), ("provenance", {}), ("confidenceBasis", "   ")):
            doc = copy.deepcopy(self.candidate)
            doc[field] = value
            with self.subTest(field=field, value=value), self.assertRaises(ValueError):
                validate(doc)

    def test_candidate_cannot_claim_verification(self):
        for field, value in (("verifiedAt", 1760000000), ("verifiedBy", "reviewer:fixture")):
            doc = copy.deepcopy(self.candidate)
            doc[field] = value
            with self.subTest(field=field), self.assertRaises(ValueError):
                validate(doc)

    def test_weak_association_never_emits_identity_equivalence(self):
        for predicate in sorted(IDENTITY_EQUIVALENCE_PREDICATES):
            doc = copy.deepcopy(self.candidate)
            doc["predicate"] = predicate
            doc["confidence"] = "1.0000"
            with self.subTest(predicate=predicate), self.assertRaises(ValueError):
                validate(doc)

    def test_inverse_predicate_cannot_promote_candidate_identity(self):
        cases = (
            (self.candidate, "owl:sameAs"),
            (self.verified, "org.starintel/core@1/related-to"),
        )
        for source, inverse in cases:
            doc = copy.deepcopy(source)
            doc["inversePredicate"] = inverse
            with self.subTest(inverse=inverse), self.assertRaisesRegex(ValueError, "consistent"):
                validate(doc)
        doc = copy.deepcopy(self.verified)
        doc["predicate"] = "org.starintel/core@1/related-to"
        doc["inversePredicate"] = "owl:sameAs"
        with self.assertRaisesRegex(ValueError, "consistent"):
            validate(doc)
        for inverse in (" owl:sameAs", "owl:sameAs ", "  "):
            doc = copy.deepcopy(self.candidate)
            doc["inversePredicate"] = inverse
            with self.subTest(inverse=inverse), self.assertRaisesRegex(ValueError, "normalized"):
                validate(doc)
        doc = copy.deepcopy(self.verified)
        doc["inversePredicate"] = "owl:sameAs"
        self.assertIs(validate(doc), doc)

    def test_verified_identity_needs_explicit_attestation(self):
        for field in ("verifiedAt", "verifiedBy", "confidence", "confidenceBasis", "evidence", "provenance"):
            doc = copy.deepcopy(self.verified)
            del doc[field]
            with self.subTest(field=field), self.assertRaises(ValueError):
                validate(doc)
        doc = copy.deepcopy(self.verified)
        doc["verifiedAt"] = True
        with self.assertRaises(ValueError):
            validate_relation_assertion(doc)
        doc = copy.deepcopy(self.verified)
        doc["verificationStatus"] = "unknown"
        with self.assertRaises(ValueError):
            validate(doc)

    def test_confidence_range_and_precision(self):
        for value in ("-0.01", "1.0001", "0.00001", "NaN", "Infinity"):
            doc = copy.deepcopy(self.candidate)
            doc["confidence"] = value
            with self.subTest(value=value), self.assertRaises(ValueError):
                validate_relation_assertion(doc)

    def test_attestation_rejected_without_verified_status(self):
        doc = copy.deepcopy(self.candidate)
        doc["verificationStatus"] = "unknown"
        doc["verifiedBy"] = "reviewer:fixture"
        with self.assertRaises(ValueError):
            validate_relation_assertion(doc)

    def test_nonrelation_untouched_and_legacy_never_authoritative(self):
        person = {"dtype": "person", "schemaVersion": "0.10.1", "verificationStatus": "candidate"}
        self.assertIs(validate_relation_assertion(person), person)
        doc = copy.deepcopy(self.candidate)
        doc["schemaVersion"] = "0.9.0"
        with self.assertRaises(ValueError):
            validate_relation_assertion(doc)

    def test_entity_candidate_never_promoted_by_confidence(self):
        doc = copy.deepcopy(self.entity_candidate)
        doc["identityConfidence"] = "1.0000"
        self.assertIs(validate(doc), doc)
        doc["sameAsIds"] = ["entity:two"]
        with self.assertRaises(ValueError):
            validate(doc)

    def test_entity_same_as_requires_all_attestation_fields(self):
        for field in ("verifiedAt", "verifiedBy", "confidence", "confidenceBasis", "sources", "provenance"):
            doc = copy.deepcopy(self.entity_verified)
            del doc[field]
            with self.subTest(field=field), self.assertRaises(ValueError):
                validate_entity_association(doc, [self.entity_proof])
        for status in ("candidate", "disputed", "rejected", None):
            doc = copy.deepcopy(self.entity_verified)
            doc["verificationStatus"] = status
            with self.subTest(status=status), self.assertRaises(ValueError):
                validate_entity_association(doc, [self.entity_proof])

    def test_entity_self_duplicate_and_overlap_checks(self):
        for field, values in (("sameAsIds", ["entity:one"]),
                              ("sameAsIds", ["entity:two", "entity:two"]),
                              ("duplicateCandidateIds", ["entity:one"]),
                              ("duplicateCandidateIds", ["entity:two", "entity:two"]),
                              ("duplicateCandidateIds", ["entity:two", " "])):
            doc = copy.deepcopy(self.entity_verified)
            doc[field] = values
            with self.subTest(field=field, values=values), self.assertRaises(ValueError):
                validate_entity_association(doc)
        doc = copy.deepcopy(self.entity_verified)
        doc["duplicateCandidateIds"] = ["entity:two"]
        with self.assertRaises(ValueError):
            validate_entity_association(doc)

    def test_entity_and_relation_legacy_versions_rejected(self):
        for doc in (self.entity_candidate, self.candidate):
            legacy = copy.deepcopy(doc)
            legacy["schemaVersion"] = "0.9.0"
            with self.assertRaises(ValueError):
                validate_graph_association(legacy)

    def test_verified_relation_self_equivalence_rejected(self):
        doc = copy.deepcopy(self.verified)
        doc["destination"] = doc["source"]
        with self.assertRaises(ValueError):
            validate_relation_assertion(doc)

    def test_verified_identity_rejects_same_document_id_under_schema_aliases(self):
        for schema in ("org.starintel/core@1/entity",
                       "org.starintel/core@1/user",
                       "org.starintel/core@1/person-identifier"):
            doc = copy.deepcopy(self.verified)
            doc["destination"] = {"schema": schema, "id": doc["source"]["id"]}
            with self.subTest(schema=schema):
                check_generated_schema(doc)
                with self.assertRaisesRegex(ValueError, "self-equivalence"):
                    validate(doc)
        distinct = copy.deepcopy(self.verified)
        distinct["destination"]["schema"] = "org.starintel/core@1/entity"
        self.assertIs(validate(distinct), distinct)

    def test_same_as_requires_per_link_evidence_not_global_entity_attestation(self):
        with self.assertRaisesRegex(ValueError, "per-link"):
            validate_entity_association(self.entity_verified)
        doc = copy.deepcopy(self.entity_verified)
        doc["sameAsIds"].append("entity:third")
        with self.assertRaisesRegex(ValueError, "entity:third"):
            validate_entity_association(doc, [self.entity_proof])

    def test_supporting_relation_must_be_verified_for_matching_typed_pair(self):
        cases = [
            ("verificationStatus", "candidate"),
            ("predicate", "org.starintel/core@1/related-to"),
            ("verifiedBy", ""),
            ("evidence", []),
            ("destination", {"schema": "org.starintel/core@1/person", "id": "entity:two"}),
            ("destination", {"schema": "org.starintel/core@1/entity", "id": "entity:third"}),
        ]
        for field, value in cases:
            proof = copy.deepcopy(self.entity_proof)
            proof[field] = value
            with self.subTest(field=field, value=value), self.assertRaises(ValueError):
                validate_entity_association(self.entity_verified, [proof])
        reversed_link = copy.deepcopy(self.entity_proof)
        reversed_link["source"], reversed_link["destination"] = reversed_link["destination"], reversed_link["source"]
        self.assertIs(validate_entity_association(self.entity_verified, [reversed_link]), self.entity_verified)

    def test_predicate_lexical_bypass_is_rejected(self):
        for predicate in (" owl:sameAs", "owl:sameAs ", "  "):
            doc = copy.deepcopy(self.candidate)
            doc["predicate"] = predicate
            with self.subTest(predicate=predicate), self.assertRaises(ValueError):
                validate_relation_assertion(doc)

    def test_reversed_common_validity_window_rejected_direct_and_dispatch(self):
        # Relation and Entity share inherited Document fields, irrespective of
        # candidate/verified resolution status.
        examples = (
            self.candidate, self.verified, self.entity_candidate, self.entity_verified,
        )
        for source in examples:
            doc = copy.deepcopy(source)
            doc["validFrom"] = 1760000200
            doc["validUntil"] = 1760000100
            links = [self.entity_proof] if doc["dtype"] == "entity" and "sameAsIds" in doc else ()
            with self.subTest(dtype=doc["dtype"], status=doc.get("verificationStatus")):
                check_generated_schema(doc)
                with self.assertRaisesRegex(ValueError, "validFrom.*validUntil"):
                    validate_graph_association(doc, links)
                direct = validate_relation_assertion if doc["dtype"] == "relation" else validate_entity_association
                with self.assertRaisesRegex(ValueError, "validFrom.*validUntil"):
                    direct(doc)

    def test_common_validity_window_on_other_graph_document_types(self):
        for dtype in ("person", "org", "network-device", "address", "observation"):
            doc = {"id": f"{dtype}:validity-fixture", "dataset": "fixtures",
                   "dtype": dtype, "schemaVersion": "0.10.1",
                   "validFrom": 200, "validUntil": 199}
            with self.subTest(dtype=dtype), self.assertRaisesRegex(ValueError, "validFrom.*validUntil"):
                validate_graph_association(doc)
            doc["validUntil"] = 200
            self.assertIs(validate_graph_association(doc), doc)
            del doc["validUntil"]
            self.assertIs(validate_graph_association(doc), doc)

    def test_common_validity_window_equal_and_open_endpoints_accepted(self):
        for source in (self.candidate, self.entity_candidate):
            for fields in ({"validFrom": 0, "validUntil": 0},
                           {"validFrom": 123}, {"validUntil": 123}, {}):
                doc = copy.deepcopy(source)
                doc.update(fields)
                with self.subTest(dtype=doc["dtype"], fields=fields):
                    check_generated_schema(doc)
                    self.assertIs(validate_graph_association(doc), doc)

    def test_common_validity_window_requires_unix_times(self):
        # Generated schema rejects malformed scalar wire values first. This
        # direct semantic-path assertion prevents bypassing validation when a
        # consumer accidentally calls admission without the schema check.
        for field in ("validFrom", "validUntil"):
            for malformed in (True, -1, "1760000100", None, 1.5):
                doc = copy.deepcopy(self.candidate)
                doc[field] = malformed
                with self.subTest(field=field, value=malformed), self.assertRaisesRegex(ValueError, field):
                    validate_relation_assertion(doc)

    def test_content_validity_windows_are_ordered_at_entity_and_generic_admission(self):
        cases = (
            ("2026-10-12T00:00:00Z", "2026-10-11T23:59:59Z"),
            ("2026-10-12T00:00:00+02:00", "2026-10-11T21:00:00Z"),
            ("2026-10-11T12:00:00.123456789Z", "2026-10-11T12:00:00.123456788Z"),
        )
        for start, end in cases:
            doc = copy.deepcopy(self.entity_candidate)
            doc.update(contentValidFrom=start, contentValidUntil=end)
            with self.subTest(start=start, end=end):
                check_generated_schema(doc)
                with self.assertRaisesRegex(ValueError, "contentValidFrom.*contentValidUntil"):
                    validate_entity_association(doc)
                with self.assertRaisesRegex(ValueError, "contentValidFrom.*contentValidUntil"):
                    validate_graph_association(doc)
                other = dict(doc, dtype="employment")
                with self.assertRaisesRegex(ValueError, "contentValidFrom.*contentValidUntil"):
                    validate_graph_association(other)

    def test_content_validity_timezone_and_open_bounds(self):
        cases = (
            {"contentValidFrom": "2026-10-11T12:00:00+02:00",
             "contentValidUntil": "2026-10-11T10:00:00Z"},
            {"contentValidFrom": "2026-10-11T20:00:00+03:00",
             "contentValidUntil": "2026-10-11T16:00:00-02:00"},
            {"contentValidFrom": "2026-10-11T12:00:00.000000001Z",
             "contentValidUntil": "2026-10-11T12:00:00.000000002Z"},
            {"contentValidFrom": None, "contentValidUntil": "2026-10-11T12:00:00Z"},
            {"contentValidFrom": "2026-10-11T12:00:00Z", "contentValidUntil": None},
            {"contentValidUntil": "2026-10-11T12:00:00Z"},
            {"contentValidFrom": "2026-10-11T12:00:00Z"},
        )
        for fields in cases:
            doc = copy.deepcopy(self.entity_candidate)
            doc.update(fields)
            with self.subTest(fields=fields):
                check_generated_schema(doc)
                self.assertIs(validate_graph_association(doc), doc)

    def test_content_validity_rejects_malformed_timestamps_without_schema_bypass(self):
        for field in ("contentValidFrom", "contentValidUntil"):
            for value in (True, 1, "2026-10-11", "2026-10-11T12:00:00", "2026-14-11T12:00:00Z"):
                doc = copy.deepcopy(self.entity_candidate)
                doc[field] = value
                with self.subTest(field=field, value=value), self.assertRaisesRegex(ValueError, field):
                    validate_entity_association(doc)

    def test_content_validity_legacy_version_not_promoted(self):
        doc = {"dtype": "employment", "schemaVersion": "0.9.1",
               "contentValidFrom": "2026-10-12T00:00:00Z",
               "contentValidUntil": "2026-10-11T00:00:00Z"}
        self.assertIs(validate_graph_association(doc), doc)

    def test_old_versions_not_promoted_by_generic_validity_rule(self):
        doc = {"dtype": "person", "schemaVersion": "0.9.0",
               "validFrom": 200, "validUntil": 100}
        self.assertIs(validate_graph_association(doc), doc)

    def test_does_not_mutate_input(self):
        for doc in (self.candidate, self.verified, self.entity_candidate, self.entity_verified):
            original = copy.deepcopy(doc)
            links = [self.entity_proof] if doc is self.entity_verified else ()
            self.assertIs(validate_graph_association(doc, links), doc)
            self.assertEqual(doc, original)


if __name__ == "__main__":
    unittest.main()
