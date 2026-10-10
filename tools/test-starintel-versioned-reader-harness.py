#!/usr/bin/env python3
"""Prove migration fixture parity cannot pass vacuously under python -O."""
import ast
from pathlib import Path
import unittest

SOURCE = Path(__file__).with_name('test-starintel-versioned-reader.py')


def loaded_helper():
    tree = ast.parse(SOURCE.read_text(encoding='utf-8'))
    found = [node for node in tree.body
             if isinstance(node, ast.FunctionDef) and node.name == 'fixture_pairs']
    if len(found) != 1:
        raise ValueError('expected one production fixture-pair validator')
    namespace = {}
    exec(compile(ast.Module(body=found, type_ignores=[]), str(SOURCE), 'exec'), namespace)
    return namespace['fixture_pairs']


def samples(count):
    return [{'name': 'migration-' + str(i)} for i in range(count)]


class MigrationPairHarnessTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.validator = staticmethod(loaded_helper())

    def test_production_gate_used_for_both_fixture_catalogs(self):
        tree = ast.parse(SOURCE.read_text(encoding='utf-8'))
        for method in ('test_paired_artifacts_and_schema_are_locked',
                       'test_numeric_migration_artifacts_support_equivalent_notation'):
            function = [node for node in ast.walk(tree)
                        if isinstance(node, ast.FunctionDef) and node.name == method]
            self.assertEqual(len(function), 1)
            calls = [node for node in ast.walk(function[0])
                     if isinstance(node, ast.Call) and isinstance(node.func, ast.Name)
                     and node.func.id == 'fixture_pairs']
            self.assertEqual(len(calls), 1, method)

    def test_complete_28_and_six_pair_catalogs_are_accepted(self):
        for count in (28, 6):
            self.assertEqual(len(self.validator(samples(count), samples(count), count)), count)

    def test_surplus_or_truncated_canonical_catalog_is_rejected(self):
        for historical, canonical, count in ((samples(28), samples(29), 28),
                                             (samples(6), samples(5), 6)):
            with self.subTest(count=count):
                with self.assertRaisesRegex(ValueError, 'count mismatch'):
                    self.validator(historical, canonical, count)

    def test_reordered_canonical_catalog_is_rejected(self):
        out_of_order = samples(6)
        out_of_order[0], out_of_order[1] = out_of_order[1], out_of_order[0]
        with self.assertRaisesRegex(ValueError, 'name mismatch'):
            self.validator(samples(6), out_of_order, 6)

    def test_duplicate_or_malformed_names_are_rejected(self):
        repeated = samples(28)
        repeated[-1]['name'] = repeated[0]['name']
        with self.assertRaisesRegex(ValueError, 'duplicate'):
            self.validator(repeated, [dict(row) for row in repeated], 28)
        malformed = samples(6)
        malformed[-1]['name'] = None
        with self.assertRaisesRegex(ValueError, 'name mismatch'):
            self.validator(samples(6), malformed, 6)

    def test_nonlist_catalogs_are_rejected(self):
        with self.assertRaisesRegex(ValueError, 'count mismatch'):
            self.validator(tuple(samples(6)), samples(6), 6)

    def test_validation_not_removed_under_python_optimization(self):
        tree = ast.parse(SOURCE.read_text(encoding='utf-8'))
        node = next(node for node in tree.body
                    if isinstance(node, ast.FunctionDef) and node.name == 'fixture_pairs')
        self.assertFalse([child for child in ast.walk(node) if isinstance(child, ast.Assert)])


if __name__ == '__main__':
    unittest.main()
