"""Tests of the common pack generator. Standard library only (unittest); pytest runs them too.

Run:  python test_gen_common.py
Needs the speed-merchants repo beside ai-setup (or PACKGEN_TOOLS = <speed-merchants>\\CrewChief\\packs\\tools) and pwsh.
"""
import glob
import json
import os
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
TOOLS = os.environ.get('PACKGEN_TOOLS') or os.path.abspath(
    os.path.join(HERE, '..', '..', '..', '..', 'speed-merchants', 'CrewChief', 'packs', 'tools'))
sys.path.insert(0, TOOLS)
from packgen.testing import run_ps  # noqa: E402

NAMES = {'common-api-key-set', 'common-base-backup-check', 'common-health-wait', 'common-instance-pools',
         'common-instance-start', 'common-instance-stop', 'common-testauto-tag-check'}
DEFAULTED = {'PoolAction': 'Recycle', 'AllowNone': 'false', 'ProfiseeApiKey': '{{$config:RestKeys:ProfiseeRestKey}}'}


class CommonPack(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls._tmp = tempfile.TemporaryDirectory()
        cls.root = os.path.join(cls._tmp.name, 'common')
        done = subprocess.run([sys.executable, os.path.join(HERE, 'gen_common.py'), cls.root], capture_output=True, text=True,
                              env=dict(os.environ, PACKGEN_TOOLS=TOOLS))
        if done.returncode != 0:
            raise RuntimeError(done.stderr)
        cls.workloads = {}
        for path in glob.glob(os.path.join(cls.root, 'workloads', 'common', 'internal', '*.workload.json')):
            with open(path, encoding='utf-8') as f:
                w = json.load(f)
            cls.workloads[w['name']] = w

    @classmethod
    def tearDownClass(cls):
        cls._tmp.cleanup()

    def test_workload_names(self):
        self.assertEqual(NAMES, set(self.workloads))

    def test_no_reference_data_and_no_box_value(self):
        self.assertFalse(os.path.exists(os.path.join(self.root, 'reference-kv')))
        for w in self.workloads.values():
            self.assertNotIn('$ref:', json.dumps(w), w['name'])
            for name, value in w['globalParameters'].items():
                self.assertTrue(value == '' or value.startswith('{{$config:'), '%s global %s' % (w['name'], name))

    def test_inputs_are_described_and_have_no_default(self):
        for w in self.workloads.values():
            self.assertTrue(w.get('inputs'), w['name'])
            for i in w['inputs']:
                self.assertTrue(i['description'], '%s input %s' % (w['name'], i['name']))
                if i['name'] in DEFAULTED:
                    self.assertEqual(DEFAULTED[i['name']], i['default'])
                else:
                    self.assertNotIn('default', i, '%s input %s' % (w['name'], i['name']))

    def test_api_key_is_set_in_one_place(self):
        holders = [w['name'] for w in self.workloads.values() if any(s['inline']['type'] == 'SetApiKeyStep' for s in w['steps'])]
        self.assertEqual(['common-api-key-set'], holders)
        labels = [s['label'] for s in self.workloads['common-api-key-set']['steps']]
        self.assertEqual(['Stop The Instance', 'Set API Key', 'Start The Instance', 'Wait For Every Service',
                          'Verify API Key Through Gateway', 'Verify API Key Through Data Service'], labels)

    def tag_script(self):
        return self.workloads['common-testauto-tag-check']['steps'][0]['inline']['scriptContent']

    def test_tag_check_trims_items_and_skips_blanks(self):
        # Review focus 3: "a, b,," is a and b.
        self.assertIn("-split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ } | Select-Object -Unique", self.tag_script())

    def test_tag_check_empty_list_fails_before_any_call(self):
        code, _out, err = run_ps(self.tag_script(), {'{{TagKeys}}': ' , ', '{{TestAutoBaseUrl}}': 'https://127.0.0.1:1',
                                                     '{{ProfiseeVersionCode}}': 'V', '{{SetupName}}': 'demo-setup', '{{AllowNone}}': 'false'})
        self.assertNotEqual(0, code)
        self.assertIn('TagKeys is empty', err)

    def test_tag_check_missing_key_message_names_the_setup(self):
        # Review focus 4: the message says which workload to run, not "No TestAuto workflow carries tag".
        script = self.tag_script()
        self.assertIn('Run $setup', script)
        self.assertIn("do not exist for this box and version", script)

    def test_service_is_found_never_named(self):
        for name in ('common-instance-stop', 'common-instance-start'):
            w = self.workloads[name]
            labels = [s['label'] for s in w['steps']]
            self.assertLess(labels.index('Find The Instance Service'), labels.index(next(l for l in labels if 'Profisee Service' in l)))
            self.assertEqual('', w['globalParameters']['InstanceServiceName'])


if __name__ == '__main__':
    unittest.main()
