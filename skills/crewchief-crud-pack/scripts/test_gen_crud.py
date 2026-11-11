"""Tests of the CRUD pack generator. Standard library only (unittest); pytest runs them too.

Run:  python test_gen_crud.py
Needs the speed-merchants repo beside ai-setup (or PACKGEN_TOOLS = <speed-merchants>\\CrewChief\\packs\\tools) and pwsh.

The generator runs into a temporary folder. The template tests run the generated PowerShell for real and compare what it
would send to TestAuto with golden_crud_workflows.json: the 26 workflows of the pack as generated before the 11/11
redesign (name, tags and a hash of every step's name, description, version and configuration). Equal = what TestAuto
runs did not change.
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

# Today's rows (the seed the generator writes), as the reference tokens the scripts read.
ROWS = {
    '{{$ref:crud/sizes:*}}': '1K=1000,10K=10000,100K=100000,1M=1000000',
    '{{$ref:crud/values:StewardMinutes}}': '1,5,15,30,60',
    '{{$ref:crud/values:StewardIterations}}': '10,100,1000',
    '{{$ref:crud/values:ReleaseSizes}}': '1M',
}
EXPECTED = {
    'internal': {'crud-base-reset', 'crud-core', 'crud-release', 'crud-rules-remove', 'crud-run-start', 'crud-stewardship'},
    'schedule': {'schedule-crud'},
    'start': {'crud-base-create', 'crud-preflight', 'crud-setup'},
    'tests': {'crud-test', 'crud-test-release'},
}


def detail_hash(d):
    return hashlib.sha256('\x1f'.join([d['Name'], d['Description'], d['ProfiseeVersion'], d['ScenarioConfiguration']]).encode('utf-8')).hexdigest()


class GeneratedPack(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls._tmp = tempfile.TemporaryDirectory()
        cls.root = os.path.join(cls._tmp.name, 'crud')
        env = dict(os.environ, PACKGEN_TOOLS=TOOLS)
        done = subprocess.run([sys.executable, os.path.join(HERE, 'gen_crud.py'), cls.root], capture_output=True, text=True, env=env)
        if done.returncode != 0:
            raise RuntimeError(done.stderr)
        cls.workloads = {}
        for path in glob.glob(os.path.join(cls.root, 'workloads', 'crud', '*', '*.workload.json')):
            with open(path, encoding='utf-8') as f:
                w = json.load(f)
            w['_folder'] = os.path.basename(os.path.dirname(path))
            w['_file'] = os.path.basename(path)
            cls.workloads[w['name']] = w
        with open(os.path.join(HERE, 'golden_crud_workflows.json'), encoding='utf-8') as f:
            cls.golden = json.load(f)
        cls.setup_steps = {s['label']: s for s in cls.workloads['crud-setup']['steps']}

    @classmethod
    def tearDownClass(cls):
        cls._tmp.cleanup()

    def inputs(self, name):
        return {i['name']: i.get('default') for i in self.workloads[name].get('inputs', [])}

    def step(self, workload, label):
        return next(s for s in self.workloads[workload]['steps'] if s['label'] == label)

    # ---- shape
    def test_workload_name_set_is_exact(self):
        got = {}
        for w in self.workloads.values():
            got.setdefault(w['_folder'], set()).add(w['name'])
        self.assertEqual(EXPECTED, got)

    def test_no_value_in_any_name_or_file_name(self):
        for w in self.workloads.values():
            self.assertFalse(has_value_in_name(w['name']), w['name'])
            self.assertEqual(w['name'] + '.workload.json', w['_file'])

    def test_run_values_are_inputs_never_globals(self):
        for w in self.workloads.values():
            self.assertFalse({'Size', 'Minutes', 'Iterations', 'BusinessRules', 'Threads'} & set(w['globalParameters']), w['name'])

    def test_crud_test_inputs_and_defaults(self):
        i = self.inputs('crud-test')
        self.assertEqual('1K', i['Size'])
        self.assertEqual('{{$ref:crud/default-minutes:{{Size}}}}', i['Minutes'])
        self.assertEqual('0', i['Iterations'])
        self.assertEqual('true', i['BusinessRules'])
        self.assertEqual('{{BusinessRules|map:true=br,false=nobr}}', i['RulesKey'])
        self.assertEqual('1M', self.inputs('crud-test-release')['Size'])

    def test_version_keys_are_inputs_with_the_family_default_everywhere(self):
        for w in self.workloads.values():
            text = json.dumps(w['steps'])
            i = self.inputs(w['name'])
            if '{{ProfiseeVersionCode}}' in text or '{{ProfiseeVersionCode}}' in json.dumps(w.get('inputs', [])):
                self.assertEqual('{{$ref:crud/environment:ProfiseeVersionCode}}', i.get('ProfiseeVersionCode'), w['name'])
            self.assertNotIn('ProfiseeVersionCode', w['globalParameters'], w['name'])
            self.assertNotIn('ProfiseeVersionNumber', w['globalParameters'], w['name'])

    def test_every_token_in_a_step_is_declared(self):
        """A plain {{Name}} in step text is an input, a global or a captured run parameter of the same workload."""
        for w in self.workloads.values():
            known = {n.lower() for n in list(w['globalParameters']) + [i['name'] for i in w.get('inputs', [])]}
            known |= {s['inline']['outputParameterName'].lower() for s in w['steps'] if s['inline'].get('outputParameterName')}
            for s in w['steps']:
                inline = dict(s['inline'])
                inline.pop('description', None)
                for token in re.findall(r'\{\{([A-Za-z][A-Za-z0-9_]*)(?:\|[^{}]*)?\}\}', json.dumps(inline)):
                    if w['name'] == 'crud-setup' and token.startswith('TestAuto'):
                        continue
                    self.assertIn(token.lower(), known, '%s / %s: {{%s}}' % (w['name'], s['label'], token))

    def test_no_shared_block_copy_in_the_pack(self):
        for w in self.workloads.values():
            self.assertFalse(w['name'].startswith('common-'))
            for s in w['steps']:
                self.assertNotEqual('SetApiKeyStep', s['inline']['type'], w['name'])
                self.assertNotEqual('ServiceControlStep', s['inline']['type'], w['name'])

    # ---- run tags and the keys setup creates
    def test_run_tags_compose_todays_keys(self):
        prefix = 'AUTO:{{$env:COMPUTERNAME}}:{{ProfiseeVersionCode}}:'
        self.assertEqual(prefix + 'crud-{{Size|lower}}-core-{{RulesKey}}', self.step('crud-core', 'Run CRUD Core')['inline']['workflowTag'])
        self.assertEqual(prefix + 'crud-steward-{{StewardForm}}-{{RulesKey}}',
                         self.step('crud-stewardship', 'Run CRUD Stewardship')['inline']['workflowTag'])
        self.assertEqual(prefix + 'crud-{{Size|lower}}-release-{{RulesKey}}',
                         self.step('crud-release', 'Run CRUD Release')['inline']['workflowTag'])

    def test_rule_removal_runs_only_without_business_rules(self):
        for name in ('crud-core', 'crud-stewardship', 'crud-release'):
            self.assertEqual('{{BusinessRules|map:true=false,false=true}}', self.step(name, 'Remove Business Rules')['inline']['runWhen'])

    def test_decide_form(self):
        script = self.step('crud-test', 'Decide The Stewardship Form')['inline']['scriptContent']
        self.assertEqual(script, self.step('crud-stewardship', 'Decide The Stewardship Form')['inline']['scriptContent'])

        def form(minutes, iterations='0', rules='true'):
            return run_ps(script, {'{{Minutes}}': minutes, '{{Iterations}}': iterations, '{{BusinessRules}}': rules})

        self.assertEqual('5min', form('5')[1].strip())
        self.assertEqual('1min', form(' 01 ')[1].strip())
        self.assertEqual('10it', form('5', '10')[1].strip())
        for bad in (('0',), ('61',), ('five',), ('5', 'x'), ('5', '0', 'yes')):
            code, _out, err = form(*bad)
            self.assertNotEqual(0, code, bad)
            self.assertRegex(err, 'Minutes is|Iterations is|BusinessRules is')

    def test_test_checks_its_workflows_before_any_restore(self):
        # Review focus 4: a value with no workflow yet is told "run crud-setup" at the start, not mid-run.
        labels = [s['label'] for s in self.workloads['crud-test']['steps']]
        self.assertLess(labels.index('Workflows For These Values Exist'), labels.index('Prepare Run Start'))
        check = self.step('crud-test', 'Workflows For These Values Exist')['inline']
        self.assertEqual('common-testauto-tag-check', check['workloadName'])
        self.assertEqual('crud-{{Size|lower}}-core-{{RulesKey}},crud-steward-{{StewardForm}}-{{RulesKey}}', check['parameters']['TagKeys'])
        self.assertEqual('crud-setup', check['parameters']['SetupName'])
        self.assertEqual('false', check['parameters']['AllowNone'])
        release = self.step('crud-test-release', 'Workflow For These Values Exists')['inline']
        self.assertEqual('crud-{{Size|lower}}-release-{{RulesKey}}', release['parameters']['TagKeys'])

    def test_preflight_lists_exactly_the_keys_setup_creates(self):
        code, out, err = run_ps(self.step('crud-preflight', 'List The Workflows Setup Creates')['inline']['scriptContent'], ROWS)
        self.assertEqual(0, code, err)
        self.assertEqual(set(self.golden), set(out.strip().split(',')))
        self.assertEqual('true', self.step('crud-preflight', 'Every Workflow Found Once')['inline']['parameters']['AllowNone'])

    # ---- what TestAuto holds is unchanged
    def expanded(self, rows=None):
        got = {}
        for label in ('Upsert Core Workflows', 'Upsert Stewardship Workflows', 'Upsert Release Workflows'):
            for spec in expand(self.setup_steps[label], rows or ROWS):
                self.assertNotIn(spec['Key'], got)
                got[spec['Key']] = spec
        return got

    def test_setup_holds_each_template_once(self):
        self.assertEqual(3, sum(1 for s in self.workloads['crud-setup']['steps'] if '$template = @' in s['inline'].get('scriptContent', '')))

    def test_templates_expand_to_todays_workflows(self):
        got = self.expanded()
        self.assertEqual(sorted(self.golden), sorted(got))
        for key, gold in self.golden.items():
            spec = got[key]
            self.assertEqual(gold['Name'], spec['Name'], key)
            self.assertEqual(gold['PlainTags'], spec['PlainTags'], key)
            self.assertEqual([d['Name'] for d in gold['Details']], [d['Name'] for d in spec['Details']], key)
            for want, d in zip(gold['Details'], spec['Details']):
                self.assertEqual(want['Order'], d['ExecutionOrder'], key)
                self.assertEqual(want['Sha256'], detail_hash(d), '%s step %s %s' % (key, d['ExecutionOrder'], d['Name']))
                self.assertLessEqual(len(d['ScenarioConfiguration']), 4000)

    def test_a_new_row_gives_new_workflows_and_changes_no_other(self):
        rows = dict(ROWS)
        rows['{{$ref:crud/sizes:*}}'] += ',500=500'
        rows['{{$ref:crud/values:StewardMinutes}}'] += ', 10'
        got = self.expanded(rows)
        self.assertEqual(set(self.golden) | {'crud-500-core-br', 'crud-500-core-nobr', 'crud-steward-10min-br', 'crud-steward-10min-nobr'}, set(got))
        ten = json.loads(got['crud-steward-10min-nobr']['Details'][0]['ScenarioConfiguration'])
        self.assertEqual('00:10:00', ten['ScenarioRuntime']['CustomParms']['TimeLimit'])
        self.assertEqual(0, ten['ScenarioEnvironment']['DqRuleCount'])
        self.assertEqual('CRUD Stewardship 10 min No Business Rules', got['crud-steward-10min-nobr']['Name'])
        small = json.loads(got['crud-500-core-br']['Details'][0]['ScenarioConfiguration'])
        self.assertEqual(500, small['ScenarioTesting']['TestRecordLimit'])
        for key in self.golden:
            self.assertEqual([d['Sha256'] for d in self.golden[key]['Details']], [detail_hash(d) for d in got[key]['Details']], key)

    def test_minutes_over_sixty_is_refused(self):
        rows = dict(ROWS)
        rows['{{$ref:crud/values:StewardMinutes}}'] = '61'
        with self.assertRaises(RuntimeError) as ctx:
            expand(self.setup_steps['Upsert Stewardship Workflows'], rows)
        self.assertIn('1 to 60', str(ctx.exception))

    def test_release_size_without_a_size_row_is_refused(self):
        rows = dict(ROWS)
        rows['{{$ref:crud/values:ReleaseSizes}}'] = '2M'
        with self.assertRaises(RuntimeError) as ctx:
            expand(self.setup_steps['Upsert Release Workflows'], rows)
        self.assertIn("'2M' has no row in the reference set crud/sizes", str(ctx.exception))

    # ---- reference seed and schedule
    def seed(self, name):
        with open(os.path.join(self.root, 'reference-kv', 'crud', name + '.json'), encoding='utf-8') as f:
            return json.load(f)

    def test_reference_seed_rows(self):
        self.assertEqual({'1K': '1000', '10K': '10000', '100K': '100000', '1M': '1000000'}, self.seed('sizes')['entries'])
        self.assertEqual({'1K': '1', '10K': '5', '100K': '30', '1M': '60'}, self.seed('default-minutes')['entries'])
        self.assertEqual({'StewardMinutes': '1,5,15,30,60', 'StewardIterations': '10,100,1000', 'ReleaseSizes': '1M'},
                         self.seed('values')['entries'])
        for name in ('sizes', 'default-minutes', 'values', 'schedule'):
            s = self.seed(name)
            self.assertTrue(s['includeInReplacements'])
            self.assertEqual(set(s['entries']), set(s['keyDescriptions']), name)
        self.assertFalse(os.path.exists(os.path.join(self.root, 'reference-kv', 'crud', 'machines.json')), 'the generator writes no box facts')

    def test_one_schedule_workload_reads_its_rows_by_name(self):
        step = self.workloads['schedule-crud']['steps'][0]['inline']
        self.assertEqual('schedule-crud-{{Schedule}}', step['taskName'])
        self.assertEqual('{{$ref:crud/schedule:{{Schedule}}.Target}}', step['targetWorkload'])
        self.assertEqual('{{$ref:crud/schedule:{{Schedule}}.Values}}', step['targetParameters'])
        rows = self.seed('schedule')['entries']
        self.assertEqual('crud-test', rows['1k-br.Target'])
        self.assertEqual('Size=1K BusinessRules=true', rows['1k-br.Values'])
        self.assertEqual('crud-test-release', rows['1m-nobr.Target'])
        for name in {k.split('.')[0] for k in rows}:
            self.assertEqual({name + s for s in ('.Target', '.Values', '.Days', '.Time')}, {k for k in rows if k.startswith(name + '.')})

    def test_generator_is_byte_stable_and_keeps_edited_rows(self):
        def snapshot():
            out = {}
            for path in glob.glob(os.path.join(self.root, '**', '*'), recursive=True):
                if os.path.isfile(path):
                    with open(path, 'rb') as f:
                        out[os.path.relpath(path, self.root)] = f.read()
            return out
        sizes = os.path.join(self.root, 'reference-kv', 'crud', 'sizes.json')
        with open(sizes, 'rb') as f:
            original = f.read()
        self.addCleanup(lambda: open(sizes, 'wb').write(original))
        edited = json.loads(original.decode('utf-8'))
        edited['entries']['500'] = '500'
        edited['keyDescriptions']['500'] = 'A person added this row.'
        with open(sizes, 'w', encoding='utf-8') as f:
            json.dump(edited, f)
        before = snapshot()
        done = subprocess.run([sys.executable, os.path.join(HERE, 'gen_crud.py'), self.root], capture_output=True, text=True,
                              env=dict(os.environ, PACKGEN_TOOLS=TOOLS))
        self.assertEqual(0, done.returncode, done.stderr)
        self.assertEqual(before, snapshot())


if __name__ == '__main__':
    unittest.main()
