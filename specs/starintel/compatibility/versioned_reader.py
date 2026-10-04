#!/usr/bin/env python3
"""Versioned archival reader and bounded, non-destructive migration reference.

Requires jsonschema. No SDK dependency, repository writes or schema generation.
"""
from __future__ import annotations
import argparse
from copy import deepcopy
from decimal import Decimal
from datetime import datetime
import re
import hashlib
import json
from pathlib import Path
import sys
from jsonschema import Draft202012Validator, FormatChecker, validators
from jsonschema.exceptions import ValidationError as SchemaValidationError

HERE = Path(__file__).resolve().parent
RELEASE = HERE.parent / '0.10.1'
sys.path.insert(0, str(RELEASE))
sys.path.insert(0, str(HERE))
from raw_json_numbers import RawJsonNumber, parse_fraction
from operation_semantics import validate_operation_semantics
from workflow_semantics import validate_workflow_semantics

# JSON Schema's integer is mathematical, not a host-language storage class.
# Exact exponent/fraction lexemes like 1e0 must not fail merely for using Decimal.
def is_integer(checker, value):
    if isinstance(value, RawJsonNumber):
        return value.is_integer()
    return not isinstance(value, bool) and (isinstance(value, int) or
        isinstance(value, Decimal) and value.is_finite() and value == value.to_integral_value())


def is_number(checker, value):
    return isinstance(value, RawJsonNumber) or Draft202012Validator.TYPE_CHECKER.is_type(value, 'number')


EXACT = Draft202012Validator.TYPE_CHECKER.redefine_many({'integer': is_integer, 'number': is_number})
Validator = validators.extend(Draft202012Validator, type_checker=EXACT)
FORMAT = FormatChecker()
MARKER = 'starintelVersionedMigration'


@FORMAT.checks('date-time', raises=ValueError)
def strict_datetime(value):
    if not isinstance(value, str):
        return True
    if not re.fullmatch(r'[0-9]{4}-[0-9]{2}-[0-9]{2}[Tt][0-9]{2}:[0-9]{2}:[0-9]{2}(?:\.[0-9]+)?(?:[Zz]|[+-][0-9]{2}:[0-9]{2})', value):
        return False
    datetime.fromisoformat(value.upper().replace('Z', '+00:00'))
    # datetime normalizes out-of-range offset minutes; RFC3339 forbids them.
    if value[-1:].upper() != 'Z' and (int(value[-5:-3]) > 23 or int(value[-2:]) > 59):
        return False
    return True



class DecimalExpansionLimit(ValueError):
    """A valid value requires unbounded plain-decimal output expansion."""


def reject(message):
    raise ValueError(message)


def pairs(items):
    result = {}
    for key, value in items:
        if key in result:
            reject('duplicate JSON key: ' + key)
        result[key] = value
    return result


def parse(raw):
    return json.loads(raw, parse_float=parse_fraction,
                      parse_int=lambda token: Decimal(token) if token == '-0' else int(Decimal(token)),
                      object_pairs_hook=pairs,
                      parse_constant=lambda x: reject('non-finite JSON: ' + x))


def encode(value):
    """JSON without binary floating-point conversion, including opaque maps."""
    if isinstance(value, RawJsonNumber):
        return value.token
    if isinstance(value, int) and not isinstance(value, bool):
        return str(Decimal(value))
    if isinstance(value, Decimal):
        if not value.is_finite():
            reject('non-finite decimal')
        return str(value)
    if isinstance(value, dict):
        return '{' + ','.join(json.dumps(k, ensure_ascii=False) + ':' + encode(v)
                              for k, v in sorted(value.items())) + '}'
    if isinstance(value, list):
        return '[' + ','.join(map(encode, value)) + ']'
    return json.dumps(value, ensure_ascii=False, allow_nan=False)


def semantic_encode(value):
    """Deterministic exact numeric-value encoding for receipts, not wire output.

    Distinguish strings/booleans from numbers, but equate 1e3 with 1000 and
    signed zero with zero. Never allocate zeros according to exponent value.
    """
    if isinstance(value, (RawJsonNumber, Decimal, int, float)) and not isinstance(value, bool):
        number = value if isinstance(value, RawJsonNumber) else RawJsonNumber(encode(value))
        sign, digits, order = number._components
        if not sign:
            return '0'
        exponent = order - len(digits)
        return ('-' if sign < 0 else '') + digits + ('e' + str(Decimal(exponent)) if exponent else '')
    if isinstance(value, dict):
        return '{' + ','.join(json.dumps(k, ensure_ascii=False) + ':' + semantic_encode(v)
                              for k, v in sorted(value.items())) + '}'
    if isinstance(value, list):
        return '[' + ','.join(map(semantic_encode, value)) + ']'
    return encode(value)


def digest(raw):
    return hashlib.sha256(raw).hexdigest()


def load(path):
    return parse(path.read_bytes())


REGISTRY = load(HERE / 'registry.json')
for relative, expected in REGISTRY['sha256'].items():
    if digest((HERE / relative).read_bytes()) != expected:
        reject('pinned artifact hash mismatch: ' + relative)

SCHEMA = load(RELEASE / 'generated/schema.json')
LEGACY = load(HERE / '0.9.0/schema.json')
MAPPINGS = load(RELEASE / 'supported-workflow-mappings.json')['contracts']
MANIFEST = load(RELEASE / 'generated/portable-manifest.json')
TYPES = {t['name'].rsplit('/', 1)[1]: ''.join(p.title() for p in t['name'].rsplit('/', 1)[1].split('-'))
         for t in MANIFEST['types'] if t['kind'] == 'document' and t['persistence'] == 'persistent'}
DECIMALS = {''.join(part.title() for part in t['name'].rsplit('/', 1)[1].split('-')): t
            for t in MANIFEST['types'] if t.get('base') == 'decimal'}


def validate_at(value, node):
    if isinstance(node.get('format'), str) and node['format'] not in FORMAT.checkers:
        reject('required JSON format checker unavailable: ' + node['format'])
    Validator({**SCHEMA, **node}, format_checker=FORMAT).validate(value)
    if '$ref' in node:
        name = node['$ref'].rsplit('/', 1)[1]
        c = DECIMALS.get(name)
        if c:
            number = Decimal(value)
            if 'minimum' in c and number < c['minimum']:
                reject('decimal below minimum')
            if 'maximum' in c and number > c['maximum']:
                reject('decimal above maximum')
            if 'scale' in c and len(value.partition('.')[2]) > c['scale']:
                reject('decimal exceeds scale')
        validate_at(value, SCHEMA['$defs'][name])
    elif 'anyOf' in node:
        for branch in node['anyOf']:
            if Validator({**SCHEMA, **branch}, format_checker=FORMAT).is_valid(value):
                validate_at(value, branch)
                break
    elif isinstance(value, dict):
        for k, v in value.items():
            child = node.get('properties', {}).get(k, node.get('additionalProperties', {}))
            if isinstance(child, dict):
                validate_at(v, child)
    elif isinstance(value, list) and isinstance(node.get('items'), dict):
        for v in value:
            validate_at(v, node['items'])


def canonical_validate(document):
    if document.get('schemaVersion') != '0.10.1' or document.get('dtype') not in TYPES:
        reject('unsupported canonical version or dtype')
    validate_at(document, {'$ref': '#/$defs/' + TYPES[document['dtype']]})
    validate_operation_semantics(document)
    validate_workflow_semantics(document)


def read(raw):
    """Validate original version without migration. Return detached parsed data."""
    if not isinstance(raw, bytes):
        reject('reader requires original UTF-8 bytes')
    document = parse(raw.decode('utf-8'))
    if not isinstance(document, dict):
        reject('document must be an object')
    if 'schema_version' in document and 'schemaVersion' in document:
        reject('ambiguous wire profiles')
    if document.get('schema_version') == '0.9.0':
        Validator(LEGACY, format_checker=FORMAT).validate(document)
        profile = 'nested-0.9.0-cb258634'
    elif document.get('schemaVersion') == '0.10.1':
        canonical_validate(document)
        profile = 'canonical-0.10.1'
    else:
        reject('unsupported version/profile; no version inference or relabeling')
    return {'profile': profile, 'document': document, 'sourceSha256': digest(raw)}


def camel(key):
    head, *rest = key.split('_')
    return head + ''.join(p[:1].upper() + p[1:] for p in rest)


def convert(value, node):
    if '$ref' in node:
        return convert(value, SCHEMA['$defs'][node['$ref'].rsplit('/', 1)[1]])
    if 'anyOf' in node:
        if value is None and any(n.get('type') == 'null' for n in node['anyOf']):
            return None
        for branch in node['anyOf']:
            try:
                result = convert(value, branch)
                validate_at(result, branch)
                return result
            except (ValueError, TypeError, SchemaValidationError) as error:
                last = error
        raise ValueError('no lossless native branch') from last
    if node.get('type') == 'string' and node.get('pattern') == '^[+-]?[0-9]+(?:\\.[0-9]+)?$':
        if isinstance(value, bool) or not isinstance(value, (int, Decimal, RawJsonNumber)):
            reject('historical numeric decimal expected')
        # A native plain decimal string requires materialized zeros. Never expand
        # a hostile exponent; preserve oversized optional conversions in source.
        symbolic = value if isinstance(value, RawJsonNumber) else RawJsonNumber(str(Decimal(value)))
        sign, digits, order = symbolic._components
        if sign and (order > max(10000, len(digits)) or len(digits) - order > max(10000, len(digits))):
            raise DecimalExpansionLimit('native decimal expansion exceeds bounded migration output; retain original')
        if not sign and (isinstance(value, RawJsonNumber) or
                         isinstance(value, Decimal) and abs(value.as_tuple().exponent) > 10000):
            return '-0' if (value.token.startswith('-') if isinstance(value, RawJsonNumber) else value.is_signed()) else '0'
        if isinstance(value, RawJsonNumber):
            value = Decimal(value.token)
        return format(Decimal(value), 'f')
    if node.get('type') == 'object' and isinstance(value, dict) and 'properties' in node:
        result = {}
        for k, v in value.items():
            wire = k if k in node['properties'] else camel(k)
            if wire not in node['properties'] or wire in result:
                reject('unknown structured key or normalized collision: ' + k)
            result[wire] = convert(v, node['properties'][wire])
        return result
    if node.get('type') == 'array':
        child = node.get('items', {})
        resolved = SCHEMA['$defs'].get(child.get('$ref', '').rsplit('/', 1)[-1], child)
        if isinstance(value, dict) and set(resolved.get('properties', {})) == {'key', 'value'}:
            return [{'key': k, 'value': convert(v, resolved['properties']['value'])} for k, v in value.items()]
        if isinstance(value, list):
            return [convert(v, child) for v in value]
    return deepcopy(value)


def migrate(raw):
    original = read(raw)
    if original['profile'] == 'canonical-0.10.1':
        return original['document'], {'status': 'unchanged', 'sourceSha256': digest(raw), 'mapping': []}
    doc = original['document']
    if doc['dtype'] not in MAPPINGS:
        reject('unsupported migration dtype: ' + doc['dtype'])
    output = {'id': doc['_id'], 'dataset': doc['dataset'], 'dtype': doc['dtype'], 'schemaVersion': '0.10.1'}
    definition = SCHEMA['$defs'][TYPES[doc['dtype']]]
    fields = MAPPINGS[doc['dtype']]['fields']
    report = {'status': 'migrated', 'sourceProfile': original['profile'], 'targetProfile': 'canonical-0.10.1',
              'sourceSha256': digest(raw), 'mapping': []}
    for key in doc:
        target = {'_id': 'id', 'dataset': 'dataset', 'dtype': 'dtype', 'schema_version': 'schemaVersion'}.get(key)
        if key != 'data':
            report['mapping'].append({'source': '/' + key, 'target': '/' + target if target else None,
                                      'action': 'mapped' if target else 'retained-original'})
    for key, value in doc['data'].items():
        wire = fields.get(key)
        item = {'source': '/data/' + key, 'target': '/' + wire if wire else None}
        if wire in output:
            reject('envelope/payload collision')
        try:
            if wire is None:
                reject('no explicit field mapping')
            converted = convert(value, definition['properties'][wire])
            validate_at(converted, definition['properties'][wire])
            output[wire] = converted
            item['action'] = 'mapped'
        except (ValueError, TypeError, SchemaValidationError) as error:
            if wire in definition['required']:
                raise ValueError('required native field cannot be migrated: ' + str(wire)) from error
            item.update(action='retained-original', reason=('native-decimal-expansion-limit'
                if isinstance(error, DecimalExpansionLimit) else 'no-lossless-native-representation'))
        report['mapping'].append(item)
    # Validate before adding provenance; missing required data is never fabricated.
    canonical_validate(output)
    target_hash = digest(semantic_encode(output).encode('utf-8'))
    output['extensions'] = {MARKER: {'contract': 'starintel-migration/1',
        'sourceProfile': original['profile'], 'sourceSha256': digest(raw),
        'sourceUtf8': raw.decode('utf-8'), 'targetSha256': target_hash, 'report': report}}
    canonical_validate(output)
    return output, report


def restore(raw):
    current = read(raw)
    if current['profile'] != 'canonical-0.10.1':
        reject('restore requires canonical migration output')
    document = deepcopy(current['document'])
    extension = document.pop('extensions', {})
    if set(extension) != {MARKER}:
        reject('missing or modified migration provenance')
    provenance = extension[MARKER]
    if provenance.get('contract') != 'starintel-migration/1':
        reject('unsupported migration contract')
    if digest(semantic_encode(document).encode('utf-8')) != provenance['targetSha256']:
        reject('canonical document edited; reverse projection is unsupported')
    source = provenance['sourceUtf8'].encode('utf-8')
    if digest(source) != provenance['sourceSha256']:
        reject('original digest mismatch')
    if provenance['sourceProfile'] != 'nested-0.9.0-cb258634' or read(source)['profile'] != provenance['sourceProfile']:
        reject('original profile mismatch')
    # Caller-editable hashes are only corruption checks. Re-derive the complete
    # permitted target and receipt from the source, so recomputing a hash cannot
    # make edited or unrelated canonical content an archival migration result.
    expected, _ = migrate(source)
    if semantic_encode(expected) != semantic_encode(current['document']):
        reject('source/target/report are not a consistent migration')
    return source


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=['read', 'migrate', 'restore'])
    parser.add_argument('--dry-run', action='store_true')
    args = parser.parse_args()
    raw = sys.stdin.buffer.read()
    try:
        if args.command == 'read':
            read(raw)
            result = raw
        elif args.command == 'restore':
            result = restore(raw)
        else:
            document, report = migrate(raw)
            result = (encode(report) if args.dry_run else encode(document)).encode('utf-8')
        sys.stdout.buffer.write(result)
    except Exception as error:
        print(encode({'status': 'error', 'message': str(error)}), file=sys.stderr)
        return 2
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
