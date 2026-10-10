#!/usr/bin/env python3
"""Exercise the exact research schema enum guard under optimized Python."""
import ast
from collections import deque
from pathlib import Path
import unittest
from jsonschema.exceptions import ValidationError

SOURCE = Path(__file__).with_name('test-starintel-research-contracts.py')


def guard_for(fake_validate):
    module = ast.parse(SOURCE.read_text(encoding='utf-8'), filename=str(SOURCE))
    match = next((n for n in module.body
                  if isinstance(n, ast.FunctionDef)
                  and n.name == 'require_enum_rejection'), None)
    if match is None:
        raise AssertionError('research enum guard is missing')
    environment = {'ValidationError': ValidationError, 'validate': fake_validate}
    exec(compile(ast.Module(body=[match], type_ignores=[]), str(SOURCE), 'exec'), environment)
    return environment['require_enum_rejection']


def raising(error):
    def validate(_):
        if error is not None:
            raise error
    return validate


class ResearchEnumHarness(unittest.TestCase):
    PATH = ('assignments', 0, 'status')

    def test_valid_enum_rejection_is_accepted(self):
        error = ValidationError('invalid enum', validator='enum', path=deque(self.PATH))
        self.assertIsNone(guard_for(raising(error))({}, self.PATH))

    def test_unexpected_acceptance_is_rejected(self):
        with self.assertRaises(AssertionError):
            guard_for(raising(None))({}, self.PATH)

    def test_unrelated_schema_failure_is_rejected(self):
        error = ValidationError('type failed', validator='type', path=deque(self.PATH))
        with self.assertRaises(AssertionError):
            guard_for(raising(error))({}, self.PATH)

    def test_enum_error_in_other_component_is_rejected(self):
        error = ValidationError('another field', validator='enum', path=deque(('phases', 0, 'state')))
        with self.assertRaises(AssertionError):
            guard_for(raising(error))({}, self.PATH)

    def test_unrelated_runtime_failure_propagates(self):
        with self.assertRaisesRegex(RuntimeError, 'downstream fault'):
            guard_for(raising(RuntimeError('downstream fault')))({}, self.PATH)


if __name__ == '__main__':
    unittest.main()
