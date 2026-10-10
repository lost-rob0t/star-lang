#!/usr/bin/env python3
"""Run shared raw JSON cases against the authority reader and optional SDK CLIs.

Each adapter command must implement the canonical roundtrip request/response
protocol. Wire documents are concatenated verbatim, never decoded/re-encoded
before reaching that process. Rejections must identify duplicate keys, so a
missing runtime or dependency cannot masquerade as a successful rejection.
"""
import argparse
import importlib.util
import json
from pathlib import Path
import re
import shlex
import subprocess

ROOT = Path(__file__).resolve().parents[1]
FIXTURE = ROOT / 'specs/starintel/wire/raw-json-unique-keys.json'
READER = ROOT / 'specs/starintel/compatibility/versioned_reader.py'


def same_value(left, right):
    if isinstance(left, dict) and isinstance(right, dict):
        return left.keys() == right.keys() and all(same_value(left[k], right[k]) for k in left)
    if isinstance(left, list) and isinstance(right, list):
        return len(left) == len(right) and all(same_value(a, b) for a, b in zip(left, right))
    if isinstance(left, bool) or isinstance(right, bool):
        return type(left) is type(right) and left == right
    return left == right


def require(condition, message):
    if not condition:
        raise ValueError(message)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--adapter', action='append', default=[], metavar='NAME=COMMAND')
    parser.add_argument('--report', type=Path)
    args = parser.parse_args()
    spec = importlib.util.spec_from_file_location('raw_json_reference', READER)
    reader = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(reader)
    fixture = json.loads(FIXTURE.read_text(encoding='utf-8'))
    require(fixture.get('contract') == 'starintel.raw-json-unique-keys/1',
            'raw JSON fixture contract mismatch')
    cases = fixture['cases']
    require(isinstance(cases, list) and all(isinstance(case, dict) and
            isinstance(case.get('name'), str) for case in cases),
            'raw JSON fixture cases must be named objects')
    require(len({case['name'] for case in cases}) == len(cases),
            'duplicate raw JSON fixture case')
    require(all(type(case.get('valid')) is bool for case in cases),
            'raw JSON fixture validity must be boolean')
    require(any(case.get('valid') is True for case in cases) and
            any(case.get('valid') is False for case in cases),
            'raw JSON fixture must include accepted and rejected cases')
    reports = []
    for case in cases:
        require(type(case.get('valid')) is bool, 'raw JSON fixture validity must be boolean')
        try:
            reader.parse(case['wire'])
            accepted = True
        except ValueError as error:
            require('duplicate JSON key' in str(error),
                    f"unexpected reference rejection for {case['name']}: {error}")
            accepted = False
        require(accepted == case['valid'],
                f"authority raw JSON case mismatch: {case['name']} accepted={accepted}")
    print(f'authority: {len(cases)} raw JSON key cases passed', flush=True)
    failures = []
    for adapter in args.adapter:
        name, separator, command = adapter.partition('=')
        if not separator or not name or not command:
            parser.error('--adapter requires NAME=COMMAND')
        for case in cases:
            request = '{"command":"roundtrip","document":' + case['wire'] + '}'
            run = subprocess.run(shlex.split(command), input=request, text=True,
                                 encoding='utf-8', capture_output=True, timeout=90)
            accepted = run.returncode == 0
            correct = accepted == case['valid']
            diagnostic = ''
            if accepted:
                try:
                    response = reader.parse(run.stdout)
                    correct = correct and response.get('ok') is True and same_value(
                        response['document'], reader.parse(case['wire']))
                except (ValueError, KeyError, AttributeError) as error:
                    correct = False
                    diagnostic = str(error)
            else:
                duplicate = re.search(r'duplicate[ _-]+(?:json[ _-]+)?key',
                                      run.stdout + run.stderr, re.IGNORECASE)
                correct = correct and duplicate is not None
            row = dict(adapter=name, case=case['name'], expected=case['valid'],
                       accepted=accepted, passed=correct, returncode=run.returncode)
            if not correct:
                row.update(stdout=run.stdout, stderr=run.stderr[-4000:], diagnostic=diagnostic)
                failures.append(row)
            reports.append(row)
        failed = sum(not row['passed'] for row in reports if row['adapter'] == name)
        print(f'{name}: {len(cases) - failed}/{len(cases)} raw JSON key cases passed', flush=True)
    if args.report:
        args.report.write_text(json.dumps(dict(contract=fixture['contract'], results=reports),
                                         ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    if failures:
        raise SystemExit(json.dumps(failures, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()
