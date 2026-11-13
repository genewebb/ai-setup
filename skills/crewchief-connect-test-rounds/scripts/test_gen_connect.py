"""Tests of the Connect pack generator. Standard library only (unittest); pytest runs them too.

Run:  python test_gen_connect.py
Needs the speed-merchants repo beside ai-setup (or PACKGEN_TOOLS = <speed-merchants>\\CrewChief\\packs\\tools) and pwsh.

The generator runs into a temporary folder. The template tests run the generated PowerShell for real and compare what it
would send to TestAuto with golden_connect_workflows.json: the 54 workflows and 54 run profiles of the pack as kept before
the 11/11 redesign (one copy per size and thread count then). Equal = what TestAuto runs did not change. A step
configuration is compared as parsed JSON (its hash). The carried-workload test compares every step taken from source/
with the step the generator wrote: only the shared blocks, the names and the run values may differ.
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

SIZES = '1K=1000,1M=1000000'
ROWS = {'{{$ref:connect/sizes:*}}': SIZES, '{{$ref:connect/values:Threads}}': '4,8,12'}
PROVIDERS = {'sql-server': ('export', 'import'), 'databricks': ('export', 'import'), 'snowflake': ('export', 'import'),
             'synapse': ('export', 'import'), 'profisee-to-profisee': ('export',)}
COMBOS = ['%s-%s' % (p, d) for p, dirs in PROVIDERS.items() for d in dirs]
PROFILE_MARKER = '# ---- upsert the run profiles'
TOKEN = re.compile(r'\{\{([A-Za-z][A-Za-z0-9]*)(?:\|[^}]*)?\}\}')
RUN_VALUES = ('Size', 'RecordCount', 'Threads', 'ProfiseeVersionCode', 'ProfiseeVersionNumber')
TARGET = ('ProfiseeToProfiseeDatabaseName', 'ProfiseeToProfiseeDatabaseServerName', 'ProfiseeToProfiseeInstanceName',
          'ProfiseeToProfiseeServerName', 'ProfiseeToProfiseeServerNameFQDN', 'ProfiseeToProfiseeUrl')
SHARED_LABELS = {'Find The Instance Service', 'Stop Profisee Service', 'Stop W3SVC', 'Stop WAS', 'Start WAS', 'Start W3SVC',
                 'Start Profisee Service', 'Recycle Connect Application Pool', 'Recycle Instance Application Pools',
                 'Recycle Target Application Pools', 'Start Every Service'}
OLD_KEY_CHILD = re.compile(r'^connect-api-key-set-')


def config_hash(text):
    return hashlib.sha256(json.dumps(json.loads(text), sort_keys=True, ensure_ascii=False).encode('utf-8')).hexdigest()


def generate(root):
    done = subprocess.run([sys.executable, os.path.join(HERE, 'gen_connect.py'), root], capture_output=True, text=True,
                          env=dict(os.environ, PACKGEN_TOOLS=TOOLS))
    if done.returncode != 0:
        raise RuntimeError(done.stderr)


def source(*parts):
    with open(os.path.join(HERE, 'source', *parts), encoding='utf-8-sig') as f:
        return json.load(f)


class GeneratedPack(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls._tmp = tempfile.TemporaryDirectory()
        cls.root = os.path.join(cls._tmp.name, 'connect')
        generate(cls.root)
        cls.workloads = {}
        base = os.path.join(cls.root, 'workloads', 'connect')
        for path in glob.glob(os.path.join(base, '**', '*.workload.json'), recursive=True):
            with open(path, encoding='utf-8') as f:
                w = json.load(f)
            w['_folder'] = os.path.relpath(os.path.dirname(path), base).replace(os.sep, '/')
            w['_file'] = os.path.basename(path)
            cls.workloads[w['name']] = w
        with open(os.path.join(HERE, 'golden_connect_workflows.json'), encoding='utf-8') as f:
            golden = json.load(f)
        cls.golden, cls.golden_profiles = golden['workflows'], golden['profiles']
        cls.manifest = source('manifest.json')
        cls.setup_steps = {s['label']: s for s in cls.workloads['connect-setup']['steps']}
        cls.templates = [s for s in cls.workloads['connect-setup']['steps'] if s['label'].startswith('Upsert ') and s['label'].endswith(' Workflows')]

    @classmethod
    def tearDownClass(cls):
        cls._tmp.cleanup()

    def inputs(self, name):
        return {i['name']: i.get('default') for i in self.workloads[name].get('inputs', [])}

    def children(self, name):
        return [s for s in self.workloads[name]['steps'] if s['inline'].get('type') == 'RunWorkloadStep']

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
        if code != 0:
            raise RuntimeError(err.strip() or out.strip())
        return [p for line in out.splitlines() if line.strip() for p in json.loads(line)]

    # ---------------------------------------------------------------- shape
    def test_workload_name_set(self):
        by_folder = {}
        for w in self.workloads.values():
            by_folder.setdefault(w['_folder'].split('/')[0], set()).add(w['name'])
            self.assertEqual(w['name'] + '.workload.json', w['_file'])
        self.assertEqual({'connect-test-' + c for c in COMBOS}, by_folder['tests'])
        self.assertEqual({'connect-preflight', 'connect-setup', 'connect-base-create', 'connect-source-size-create'}, by_folder['start'])
        self.assertEqual({'schedule-connect'}, by_folder['schedule'])
        built = ({'connect-' + c for c in COMBOS} | {'connect-%s-run' % c for c in COMBOS} | {'connect-%s-all' % p for p in PROVIDERS})
        carried = set(self.manifest) - {'connect-base-create'}
        self.assertEqual(built | carried, by_folder['internal'])
        self.assertEqual(77, len(self.workloads))

    def test_no_size_or_thread_count_in_any_name(self):
        for w in self.workloads.values():
            self.assertFalse(has_value_in_name(w['name']), w['name'])
            self.assertIsNone(re.search(r'(^|-)(\d+[km]|t\d+|\d+t)(-|$)', w['name']), w['name'])

    def test_run_values_are_inputs_never_globals(self):
        for w in self.workloads.values():
            for name in RUN_VALUES + ('WorkerThreadCount', 'ModelSourceSize'):
                self.assertNotIn(name, w['globalParameters'], w['name'])

    def test_no_run_value_comes_from_a_box_set(self):
        # A size, record count or thread count read from connect/environment would silently run the wrong size.
        for w in self.workloads.values():
            text = json.dumps(w)
            self.assertIsNone(re.search(r'connect/environment:(ModelSourceSize|RecordCount|WorkerThreadCount)', text), w['name'])
            for old in ('{{WorkerThreadCount}}', '{{ModelSourceSize}}'):
                self.assertNotIn(old, text, w['name'])

    def test_run_value_inputs_have_one_default_everywhere(self):
        want = {'Size': '1K', 'RecordCount': '{{$ref:connect/sizes:{{Size}}}}', 'Threads': '4',
                'ProfiseeVersionCode': '{{$ref:connect/environment:ProfiseeVersionCode}}',
                'ProfiseeVersionNumber': '{{$ref:connect/environment:ProfiseeVersionNumber}}'}
        for w in self.workloads.values():
            got = self.inputs(w['name'])
            for name, default in want.items():
                if name in got:
                    self.assertEqual(default, got[name], w['name'])
            if 'RecordCount' in got:
                self.assertIn('Size', got, w['name'])

    def test_every_plain_token_is_declared_or_passed_by_every_parent(self):
        parents = {}
        for w in self.workloads.values():
            for s in self.children(w['name']):
                parents.setdefault(s['inline']['workloadName'], []).append((w, s))
        for w in self.workloads.values():
            declared = set(w['globalParameters']) | set(self.inputs(w['name']))
            for s in w['steps']:
                local = declared | set(s['inline'].get('parameters') or {})
                for name in set(TOKEN.findall(json.dumps(s))) - local:
                    # Set during the run by an earlier step of the same workload, or supplied by every parent.
                    produced = any(name == (p['inline'].get('outputParameter') or p['inline'].get('captureOutputAs')) or
                                   name in json.dumps(p['inline'].get('outputs') or p['inline'].get('captures') or '')
                                   for p in w['steps'])
                    if produced:
                        continue
                    self.assertTrue(parents.get(w['name']), '%s / %s reads {{%s}} and nothing runs it' % (w['name'], s['label'], name))
                    for parent, step in parents[w['name']]:
                        have = set(parent['globalParameters']) | set(self.inputs(parent['name'])) | set(step['inline'].get('parameters') or {})
                        self.assertIn(name, have, '%s / %s reads {{%s}}; parent %s does not have it' % (w['name'], s['label'], name, parent['name']))

    def test_values_a_child_declares_are_declared_by_its_parent(self):
        for w in self.workloads.values():
            mine = set(self.inputs(w['name'])) | set(w['globalParameters'])
            for s in self.children(w['name']):
                child = s['inline']['workloadName']
                if child not in self.workloads:
                    continue
                for name in RUN_VALUES + TARGET:
                    if name in self.inputs(child):
                        self.assertIn(name, mine | set(s['inline'].get('parameters') or {}), '%s runs %s' % (w['name'], child))

    def test_every_child_exists(self):
        for w in self.workloads.values():
            for s in self.children(w['name']):
                child = s['inline']['workloadName']
                self.assertTrue(child in self.workloads or child.startswith(('common-', 'install-')), '%s runs %s' % (w['name'], child))
                self.assertNotIn('{{', child)

    def test_no_shared_block_copy_in_the_pack(self):
        for w in self.workloads.values():
            for s in w['steps']:
                where = '%s / %s' % (w['name'], s['label'])
                self.assertNotIn(s['inline'].get('type'), ('SetApiKeyStep', 'ServiceControlStep'), where)
                self.assertNotIn(s['label'], SHARED_LABELS, where)
            self.assertIsNone(OLD_KEY_CHILD.match(w['name']), w['name'])
            self.assertNotIn('connect-api-key-set', json.dumps(w), w['name'])

    def test_no_retired_name_is_left(self):
        for w in self.workloads.values():
            self.assertIsNone(re.search(r'connect-(test-)?1[km]-', json.dumps(w)), w['name'])
            self.assertNotIn('connect/workflows', json.dumps(w), w['name'])

    # ---------------------------------------------------------------- carried workloads = the source, but for the shared parts
    def test_carried_steps_equal_their_source(self):
        renames = {'{{WorkerThreadCount}}': '{{Threads}}', '{{ModelSourceSize}}': '{{Size}}'}
        old_names = {m['from']: new for new, m in self.manifest.items() if m['from'] != new}
        old_names.update({'connect-api-key-set-profisee-to-profisee': 'common-api-key-set', 'connect-api-key-set-main': 'common-api-key-set',
                          'connect-api-key-set-all': 'common-api-key-set'})

        def renamed(obj):
            text = json.dumps(obj)
            for old, new in list(renames.items()) + sorted(old_names.items(), key=lambda kv: -len(kv[0])):
                text = text.replace(old, new)
            return json.loads(text)
        self.assertEqual(41, len(self.manifest))
        for name, meta in self.manifest.items():
            src = source('workloads', name + '.workload.json')
            got = self.workloads[name]
            self.assertEqual(meta['from'], src['name'], name)
            kept = [s for s in src['steps'] if s['label'] not in SHARED_LABELS
                    and not OLD_KEY_CHILD.match(s['inline'].get('workloadName') or '')]
            mine = [s for s in got['steps'] if not (s['inline'].get('workloadName') or '').startswith('common-')]
            if name == 'connect-base-create':  # the generator adds the two prove steps and writes its description
                self.assertEqual(['Prove Every Export Prepares', 'Prove Every Import Prepares'], [s['label'] for s in mine[-2:]])
                mine = mine[:-2]
                got = dict(got, description=renamed(src['description']))
            self.assertEqual([s['label'] for s in kept], [s['label'] for s in mine], name)
            for a, b in zip(kept, mine):
                self.assertEqual(renamed(a), b, '%s / %s' % (name, a['label']))
            # Every shared block and every key step became a common child, in the same place.
            shared = sum(1 for s in src['steps'] if s['label'] in SHARED_LABELS or OLD_KEY_CHILD.match(s['inline'].get('workloadName') or ''))
            common = sum(1 for s in got['steps'] if (s['inline'].get('workloadName') or '').startswith('common-'))
            self.assertEqual(shared > 0, common > 0, name)
            self.assertEqual(renamed(src['description']), got['description'], name)
            for g, value in renamed(src.get('globalParameters') or {}).items():
                if g in got['globalParameters']:
                    self.assertEqual(value, got['globalParameters'][g], '%s global %s' % (name, g))
                else:
                    self.assertIn(g, ('RecordCount', 'WorkerThreadCount', 'ModelSourceSize', 'ProfiseeVersionCode', 'ProfiseeVersionNumber',
                                      'InstanceServiceName', 'MainHealthUrl', 'TargetHealthUrl'), '%s lost global %s' % (name, g))

    def test_a_restore_is_between_a_stop_and_a_start_then_the_key(self):
        for name in ('connect-database-reset', 'connect-database-seed-restore', 'connect-profisee-to-profisee-target-reset'):
            kinds = [s['inline'].get('workloadName') or s['inline'].get('operation') or s['inline'].get('type') for s in self.workloads[name]['steps']]
            at = kinds.index('RestoreDatabase')
            self.assertIn('common-instance-stop', kinds[:at], name)
            after = kinds[at:]
            self.assertLess(after.index('common-instance-start'), after.index('common-api-key-set'), name)

    def test_the_target_key_step_names_the_target(self):
        found = 0
        for w in self.workloads.values():
            for s in self.children(w['name']):
                params = s['inline'].get('parameters') or {}
                if s['inline']['workloadName'] == 'common-api-key-set' and 'ProfiseeToProfiseeRestKey' in json.dumps(params):
                    found += 1
                    box = {k: params.get(k) or w['globalParameters'].get(k) for k in
                           ('ApplicationServerName', 'DatabaseServerName', 'ProfiseeInstanceName', 'ProfiseeDatabaseName', 'ProfiseeBaseUrl')}
                    for k, v in box.items():
                        self.assertIn('ProfiseeToProfisee', v or '', '%s / %s: %s' % (w['name'], s['label'], k))
        self.assertGreater(found, 0)

    # ---------------------------------------------------------------- chain
    def test_a_test_checks_its_workflow_then_runs(self):
        for combo in COMBOS:
            kids = [s['inline']['workloadName'] for s in self.children('connect-test-' + combo)]
            want = ['common-testauto-tag-check'] + (['connect-profisee-to-profisee-bootstrap'] if combo.startswith('profisee') else []) + ['connect-%s-run' % combo]
            self.assertEqual(want, kids, combo)
            self.assertEqual({'Size': '1K', 'Threads': '4'}, {k: v for k, v in self.inputs('connect-test-' + combo).items() if k in ('Size', 'Threads')})

    def test_a_run_prepares_checks_rows_and_runs_its_tag(self):
        for combo in COMBOS:
            w = self.workloads['connect-%s-run' % combo]
            labels = [s['label'] for s in w['steps']]
            self.assertEqual('connect-' + combo, self.children(w['name'])[0]['inline']['workloadName'])
            self.assertEqual(combo.endswith('export'), 'Check Source Rows' in labels, combo)
            self.assertIn('connect-{{Size|lower}}-%s-{{Threads}}t' % combo, json.dumps(w['steps'][-1]), combo)
            self.assertEqual('TestAutoWorkflowStep', w['steps'][-1]['inline']['type'])
            kids = [s['inline']['workloadName'] for s in self.children('connect-' + combo)]
            want = ['connect-database-reset'] + (['connect-source-data-load'] if combo.endswith('export') else []) + ['connect-%s-prepare' % combo]
            self.assertEqual(want, kids, combo)

    def test_provider_all_runs_export_then_import(self):
        for p, dirs in PROVIDERS.items():
            kids = [s['inline']['workloadName'] for s in self.children('connect-%s-all' % p)]
            self.assertEqual(['connect-%s-%s-run' % (p, d) for d in dirs], [k for k in kids if k.endswith('-run')], p)

    def test_source_size_create_never_overwrites(self):
        sql = json.dumps(self.workloads['connect-source-size-create'])
        self.assertLess(sql.index('already exists; a source backup is never'), sql.index('RESTORE DATABASE'))
        self.assertNotIn('WITH REPLACE', sql.upper().replace(', REPLACE', ' WITH REPLACE'))
        self.assertNotIn('INIT', sql.replace('WITH FORMAT', ''))
        self.assertNotIn('[ModelSource]', sql)

    # ---------------------------------------------------------------- templates = today's workflows
    def test_setup_holds_each_template_once(self):
        self.assertEqual(9, len(self.templates))
        labels = [s['label'] for s in self.workloads['connect-setup']['steps']]
        self.assertEqual(['ScenarioMgt Check', 'Upsert Run Profiles'] + [s['label'] for s in self.templates], labels)

    def test_setup_touches_testauto_only(self):
        # Adding a size row = run setup again: it must never rebuild the database or call a provider.
        for s in self.workloads['connect-setup']['steps']:
            self.assertIn(s['inline']['type'], ('HTTP', 'PowerShellStep'), s['label'])

    def test_base_create_never_overwrites_and_proves_the_providers_once(self):
        w = self.workloads['connect-base-create']
        self.assertEqual('false', w['globalParameters']['BaseMissing'])
        labels = [s['label'] for s in w['steps']]
        at = labels.index('Report The Base State')
        self.assertEqual(['Bootstrap Main And Back Up The Baseline', 'Prove Every Export Prepares', 'Prove Every Import Prepares'], labels[at + 1:])
        for s in w['steps'][at + 1:]:
            self.assertEqual('{{BaseMissing}}', s.get('runWhen') or s['inline'].get('runWhen'), s['label'])
        # Nothing but base-create (and a person) runs the bootstrap that replaces the Main database.
        for other in self.workloads.values():
            if other['name'] != 'connect-base-create':
                self.assertNotIn('connect-bootstrap-main', [s['inline']['workloadName'] for s in self.children(other['name'])], other['name'])

    def test_a_scheduled_profisee_to_profisee_run_sets_up_its_target(self):
        kids = [s['inline']['workloadName'] for s in self.children('connect-profisee-to-profisee-all')]
        self.assertEqual(['connect-profisee-to-profisee-bootstrap', 'connect-profisee-to-profisee-export-run'], kids)
        with open(os.path.join(self.root, 'reference-kv', 'connect', 'schedule.json'), encoding='utf-8') as f:
            schedule = json.load(f)['entries']
        for name in ('1k-profisee-to-profisee', '1m-profisee-to-profisee'):
            self.assertEqual('connect-profisee-to-profisee-all', schedule[name + '.Target'])

    def test_templates_expand_to_todays_workflows(self):
        got = self.expand_all()
        self.assertEqual(sorted(self.golden), sorted(got))
        for key, gold in self.golden.items():
            spec = got[key]
            # The one name change: a 4-thread workflow now says so, like the 8 and 12 thread ones always did.
            self.assertEqual(gold['Name'] + (' 4T' if key.endswith('-4t') else ''), spec['Name'], key)
            for field in ('Category', 'PlainTags'):
                self.assertEqual(gold[field], spec[field], key)
            self.assertEqual(len(gold['Details']), len(spec['Details']), key)
            for g, d in zip(gold['Details'], spec['Details']):
                where = '%s / %s' % (key, g['Name'])
                for field in ('Name', 'Description', 'ExecutionOrder', 'ProfiseeVersion'):
                    self.assertEqual(g[field], d[field], where)
                self.assertEqual(g['ConfigSha256'], config_hash(d['ScenarioConfiguration']), where)
                self.assertLessEqual(len(d['ScenarioConfiguration']), 4000, where)

    def test_descriptions_name_the_new_workloads(self):
        for key, spec in self.expand_all().items():
            combo = re.match(r'connect-1[km]-(.+)-\d+t$', key).group(1)
            self.assertIn('Automation ID: <AUTOMATION_ID>', spec['Description'], key)
            self.assertIn("'connect-test-%s'" % combo, spec['Description'], key)
            self.assertNotIn('connect/workflows', spec['Description'], key)

    def test_run_profiles_are_todays(self):
        got = {}
        for p in self.profiles():
            code = p.pop('Code')
            self.assertNotIn(code, got)
            got[code] = p
        self.assertEqual(self.golden_profiles, got)

    def test_a_new_size_and_thread_row_give_new_workflows_and_change_no_other(self):
        rows = {'{{$ref:connect/sizes:*}}': SIZES + ',100=100', '{{$ref:connect/values:Threads}}': '4,8,12,16'}
        got = self.expand_all(rows)
        self.assertEqual(9 * 3 * 4, len(got))
        self.assertTrue(set(self.golden) <= set(got))
        for key, gold in self.golden.items():
            self.assertEqual([g['ConfigSha256'] for g in gold['Details']],
                             [config_hash(d['ScenarioConfiguration']) for d in got[key]['Details']], key)
        new = got['connect-100-sql-server-export-16t']
        self.assertEqual('Connect SQL Server Export 100 16T', new['Name'])
        self.assertTrue(new['PlainTags'].endswith(',100,16T'))
        self.assertIn('-PROFISEE-SQLSERVER-E-100-100-0-16', new['Details'][-1]['ScenarioConfiguration'])
        codes = {p['Code']: p for p in self.profiles(rows)}
        row = codes['{{ProfiseeVersionCode}}-PROFISEE-SQLSERVER-E-100-100-0-16']
        self.assertEqual((100, 100, 16), (row['SourceRecordCount'], row['TargetRecordCount'], row['WorkerThreadCount']))

    def test_a_bad_row_is_refused(self):
        for rows, part in (({'{{$ref:connect/sizes:*}}': 'X=abc'}, 'connect/sizes'), ({'{{$ref:connect/sizes:*}}': 'Z=0'}, 'connect/sizes'),
                           ({'{{$ref:connect/values:Threads}}': '4,x'}, 'connect/values:Threads')):
            with self.assertRaises(RuntimeError, msg=str(rows)) as caught:
                expand(self.templates[0], dict(ROWS, **rows))
            self.assertIn(part, str(caught.exception), str(rows))
            with self.assertRaises(RuntimeError, msg=str(rows)):
                self.profiles(dict(ROWS, **rows))

    def test_preflight_lists_exactly_the_keys_setup_creates(self):
        step = next(s for s in self.workloads['connect-preflight']['steps'] if s['label'] == 'List The Workflows Setup Creates')
        code, out, err = run_ps(step['inline']['scriptContent'], ROWS)
        self.assertEqual(0, code, err)
        self.assertEqual(set(self.golden), set(out.strip().split(',')))

    def test_preflight_reads_the_sizes_from_reference_data(self):
        text = json.dumps(self.workloads['connect-preflight'])
        self.assertIn('{{$ref:connect/sizes:*}}', text)
        for size in ('1K', '1M'):
            self.assertNotIn('ModelSourcePDATA%s' % size, text)

    # ---------------------------------------------------------------- reference sets, schedule, rounds
    def test_reference_seed_rows(self):
        def entries(name):
            with open(os.path.join(self.root, 'reference-kv', 'connect', name + '.json'), encoding='utf-8') as f:
                return json.load(f)['entries']
        self.assertEqual({'1K': '1000', '1M': '1000000'}, entries('sizes'))
        self.assertEqual({'Threads': '4,8,12'}, entries('values'))
        schedule = entries('schedule')
        old = source('schedules.json')
        self.assertEqual({'%s.%s' % (n, f) for n in old for f in ('Target', 'Values', 'Days', 'Time')}, set(schedule))
        self.assertEqual('connect-sql-server-all', schedule['1k-sql-server.Target'])
        self.assertEqual('Size=1M Threads=4', schedule['1m-snowflake.Values'])
        for name, row in old.items():
            self.assertEqual((row['Days'], row['Time']), (schedule[name + '.Days'], schedule[name + '.Time']), name)
            self.assertIn(schedule[name + '.Target'], self.workloads, name)
        self.assertFalse(os.path.exists(os.path.join(self.root, 'reference-kv', 'connect', 'workflows.json')))

    def test_one_schedule_workload_reads_its_rows_by_name(self):
        step = self.workloads['schedule-connect']['steps'][0]['inline']
        self.assertEqual('schedule-connect-{{Schedule}}', step['taskName'])
        self.assertEqual('{{$ref:connect/schedule:{{Schedule}}.Target}}', step['targetWorkload'])
        self.assertEqual('{{$ref:connect/schedule:{{Schedule}}.Values}}', step['targetParameters'])

    def test_rounds_pass_size_and_threads_as_values(self):
        seen = {}
        for path in glob.glob(os.path.join(self.root, 'rounds', '*.txt')):
            with open(path, encoding='utf-8') as f:
                lines = [ln.lstrip('+').strip() for ln in f if ln.strip() and not ln.startswith('#')]
            self.assertTrue(lines, path)
            for line in lines:
                name, _, values = line.partition(' ')
                self.assertIn(name, self.workloads, path)
                self.assertRegex(values, r'^Size=\w+ Threads=\d+$', path)
            seen[os.path.basename(path)] = lines
        self.assertEqual({'smoke.txt', '1k-4t-round.txt', '1k-round.txt', '1m-4t-round.txt', '1m-round.txt'}, set(seen))
        # The full round covers every provider and direction at every thread count.
        for t in (4, 8, 12):
            got = [ln for ln in seen['1m-round.txt'] if ln.endswith('Size=1M Threads=%d' % t)]
            self.assertEqual(9, len(got), t)

    def test_generator_is_byte_stable_and_keeps_edited_rows(self):
        def snapshot():
            out = {}
            for folder, _dirs, files in os.walk(self.root):
                for name in files:
                    with open(os.path.join(folder, name), 'rb') as f:
                        out[os.path.relpath(os.path.join(folder, name), self.root)] = f.read()
            return out
        before = snapshot()
        path = os.path.join(self.root, 'reference-kv', 'connect', 'sizes.json')

        def restore():
            with open(path, 'wb') as f:
                f.write(before[os.path.relpath(path, self.root)])
        self.addCleanup(restore)
        generate(self.root)
        self.assertEqual(before, snapshot())
        with open(path, encoding='utf-8') as f:
            data = json.load(f)
        data['entries']['100'] = '100'
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

    # ---------------------------------------------------------------- P2P target on a box whose model already uses the domains
    TARGET_BUILD = 'connect-model-profisee-to-profisee-target-build'

    def target_step(self, label):
        return next(s for s in self.workloads[self.TARGET_BUILD]['steps'] if s['label'] == label)['inline']

    def spec_domains(self):
        """Domain name -> spec id, from the Create Domain bodies."""
        out = {}
        for s in self.workloads[self.TARGET_BUILD]['steps']:
            if s['label'].startswith('Create Domain '):
                body = json.loads(s['inline']['body'])[0]
                out[body['identifier']['name']] = body['identifier']['id']
        return out

    def test_target_build_creates_and_loads_domains_only_when_they_are_not_there(self):
        w = self.workloads[self.TARGET_BUILD]
        labels = [s['label'] for s in w['steps']]
        self.assertEqual(labels.index('Delete Family') + 1, labels.index('Decide Domain Create'))
        self.assertEqual('DomainsToCreate', self.target_step('Decide Domain Create')['outputParameterName'])
        self.assertEqual('', w['globalParameters']['DomainsToCreate'])
        gated = [s for s in w['steps'] if s['label'].startswith(('Create Domain ', 'Load Domain '))]
        self.assertEqual(100, len(gated))
        for s in gated:
            self.assertEqual('{{DomainsToCreate}}', s['inline'].get('runWhen'), s['label'])
            self.assertIn('Skipped when', s['inline']['description'], s['label'])
        for label in ('Create Entity PDataProfiseeToProfiseeImport', 'Create Attributes PDataProfiseeToProfiseeImport', 'Verify Model'):
            self.assertIsNone(self.target_step(label).get('runWhen'), label)
        # The Main build is not changed: it owns its model.
        for s in self.workloads['connect-model-main-build']['steps']:
            self.assertIsNone(s['inline'].get('runWhen'), s['label'])

    @staticmethod
    def serve_model(entities, attributes):
        """A local stand-in for the target's REST address (synthetic model). Returns (server, base url, deleted list)."""
        import http.server
        import threading
        deleted = []

        class Handler(http.server.BaseHTTPRequestHandler):
            def answer(self, code, obj=None):
                data = b'' if obj is None else json.dumps(obj).encode('utf-8')
                self.send_response(code)
                self.send_header('Content-Type', 'application/json')
                self.send_header('Content-Length', str(len(data)))
                self.end_headers()
                self.wfile.write(data)

            def do_GET(self):
                if self.path.startswith('/rest/v1/Entities'):
                    return self.answer(200, {'data': [{'identifier': {'name': n, 'id': i, 'modelId': {'id': 'm'}}, 'isSystem': False}
                                                      for n, i in entities.items()]})
                if self.path.startswith('/rest/v1/Attributes'):
                    return self.answer(200, {'data': [{'identifier': {'name': a, 'entityId': {'name': e}}, 'domainEntityId': {'name': d}}
                                                      for e, a, d in attributes if e in entities]})
                return self.answer(404)

            def do_DELETE(self):
                name = self.path.rsplit('/', 1)[1]
                deleted.append(name)
                entities.pop(name, None)
                return self.answer(204)

            def log_message(self, *args):
                pass

        server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Handler)
        threading.Thread(target=server.serve_forever, daemon=True).start()
        return server, 'http://127.0.0.1:%d/rest' % server.server_address[1], deleted

    def run_target(self, label, url):
        return run_ps(self.target_step(label)['scriptContent'], {
            '{{ProfiseeBaseUrl}}': url, '{{ProfiseeApiKey}}': 'synthetic-key',
            '{{PDataProfiseeToProfiseeImport}}': 'PDataProfiseeToProfiseeImport',
            '{{PDataProfiseeToProfiseeExport}}': 'PDataProfiseeToProfiseeExport'})

    @staticmethod
    def serve_statements():
        """A local stand-in for the Databricks statement API (synthetic). Every statement SUCCEEDS at once; the primary key
        count answers 0. Returns (server, host url, list of the statements sent, in order)."""
        import http.server
        import threading
        sent = []

        class Handler(http.server.BaseHTTPRequestHandler):
            def do_POST(self):
                body = json.loads(self.rfile.read(int(self.headers['Content-Length'])).decode('utf-8'))
                sent.append(body['statement'])
                data = json.dumps({'statement_id': 's%d' % len(sent), 'status': {'state': 'SUCCEEDED'},
                                   'result': {'data_array': [['0']]}}).encode('utf-8')
                self.send_response(200)
                self.send_header('Content-Type', 'application/json')
                self.send_header('Content-Length', str(len(data)))
                self.end_headers()
                self.wfile.write(data)

            def log_message(self, *args):
                pass

        server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Handler)
        threading.Thread(target=server.serve_forever, daemon=True).start()
        return server, 'http://127.0.0.1:%d/' % server.server_address[1], sent

    def test_databricks_export_table_sets_its_stats_columns_before_connect_writes(self):
        # 11/12: on the first large Connect MERGE into the fresh table Databricks picks the data-skipping stats columns
        # itself and commits that as a metadata change; the parallel MERGEs then fail (DELTA_CONCURRENT_APPEND.
        # METADATA_CHANGE) and the 1M export goes red. Setting the columns when the table is made leaves that write nothing
        # to change (proven on a scratch table: unchanged with the property set, changed without it).
        w = self.workloads['connect-databricks-export-prepare']
        stats = w['globalParameters']['ExportStatsColumns']
        cols = [c.strip() for c in stats.split(',')]
        self.assertEqual(32, len(cols))
        self.assertEqual(len(cols), len(set(cols)))
        self.assertIn(w['globalParameters']['ExportKeyColumn'], cols)
        step = next(s for s in w['steps'] if s['label'] == 'Recreate Databricks Export Table')['inline']
        server, url, sent = self.serve_statements()
        try:
            tokens = {'{{%s}}' % k: v for k, v in w['globalParameters'].items()}
            tokens.update({'{{DatabricksHost}}': url, '{{DatabricksToken}}': 'synthetic-token'})
            code, out, err = run_ps(step['scriptContent'], tokens)
        finally:
            server.shutdown()
        self.assertEqual(0, code, err.strip() or out.strip())
        table = 'connex_test.pdatadatabricksexport'
        expected = "ALTER TABLE %s SET TBLPROPERTIES ('delta.dataSkippingStatsColumns' = '%s')" % (table, stats)
        self.assertEqual([expected], [s for s in sent if 'dataSkipping' in s])
        last_key = max(i for i, s in enumerate(sent) if 'PRIMARY KEY' in s or 'SET NOT NULL' in s)
        self.assertGreater(sent.index(expected), last_key)
        self.assertNotIn('{{', ''.join(sent))

    def test_target_build_keeps_domains_another_entity_uses_and_deletes_only_its_own_entities(self):
        domains = self.spec_domains()
        entities = dict(domains, OTHER_ENTITY='o1', PDataProfiseeToProfiseeImport='p1')
        attributes = [('OTHER_ENTITY', 'Dba_%03d' % n, 'Dba_%03d_PDATA' % n) for n in range(1, 51)] + \
                     [('PDataProfiseeToProfiseeImport', 'Dba_001', 'Dba_001_PDATA')]
        server, url, deleted = self.serve_model(entities, attributes)
        try:
            code, out, err = self.run_target('Delete Family', url)
            self.assertEqual(0, code, err)
            self.assertEqual(['PDataProfiseeToProfiseeImport'], deleted, 'never a domain, never the other entity')
            self.assertIn('Kept the 50 domains', out)
            self.assertIn('OTHER_ENTITY', out)
            code, out, err = self.run_target('Decide Domain Create', url)
            self.assertEqual(0, code, err)
            self.assertEqual('false', out.strip())
        finally:
            server.shutdown()

    def test_target_build_still_stops_when_a_used_domain_is_not_the_spec_one(self):
        domains = self.spec_domains()
        entities = dict(domains, OTHER_ENTITY='o1')
        entities['Dba_007_PDATA'] = '00000000-0000-0000-0000-000000000007'
        del entities['Dba_050_PDATA']
        attributes = [('OTHER_ENTITY', 'Dba_001', 'Dba_001_PDATA')]
        server, url, deleted = self.serve_model(entities, attributes)
        try:
            code, _out, err = self.run_target('Delete Family', url)
            self.assertNotEqual(0, code)
            self.assertEqual([], deleted, 'nothing is deleted before the stop')
            self.assertIn('Dba_007_PDATA', err)
            self.assertIn('Dba_050_PDATA', err)
            code, _out, err = self.run_target('Decide Domain Create', url)
            self.assertNotEqual(0, code, 'some but not all domains, or a wrong id: never guessed')
        finally:
            server.shutdown()

    def test_target_build_on_an_empty_or_own_model_deletes_the_family_and_creates_the_domains(self):
        domains = self.spec_domains()
        entities = dict(domains, PDataProfiseeToProfiseeImport='p1')
        attributes = [('PDataProfiseeToProfiseeImport', 'Dba_001', 'Dba_001_PDATA')]
        server, url, deleted = self.serve_model(entities, attributes)
        try:
            code, out, err = self.run_target('Delete Family', url)
            self.assertEqual(0, code, err)
            self.assertEqual(51, len(deleted))
            self.assertEqual('PDataProfiseeToProfiseeImport', deleted[0], 'dependents first')
            code, out, err = self.run_target('Decide Domain Create', url)
            self.assertEqual(0, code, err)
            self.assertEqual('true', out.strip())
        finally:
            server.shutdown()


if __name__ == '__main__':
    unittest.main()
