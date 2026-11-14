"""Tests of the Matching Large pack generator. Standard library only (unittest); pytest runs them too.

Run:  python test_gen_matching_large.py
Needs the speed-merchants repo beside ai-setup (or PACKGEN_TOOLS = <speed-merchants>\\CrewChief\\packs\\tools) and pwsh.

The generator runs into a temporary folder. The template tests run the generated PowerShell for real with the pack's own
reference rows and check what TestAuto would hold: the slice from matching-large/values, the run limits for days-long
runs, the Scenario 1 finish linking, and the configurations under the repository's 4000-character limit.
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
from packgen.testing import expand, run_ps  # noqa: E402

FAM = 'matching-large'
EXPECTED = {
    'internal': {'matching-large-scenario1-finish', 'matching-large-scenario2', 'matching-large-scenario3a',
                 'matching-large-scenario3b', 'matching-large-scenario3c'},
    'start': {'matching-large-preflight', 'matching-large-setup'},
    'tests': {'matching-large-continue'},
}


def generate(root):
    done = subprocess.run([sys.executable, os.path.join(HERE, 'gen_matching_large.py'), root], capture_output=True, text=True,
                          env=dict(os.environ, PACKGEN_TOOLS=TOOLS))
    if done.returncode != 0:
        raise RuntimeError(done.stderr)


def whole_set(root, name):
    with open(os.path.join(root, 'reference-kv', FAM, name + '.json'), encoding='utf-8') as f:
        return ','.join(f"{k}={v}" for k, v in json.load(f)['entries'].items())


class GeneratedPack(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls._tmp = tempfile.TemporaryDirectory()
        cls.root = os.path.join(cls._tmp.name, FAM)
        generate(cls.root)
        cls.workloads = {}
        for path in glob.glob(os.path.join(cls.root, 'workloads', FAM, '**', '*.workload.json'), recursive=True):
            with open(path, encoding='utf-8') as f:
                w = json.load(f)
            cls.workloads[w['name']] = (os.path.basename(os.path.dirname(path)), w)
        cls.tokens = {'{{$ref:%s/sizes:*}}' % FAM: whole_set(cls.root, 'sizes'),
                      '{{$ref:%s/values:*}}' % FAM: whole_set(cls.root, 'values')}
        setup = cls.workloads['matching-large-setup'][1]
        cls.specs = {}
        for st in setup['steps']:
            if st['label'].startswith('Upsert Scenario'):
                for spec in expand(st, cls.tokens):
                    cls.specs[spec['Key']] = spec
        cls.profiles_step = next(s for s in setup['steps'] if s['label'] == 'Upsert Run Profiles')

    @classmethod
    def tearDownClass(cls):
        cls._tmp.cleanup()

    def config(self, key, step_name):
        spec = self.specs[key]
        detail = next(d for d in spec['Details'] if d['Name'] == step_name)
        return json.loads(detail['ScenarioConfiguration'])

    def test_workloads_are_the_expected_set(self):
        got = {}
        for name, (folder, _w) in self.workloads.items():
            got.setdefault(folder, set()).add(name)
        self.assertEqual(EXPECTED, got)

    def test_one_workflow_per_scenario_for_100m(self):
        self.assertEqual({'matching-large-100m-scenario1-finish', 'matching-large-100m-scenario2', 'matching-large-100m-scenario3a',
                          'matching-large-100m-scenario3b', 'matching-large-100m-scenario3c'}, set(self.specs))

    def test_every_configuration_fits_the_repository(self):
        for key, spec in self.specs.items():
            for d in spec['Details']:
                self.assertLessEqual(len(d['ScenarioConfiguration']), 4000, f"{key} / {d['Name']}")
                self.assertNotIn('<<', d['ScenarioConfiguration'], f"{key} / {d['Name']}")

    def test_later_scenarios_work_on_the_slice_row(self):
        for scn, step in (('2', 'Matching Scenario 2 Incremental Batch Load'), ('3b', 'Matching Scenario 3b Continuous Matching'),
                          ('3c', 'Matching Scenario 3c Continuous Matching'), ('3a', 'Matching Scenario 3a Lookup Before Create')):
            cfg = self.config(f'matching-large-100m-scenario{scn}', step)
            self.assertEqual(1000000, cfg['ScenarioTesting']['TestRecordLimit'], scn)
            if scn != '3a':
                self.assertEqual(f'RetailClient100MScenario{scn}', cfg['ScenarioTables']['SourceEntityName'])
        lookup = self.config('matching-large-100m-scenario3a', 'Matching Scenario 3a Lookup Before Create')['ScenarioRuntime']['CustomParms']
        self.assertEqual(1000000, lookup['IterationLimit'])
        self.assertEqual(1000000, sum(lookup['SourceSystemDistribution'].values()))

    def test_creates_run_every_row_and_idle_waits_a_day(self):
        for scn in ('3b', '3c'):
            c = self.config(f'matching-large-100m-scenario{scn}', f'Matching Scenario {scn} Continuous Matching')['ScenarioRuntime']['CustomParms']
            self.assertEqual('00:00:00', c['TimeLimit'], scn)
            self.assertEqual(1000000, c['IterationLimit'], scn)
        for scn in ('2', '3b', '3c'):
            c = self.config(f'matching-large-100m-scenario{scn}', 'Wait for Matching To Be Idle')['ScenarioRuntime']['CustomParms']
            self.assertEqual(1440, c['MaxWaitMinutes'], scn)

    def test_run_profiles_are_the_existing_100m_ones(self):
        lines = [json.loads(d['ScenarioConfiguration'])['ScenarioRuntime']['CustomParms'].get('UnifiedMatchingApiExecutionRunProfile')
                 for spec in self.specs.values() for d in spec['Details']]
        self.assertTrue({l for l in lines if l} <= {f'{{{{ProfiseeVersionCode}}}}-RetailClient-Scenario {s}-100000000-0'
                                                     for s in ('1', '2', '3a', '3b', '3c')})
        expansion = self.profiles_step['inline']['scriptContent'].split('# ---- upsert the run profiles')[0]
        code, out, err = run_ps(expansion.replace('\r\n', '\n') + "\n$specs | ForEach-Object { $_ }\n", self.tokens)
        self.assertEqual(0, code, err)
        rows = [p for line in out.splitlines() if line.strip() for p in json.loads(line)]
        # As PROD's 26R3 100M rows (read 11/14): IncrementalVolumeCount 1,000,000 for 2, 3b, 3c; 0 for 1 and 3a.
        self.assertEqual({'Scenario 1': 0, 'Scenario 2': 1000000, 'Scenario 3a': 0, 'Scenario 3b': 1000000, 'Scenario 3c': 1000000},
                         {r['MatchingScenarioName']: int(r['IncrementalVolumeCount']) for r in rows})
        self.assertEqual({100000000}, {int(r['SourceRecordCount']) for r in rows})

    def test_finish_records_end_counts_and_timing_linked_to_its_first_step(self):
        spec = self.specs['matching-large-100m-scenario1-finish']
        self.assertEqual(['Capture Matching Status Counts for End of Scenario 1', 'Matching Timing Results Scenario 1'],
                         [d['Name'] for d in spec['Details']])
        for d in spec['Details']:
            c = json.loads(d['ScenarioConfiguration'])['ScenarioRuntime']['CustomParms']
            self.assertEqual('{{STEP:1}}', c['UnifiedMatchingScenarioWorkloadExecution'], d['Name'])
            self.assertEqual('{{ProfiseeVersionCode}}-RetailClient-Scenario 1-100000000-0',
                             c['UnifiedMatchingApiExecutionRunProfile'], d['Name'])
        timing = json.loads(spec['Details'][1]['ScenarioConfiguration'])['ScenarioRuntime']['CustomParms']
        self.assertEqual(('Start of Scenario 1 for Retail Client', 'End of Scenario 1 for Retail Client'),
                         (timing['StartMarkerText'], timing['EndMarkerText']))

    def test_3c_collects_after_its_run_as_production_does(self):
        names = [d['Name'] for d in self.specs['matching-large-100m-scenario3c']['Details']]
        self.assertLess(names.index('Write End of Scenario 3c Monitor Message'), names.index('Matching Scenario 3c Post-Run Metric Collection'))
        c = self.config('matching-large-100m-scenario3c', 'Matching Scenario 3c Post-Run Metric Collection')['ScenarioRuntime']['CustomParms']
        self.assertEqual('{{STEP:4}}', c['SourceWorkloadExecution'])

    def test_scenarios_restore_and_back_up_striped_checkpoints(self):
        for scn, (start, end) in {'2': ('after-1', 'after-2'), '3a': ('after-2', 'after-3a'), '3b': ('after-3a', 'after-3b'),
                                  '3c': ('after-3b', 'after-3c')}.items():
            w = self.workloads[f'matching-large-scenario{scn}'][1]
            labels = [s['label'] for s in w['steps']]
            self.assertLess(labels.index(f'Restore {start.title().replace('-', ' ')}'), labels.index('Set And Verify API Key'), scn)
            self.assertLess(labels.index(f'Run Matching Scenario {scn}'), labels.index(f'Check Scenario {scn} Ran Here'), scn)
            restore = next(s for s in w['steps'] if s['label'] == f'Restore {start.title().replace('-', ' ')}')['inline']['sqlScript']
            backup = next(s for s in w['steps'] if s['label'] == f'Back Up {end.title().replace('-', ' ')}')['inline']['sqlScript']
            self.assertIn(f"profisee_MatchingLarge_{{{{Size}}}}_{start}_{{{{ProfiseeVersionCode}}}}.bak", restore)
            self.assertIn(f"profisee_MatchingLarge_{{{{Size}}}}_{end}_{{{{ProfiseeVersionCode}}}}.bak", backup)
            self.assertIn('COPY_ONLY', backup)
            self.assertIn('RESTORE VERIFYONLY', backup)
            self.assertNotIn('DatabaseOperationsStep', json.dumps(w))

    def test_finish_guards_before_it_writes(self):
        labels = [s['label'] for s in self.workloads['matching-large-scenario1-finish'][1]['steps']]
        self.assertLess(labels.index('Check Scenario 1 Can Be Finished'), labels.index('Write End Of Scenario 1 Marker'))
        self.assertLess(labels.index('Check Source Tables Fit The Load'), labels.index('Write End Of Scenario 1 Marker'))
        self.assertEqual('Back Up After 1', labels[-1])

    def test_rounds_continue_from_the_finish(self):
        with open(os.path.join(self.root, 'rounds', '100m-continue-round.txt'), encoding='utf-8') as f:
            lines = [l for l in f.read().splitlines() if l and not l.startswith('#')]
        self.assertEqual(['matching-large-scenario1-finish Size=100M', '+matching-large-scenario2 Size=100M',
                          '+matching-large-scenario3a Size=100M', '+matching-large-scenario3b Size=100M',
                          '+matching-large-scenario3c Size=100M'], lines)


if __name__ == '__main__':
    unittest.main()
