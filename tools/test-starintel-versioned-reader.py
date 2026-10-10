#!/usr/bin/env python3
"""Executable historical-reader/migration contract, never a production rewrite."""
import copy
from decimal import Decimal
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
PATH = ROOT / 'specs/starintel/compatibility/versioned_reader.py'
spec = importlib.util.spec_from_file_location('versioned_reader', PATH)
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)


def historical(dtype='alert', data=None):
    return {'_id': 'fixture:' + dtype, 'dataset': 'conformance', 'dtype': dtype,
            'schema_version': '0.9.0', 'version': 1, 'date_added': '2026-10-04T00:00:00Z',
            'date_updated': '2026-10-04T00:00:00Z', 'sources': [], 'evidence': [], 'data': data or {}}



def fixture_pairs(historical, canonical, expected_count):
    """Require a complete, ordered, unique pairing before testing migrations."""
    if (type(historical) is not list or type(canonical) is not list
            or len(historical) != expected_count or len(canonical) != expected_count):
        raise ValueError('paired migration fixture count mismatch')
    pairs = list(zip(historical, canonical, strict=True))
    names = []
    for before, after in pairs:
        if (not isinstance(before, dict) or not isinstance(after, dict)
                or not isinstance(before.get('name'), str)
                or not before['name'] or before['name'] != after.get('name')):
            raise ValueError('paired migration fixture name mismatch')
        names.append(before['name'])
    if len(names) != len(set(names)):
        raise ValueError('duplicate paired migration fixture name')
    return pairs

class VersionedReaderTests(unittest.TestCase):
    def raw(self, doc):
        return m.encode(doc).encode()

    def test_all_paired_workflows(self):
        fixtures = json.loads((ROOT / 'specs/starintel/0.10.1/supported-workflow-fixtures.json').read_text())
        count = 0
        for f in fixtures:
            if not f.get('valid'):
                continue
            dtype = f['document']['dtype']
            if dtype not in m.LEGACY['properties']['dtype']['enum']:
                continue
            old_schema = next(x['then']['properties']['data'] for x in m.LEGACY['allOf']
                              if x['if']['properties']['dtype']['const'] == dtype)
            old_data = {k: v for k, v in f['legacyData'].items() if k in old_schema['properties']}
            raw = self.raw(historical(dtype, old_data))
            with self.subTest(dtype=dtype):
                result, report = m.migrate(raw)
                m.canonical_validate(result)
                self.assertEqual(m.restore(self.raw(result)), raw)
                self.assertEqual(m.migrate(self.raw(result))[0], result)
                self.assertEqual(m.migrate(self.raw(result))[1]['status'], 'unchanged')
                expected = {k: v for k, v in f['document'].items()
                            if k in {'id', 'dataset', 'dtype', 'schemaVersion'} or k in
                            {m.MAPPINGS[dtype]['fields'][old] for old in old_data}}
                actual = {k: v for k, v in result.items() if k != 'extensions'}
                if dtype == 'dataset-manifest' and 'countsByDtype' in actual:
                    expected['countsByDtype'] = sorted(expected['countsByDtype'], key=lambda x: x['key'])
                self.assertEqual(actual, expected)
                count += 1
        self.assertEqual(count, 28)

    def test_exact_precision_null_false_unknown_and_omission(self):
        doc = historical(data={'threshold': Decimal('0.123456789012345678901234567890'),
                               'triggered_at': None})
        doc['extensions'] = {'unknown_key': None, 'flag': False, 'huge': 9007199254740993,
                             'decimal': Decimal('1.234567890123456789')}
        raw = (' \n' + m.encode(doc) + '\n').encode()
        before = raw[:]
        result, report = m.migrate(raw)
        self.assertEqual(raw, before)
        self.assertEqual(result['threshold'], '0.123456789012345678901234567890')
        self.assertIsNone(result['triggeredAt'])
        self.assertNotIn('lastTriggeredAt', result)
        self.assertEqual(m.read(m.restore(self.raw(result)))['document']['extensions'], doc['extensions'])
        self.assertEqual(m.restore(self.raw(result)), raw)
        self.assertTrue(any(r['action'] == 'retained-original' for r in report['mapping']))

    def test_read_returns_detached_document_original_bytes_unchanged(self):
        raw = self.raw(historical())
        read = m.read(raw)
        read['document']['data']['x'] = 1
        self.assertNotIn('x', m.read(raw)['document']['data'])

    def test_unsupported_versions_profiles_and_dtypes(self):
        for version in ['0.8.0', '0.10.0', '0.10.1', '0.10.2', None]:
            doc = historical(); doc['schema_version'] = version
            with self.subTest(version=version), self.assertRaises(Exception): m.read(self.raw(doc))
        doc = historical(); doc['schemaVersion'] = '0.10.1'
        with self.assertRaises(ValueError): m.read(self.raw(doc))
        doc = historical('person', {'name': 'Example'})
        m.read(self.raw(doc))
        with self.assertRaisesRegex(ValueError, 'unsupported migration dtype'): m.migrate(self.raw(doc))

    def test_invalid_source_not_laundered(self):
        for patch in [{'data': {'severity': False}}, {'date_added': 'not-a-time'}, {'unexpected': 1}, {'dtype': 'unknown'}]:
            doc = historical(); doc.update(patch)
            with self.subTest(patch=patch), self.assertRaises(Exception): m.migrate(self.raw(doc))
        doc = historical(); del doc['version']
        with self.assertRaises(Exception): m.migrate(self.raw(doc))

    def test_integral_exponent_numbers_are_schema_integers(self):
        raw = self.raw(historical()).replace(b'"version":1', b'"version":1e0')
        self.assertEqual(m.read(raw)['document']['version'], 1)
        result, _ = m.migrate(raw)
        self.assertEqual(m.restore(self.raw(result)), raw)

    def test_shared_raw_duplicate_key_contract(self):
        fixture = json.loads((ROOT / 'specs/starintel/wire/raw-json-unique-keys.json').read_text())
        for case in fixture['cases']:
            with self.subTest(case=case['name']):
                if case['valid']:
                    m.parse(case['wire'])
                else:
                    with self.assertRaisesRegex(ValueError, 'duplicate JSON key'):
                        m.parse(case['wire'])

    def test_duplicate_and_nonfinite_rejected(self):
        for raw in [b'{"schema_version":"0.9.0","schema_version":"0.9.0"}', b'{"x":NaN}', b'{"x":Infinity}']:
            with self.assertRaises(Exception): m.read(raw)

    def test_edited_canonical_and_corrupt_provenance_reject_restore(self):
        original, _ = m.migrate(self.raw(historical()))
        for mode in ['edit', 'hash', 'source']:
            result = copy.deepcopy(original)
            if mode == 'edit': result['dataset'] = 'edited'
            if mode == 'hash': result['extensions'][m.MARKER]['sourceSha256'] = 'bad'
            if mode == 'source': result['extensions'][m.MARKER]['sourceUtf8'] += ' '
            with self.subTest(mode=mode), self.assertRaises(ValueError): m.restore(self.raw(result))

    def test_recomputed_hashes_and_forged_reports_do_not_bypass_restore(self):
        original, _ = m.migrate(self.raw(historical()))
        for mode in ['target', 'report', 'source', 'extra-provenance']:
            changed = copy.deepcopy(original)
            receipt = changed['extensions'][m.MARKER]
            if mode == 'target':
                changed['dataset'] = 'edited'
                receipt['targetSha256'] = m.digest(m.semantic_encode({k: v for k, v in changed.items() if k != 'extensions'}).encode())
            elif mode == 'report':
                receipt['report'] = {'status': 'invented'}
            elif mode == 'source':
                unrelated = historical(); unrelated['dataset'] = 'unrelated'
                receipt['sourceUtf8'] = m.encode(unrelated)
                receipt['sourceSha256'] = m.digest(receipt['sourceUtf8'].encode())
            else:
                receipt['unknown'] = 'injected'
            with self.subTest(mode=mode), self.assertRaises(ValueError):
                m.restore(self.raw(changed))

    def test_required_missing_not_invented(self):
        # The historical research-node requires objective/status; never fabricate them.
        doc = historical('research-node')
        with self.assertRaises(Exception): m.migrate(self.raw(doc))

    def test_native_constraints_fail_closed_and_precision_stays_exact(self):
        doc = historical('analysis', {'confidence': Decimal('0.123456789')})
        result, report = m.migrate(self.raw(doc))
        self.assertEqual(result['payloadConfidence'], '0.123456789')
        retained = next(x for x in report['mapping'] if x['source'] == '/data/confidence')
        self.assertEqual(retained['action'], 'mapped')
        self.assertEqual(m.restore(self.raw(result)), self.raw(doc))
        doc = historical(); doc['_id'] = 'contains spaces'
        m.read(self.raw(doc))
        with self.assertRaises(Exception): m.migrate(self.raw(doc))

    def canonical_number_wire(self, token, field='extensions'):
        base = b'{"id":"number:test","dataset":"test","dtype":"person","schemaVersion":"0.10.1",'
        value = '{"n":' + token + '}' if field == 'extensions' else token
        return base + ('"' + field + '":' + value + '}').encode()

    def test_extreme_json_numbers_preserve_exact_wire_values(self):
        exponent = '999999999999999999999'
        tokens = ['1e' + exponent, '-1e' + exponent, '1e-' + exponent,
                  '-1e-' + exponent, '0e' + exponent, '-0e-' + exponent,
                  '1e' + '9' * 5000, '1234567890' * 500,
                  '-0', '-0.0', '0.12345678901234567890123456789']
        for token in tokens:
            with self.subTest(token=token[:60]):
                raw = self.canonical_number_wire(token)
                parsed = m.read(raw)['document']
                output, report = m.migrate(raw)
                self.assertEqual(report['status'], 'unchanged')
                self.assertEqual(parsed, output)
                encoded = m.encode(output)
                self.assertEqual(m.parse(encoded), parsed)
                if isinstance(parsed['extensions']['n'], m.RawJsonNumber) or token in {'-0', '-0.0'}:
                    self.assertIn('"n":' + token, encoded)

    def test_symbolic_exact_integer_and_bounds_without_expansion(self):
        exponent = '999999999999999999999'
        for token in ['1e' + exponent, '0e-' + exponent, '-0e' + exponent, '1e0']:
            m.read(self.canonical_number_wire(token, 'createdAt'))
        for token in ['-1e' + exponent, '1e-' + exponent, '-1e-' + exponent,
                      '1.00000000000000000000000000001', 'true']:
            with self.subTest(token=token), self.assertRaises(Exception):
                m.read(self.canonical_number_wire(token, 'createdAt'))
        node = {'type': 'number', 'minimum': -1, 'maximum': 1}
        for token in ['1e-' + exponent, '-1e-' + exponent, '-0e' + exponent]:
            m.validate_at(m.parse(token), node)
        for token in ['1e' + exponent, '-1e' + exponent]:
            with self.assertRaises(Exception): m.validate_at(m.parse(token), node)
        self.assertLess(m.RawJsonNumber('-1.23'), m.RawJsonNumber('-1.2'))
        self.assertTrue(m.RawJsonNumber('10e-1').is_integer())
        self.assertFalse(m.RawJsonNumber('10e-2').is_integer())
        self.assertNotEqual(m.RawJsonNumber('1'), True)

    def test_oversized_native_decimal_conversion_is_retained_not_expanded(self):
        for token in ['1e1000000000', '1e-1000000000', '1e999999999999999999999']:
            raw = self.raw(historical()).replace(b'"data":{}', ('"data":{"threshold":' + token + '}').encode())
            output, report = m.migrate(raw)
            self.assertNotIn('threshold', output)
            item = next(x for x in report['mapping'] if x['source'] == '/data/threshold')
            self.assertEqual(item['action'], 'retained-original')
            self.assertEqual(item['reason'], 'native-decimal-expansion-limit')
            self.assertLess(len(m.encode(output)), 10000)
            self.assertEqual(m.restore(self.raw(output)), raw)
        for token in ['-0e1000000000', '-0e999999999999999999999']:
            raw = self.raw(historical()).replace(b'"data":{}', ('"data":{"threshold":' + token + '}').encode())
            output, _ = m.migrate(raw)
            self.assertEqual(output['threshold'], '-0')
            self.assertEqual(m.restore(self.raw(output)), raw)

    def test_restore_accepts_equal_numeric_notation_but_rejects_changed_values(self):
        pairs = [('1e3', '1000'), ('1.0', '1'), ('-0', '0'), ('-0.0', '0.000'),
                 ('1e999999999999999999999', '10e999999999999999999998'),
                 ('1e-999999999999999999999', '10e-1000000000000000000000')]
        for original_token, equivalent_token in pairs:
            with self.subTest(original=original_token):
                raw = self.raw(historical('source', {'metadata': {'n': 0}})).replace(
                    b'"n":0', ('"n":' + original_token).encode())
                output, _ = m.migrate(raw)
                equivalent = copy.deepcopy(output)
                equivalent['metadata']['n'] = m.parse(equivalent_token)
                self.assertEqual(m.restore(self.raw(equivalent)), raw)
                self.assertEqual(m.semantic_encode(output), m.semantic_encode(equivalent))
                for wrong in [True, original_token, m.parse('2.1')]:
                    changed = copy.deepcopy(output)
                    changed['metadata']['n'] = wrong
                    receipt = changed['extensions'][m.MARKER]
                    receipt['targetSha256'] = m.digest(m.semantic_encode(
                        {k: v for k, v in changed.items() if k != 'extensions'}).encode())
                    with self.assertRaises(ValueError): m.restore(self.raw(changed))

    def test_symbolic_number_parser_rejects_malformed_and_nonfinite(self):
        for token in ['+1', '01', '1.', '.1', '1e', '1e+', '1e--2', 'NaN', 'Infinity', '-Infinity']:
            with self.subTest(token=token), self.assertRaises(Exception):
                m.read(self.canonical_number_wire(token))
            with self.assertRaises(ValueError): m.RawJsonNumber(token)

    def test_formats_are_enforced_without_silent_optional_checker_skips(self):
        node = {'type': 'string', 'format': 'date-time'}
        m.validate_at('2024-02-29T23:59:59.123456789+00:00', node)
        for value in ['2026-02-29T00:00:00Z', '2026-10-04T24:00:00Z',
                      '2026-10-04T00:00:00+00:99', '2026-10-04', 'not-a-time']:
            with self.subTest(value=value), self.assertRaises(Exception):
                m.validate_at(value, node)
        checker = m.FORMAT.checkers.pop('uri', None)
        try:
            with self.assertRaisesRegex(ValueError, 'format checker unavailable: uri'):
                m.validate_at('https://example.test', {'$ref': '#/$defs/Uri'})
        finally:
            if checker is not None:
                m.FORMAT.checkers['uri'] = checker

    def test_datetime_calendar_and_clock_validation_is_authority_owned(self):
        node = {'type': 'string', 'format': 'date-time'}
        valid = ['2000-02-29T23:59:59Z', '2024-02-29t00:00:00z',
                 '2026-10-04T00:00:00.123456789+23:59', '0001-01-01T00:00:00-00:00']
        invalid = ['1900-02-29T00:00:00Z', '0000-01-01T00:00:00Z',
                   '2026-04-31T00:00:00Z', '2026-00-01T00:00:00Z',
                   '2026-13-01T00:00:00Z', '2026-10-00T00:00:00Z',
                   '2026-10-04T24:00:00Z', '2026-10-04T23:60:00Z',
                   '2026-10-04T23:59:60Z', '2026-10-04T00:00:00+24:00',
                   '2026-10-04T00:00:00-00:60', '2026-10-04T00:00:00.Z',
                   '2026-10-04 00:00:00Z', '2026-10-04T00:00:00Z\n']
        checker = m.FORMAT.checkers['date-time']
        # Simulate an optional/host checker that accepts everything. The
        # authority validator must still enforce both current and old records.
        m.FORMAT.checkers['date-time'] = (lambda value: True, ())
        try:
            for value in valid:
                with self.subTest(valid=value): m.validate_at(value, node)
            for value in invalid:
                with self.subTest(invalid=value):
                    self.assertFalse(m.strict_datetime(value))
                    with self.assertRaises(Exception): m.validate_at(value, node)
                    doc = historical(); doc['date_added'] = value
                    with self.assertRaises(Exception): m.read(self.raw(doc))
        finally:
            m.FORMAT.checkers['date-time'] = checker

    def test_paired_artifacts_and_schema_are_locked(self):
        registry = json.loads((PATH.parent / 'registry.json').read_text())
        for path, expected in registry['sha256'].items():
            self.assertEqual(m.digest((PATH.parent / path).read_bytes()), expected)
        old = json.loads((PATH.parent / 'historical-reader-fixtures.json').read_text())
        new = json.loads((PATH.parent / 'canonical-migration-fixtures.json').read_text())
        for before, after in fixture_pairs(old, new, 28):
            raw = before['sourceUtf8'].encode()
            self.assertEqual(before['name'], after['name'])
            self.assertEqual(m.digest(raw), before['sourceSha256'])
            self.assertEqual(m.restore(self.raw(after['document'])), raw)
            self.assertEqual(m.migrate(raw)[0], after['document'])

    def test_numeric_migration_artifacts_support_equivalent_notation(self):
        old = m.load(PATH.parent / 'numeric-historical-reader-fixtures.json')
        new = m.load(PATH.parent / 'numeric-canonical-migration-fixtures.json')
        for source, target in fixture_pairs(old, new, 6):
            raw = source['sourceUtf8'].encode()
            self.assertEqual(source['name'], target['name'])
            self.assertEqual(m.migrate(raw)[0], target['document'])
            self.assertEqual(m.restore(self.raw(target['document'])), raw)
            equivalent = copy.deepcopy(target['document'])
            equivalent['metadata']['n'] = m.parse(source['equivalentNumberToken'])
            self.assertEqual(m.restore(self.raw(equivalent)), raw)

    def test_cli_read_restore_dry_run_errors(self):
        raw = self.raw(historical())
        def call(*args, value=raw):
            return subprocess.run([sys.executable, str(PATH), *args], input=value, capture_output=True)
        self.assertEqual(call('read').stdout, raw)
        migrated = call('migrate'); self.assertEqual(migrated.returncode, 0, migrated.stderr)
        self.assertEqual(call('restore', value=migrated.stdout).stdout, raw)
        report = json.loads(call('migrate', '--dry-run').stdout)
        self.assertEqual(report['status'], 'migrated'); self.assertNotIn('sourceUtf8', report)
        error = call('migrate', value=b'{}')
        self.assertEqual(error.returncode, 2); self.assertEqual(error.stdout, b'')
        self.assertEqual(json.loads(error.stderr)['status'], 'error')

if __name__ == '__main__': unittest.main()
