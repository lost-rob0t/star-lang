#!/usr/bin/env python3
"""Cross-check the generated research structures and operation invariants."""
import copy
import json
from pathlib import Path
import unittest
from jsonschema import Draft202012Validator, ValidationError
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "specs/starintel/0.10.1"))
from operation_semantics import validate_operation_semantics

ROOT = Path(__file__).resolve().parents[1]
RELEASE = ROOT / 'specs/starintel/0.10.1'
SCHEMA = json.loads((RELEASE / 'generated/schema.json').read_text())

def validate(doc):
    name = {'operation': 'Operation', 'investigation-target': 'InvestigationTarget'}[doc['dtype']]
    Draft202012Validator({**SCHEMA, '$ref': '#/$defs/' + name}).validate(doc)
    validate_operation_semantics(doc)


def require_enum_rejection(document, expected_path):
    try:
        validate(document)
    except ValidationError as error:
        actual_path = tuple(error.absolute_path)
        if error.validator != 'enum' or actual_path != tuple(expected_path):
            raise AssertionError(
                f'expected enum violation at {tuple(expected_path)!r}, '
                f'got {error.validator!r} at {actual_path!r}'
            ) from error
        return
    raise AssertionError(f'expected enum violation at {tuple(expected_path)!r}')

BASE = {'id': 'operation:test', 'dataset': 'test', 'dtype': 'operation', 'schemaVersion': '0.10.1',
        'mission': 'Verify a documented question', 'status': 'planned',
        'phases': [{'phaseId': 'collect', 'objective': 'Collect references', 'state': 'planned'}]}

class ResearchContractTests(unittest.TestCase):
    def test_valid_operation_and_investigation_are_distinct(self):
        validate(copy.deepcopy(BASE))
        validate({'id': 'research:test', 'dataset': 'test', 'dtype': 'investigation-target',
                  'schemaVersion': '0.10.1', 'target': 'Public question', 'researchQuestion': 'What changed?',
                  'maxDepth': 3, 'priority': '0.75', 'options': [False, None, {'opaque_key': 'value'}]})
        self.assertIn('actor', SCHEMA['$defs']['Target']['required'])
        self.assertNotIn('actor', SCHEMA['$defs']['InvestigationTarget']['required'])

    def test_all_operation_components_preserve_specific_enums(self):
        doc = copy.deepcopy(BASE)
        doc.update(datasets=[{'bindingId': 'working', 'dataset': 'test', 'role': 'working', 'access': 'read-write', 'phases': ['collect']}],
                   capabilityGaps=[{'capabilityId': 'source', 'category': 'source', 'description': 'Acquire source', 'blocking': False, 'status': 'available', 'requiredBy': ['collect']}],
                   assignments=[{'assignmentId': 'agent', 'phaseIds': ['collect'], 'status': 'assigned'}],
                   postActions=[{'actionId': 'export', 'actionType': 'export', 'status': 'ready', 'datasetBindingIds': ['working']}])
        doc['phases'][0].update(datasetBindingIds=['working'], requiredCapabilityIds=['source'])
        validate(doc)
        # Keep every generated closed Operation enum in the conformance gate.
        # Reject only the requested enum/property, not unrelated validator faults.
        cases = (
            (('status',), 'invalid-operation-status'),
            (('phases', 0, 'state'), 'invalid-phase-state'),
            (('datasets', 0, 'role'), 'invalid-dataset-role'),
            (('datasets', 0, 'access'), 'invalid-dataset-access'),
            (('capabilityGaps', 0, 'category'), 'invalid-category'),
            (('capabilityGaps', 0, 'status'), 'invalid-capability-status'),
            (('assignments', 0, 'status'), 'draft'),
            (('postActions', 0, 'status'), 'invalid-post-action-status'),
        )
        for path, invalid in cases:
            mutated = copy.deepcopy(doc)
            item = mutated
            for key in path[:-1]:
                item = item[key]
            item[path[-1]] = invalid
            with self.subTest(path=path):
                require_enum_rejection(mutated, path)

    def test_invalid_semantics(self):
        mutations = [lambda d: d.update(mission=' '), lambda d: d.update(phases=[]),
            lambda d: d['phases'].append(copy.deepcopy(d['phases'][0])),
            lambda d: d['phases'][0].update(dependsOn=['collect']),
            lambda d: d['phases'][0].update(dependsOn=['absent']),
            lambda d: d['phases'][0].update(datasetBindingIds=['absent']),
            lambda d: d['phases'][0].update(requiredCapabilityIds=['absent']),
            lambda d: (d.update(outOfScope=['private']), d['phases'][0].update(inScope=['private'])),
            lambda d: d['phases'][0].update(state='completed'),
            lambda d: d.update(status='completed')]
        for mutate in mutations:
            doc = copy.deepcopy(BASE); mutate(doc)
            with self.subTest(document=doc), self.assertRaises(ValueError): validate(doc)
        doc = copy.deepcopy(BASE)
        doc['phases'] += [{'phaseId': 'review', 'objective': 'Review', 'state': 'planned', 'dependsOn': ['collect']}]
        doc['phases'][0]['dependsOn'] = ['review']
        with self.assertRaises(ValueError): validate(doc)

    def test_transient_helpers_are_not_corpus_documents(self):
        manifest = json.loads((RELEASE/'generated/portable-manifest.json').read_text())
        persistent = [x for x in manifest['types'] if x['kind'] == 'document' and x['persistence'] == 'persistent']
        self.assertTrue({"operation", "investigation-target"}.issubset({x["name"].rsplit("/", 1)[-1] for x in persistent}))
        self.assertFalse(any(x['name'].endswith('/operation-phase') for x in persistent))

if __name__ == '__main__': unittest.main()
