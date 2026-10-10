#!/usr/bin/env python3
"""Optimized-mode mutation coverage for Operation component persistence."""
import copy
import importlib.util
import json
from pathlib import Path
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location(
    'research_contracts', Path(__file__).with_name('test-starintel-research-contracts.py'))
CONTRACTS = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(CONTRACTS)
MANIFEST = json.loads((CONTRACTS.RELEASE / 'generated/portable-manifest.json').read_text())


def modified(name, **changes):
    result = copy.deepcopy(MANIFEST)
    entry = next(t for t in result['types'] if t['name'].endswith('/' + name))
    entry.update(changes)
    return result


class OperationComponentPersistenceTests(unittest.TestCase):
    def test_real_compiler_manifest_has_exact_persistence_roles(self):
        CONTRACTS.check_operation_component_persistence(MANIFEST)

    def test_every_internal_component_rejects_persistent_classification(self):
        for name in CONTRACTS.OPERATION_HELPERS:
            with self.subTest(name=name), self.assertRaisesRegex(
                    ValueError, 'component must remain transient'):
                CONTRACTS.check_operation_component_persistence(
                    modified(name, persistence='persistent'))

    def test_missing_internal_component_is_rejected(self):
        broken = copy.deepcopy(MANIFEST)
        broken['types'] = [t for t in broken['types']
                           if not t['name'].endswith('/operation-condition')]
        with self.assertRaisesRegex(ValueError, 'component must remain transient'):
            CONTRACTS.check_operation_component_persistence(broken)

    def test_non_document_component_is_rejected(self):
        with self.assertRaisesRegex(ValueError, 'non-document'):
            CONTRACTS.check_operation_component_persistence(
                modified('operation-dataset-binding', kind='enum'))

    def test_duplicate_component_is_rejected(self):
        broken = copy.deepcopy(MANIFEST)
        entry = next(t for t in broken['types'] if t['name'].endswith('/operation-post-action'))
        broken['types'].append(copy.deepcopy(entry))
        with self.assertRaisesRegex(ValueError, 'Duplicate'):
            CONTRACTS.check_operation_component_persistence(broken)

    def test_both_public_carriers_must_remain_persistent(self):
        for name in CONTRACTS.OPERATION_ROOTS:
            with self.subTest(name=name), self.assertRaisesRegex(
                    ValueError, 'carrier must remain persistent'):
                CONTRACTS.check_operation_component_persistence(
                    modified(name, persistence='transient'))

    def test_missing_carrier_is_rejected(self):
        broken = copy.deepcopy(MANIFEST)
        broken['types'] = [t for t in broken['types']
                           if not t['name'].endswith('/investigation-target')]
        with self.assertRaisesRegex(ValueError, 'carrier must remain persistent'):
            CONTRACTS.check_operation_component_persistence(broken)

    def test_original_conformance_case_calls_strict_gate(self):
        class GateReached(Exception):
            pass
        with patch.object(CONTRACTS, 'check_operation_component_persistence',
                          side_effect=GateReached):
            with self.assertRaises(GateReached):
                CONTRACTS.ResearchContractTests(
                    'test_transient_helpers_are_not_corpus_documents'
                ).test_transient_helpers_are_not_corpus_documents()


if __name__ == '__main__':
    unittest.main()
