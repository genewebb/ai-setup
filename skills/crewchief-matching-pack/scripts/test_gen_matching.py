"""Tests of the Matching pack generator. Standard library only (unittest); pytest runs them too.

Run:  python test_gen_matching.py
Needs the speed-merchants repo beside ai-setup (or PACKGEN_TOOLS = <speed-merchants>\\CrewChief\\packs\\tools) and pwsh.

The generator runs into a temporary folder. The template tests run the generated PowerShell for real and compare what it
would send to TestAuto with golden_matching_workflows.json: the 25 workflows and 25 run profiles of the pack as generated
before the 11/11 redesign (one copy per size then). Equal = what TestAuto runs did not change. A step configuration is
compared as parsed JSON (its hash), because the stored text may be indented or compact.
"""
import glob
import hashlib
import json
import os
import re
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
TOOLS = os.environ.get('PACKGEN_TOOLS') or os.path.abspath(
    os.path.join(HERE, '..', '..', '..', '..', 'speed-merchants', 'CrewChief', 'packs', 'tools'))
sys.path.insert(0, TOOLS)
from packgen.testing import expand, run_ps  # noqa: E402
from packgen.values import has_value_in_name  # noqa: E402

SIZES = '1K=1000,10K=10000,100K=100000,1M=1000000,100M=100000000'
ROWS = {'{{$ref:matching/sizes:*}}': SIZES}
EXPECTED = {
    'internal': {'matching-all', 'matching-scenario1-load', 'matching-scenario1', 'matching-scenario2', 'matching-scenario3a',
                 'matching-scenario3b', 'matching-scenario3c'},
    'schedule': {'schedule-matching'},
    'start': {'matching-base-create', 'matching-preflight', 'matching-setup'},
    'tests': {'matching-test'},
}
SCENARIOS = ('1', '2', '3a', '3b', '3c')
PROFILE_MARKER = '# ---- upsert the run profiles'
# Text that names the workload or the retired reference set; it changed with the redesign and nothing reads it.
OLD_KEY_NOTE = re.compile(r' \(reference key matching/workflows:[a-z0-9-]+\)')
OLD_RUNNER = re.compile(r"'matching-\d+[km]-(scenario\w+)'")


def config_hash(text):
    return hashlib.sha256(json.dumps(json.loads(text), sort_keys=True, ensure_ascii=False).encode('utf-8')).hexdigest()


def generate(root):
    done = subprocess.run([sys.executable, os.path.join(HERE, 'gen_matching.py'), root], capture_output=True, text=True,
                          env=dict(os.environ, PACKGEN_TOOLS=TOOLS))
    if done.returncode != 0:
        raise RuntimeError(done.stderr)


class GeneratedPack(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls._tmp = tempfile.TemporaryDirectory()
        cls.root = os.path.join(cls._tmp.name, 'matching')
        generate(cls.root)
        cls.workloads = {}
        for path in glob.glob(os.path.join(cls.root, 'workloads', 'matching', '*', '*.workload.json')):
            with open(path, encoding='utf-8') as f:
                w = json.load(f)
            w['_folder'] = os.path.basename(os.path.dirname(path))
            w['_file'] = os.path.basename(path)
            cls.workloads[w['name']] = w
        with open(os.path.join(HERE, 'golden_matching_workflows.json'), encoding='utf-8') as f:
            golden = json.load(f)
        cls.golden, cls.golden_profiles = golden['workflows'], golden['profiles']
        cls.setup_steps = {s['label']: s for s in cls.workloads['matching-setup']['steps']}
        cls.templates = [cls.setup_steps[f'Upsert Scenario {scn} Workflows'] for scn in SCENARIOS]

    @classmethod
    def tearDownClass(cls):
        cls._tmp.cleanup()

    def inputs(self, name):
        return {i['name']: i.get('default') for i in self.workloads[name].get('inputs', [])}

    def labels(self, name):
        return [s['label'] for s in self.workloads[name]['steps']]

    def expand_all(self, rows=None):
        got = {}
        for step in self.templates:
            for spec in expand(step, rows or ROWS):
                self.assertNotIn(spec['Key'], got)
                got[spec['Key']] = spec
        return got

    def profiles(self, rows=None):
        script = self.setup_steps['Upsert Run Profiles']['inline']['scriptContent'].replace('\r\n', '\n')
        expansion = script[:script.index('\n' + PROFILE_MARKER)]
        code, out, err = run_ps(expansion + "\n$specs | ForEach-Object { $_ }\n", rows or ROWS)
        self.assertEqual(0, code, err)
        return [p for line in out.splitlines() if line.strip() for p in json.loads(line)]

    # ---------------------------------------------------------------- shape
    def test_workload_name_set_is_exact(self):
        got = {}
        for w in self.workloads.values():
            got.setdefault(w['_folder'], set()).add(w['name'])
            self.assertEqual(w['name'] + '.workload.json', w['_file'])
        self.assertEqual(EXPECTED, got)

    def test_no_size_in_any_name_or_file_name(self):
        for w in self.workloads.values():
            self.assertFalse(has_value_in_name(w['name']), w['name'])
            self.assertIsNone(re.search(r'\d+[km]\b', w['name']), w['name'])

    def test_run_values_are_inputs_never_globals(self):
        for w in self.workloads.values():
            for name in ('Size', 'SizeLabel', 'RecordCount', 'SourceTableName', 'ProfiseeVersionCode', 'ProfiseeVersionNumber'):
                self.assertNotIn(name, w['globalParameters'], w['name'])

    def test_size_inputs(self):
        self.assertEqual('1K', self.inputs('matching-test')['Size'])
        for name in ['matching-scenario1-load'] + ['matching-scenario' + s for s in SCENARIOS]:
            got = self.inputs(name)
            self.assertEqual('1K', got['Size'], name)
            self.assertEqual('{{$ref:matching/sizes:{{Size}}}}', got['RecordCount'], name)
        self.assertEqual('RetailClient{{Size}}Scenario1', self.inputs('matching-scenario1-load')['SourceTableName'])

    def test_version_inputs_have_the_family_default_everywhere(self):
        for w in self.workloads.values():
            got = self.inputs(w['name'])
            for name in ('ProfiseeVersionCode', 'ProfiseeVersionNumber'):
                if name in got:
                    self.assertEqual('{{$ref:matching/environment:%s}}' % name, got[name], w['name'])
        # A workload that runs Configuration (install-configure-upgrade) carries the version number too.
        for name in ('matching-scenario1-load', 'matching-all', 'matching-test', 'matching-base-create'):
            self.assertIn('ProfiseeVersionNumber', self.inputs(name), name)

    def test_every_plain_token_in_a_step_is_declared(self):
        token = re.compile(r'\{\{([A-Za-z][A-Za-z0-9]*)(?:\|[^}]*)?\}\}')
        for w in self.workloads.values():
            declared = set(w['globalParameters']) | set(self.inputs(w['name']))
            for s in w['steps']:
                declared |= set((s['inline'].get('parameters') or {}))
                for name in token.findall(json.dumps(s)):
                    self.assertIn(name, declared, '%s / %s' % (w['name'], s['label']))

    def test_no_shared_block_copy_in_the_pack(self):
        for w in self.workloads.values():
            for s in w['steps']:
                self.assertNotIn(s['inline']['type'], ('SetApiKeyStep', 'AppPoolStep'), '%s / %s' % (w['name'], s['label']))
        self.assertNotIn('matching-api-key-set', self.workloads)

    # ---------------------------------------------------------------- chain
    def test_test_runs_the_chain_in_order(self):
        self.assertEqual(['matching-all'], [s['inline']['workloadName'] for s in self.workloads['matching-test']['steps']])
        steps = self.workloads['matching-all']['steps']
        self.assertEqual('common-testauto-tag-check', steps[0]['inline']['workloadName'])
        self.assertEqual(['matching-scenario1-load'] + ['matching-scenario' + s for s in SCENARIOS],
                         [s['inline']['workloadName'] for s in steps[1:]])

    def test_checkpoints_chain(self):
        chain = ['loaded', 'after-1', 'after-2', 'after-3a', 'after-3b', 'after-3c']
        for n, scn in enumerate(SCENARIOS):
            steps = self.workloads['matching-scenario' + scn]['steps']
            restore = next(s for s in steps if s['inline'].get('operation') == 'RestoreDatabase')['inline']
            backup = next(s for s in steps if s['inline'].get('operation') == 'BackupDatabase')['inline']
            form = 'profisee_Matching_{{Size}}_%s_{{ProfiseeVersionCode}}.bak'
            self.assertIn(form % chain[n], json.dumps(restore), scn)
            self.assertIn(form % chain[n + 1], json.dumps(backup), scn)

    def test_scenario_order_of_steps(self):
        first = self.labels('matching-scenario1')
        self.assertNotIn('Turn Continuous Matching On', first)
        for scn in SCENARIOS[1:]:
            got = self.labels('matching-scenario' + scn)
            self.assertLess(got.index('Turn Continuous Matching On'), got.index('Wait For Monitor Quiet'), scn)
            self.assertLess(got.index('Wait For Monitor Quiet'), got.index('Run Matching Scenario ' + scn), scn)

    def test_run_tags_compose_todays_keys(self):
        for scn in SCENARIOS:
            text = json.dumps(self.workloads['matching-scenario' + scn])
            self.assertIn('matching-{{Size|lower}}-scenario' + scn, text)
            self.assertIn('matching-1k-scenario' + scn, self.golden)

    def test_load_configures_then_sets_the_key(self):
        got = self.labels('matching-scenario1-load')
        children = [s['inline'].get('workloadName') for s in self.workloads['matching-scenario1-load']['steps']]
        self.assertLess(children.index('install-configure-upgrade'), children.index('common-api-key-set'))
        self.assertLess(got.index('Restore Empty Baseline'), children.index('install-configure-upgrade'))

    def test_base_create_never_overwrites(self):
        w = self.workloads['matching-base-create']
        self.assertEqual('false', w['globalParameters']['BaseMissing'])
        at = self.labels('matching-base-create').index('Report The Base State')
        for s in w['steps'][at + 1:]:
            self.assertEqual('{{BaseMissing}}', s.get('runWhen') or s['inline'].get('runWhen'), s['label'])

    # ---------------------------------------------------------------- templates = today's workflows
    def test_setup_holds_each_template_once(self):
        self.assertEqual(['ScenarioMgt Check', 'TestAuto Version Exists', 'Upsert Run Profiles']
                         + [f'Upsert Scenario {s} Workflows' for s in SCENARIOS], self.labels('matching-setup'))

    def test_templates_expand_to_todays_workflows(self):
        got = self.expand_all()
        self.assertEqual(sorted(self.golden), sorted(got))
        for key, gold in self.golden.items():
            spec = got[key]
            for field in ('Name', 'Category', 'PlainTags'):
                self.assertEqual(gold[field], spec[field], key)
            self.assertEqual(len(gold['Details']), len(spec['Details']), key)
            for g, d in zip(gold['Details'], spec['Details']):
                where = '%s / %s' % (key, g['Name'])
                for field in ('Name', 'Description', 'ExecutionOrder', 'ProfiseeVersion'):
                    self.assertEqual(g[field], d[field], where)
                self.assertEqual(g['ConfigSha256'], config_hash(d['ScenarioConfiguration']), where)
                self.assertLessEqual(len(d['ScenarioConfiguration']), 4000, where)

    def test_descriptions_differ_only_in_the_names_that_changed(self):
        # The workflow description named the per-size workload and the retired reference set; nothing else moved.
        got = self.expand_all()
        for key, spec in got.items():
            text = spec['Description']
            self.assertIn('Automation ID: <AUTOMATION_ID>', text, key)
            self.assertNotIn('matching/workflows', text, key)
            self.assertIn("workload 'matching-scenario%s'" % key.rsplit('scenario', 1)[1], text, key)

    def test_run_profiles_are_todays(self):
        got = {}
        for p in self.profiles():
            code = p.pop('Code')
            got[code] = {k: str(v) for k, v in p.items()}
        self.assertEqual(self.golden_profiles, got)

    def test_a_new_size_row_gives_new_workflows_and_changes_no_other(self):
        rows = {'{{$ref:matching/sizes:*}}': SIZES + ',50K=50000'}
        got = self.expand_all(rows)
        new = {'matching-50k-scenario' + s for s in SCENARIOS}
        self.assertEqual(set(self.golden) | new, set(got))
        for key, gold in self.golden.items():
            self.assertEqual([g['ConfigSha256'] for g in gold['Details']],
                             [config_hash(d['ScenarioConfiguration']) for d in got[key]['Details']], key)
        lookup = json.loads(got['matching-50k-scenario3a']['Details'][2]['ScenarioConfiguration'])
        mix = lookup['ScenarioRuntime']['CustomParms']['SourceSystemDistribution']
        self.assertEqual(5000, sum(mix.values()))
        self.assertEqual(5000, lookup['ScenarioTesting']['TestRecordLimit'])
        batch = json.loads(got['matching-50k-scenario2']['Details'][3]['ScenarioConfiguration'])
        self.assertEqual('RetailClient50KScenario2', batch['ScenarioTables']['SourceEntityName'])
        codes = {p['Code'] for p in self.profiles(rows)}
        self.assertIn('{{ProfiseeVersionCode}}-RetailClient-Scenario 3b-50000-0', codes)

    def test_a_record_count_that_is_not_a_multiple_of_ten_is_refused(self):
        for bad in ('7=7', 'X=abc', 'Z=0'):
            with self.assertRaises(RuntimeError, msg=bad) as caught:
                expand(self.templates[0], {'{{$ref:matching/sizes:*}}': bad})
            self.assertIn('matching/sizes', str(caught.exception), bad)

    def test_preflight_lists_exactly_the_keys_setup_creates(self):
        step = next(s for s in self.workloads['matching-preflight']['steps'] if s['label'] == 'List The Workflows Setup Creates')
        code, out, err = run_ps(step['inline']['scriptContent'], ROWS)
        self.assertEqual(0, code, err)
        self.assertEqual(set(self.golden), set(out.strip().split(',')))

    def test_preflight_reads_the_sizes_from_reference_data(self):
        text = json.dumps(self.workloads['matching-preflight'])
        self.assertIn('{{$ref:matching/sizes:*}}', text)
        self.assertIn('{{$ref:matching/values:OptionalSizes}}', text)
        for size in ('1K', '10K', '100K', '100M'):
            self.assertNotIn('RetailClient%sScenario' % size, text)

    # ---------------------------------------------------------------- reference sets, schedule, rounds
    def test_reference_seed_rows(self):
        def entries(name):
            with open(os.path.join(self.root, 'reference-kv', 'matching', name + '.json'), encoding='utf-8') as f:
                return json.load(f)['entries']
        self.assertEqual({'1K': '1000', '10K': '10000', '100K': '100000', '1M': '1000000', '100M': '100000000'}, entries('sizes'))
        self.assertEqual({'OptionalSizes': '1M,100M'}, entries('values'))
        schedule = entries('schedule')
        self.assertEqual('matching-test', schedule['1k.Target'])
        self.assertEqual('Size=100M', schedule['100m.Values'])
        self.assertFalse(os.path.exists(os.path.join(self.root, 'reference-kv', 'matching', 'workflows.json')))

    def test_one_schedule_workload_reads_its_rows_by_name(self):
        step = self.workloads['schedule-matching']['steps'][0]['inline']
        self.assertEqual('schedule-matching-{{Schedule}}', step['taskName'])
        self.assertEqual('{{$ref:matching/schedule:{{Schedule}}.Target}}', step['targetWorkload'])
        self.assertEqual('{{$ref:matching/schedule:{{Schedule}}.Values}}', step['targetParameters'])

    def test_rounds_pass_the_size_as_a_value(self):
        for path in glob.glob(os.path.join(self.root, 'rounds', '*.txt')):
            with open(path, encoding='utf-8') as f:
                lines = [ln.lstrip('+').strip() for ln in f if ln.strip() and not ln.startswith('#')]
            self.assertTrue(lines, path)
            for line in lines:
                name, _, values = line.partition(' ')
                self.assertIn(name, self.workloads, path)
                self.assertRegex(values, r'^Size=\w+$', path)

    def test_generator_is_byte_stable_and_keeps_edited_rows(self):
        def snapshot():
            out = {}
            for folder, _dirs, files in os.walk(self.root):
                for name in files:
                    with open(os.path.join(folder, name), 'rb') as f:
                        out[os.path.relpath(os.path.join(folder, name), self.root)] = f.read()
            return out
        before = snapshot()
        path = os.path.join(self.root, 'reference-kv', 'matching', 'sizes.json')

        def restore():
            with open(path, 'wb') as f:
                f.write(before[os.path.relpath(path, self.root)])
        self.addCleanup(restore)
        generate(self.root)
        self.assertEqual(before, snapshot())
        with open(path, encoding='utf-8') as f:
            data = json.load(f)
        data['entries']['50K'] = '50000'
        with open(path, 'w', encoding='utf-8') as f:
            json.dump(data, f)
        with open(path, 'rb') as f:
            edited = f.read()
        generate(self.root)
        after = snapshot()
        self.assertEqual(edited, after[os.path.relpath(path, self.root)])
        # A new size changes no workload file.
        self.assertEqual({k: v for k, v in before.items() if k.startswith('workloads')},
                         {k: v for k, v in after.items() if k.startswith('workloads')})


if __name__ == '__main__':
    unittest.main()
