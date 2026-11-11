"""Tests of the install pack generator. Standard library only (unittest); pytest runs them too.

Run:  python test_gen_install.py
Needs the speed-merchants repo beside ai-setup (or PACKGEN_TOOLS = <speed-merchants>\\CrewChief\\packs\\tools).
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

# Names other packs and TestAutoManager call: they never change.
NAMES = {'install-addons', 'install-build-get', 'install-clean', 'install-clean-base-prep', 'install-configure-new',
         'install-configure-upgrade', 'install-preflight', 'install-programs', 'install-remove', 'install-remove-preview',
         'install-upgrade', 'install-verify'}
TESTS = ('install-clean', 'install-clean-base-prep', 'install-upgrade')
OWNER = 'Give The Database To The System Administrator Login'


def generate(root):
    done = subprocess.run([sys.executable, os.path.join(HERE, 'gen_install.py'), root], capture_output=True, text=True,
                          env=dict(os.environ, PACKGEN_TOOLS=TOOLS))
    if done.returncode != 0:
        raise RuntimeError(done.stderr)


class InstallPack(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls._tmp = tempfile.TemporaryDirectory()
        cls.root = os.path.join(cls._tmp.name, 'install')
        generate(cls.root)
        cls.workloads = {}
        for path in glob.glob(os.path.join(cls.root, 'workloads', 'install', '**', '*.workload.json'), recursive=True):
            with open(path, encoding='utf-8') as f:
                w = json.load(f)
            cls.workloads[w['name']] = w

    @classmethod
    def tearDownClass(cls):
        cls._tmp.cleanup()

    def labels(self, name):
        return [s['label'] for s in self.workloads[name]['steps']]

    def test_workload_names(self):
        self.assertEqual(NAMES, set(self.workloads))

    def test_api_key_is_the_common_workload(self):
        for w in self.workloads.values():
            for s in w['steps']:
                self.assertNotEqual('SetApiKeyStep', s['inline']['type'], w['name'])
        for name in ('install-configure-new', 'install-configure-upgrade'):
            last = self.workloads[name]['steps'][-1]['inline']
            self.assertEqual('common-api-key-set', last['workloadName'])
            # The common workload reads the box from its caller's values.
            for box in ('ApplicationServerName', 'DatabaseServerName', 'ProfiseeDatabaseName', 'ProfiseeInstanceName', 'ProfiseeBaseUrl'):
                self.assertIn(box, self.workloads[name]['globalParameters'], name)

    def test_owner_step_position(self):
        self.assertEqual(0, self.labels('install-configure-upgrade').index(OWNER))
        self.assertEqual(2, self.labels('install-configure-new').index(OWNER))

    def test_build_and_version_are_inputs_never_globals(self):
        for w in self.workloads.values():
            for name in ('AdoBranch', 'AdoBuildId', 'ProfiseeVersionNumber', 'ProfiseeVersionCode'):
                if w['name'] == 'install-preflight' and name == 'AdoBranch':
                    continue    # the preflight only reads the branch to show its newest build; nothing passes it one
                self.assertNotIn(name, w['globalParameters'], w['name'])
        for name in TESTS:
            inputs = {i['name']: i for i in self.workloads[name]['inputs']}
            self.assertEqual('{{$ref:install/build:AdoBranch}}', inputs['AdoBranch']['default'])
            self.assertEqual('', inputs['AdoBuildId']['default'])
            self.assertEqual('{{$ref:install/environment:ProfiseeVersionNumber}}', inputs['ProfiseeVersionNumber']['default'])

    def test_version_input_is_the_same_everywhere(self):
        seen = {json.dumps(i, sort_keys=True) for w in self.workloads.values() for i in w.get('inputs', [])
                if i['name'] == 'ProfiseeVersionNumber'}
        self.assertEqual(1, len(seen))

    def test_reference_sets_are_never_overwritten(self):
        path = os.path.join(self.root, 'reference-kv', 'install', 'machines.json')
        with open(path, encoding='utf-8') as f:
            before = f.read()

        def restore():
            with open(path, 'w', encoding='utf-8', newline='') as f:
                f.write(before)
        self.addCleanup(restore)
        edited = before.replace('"ApplicationServerName":', '"ApplicationServerName" :', 1)
        self.assertNotEqual(before, edited)
        with open(path, 'w', encoding='utf-8', newline='') as f:
            f.write(edited)
        generate(self.root)
        with open(path, encoding='utf-8', newline='') as f:
            self.assertEqual(edited, f.read())

    def test_retired_workload_file_is_removed(self):
        stale = os.path.join(self.root, 'workloads', 'install', 'internal', 'install-api-key-set.workload.json')
        with open(stale, 'w', encoding='utf-8') as f:
            f.write('{}')
        generate(self.root)
        self.assertFalse(os.path.exists(stale))


if __name__ == '__main__':
    unittest.main()
