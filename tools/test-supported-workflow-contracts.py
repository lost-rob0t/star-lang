#!/usr/bin/env python3
"""Dual-oracle, lossless field-mapping and rejection tests for retained workflows."""
import copy
from decimal import Decimal
import json
from pathlib import Path
import unittest
from jsonschema import Draft202012Validator, FormatChecker

ROOT = Path(__file__).resolve().parents[1] / 'specs/starintel/0.10.1'
SCHEMA = json.loads((ROOT / 'generated/schema.json').read_text())
MANIFEST = json.loads((ROOT / 'generated/portable-manifest.json').read_text())
ORACLE = json.loads((ROOT / 'legacy-workflow-oracle.json').read_text())
MAPPINGS = json.loads((ROOT / 'supported-workflow-mappings.json').read_text())['contracts']
FIXTURES = json.loads((ROOT / 'supported-workflow-fixtures.json').read_text())
FORMAT = FormatChecker()
import sys
sys.path.insert(0,str(ROOT))
from workflow_semantics import validate_workflow_semantics

def definition(name): return ''.join(x.capitalize() for x in name.split('/')[-1].split('-'))
DECIMALS = {definition(t['name']): t for t in MANIFEST['types'] if t['kind']=='scalar' and t['base']=='decimal'}
def constraints(value, node):
    if '$ref' in node:
        name=node['$ref'].split('/')[-1]
        if name in DECIMALS and isinstance(value,str):
            contract=DECIMALS[name]; number=Decimal(value)
            for bound in ['minimum','maximum']:
                if bound in contract and ((bound=='minimum' and number<Decimal(str(contract[bound]))) or (bound=='maximum' and number>Decimal(str(contract[bound])))):
                    raise ValueError('Decimal bound violated: '+name)
        constraints(value,SCHEMA['$defs'][name])
    elif 'anyOf' in node:
        for branch in node['anyOf']:
            if Draft202012Validator({**SCHEMA,**branch},format_checker=FORMAT).is_valid(value):
                constraints(value,branch);break
    elif isinstance(value,dict):
        for key,item in value.items(): constraints(item,node.get('properties',{}).get(key,{}))
    elif isinstance(value,list) and 'items' in node:
        for item in value:constraints(item,node['items'])
def canonical(doc):
    ref={'$ref':'#/$defs/'+definition(doc['dtype'])}
    Draft202012Validator({**SCHEMA,**ref},format_checker=FORMAT).validate(doc)
    constraints(doc,ref)
    validate_workflow_semantics(doc)
def legacy(dtype,data): Draft202012Validator(ORACLE['schemas'][dtype],format_checker=FORMAT).validate(data)
def camel(key):return key.split('_')[0]+''.join(p.title() for p in key.split('_')[1:])
def inverse(schema, wire):
    if wire is None:return None
    if 'anyOf'in schema:return inverse(next(s for s in schema['anyOf'] if s.get('type')!='null'),wire)
    if schema.get('type')=='number':return Decimal(wire)
    if schema.get('type')=='array':return [inverse(schema['items'],item) for item in wire]
    if schema.get('type')=='object' and isinstance(schema.get('additionalProperties'),dict):
        if len({item['key'] for item in wire})!=len(wire):raise ValueError('Duplicate map key')
        return {item['key']:inverse(schema['additionalProperties'],item['value']) for item in wire}
    if schema.get('type')=='object' and 'properties' in schema:
        return {key:inverse(child,wire[camel(key)]) for key,child in schema['properties'].items() if camel(key) in wire}
    return wire

def normalize_numbers(value):
    if isinstance(value,float):return Decimal(str(value))
    if isinstance(value,list):return [normalize_numbers(x) for x in value]
    if isinstance(value,dict):return {k:normalize_numbers(v) for k,v in value.items()}
    return value

class SupportedWorkflowTests(unittest.TestCase):
    def test_paired_original_and_canonical_oracles_and_roundtrip(self):
        self.assertEqual(set(MAPPINGS),set(ORACLE['schemas']))
        for fixture in FIXTURES:
            doc=fixture['document'];dtype=doc['dtype'];data=fixture['legacyData']
            with self.subTest(dtype=dtype):
                legacy(dtype,data)
                canonical(doc)
                canonical(json.loads(json.dumps(doc)))
                recovered={k:inverse(ORACLE['schemas'][dtype]['properties'][k],doc[wire])
                           for k,wire in MAPPINGS[dtype]['fields'].items() if wire in doc}
                self.assertEqual(recovered,normalize_numbers(data))
                self.assertEqual(doc['id'],'fixture:'+dtype)

    def test_old_and_new_reject_matching_invalid_fields(self):
        fixtures={f['document']['dtype']:f for f in FIXTURES}
        for dtype,old,new,bad in [('research-node','status','status','impossible'),('research-node','objective','objective',None),('claim','claim','claim',None)]:
            before=copy.deepcopy(fixtures[dtype]['legacyData']);after=copy.deepcopy(fixtures[dtype]['document'])
            if bad is None:del before[old];del after[new]
            else:before[old]=bad;after[new]=bad
            with self.subTest(dtype=dtype,key=old):
                with self.assertRaises(Exception):legacy(dtype,before)
                with self.assertRaises(Exception):canonical(after)
        for old,new,bad in [('max_depth','maxDepth',0),('max_cost','maxCost',-1)]:
            before=copy.deepcopy(fixtures['research-node']['legacyData']);after=copy.deepcopy(fixtures['research-node']['document'])
            before['limits'][old]=bad;after['limits'][new]=str(bad) if old=='max_cost' else bad
            with self.assertRaises(Exception):legacy('research-node',before)
            with self.assertRaises(Exception):canonical(after)
        before=copy.deepcopy(fixtures['research-node']['legacyData']);after=copy.deepcopy(fixtures['research-node']['document'])
        before['limits']['unknown']=True;after['limits']['unknown']=True
        with self.assertRaises(Exception):legacy('research-node',before)
        with self.assertRaises(Exception):canonical(after)

    def test_dynamic_integer_map_keys_remain_injective(self):
        doc=copy.deepcopy(next(f['document'] for f in FIXTURES if f['document']['dtype']=='dataset-manifest'))
        doc['countsByDtype'].append({'key':doc['countsByDtype'][0]['key'],'value':999})
        with self.assertRaises(ValueError):canonical(doc)

    def test_payload_times_do_not_overwrite_envelope_times(self):
        for fixture in FIXTURES:
            doc=fixture['document']
            self.assertIsInstance(doc['createdAt'],int)
            self.assertIsInstance(doc['validFrom'],int)
            if doc['dtype']=='event':self.assertEqual(doc['contentValidFrom'],'2026-10-04T01:02:03.456789+01:00')
            if doc['dtype']=='research-node':self.assertEqual(doc['nodeCreatedAt'],'2026-10-04T01:02:03.456789+01:00')

if __name__=='__main__':unittest.main()
