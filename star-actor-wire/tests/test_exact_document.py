"""Actual CL lifecycle codec checked against the pinned authority document reader."""
import os
import subprocess
import sys
import unittest
from pathlib import Path
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'specs/starintel/compatibility'))
import versioned_reader as authority
FIXTURES = ROOT / 'fixtures/actor2actor/lifecycle-v1'

class ExactDocumentWire(unittest.TestCase):
    def invoke(self, text, mode='document'):
        env = dict(os.environ, STAR_WIRE_SMOKE_MODE=mode)
        return subprocess.run([env.get('STAR_WIRE_SBCL', 'sbcl'), '--noinform', '--no-sysinit',
                               '--script', str(Path(__file__).with_name('exact-wire-smoke.lisp'))],
                              input=text, text=True, capture_output=True, env=env, timeout=30)

    def test_real_document_through_actual_codec_and_snapshot(self):
        source = (FIXTURES / 'exact-document.json').read_text()
        document = authority.read(source.encode())['document']
        result = self.invoke(source)
        self.assertEqual(result.returncode, 0, result.stderr[-2000:])
        decoded = authority.parse(result.stdout)
        returned = decoded['payload']['document']
        authority.canonical_validate(returned)
        self.assertEqual(document, returned)
        self.assertIn('1e999999999999999999999', result.stdout)
        self.assertIn('0.12345678901234567890123456789', result.stdout)
        self.assertIn('9007199254740993', result.stdout)
        self.assertIn('-1234567890123456789012345678901234567890', result.stdout)
        self.assertFalse(returned['extensions']['__proto__']['polluted'])
        self.assertNotIn('missing', returned['extensions']['nested'])
        self.assertEqual(result.stdout, (FIXTURES / 'exact-request.json').read_text())
        roundtrip = self.invoke(result.stdout, 'command')
        self.assertEqual(roundtrip.returncode, 0, roundtrip.stderr[-2000:])
        self.assertEqual(result.stdout, roundtrip.stdout)

    def test_reply_is_not_command(self):
        result = self.invoke((FIXTURES / 'exact-reply.json').read_text(), 'command')
        self.assertNotEqual(result.returncode, 0)

    def test_json_rejection_before_encode(self):
        for bad in ['{"a":null,"a":false}', '{"x":1e+}', '{"x":01}', '{"x":NaN}']:
            with self.subTest(bad=bad):
                self.assertNotEqual(self.invoke(bad).returncode, 0)

if __name__ == '__main__':
    unittest.main()
