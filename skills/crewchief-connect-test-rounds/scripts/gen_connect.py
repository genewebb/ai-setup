"""Builds the CrewChief Connect pack (CrewChief/packs/connect). One workload per SHAPE: provider and direction are real
step differences and stay in the name; size and worker threads are run values, never part of a name or a copy of a file
(Gene 11/11).

  tests/      connect-test-<provider>-<direction>      what a person starts: one measured run at the Size and Threads passed
  internal/   connect-<provider>-<direction>-run       wait, prepare, check the rows, run the TestAuto workflow
              connect-<provider>-<direction>           reset, load the source data (exports), prepare
              connect-<provider>-all                   the provider's export, then its import (a schedule's target)
              ... the building blocks (model, strategies, service configurations, resets), carried from source/
  start/      connect-preflight, connect-setup, connect-base-create, connect-source-size-create
  schedule/   schedule-connect                         one workload; the schedule name passed picks its rows

  Before: connect-test-1k-sql-server-export (ran 4, 8 and 12 threads), connect-1k-t8-sql-server-export-run ...: 217 workloads.
  After:  connect-test-sql-server-export --param Size=1K --param Threads=8

Adding a size or a thread count is rows in git, never a workload and never a run of this generator:
  connect/sizes    100 = 100           (key = the Size a run passes and the end of ModelSourcePDATA<Size>.bak; value = records)
  connect/values   Threads = 4,8,12
then make the size's source backup (connect-source-size-create) and run connect-setup again: its template steps create
the run profiles and one TestAuto workflow per provider, direction, size and thread count.

Where the steps come from: source/ holds the step data of the pack as it was kept by hand before 11/11 (model builds,
strategy and service configuration artifacts, provider scripts: about 2 MB). This generator reads a source workload,
swaps every shared block (instance stop and start, health wait, API key) for the common pack's workload, turns size,
threads and version into inputs, and writes it. Every wrapper, test, schedule and the setup are built here. To change a
carried step, edit it in source/workloads and run the generator.

Usage: python gen_connect.py <packRoot>      (e.g. C:\\devops\\repos\\speed-merchants\\CrewChief\\packs\\connect)
"""
import json
import os
import re
import sys

root = os.path.abspath(sys.argv[1])
here = os.path.dirname(os.path.abspath(__file__))
FAM = 'connect'
SETUP = 'connect-setup'
SRC = os.path.join(here, 'source')
ref_dir = os.path.join(root, 'reference-kv', FAM)
wl_root = os.path.join(root, 'workloads', FAM)
sys.path.insert(0, os.environ.get('PACKGEN_TOOLS') or os.path.join(os.path.dirname(root), 'tools'))
from packgen import specs, steps  # noqa: E402
from packgen.values import record_count_input, ref as _ref, size_input, value_input, version_inputs  # noqa: E402
from packgen.workloads import clear_workloads, dump, seed_reference_set, workload  # noqa: E402

VER = "{{ProfiseeVersionCode}}"
PROVIDERS = [('sql-server', 'SQL Server', ('export', 'import')), ('databricks', 'Databricks', ('export', 'import')),
             ('snowflake', 'Snowflake', ('export', 'import')), ('synapse', 'Synapse', ('export', 'import')),
             ('profisee-to-profisee', 'Profisee To Profisee', ('export',))]
P2P = 'profisee-to-profisee'
COMBOS = [(p, text, d) for p, text, dirs in PROVIDERS for d in dirs]
BASELINE = "profisee_ConnectBaseline_PDATA_" + VER + ".bak"


def ref(set_name, key):
    return _ref(FAM, set_name, key)


def load_json(*parts):
    with open(os.path.join(SRC, *parts), encoding='utf-8-sig') as f:
        return json.load(f)


MANIFEST = load_json('manifest.json')

# ---------------------------------------------------------------- pack-owned reference sets (seeded once, then git is the source)
SIZES_TOKEN = "{{$ref:connect/sizes:*}}"
THREADS_TOKEN = ref('values', 'Threads')
seed_reference_set(os.path.join(ref_dir, 'sizes.json'),
    "Connect pack: the sizes a Connect run can have. Key = the Size a run passes and the end of the source backup's name "
    "(ModelSourcePDATA<Size>.bak in the SQL Server default backup folder); value = the number of records in its PDATA table. "
    "Add a size by adding a row here, making its source backup (connect-source-size-create) and running connect-setup (it "
    "creates the run profiles and TestAuto workflows of every row). Kept in git with the pack and restored to a box with "
    "Replace; never edited on a box.",
    {"1K": "1000", "1M": "1000000"},
    {"1K": "1,000 records in ModelSourcePDATA1K.bak.", "1M": "One million records in ModelSourcePDATA1M.bak."})
seed_reference_set(os.path.join(ref_dir, 'values.json'),
    "Connect pack: value lists the pack reads. Each row is a list separated by commas. Kept in git with the pack; never "
    "edited on a box.",
    {"Threads": "4,8,12"},
    {"Threads": "Connect worker thread counts connect-setup creates TestAuto workflows and run profiles for; a run passes "
                "one of them as Threads. Add a count here, then run connect-setup again."})
sched_entries, sched_desc = {}, {}
for sname, old in load_json('schedules.json').items():
    size, provider = sname.split('-', 1)
    for field, value, text in (("Target", "connect-%s-all" % provider, "the workload the scheduled task runs"),
                               ("Values", "Size=%s Threads=4" % size.upper(), "the values it passes to that workload, Name=Value separated by spaces"),
                               ("Days", old['Days'], "the weekday(s) it starts, e.g. Sat or Sat,Wed"),
                               ("Time", old['Time'], "the start time, HH:mm, 24-hour, local time")):
        sched_entries[f"{sname}.{field}"] = value
        sched_desc[f"{sname}.{field}"] = f"Schedule '{sname}' (Windows task schedule-connect-{sname}): {text}."
seed_reference_set(os.path.join(ref_dir, 'schedule.json'),
    "Connect pack: the schedules schedule-connect can apply. A schedule is four rows named <schedule>.Target, .Values, .Days "
    "and .Time; run schedule-connect with Schedule=<schedule> to create or update its Windows task. Add a schedule (another "
    "thread count, another size) by adding its four rows. Only ONE Connect run at a time per box: never let two schedules "
    "overlap. Kept in git with the pack; never edited on a box.",
    sched_entries, sched_desc)
for retired in ('workflows.json',):  # display names are composed by the setup templates now
    if os.path.exists(os.path.join(ref_dir, retired)):
        os.remove(os.path.join(ref_dir, retired))

# ---------------------------------------------------------------- box facts and inputs
MAIN_URL = "https://" + ref('machines', 'ApplicationServerNameFQDN') + "/" + ref('instances', 'ProfiseeInstanceName') + "/rest"
MAIN = {
    "ApplicationServerName": ref('machines', 'ApplicationServerName'),
    "DatabaseServerName": ref('machines', 'DatabaseServerName'),
    "ProfiseeInstanceName": ref('instances', 'ProfiseeInstanceName'),
    "ProfiseeDatabaseName": ref('databases', 'ProfiseeDatabaseName'),
    "ProfiseeBaseUrl": MAIN_URL,
    "TestAutoBaseUrl": "https://" + ref('machines', 'TestServerNameFQDN') + ":8443",
}
TARGET_URL = "https://{{ProfiseeToProfiseeServerNameFQDN}}/{{ProfiseeToProfiseeInstanceName}}/rest"
TARGET_KEY = {"ProfiseeApiKey": "{{$config:RestKeys:ProfiseeToProfiseeRestKey}}"}
TARGET_BOX = {"ApplicationServerName": "{{ProfiseeToProfiseeServerName}}", "DatabaseServerName": "{{ProfiseeToProfiseeDatabaseServerName}}",
              "ProfiseeInstanceName": "{{ProfiseeToProfiseeInstanceName}}", "ProfiseeDatabaseName": "{{ProfiseeToProfiseeDatabaseName}}",
              "ProfiseeBaseUrl": TARGET_URL}
# What each common workload reads from the workload that runs it.
COMMON_NEEDS = {
    'common-instance-stop': ("ApplicationServerName", "ProfiseeInstanceName"),
    'common-instance-start': ("ApplicationServerName", "ProfiseeInstanceName"),
    'common-instance-pools': ("ApplicationServerName", "ProfiseeInstanceName"),
    'common-health-wait': ("ProfiseeBaseUrl",),
    'common-api-key-set': ("ApplicationServerName", "DatabaseServerName", "ProfiseeInstanceName", "ProfiseeDatabaseName", "ProfiseeBaseUrl"),
    'common-base-backup-check': ("DatabaseServerName",),
    'common-testauto-tag-check': ("TestAutoBaseUrl",),
}

SIZE = size_input(FAM)
RECORD_COUNT = record_count_input(FAM)
THREADS = value_input('Threads', '4', "Connect worker threads of the run: one of the counts in connect/values:Threads.")
VERSION = {i['name']: i for i in version_inputs(FAM)}
P2P_TEXT = {
    'ProfiseeToProfiseeDatabaseName': ('databases', "Database of the Profisee To Profisee target instance."),
    'ProfiseeToProfiseeDatabaseServerName': ('machines', "SQL Server of the Profisee To Profisee target instance."),
    'ProfiseeToProfiseeInstanceName': ('instances', "Name of the Profisee To Profisee target instance."),
    'ProfiseeToProfiseeServerName': ('machines', "Application server of the Profisee To Profisee target instance."),
    'ProfiseeToProfiseeServerNameFQDN': ('machines', "Application server of the Profisee To Profisee target instance, full name."),
    'ProfiseeToProfiseeUrl': ('urls', "REST address of the Profisee To Profisee target instance."),
}
STANDARD = {'Size': SIZE, 'RecordCount': RECORD_COUNT, 'Threads': THREADS, **VERSION}
for _n, (_set, _text) in P2P_TEXT.items():
    STANDARD[_n] = value_input(_n, ref(_set, _n), _text + " Default: connect/%s:%s; a caller (a TestAutoManager lane) may pass its own." % (_set, _n))
ORDER = list(STANDARD)
# A workload that runs one of these needs the value itself (it is another pack's workload).
EXTERNAL_NEEDS = {'install-configure-upgrade': ('ProfiseeVersionNumber',)}
TOKEN = re.compile(r'\{\{([A-Za-z][A-Za-z0-9]*)(?:\|[^}]*)?\}\}')

WORKLOADS = {}  # name -> (folder, workload); written at the end, after the values a child needs are declared up the chain


def add(folder, name, description, tags, step_list, inputs=None, globals_=None, notes=""):
    assert name not in WORKLOADS, name
    globals_ = dict(globals_ or {})
    # The box facts the common pack's workloads read: declared here unless the step passes them itself.
    for s in step_list:
        child = s['inline'].get('workloadName')
        for need in COMMON_NEEDS.get(child, ()):
            if need not in globals_ and need not in (s['inline'].get('parameters') or {}):
                globals_[need] = MAIN[need]
    WORKLOADS[name] = (folder, {"name": name, "description": description, "tags": [FAM] + tags, "steps": step_list,
                                "inputs": list(inputs or []), "globals": globals_, "notes": notes})


def children(w):
    return [s['inline']['workloadName'] for s in w['steps'] if s['inline'].get('type') == 'RunWorkloadStep']


def declare_inputs():
    """Every run value, version key and target fact a workload or a workload below it reads is a declared input there,
    with the same default at every level: the value a caller passes travels down, a default only fills a gap."""
    for _folder, w in WORKLOADS.values():
        text = json.dumps(w['steps']) + json.dumps(w['globals'])
        have = {i['name'] for i in w['inputs']}
        w['_need'] = {n for n in TOKEN.findall(text) if n in STANDARD} | (have & set(STANDARD))
        for child in children(w):
            w['_need'] |= set(EXTERNAL_NEEDS.get(child, ()))
        if 'RecordCount' in w['_need']:
            w['_need'].add('Size')
    changed = True
    while changed:
        changed = False
        for _folder, w in WORKLOADS.values():
            for child in children(w):
                if child in WORKLOADS:
                    more = WORKLOADS[child][1]['_need'] - w['_need']
                    if more:
                        w['_need'] |= more
                        changed = True
    for _folder, w in WORKLOADS.values():
        other = [i for i in w['inputs'] if i['name'] not in STANDARD]
        w['inputs'] = [STANDARD[n] for n in ORDER if n in w['_need'] and n not in w['globals']] + other


# ---------------------------------------------------------------- carrying a source workload
RENAMES = {'{{WorkerThreadCount}}': '{{Threads}}', '{{ModelSourceSize}}': '{{Size}}'}
OLD_NAMES = {m['from']: new for new, m in MANIFEST.items() if m['from'] != new}
OLD_NAMES.update({'connect-api-key-set-main': 'common-api-key-set', 'connect-api-key-set-all': 'common-api-key-set',
                  'connect-api-key-set-profisee-to-profisee': 'common-api-key-set'})
OLD_NAME = re.compile(r'(?<![A-Za-z0-9-])(%s)(?![A-Za-z0-9-])' % '|'.join(re.escape(n) for n in sorted(OLD_NAMES, key=len, reverse=True)))
DROP_GLOBALS = ('RecordCount', 'WorkerThreadCount', 'ModelSourceSize', 'ProfiseeVersionCode', 'ProfiseeVersionNumber', 'InstanceServiceName')
FIND, STOP_SVC, START_SVC = 'Find The Instance Service', 'Stop Profisee Service', 'Start Profisee Service'
RESTORE_WHY = "a restore or a settings change must not happen under running services"
START_WHY = "the services must read the restored database and the changed settings"
# Shared blocks as the hand-kept pack wrote them (labels in order) -> the common pack's workloads.
BLOCKS = [
    ((FIND, STOP_SVC, 'Stop W3SVC', 'Stop WAS'), ('stop',)),
    ((FIND, STOP_SVC, 'Recycle Connect Application Pool', START_SVC), ('stop', 'start')),
    ((FIND, STOP_SVC), ('stop',)),
    (('Start WAS', 'Start W3SVC', START_SVC), ('start',)),
    (('Recycle Instance Application Pools', START_SVC), ('start',)),
    (('Recycle Target Application Pools', START_SVC), ('start',)),
    (('Start Every Service',), ('health',)),
]
SHARED_TYPES = ('ServiceControlStep', 'SetApiKeyStep')


def common_step(kind):
    if kind == 'stop':
        return steps.instance_stop_child(RESTORE_WHY)
    if kind == 'start':
        return steps.instance_start_child(START_WHY)
    return steps.health_child()


def swap_shared_blocks(name, old_steps, globals_):
    out, i, labels = [], 0, [s['label'] for s in old_steps]
    while i < len(old_steps):
        for pattern, kinds in BLOCKS:
            if tuple(labels[i:i + len(pattern)]) == pattern:
                out.extend(common_step(k) for k in kinds)
                i += len(pattern)
                break
        else:
            s = old_steps[i]
            child = s['inline'].get('workloadName')
            if child in ('connect-api-key-set-main', 'connect-api-key-set-all'):
                s = steps.key_set_child()
            elif child == 'connect-api-key-set-profisee-to-profisee':
                # The target instance: its key is another secret; its box comes from this workload's globals when they
                # name the target, else it is passed here.
                params = dict(TARGET_KEY)
                if 'ApplicationServerName' not in globals_:
                    params.update(TARGET_BOX)
                s = steps.key_set_child(parameters=params)
            out.append(s)
            i += 1
    for s in out:
        assert s['inline'].get('type') not in SHARED_TYPES and s['label'] != FIND, '%s: shared step %r was not swapped' % (name, s['label'])
    return out


def carry(name):
    meta = MANIFEST[name]
    with open(os.path.join(SRC, 'workloads', name + '.workload.json'), encoding='utf-8-sig') as f:
        w = json.load(f)
    assert w['name'] == meta['from'], name
    globals_ = dict(w.get('globalParameters') or {})
    step_list = swap_shared_blocks(name, w['steps'], globals_)
    text = json.dumps({"d": w['description'], "s": step_list, "g": globals_, "n": w.get('globalParametersNotes') or ""})
    for old, new in RENAMES.items():
        text = text.replace(old, new)
    text = OLD_NAME.sub(lambda m: OLD_NAMES[m.group(1)], text)
    data = json.loads(text)
    globals_ = data['g']
    for g in DROP_GLOBALS:
        globals_.pop(g, None)
    # The health address: the common health workload reads the instance's REST address.
    used = set(TOKEN.findall(json.dumps(data['s'])))
    for old_health, url in (('TargetHealthUrl', TARGET_URL), ('MainHealthUrl', MAIN_URL)):
        if old_health in globals_:
            assert globals_[old_health] == url + '/health', '%s: %s is %s' % (name, old_health, globals_[old_health])
            assert old_health not in used, '%s still reads %s' % (name, old_health)
            del globals_[old_health]
            globals_.setdefault('ProfiseeBaseUrl', url)
    inputs = [i for i in (w.get('inputs') or []) if i['name'] not in STANDARD and i['name'] not in ('WorkerThreadCount', 'ModelSourceSize')]
    folder = 'internal/shared' if meta['folder'] == 'internal' else meta['folder']
    tags = [t for t in w.get('tags', []) if t != FAM and not re.fullmatch(r'\d+[KMT]', t)]
    add(folder, name, data['d'], tags, data['s'], inputs=inputs, globals_=globals_, notes=data['n'])


for _name in MANIFEST:
    carry(_name)

BASE_EXISTS = "the Connect baseline of this version already exists (the check step found it), so there is nothing to make or prove"
_base = WORKLOADS['connect-base-create'][1]
assert _base['steps'][-1]['label'] == 'Bootstrap Main And Back Up The Baseline' and _base['steps'][-1]['inline']['runWhen'] == '{{BaseMissing}}'
_base['steps'] += [
    steps.gated(steps.run_child("Prove Every Export Prepares", "connect-exports-prepare-all",
                                "Reset to the new baseline, load the 1K source data and prepare every export provider once, proving "
                                "each provider is reachable before the first test", timeout=43200), "{{BaseMissing}}", BASE_EXISTS),
    steps.gated(steps.run_child("Prove Every Import Prepares", "connect-imports-prepare-all",
                                "Reset to the new baseline and prepare every import provider once, proving each provider is "
                                "reachable before the first test", timeout=43200), "{{BaseMissing}}", BASE_EXISTS)]
_base['description'] = (
    "What: Make the Connect baseline of one Profisee version on this box: wait for any TestAuto run, check whether this "
    "version's baseline already exists (when it does, skip everything else and end green: nothing is overwritten), then run "
    "connect-bootstrap-main (it REPLACES the Main Profisee database with the seed backup connect/databases:BaseSeedBackupFileName "
    "and runs Profisee Configuration on it, then API key, legacy cleanup, Main model build, SQL export table, Connect objects), "
    "which ends with the baseline backup profisee_ConnectBaseline_PDATA_<version code>.bak of Main, then prepare every export "
    "and every import once (1K, 4 worker threads) to prove each provider is reachable. Why: every Connect test run resets Main "
    "to the baseline of its version; connect-preflight fails until it exists. When: once per box and version, after the "
    "Profisee of that version is installed; then run connect-setup (it creates this version's TestAuto workflows and touches "
    "no database). To prove the providers again later run connect-exports-prepare-all and connect-imports-prepare-all. Needs: "
    "the connect/* reference sets (or a lane's version parameters) and the box's secrets; the seed backup and "
    "ModelSourcePDATA1K.bak in the SQL Server default backup folder of connect/machines:DatabaseServerName; the install pack "
    "on this box; no test running against this Profisee database. It never touches the Profisee to Profisee target and never "
    "overwrites a baseline. Success: Every step Succeeded or Skipped. If it fails: open the first failed step; for the "
    "bootstrap, the run output of connect-bootstrap-main names what to check.")

# ---------------------------------------------------------------- per provider and direction: prepare chain, measured run, test
def key(provider, direction):
    """Automation tag key of the TestAuto workflow of one provider and direction, as workload text."""
    return "connect-{{Size|lower}}-%s-%s-{{Threads}}t" % (provider, direction)


ROWS_SQL = """DECLARE @n BIGINT = (SELECT COUNT_BIG(*) FROM data.tPDataSourceImport);
IF @n <> {{RecordCount}} THROW 50000, 'PDataSourceImport holds the wrong number of rows for a {{Size}} export run (want {{RecordCount}}).', 1;
SELECT @n AS PDataSourceImportRows;"""
BLOCK = ("Why: a building block of the Connect pack; a test, setup or schedule workload runs it so its steps exist once. When: "
         "Never run directly once the pack is tested; its parents run it. ")
RESULT = ("Success: Every step Succeeded or Skipped. If it fails: Run connect-preflight first; then open the first failed "
          "step, whose If it fails text names what to check.")

for provider, ptext, direction in COMBOS:
    dtext = direction.title()
    what = f"Connect {ptext} {dtext}"
    base = f"connect-{provider}-{direction}"
    export = direction == 'export'
    prepare = [steps.run_child("Reset To Baseline", "connect-database-reset",
                               "Restore the Connect baseline of this version and check the source data load strategy", timeout=43200)]
    if export:
        prepare.append(steps.run_child("Source Data Load", "connect-source-data-load",
                                       "Restore the source backup of the Size passed as ModelSource, check its row count, load PDataSourceImport from it",
                                       timeout=43200))
    prepare.append(steps.run_child(f"Prepare {ptext} {dtext}", base + "-prepare",
                                   f"Prepare the {ptext} {dtext} run at the Connect worker threads passed", timeout=43200))
    add(f"internal/providers/{provider}", base,
        (f"What: Everything before a measured {what} run at the Size and Threads passed: reset to the baseline, "
         + ("load the source data of that size, " if export else "") + "prepare (sets the worker threads). " + BLOCK
         + "Needs: workloads it runs: " + ", ".join(s['inline']['workloadName'] for s in prepare) + ". " + RESULT),
        ["providers", provider], prepare, inputs=[SIZE, RECORD_COUNT, THREADS], globals_={"SourceTableName": "PDATA"},
        notes="SourceTableName is the table every size's source backup holds; every shared child reads it from here.")
    run = [steps.wait_runs(),
           steps.run_child(f"Prepare {ptext} {dtext}", base, "Reset, " + ("load the source data, " if export else "") + "prepare at the worker threads passed",
                           timeout=43200)]
    if export:
        run.append(steps.sql("Check Source Rows", ROWS_SQL,
                             "What: Fail unless PDataSourceImport holds exactly the record count of the Size passed, so a short load never "
                             "produces a measured run. Why: an export of fewer rows would record a faster time under the full size. Success: "
                             "the count is printed. If it fails: read the SQL error text first; then check the source data load of this run.",
                             timeout=300))
    run.append(steps.testauto(f"Run {what}", key(provider, direction), f"{what} at the Size and Threads passed", SETUP))
    add(f"internal/providers/{provider}", base + "-run",
        (f"What: One measured run: {what} at the Size and Threads passed. Waits for any interrupted earlier run on this box, "
         f"runs {base} (reset, " + ("source load, " if export else "") + "prepare), "
         + ("checks PDataSourceImport holds the record count, " if export else "")
         + f"then runs its TestAuto workflow (found by its automation tag) and waits for it. Example: {base}-run --param Size=1K "
         f"--param Threads=8. " + BLOCK + f"Needs: {SETUP} ran on this box for this version; workloads it runs: {base}. " + RESULT),
        ["providers", provider], run, inputs=[SIZE, RECORD_COUNT, THREADS],
        globals_={"TestAutoBaseUrl": MAIN["TestAutoBaseUrl"], "DatabaseServerName": MAIN["DatabaseServerName"],
                  "ProfiseeDatabaseName": MAIN["ProfiseeDatabaseName"]})
    test = [steps.tag_check_child("Workflow For This Run Exists", key(provider, direction), SETUP)]
    if provider == P2P:
        test.append(steps.run_child("Profisee To Profisee Setup", "connect-profisee-to-profisee-bootstrap",
                                    "Set the target's API key, build the target model, set up Connect for it and back up the target baseline",
                                    timeout=43200))
    test.append(steps.run_child(f"{ptext} {dtext}", base + "-run", f"The measured {what} run at the Size and Threads passed", timeout=43200))
    add("tests", f"connect-test-{provider}-{direction}",
        (f"What: Runs the {what} test at the Size (a key of connect/sizes; default 1K) and Threads (one of "
         f"connect/values:Threads; default 4) passed: checks its TestAuto workflow exists, "
         + ("sets up the target instance, " if provider == P2P else "")
         + f"resets, prepares and runs one measured TestAuto run. Example: connect-test-{provider}-{direction} --param Size=1M "
         "--param Threads=12. Why: this is the test a person starts; a round runs it once per thread count. When: any time "
         f"after {SETUP} has run on this box for the current Profisee version; only ONE Connect run at a time per box. Needs: "
         f"{SETUP}; the connect/* reference sets filled in; the source backup of the size (ModelSourcePDATA<Size>.bak)"
         + ("; the target instance in connect/machines, connect/instances and connect/urls" if provider == P2P else "")
         + ". Success: The run ends Succeeded; the TestAuto execution holds its metrics. If it fails: Run connect-preflight "
         "first; then open the first failed step."),
        [provider], test, inputs=[SIZE, THREADS], globals_={"TestAutoBaseUrl": MAIN["TestAutoBaseUrl"]})

for provider, ptext, dirs in PROVIDERS:
    chain = [steps.run_child(f"{ptext} {d.title()}", f"connect-{provider}-{d}-run", f"The measured {ptext} {d.title()} run", timeout=43200)
             for d in dirs]
    if provider == P2P:  # nothing else builds the target, so a scheduled run must
        chain.insert(0, steps.run_child("Profisee To Profisee Setup", "connect-profisee-to-profisee-bootstrap",
                                        "Set the target's API key, build the target model, set up Connect for it and back up the target baseline",
                                        timeout=43200))
    add(f"internal/providers/{provider}", f"connect-{provider}-all",
        (f"What: Every {ptext} run at the Size and Threads passed: " + ("the target setup, then " if provider == P2P else "")
         + ", then ".join("the " + d for d in dirs) + ". " + BLOCK
         + "A schedule (schedule-connect) targets it. Needs: workloads it runs: "
         + ", ".join(s['inline']['workloadName'] for s in chain) + ". " + RESULT),
        ["providers", provider], chain,
        inputs=[SIZE, THREADS], notes="The import reads what the export wrote; a failed export stops the chain.")

# ---------------------------------------------------------------- start/connect-setup: run profiles and one template per provider and direction
SETS = {"Sizes": SIZES_TOKEN}
LOOPS = {"Size": specs.set_keys('Sizes'), "Threads": specs.items(THREADS_TOKEN)}
PRELUDE = r"""function Set-Run($v) {
    $v.SizeLower = $v.Size.ToLower()
    $v.RecordCount = Get-SetValue 'Sizes' $v.Size
    if ($v.RecordCount -notmatch '^[1-9]\d*$') { throw "connect/sizes:$($v.Size) is '$($v.RecordCount)'; a record count is a whole number above 0." }
    if ($v.Threads -notmatch '^[1-9]\d?$') { throw "connect/values:Threads holds '$($v.Threads)'; a thread count is a whole number from 1 to 99." }
}
"""
DERIVE = "Set-Run $v"
OLD_CODE = re.compile(r'-1000-1000-0-4(?![0-9])')
NEW_CODE = '-<<RecordCount>>-<<RecordCount>>-0-<<Threads>>'
SETUP_FAIL = (" If it fails: the message names the value or the workflow: a size with a bad record count, a step configuration "
              "over 4000 characters, or two workflows with the same tag (untag the copy by hand); any other error names the record.")


def code_template(text, where):
    out, n = OLD_CODE.subn(NEW_CODE, text)
    assert n >= 1, where + ': no run profile code found'
    assert '1000' not in out.replace('"JobPageSize": 1000', '') and '1K' not in out, where + ': a size is left in the template'
    return out


TEMPLATES = {}
for (provider, ptext, direction), (pd, spec) in zip(COMBOS, sorted(load_json('specs.json').items(), key=lambda kv: [f"{p}-{d}" for p, _t, d in COMBOS].index(kv[0]))):
    assert pd == f"{provider}-{direction}", pd
    assert spec['DisplayName'].endswith(' 1K') and spec['PlainTags'].endswith(',1K,4T'), pd
    details = []
    for d in spec['Details']:
        cfg = d['ScenarioConfiguration']
        assert len(cfg) <= specs.CONFIG_LIMIT - 150, '%s / %s: configuration is %d characters' % (pd, d['Name'], len(cfg))
        details.append((d['Name'], d['Description'].replace('-1000-1000-0-4.', NEW_CODE + '.'),
                        code_template(cfg, pd) if 'RunProfileCode' in cfg else cfg))
    assert sum('<<RecordCount>>' in c for _n, _d, c in details) == 1, pd + ': the metrics step holds the run profile code'
    name = spec['DisplayName'][:-len(' 1K')]
    TEMPLATES[pd] = dict(
        label=f"Upsert {ptext} {direction.title()} Workflows", key=f"connect-<<SizeLower>>-{pd}-<<Threads>>t",
        name=f"{name} <<Size>> <<Threads>>T",
        spec={"PlainTags": spec['PlainTags'][:-len(',1K,4T')] + ",<<Size>>,<<Threads>>T",
              "Description": ("Automation ID: <AUTOMATION_ID>. CrewChief finds this workflow by that tag alone; do not edit or remove "
                              "the tag, and to experiment copy the workflow and remove the tag from the copy. "
                              f"Measures: {name}, <<RecordCount>> records, <<Threads>> worker threads, on the Profisee version in "
                              f"connect/environment:ProfiseeVersionCode. Run by the CrewChief test workload 'connect-test-{pd}' "
                              f"(through 'connect-{pd}-run'), which resets, prepares and checks the data first; running it alone "
                              "measures nothing useful."),
              "Details": details})


def template_step(t):
    return specs.template_upsert_step(
        t["label"], t["key"], t["name"], t["spec"], LOOPS,
        f"What: Create or update the TestAuto workflow '{t['name'].replace('<<Size>>', '<Size>').replace('<<Threads>>', '<Threads>')}' "
        f"({len(t['spec']['Details'])} steps) for every size in connect/sizes and every thread count in connect/values:Threads, "
        "each found by its automation tag. The step holds the workflow once, as a template; a new row gives a new workflow and "
        "the existing ones are updated in place. Why: a Connect run finds its workflow by that tag. Success: the last line "
        "lists the workflows created or updated." + SETUP_FAIL,
        setup_name=SETUP, category="Connect", sets=SETS, prelude=PRELUDE, derive=DERIVE)


def key_patterns():
    return [(t["key"], LOOPS, SETS, PRELUDE, DERIVE) for t in TEMPLATES.values()]


profile_rows = []
for p in load_json('profiles.json'):
    assert p['SourceRecordCount'] == 1000 and p['TargetRecordCount'] == 1000 and p['WorkerThreadCount'] == 4, p['Code']
    assert p['Name'].count('(1000 records, 4 threads, ') == 1, p['Name']
    profile_rows.append(dict(p, Code=code_template(p['Code'], p['Code']),
                             Name=p['Name'].replace('(1000 records, 4 threads, ', '(<<RecordCount>> records, <<Threads>> threads, '),
                             SourceRecordCount='<<RecordCount>>', TargetRecordCount='<<RecordCount>>', WorkerThreadCount='<<Threads>>'))
PROFILE_TEMPLATE = json.dumps(profile_rows)
for _field in ('SourceRecordCount', 'TargetRecordCount', 'WorkerThreadCount'):  # numbers, not text
    PROFILE_TEMPLATE = re.sub(r'("%s": )"(<<[A-Za-z]+>>)"' % _field, r'\1\2', PROFILE_TEMPLATE)
PROFILE_MARKER = '# ---- upsert the run profiles'
PROFILE_UPSERT = r"""$base = '{{ScenarioMgtBaseUrl}}'.TrimEnd('/') + '/'
$headers = @{ 'x-api-key' = '{{ScenarioMgtApiKey}}'; accept = 'application/json' }
$profiles = @(foreach ($one in $specs) { $one | ConvertFrom-Json })
Invoke-RestMethod -Method Patch -Uri "${base}v1/Records/ConnectRunProfile?IsUpsert=true&recordsAreSameShape=true" -Headers $headers -ContentType 'application/json' -Body (ConvertTo-Json -Depth 5 -InputObject $profiles) | Out-Null
foreach ($p in $profiles) {
    $read = Invoke-RestMethod -Uri "${base}v1/Records/ConnectRunProfile/$([uri]::EscapeDataString($p.Code))" -Headers $headers
    "Run profile present: $($p.Code)"
}
"""
SM_GLOBALS = {"ScenarioMgtBaseUrl": ref('urls', 'ScenarioMgtBaseUrl'), "ScenarioMgtApiKey": "{{$config:RestClients:ScenarioMgt:ApiKey}}"}
add("start", SETUP,
    ("What: Create or update the Connect run profiles and the tagged TestAuto workflows of every provider and direction for "
     "every size in connect/sizes and every thread count in connect/values:Threads (one template each). It writes to TestAuto "
     "only: it never touches the Profisee database, a backup or a provider (connect-base-create builds those, once). Why: "
     "every run finds its workflow by automation tag and records under its run profile. When: once per box and Profisee "
     "version (after connect-base-create); after adding a size row or a thread count; after any change to a workflow "
     "template. Takes minutes. Reruns update in place and never remove a workflow. Needs: connect-preflight passes up to the "
     "workflow check. Success: Every step Succeeded; each template step lists its workflows. If it fails: open the first "
     "failed step, whose If it fails text names what to check."),
    ["setup"],
    [steps.http_get("ScenarioMgt Check", "{{ScenarioMgtBaseUrl}}v1/Records/TestAutoWorkflow?PageSize=1",
                    "What: List one TestAuto workflow. Why: proves the address and key reach the TestAuto repository before anything "
                    "is written. Success: HTTP 200. If it fails: 401 = wrong ScenarioMgt key (RestClients:ScenarioMgt:ApiKey); 404 = "
                    "wrong address in connect/urls:ScenarioMgtBaseUrl.", headers={"x-api-key": "{{ScenarioMgtApiKey}}"}),
     steps.ps("Upsert Run Profiles",
              specs.expand_script(PROFILE_TEMPLATE, LOOPS, SETUP, SETS, PRELUDE, DERIVE) + '\n' + PROFILE_MARKER + '\n' + PROFILE_UPSERT,
              "What: Create or update the Connect run profile of every provider and direction for every size in connect/sizes and "
              "every thread count in connect/values:Threads (<version>-<source>-<target>-<E or I>-<records>-<records>-0-<threads>), "
              "then read each back. Why: the metrics step of every workflow records under its run profile. Success: one line per "
              "profile. If it fails: a bad size or thread row is named in the error; 401 = the ScenarioMgt key.", timeout=900)]
    + [template_step(t) for t in TEMPLATES.values()],
    globals_={**SM_GLOBALS, "TestAutoBaseUrl": MAIN["TestAutoBaseUrl"], "TestAutoEnvironmentName": ref('machines', 'TestServerName'),
              "TestAutoApplicationServer": ref('machines', 'ApplicationServerName'),
              "TestAutoDatabaseServer": ref('machines', 'DatabaseServerName')})

# ---------------------------------------------------------------- start/connect-preflight
SIZE_ROWS_SQL = ("SELECT LTRIM(RTRIM(LEFT(s.value, CHARINDEX(N'=', s.value + N'=') - 1))) AS size "
                 "FROM STRING_SPLIT(N'" + SIZES_TOKEN + "', N',') s WHERE LTRIM(RTRIM(s.value)) <> N''")
SOURCE_BACKUPS_SQL = """SET NOCOUNT ON;
-- The sizes are the rows of the reference set connect/sizes (written here as key=value pairs separated by commas).
DECLARE @dir nvarchar(400) = CAST(SERVERPROPERTY('InstanceDefaultBackupPath') AS nvarchar(400));
DECLARE @exists int, @f nvarchar(600), @size nvarchar(50), @have nvarchar(max) = N'', @missing nvarchar(max) = N'';
DECLARE names CURSOR LOCAL FAST_FORWARD FOR @@SIZES@@;
OPEN names;
FETCH NEXT FROM names INTO @size;
WHILE @@FETCH_STATUS = 0
BEGIN
    SET @f = @dir + N'\\ModelSourcePDATA' + @size + N'.bak';
    EXEC master.dbo.xp_fileexist @f, @exists OUTPUT;
    IF @exists = 1 SET @have += N'ModelSourcePDATA' + @size + N'.bak ' ELSE SET @missing += @f + N' ';
    FETCH NEXT FROM names INTO @size;
END
CLOSE names; DEALLOCATE names;
IF @missing <> N''
BEGIN
    DECLARE @msg nvarchar(2048) = CONCAT(N'Source backup file(s) missing on the database server: ', @missing, N'. Copy them into the SQL Server default backup folder, or make a smaller size from a larger one with connect-source-size-create.');
    THROW 50010, @msg, 1;
END
PRINT CONCAT(N'Found in ', @dir, N': ', @have);""".replace('@@SIZES@@', SIZE_ROWS_SQL)
HTTP_RESULT = ("Success: The response status is 200. If it fails: 401 = the API key secret is wrong; 404 = the address is wrong; "
               "no response = the server in the URL (connect/urls, connect/machines) is down.")
add("start", "connect-preflight",
    ("What: Checks this box is ready for Connect testing: the instance's application pools exist and run, the source backup of "
     "every size in connect/sizes and the Connect baseline of this version are on the database server, TestAuto and its "
     "repository answer, the standard API key is set and works through the gateway and the Data service (common-api-key-set), "
     "and every TestAuto workflow connect-setup creates for the size and thread rows now in reference data sits on exactly one "
     "workflow. CrewChief's own pre-run check first proves every connect/* reference value it uses is filled in. Why: finds "
     "every environment problem in one run, before a test fails half way through. When: before and after connect-setup, after "
     "any reference data change, after a Profisee upgrade, before every round, and first whenever a test fails; never while a "
     "test runs on this application server. Needs: the connect/* reference sets, the common pack and the box's secrets. It "
     "changes only two things: the pool step starts a pool that is stopped, and the key step writes the standard API key and "
     "restarts IIS. Success: Every step Succeeded or Skipped; before the first connect-setup the workflow step says \"not "
     "created yet\", normal. If it fails: each step's failure text names the reference key, secret or machine to fix; fix "
     "reference data or the box, never a workload file."),
    [],
    [steps.pools_child("Application Pools Exist", "Start",
                       "a reset fails half way when the instance has no pools or one will not start; this finds it first"),
     steps.sql("Source Backups Exist", SOURCE_BACKUPS_SQL,
               "What: Check the SQL Server default backup folder holds the source backup of every size in connect/sizes "
               "(ModelSourcePDATA<Size>.bak). Why: every export run restores its size's backup as the ModelSource database. Success: "
               "the files found are listed. If it fails: the message names the missing files; copy them there, or make a smaller "
               "size from a larger one with connect-source-size-create.", conn=steps.MASTER, timeout=120),
     steps.backup_check_child("Connect Baseline Exists", BASELINE, "connect-base-create"),
     steps.http_get("TestAuto Answers", "{{TestAutoBaseUrl}}/api/workflows/by-tag?tag=AUTO%3Apreflight",
                    "What: Ask TestAuto on this box (connect/machines:TestServerNameFQDN, port 8443) for workflows tagged with a probe "
                    "tag. Why: every Connect run finds its TestAuto workflow by tag through this call. " + HTTP_RESULT,
                    verify_ssl=False, max_time=120),
     steps.http_get("TestAuto Model Answers", "{{ScenarioMgtBaseUrl}}v1/Records/TestAutoWorkflow?PageSize=1",
                    "What: Read one TestAuto workflow record from the TestAuto repository (connect/urls:ScenarioMgtBaseUrl) with the "
                    "RestClients:ScenarioMgt:ApiKey secret. Why: connect-setup writes the run profiles and workflows through it. "
                    + HTTP_RESULT, headers={"x-api-key": "{{ScenarioMgtApiKey}}"}, max_time=120),
     steps.wait_runs(),
     steps.key_set_child(),
     specs.keys_step("List The Workflows Setup Creates", key_patterns(),
                     "What: Work out, from the size and thread rows now in reference data (connect/sizes, connect/values:Threads), the "
                     "key of every TestAuto workflow connect-setup creates, with the same loops connect-setup uses, into the run "
                     "parameter SetupTagKeys. Why: the next step checks each of them; the list is never typed, so it cannot fall "
                     "behind a new row. Success: one line of keys. If it fails: a row is empty or malformed; the message names it.",
                     setup_name=SETUP, output="SetupTagKeys"),
     steps.tag_check_child("Every Workflow Found Once", "{{SetupTagKeys}}", SETUP, allow_none=True)],
    globals_={**SM_GLOBALS, "SetupTagKeys": ""},
    notes="SetupTagKeys is set by the step List The Workflows Setup Creates during the run; it starts blank and is never passed.")

# ---------------------------------------------------------------- start/connect-source-size-create
# Makes the source backup of a smaller size from a larger one. It works in its own scratch database and never
# overwrites a file: an existing backup of the size stops it at the first step.
SCRATCH_DB = "ModelSourceSizeBuild"
SIZE_CREATE_SQL = """SET NOCOUNT ON;
DECLARE @dir nvarchar(400) = CAST(SERVERPROPERTY('InstanceDefaultBackupPath') AS nvarchar(400));
DECLARE @from nvarchar(600) = @dir + N'\\ModelSourcePDATA{{SourceSize}}.bak', @to nvarchar(600) = @dir + N'\\ModelSourcePDATA{{Size}}.bak';
DECLARE @want bigint = {{RecordCount}}, @exists int, @sql nvarchar(max), @msg nvarchar(2048);
EXEC master.dbo.xp_fileexist @to, @exists OUTPUT;
IF @exists = 1 BEGIN SET @msg = CONCAT(@to, N' already exists; a source backup is never overwritten. Delete it by hand first when it must be rebuilt.'); THROW 50020, @msg, 1; END
EXEC master.dbo.xp_fileexist @from, @exists OUTPUT;
IF @exists = 0 BEGIN SET @msg = CONCAT(N'The larger source backup ', @from, N' (SourceSize {{SourceSize}}) is missing.'); THROW 50021, @msg, 1; END
IF DB_ID(N'@@DB@@') IS NOT NULL BEGIN SET @msg = N'Database @@DB@@ exists: an earlier run of this workload stopped half way. Check nobody uses it, drop it, then run again.'; THROW 50022, @msg, 1; END
DECLARE @dataDir nvarchar(400) = CAST(SERVERPROPERTY('InstanceDefaultDataPath') AS nvarchar(400)), @logDir nvarchar(400) = CAST(SERVERPROPERTY('InstanceDefaultLogPath') AS nvarchar(400));
DECLARE @files TABLE (
    LogicalName nvarchar(128), PhysicalName nvarchar(260), Type char(1), FileGroupName nvarchar(128),
    Size numeric(20,0), MaxSize numeric(20,0), FileId bigint, CreateLSN numeric(25,0), DropLSN numeric(25,0),
    UniqueId uniqueidentifier, ReadOnlyLSN numeric(25,0), ReadWriteLSN numeric(25,0), BackupSizeInBytes bigint,
    SourceBlockSize int, FileGroupId int, LogGroupGUID uniqueidentifier, DifferentialBaseLSN numeric(25,0),
    DifferentialBaseGUID uniqueidentifier, IsReadOnly bit, IsPresent bit, TDEThumbprint varbinary(32), SnapshotUrl nvarchar(360));
DECLARE @disk nvarchar(700) = N'N''' + REPLACE(@from, N'''', N'''''') + N'''';
SET @sql = N'RESTORE FILELISTONLY FROM DISK = ' + @disk;
INSERT @files EXEC (@sql);
DECLARE @move nvarchar(max) = (
    SELECT STRING_AGG(CONVERT(nvarchar(max), N'MOVE N''' + REPLACE(LogicalName, N'''', N'''''') + N''' TO N'''
        + REPLACE(CASE WHEN Type = 'L' THEN @logDir ELSE @dataDir END
            + CASE WHEN RIGHT(CASE WHEN Type = 'L' THEN @logDir ELSE @dataDir END, 1) = N'\\' THEN N'' ELSE N'\\' END
            + N'@@DB@@_' + CAST(FileId AS nvarchar(20)) + CASE WHEN Type = 'L' THEN N'.ldf' ELSE N'.mdf' END, N'''', N'''''') + N''''), N', ')
    FROM @files);
SET @sql = N'RESTORE DATABASE [@@DB@@] FROM DISK = ' + @disk + N' WITH ' + @move;
EXEC (@sql);
BEGIN TRY
    DECLARE @have bigint;
    EXEC sp_executesql N'SELECT @n = COUNT_BIG(*) FROM [@@DB@@].dbo.PDATA', N'@n bigint OUTPUT', @n = @have OUTPUT;
    IF @have <= @want BEGIN SET @msg = CONCAT(N'ModelSourcePDATA{{SourceSize}}.bak holds ', @have, N' PDATA rows; size {{Size}} needs ', @want, N' and must be smaller than its source. Pass a larger SourceSize.'); THROW 50023, @msg, 1; END
    -- Keep the first @want rows in Code order, so the same rows are kept every time.
    EXEC sp_executesql N'WITH ordered AS (SELECT ROW_NUMBER() OVER (ORDER BY Code) AS rn FROM [@@DB@@].dbo.PDATA) DELETE FROM ordered WHERE rn > @want', N'@want bigint', @want = @want;
    EXEC sp_executesql N'SELECT @n = COUNT_BIG(*) FROM [@@DB@@].dbo.PDATA', N'@n bigint OUTPUT', @n = @have OUTPUT;
    IF @have <> @want BEGIN SET @msg = CONCAT(N'After trimming, PDATA holds ', @have, N' rows, not ', @want, N'.'); THROW 50024, @msg, 1; END
    SET @sql = N'BACKUP DATABASE [@@DB@@] TO DISK = N''' + REPLACE(@to, N'''', N'''''') + N''' WITH FORMAT, COMPRESSION, CHECKSUM';
    EXEC (@sql);
    SET @sql = N'RESTORE VERIFYONLY FROM DISK = N''' + REPLACE(@to, N'''', N'''''') + N''' WITH CHECKSUM';
    EXEC (@sql);
END TRY
BEGIN CATCH
    IF DB_ID(N'@@DB@@') IS NOT NULL BEGIN ALTER DATABASE [@@DB@@] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE [@@DB@@]; END;
    THROW;
END CATCH
ALTER DATABASE [@@DB@@] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
DROP DATABASE [@@DB@@];
PRINT CONCAT(N'Wrote and verified ', @to, N': the first ', @want, N' PDATA rows of ModelSourcePDATA{{SourceSize}}.bak in Code order.');""".replace('@@DB@@', SCRATCH_DB)
SIZE_CREATE_STEP = steps.sql(
    "Build The Source Backup Of This Size", SIZE_CREATE_SQL,
    "What: Restore the larger source backup under a scratch name, trim PDATA to the record count of the Size passed, back "
    "it up as ModelSourcePDATA<Size>.bak, verify it and drop the scratch database. Why: every export run of a size "
    "restores this file. Success: one line names the file written. If it fails: the message names the file or row to "
    "fix; nothing was overwritten.", conn=steps.MASTER, timeout=7200)
SIZE_CREATE_STEP["inline"]["timeoutSeconds"] = 7500  # the whole step may take as long as its SQL (a 1M restore, trim and backup)
add("start", "connect-source-size-create",
    ("What: Make the source backup of a smaller size from a larger one: restore ModelSourcePDATA<SourceSize>.bak as the scratch "
     f"database {SCRATCH_DB}, keep the first <record count of Size> PDATA rows in Code order, back it up as "
     "ModelSourcePDATA<Size>.bak, verify the file and drop the scratch database. Example: add the row connect/sizes:100 = 100, "
     "then connect-source-size-create --param Size=100 --param SourceSize=1K. Why: a new size needs its source data; this makes "
     "it from data already on the box, so a size is one row plus one run of this workload and connect-setup. When: once per "
     "new size and database server. It never overwrites: when the size's backup exists it stops at once. It does not touch the "
     "ModelSource database, the Profisee database or any other backup. Needs: the size's row in connect/sizes; the larger "
     "source backup in the SQL Server default backup folder; the CrewChief account is sysadmin on the database server. Success: "
     "the step prints the file it wrote. If it fails: the message says which file or row is wrong; a failure after the restore "
     "drops the scratch database itself."),
    ["source-data"],
    [SIZE_CREATE_STEP],
    inputs=[SIZE, RECORD_COUNT,
            value_input("SourceSize", "1K", "The larger size (a key of connect/sizes) whose source backup the new one is cut from.")],
    globals_={"DatabaseServerName": MAIN["DatabaseServerName"]})

# ---------------------------------------------------------------- schedule/schedule-connect
def sched(field):
    return "{{$ref:connect/schedule:{{Schedule}}.%s}}" % field


add("schedule", "schedule-connect",
    ("What: Create or update the Windows scheduled task '\\CrewChief\\schedule-connect-<Schedule>' for the schedule passed "
     "(Schedule, e.g. 1k-sql-server): the task runs the workload in the row connect/schedule:<Schedule>.Target with the values "
     "in <Schedule>.Values, weekly on <Schedule>.Days at <Schedule>.Time, from the CrewChief CLI. Example: schedule-connect "
     "--param Schedule=1m-snowflake. Nothing is scheduled until it runs; run it again after changing a row. Why: lets a test "
     "repeat without a person; one workload serves every schedule, so a new schedule (another thread count) is four reference "
     "rows. When: once per schedule to create or update its task. Needs: connect-setup ran on this box; the secret "
     "Scheduler:RunAsPassword. Success: Every step Succeeded or Skipped. If it fails: open the first failed step, whose If it "
     "fails text names what to check."),
    [],
    [{"label": "Apply Schedule", "inline": {
        "action": "Apply", "taskName": "schedule-connect-{{Schedule}}", "targetWorkload": sched('Target'),
        "targetParameters": sched('Values'), "cliPath": "{{CliPath}}", "dataFolder": "{{DataFolder}}", "startDate": "{{StartDate}}",
        "startTime": sched('Time'), "recurrence": "{{Recurrence}}", "interval": "{{Interval}}", "daysOfWeek": sched('Days'),
        "endDate": "", "runAsAccount": "{{RunAsAccount}}", "runAsPassword": "{{$config:Scheduler:RunAsPassword}}",
        "runElevated": True, "type": "ScheduleTaskStep", **steps.BASE, "timeoutSeconds": 120,
        "description": ("What: Create or update the scheduled task of the schedule passed. Why: puts the run on the Windows Task "
                        "Scheduler so it repeats without a person. Success: Task Scheduler holds the task under \\CrewChief with "
                        "the day, time, workload and values of the schedule's rows. If it fails: a row of the schedule is missing "
                        "in connect/schedule (the message names it); or check the run-as account and its password secret "
                        "(Scheduler:RunAsPassword) and that the CrewChief CLI path in the globals exists.")}}],
    inputs=[value_input("Schedule", "1k-sql-server", "Name of the schedule to apply: the start of its four rows in connect/schedule "
                                                     "(<Schedule>.Target, .Values, .Days, .Time).")],
    globals_={"CliPath": "C:\\Deploy\\CrewChief\\cli\\crewchief.exe", "DataFolder": "C:\\Deploy\\CrewChief\\web\\data",
              "StartDate": "2026-11-07", "Recurrence": "Weekly", "Interval": "1", "RunAsAccount": "CORP\\speedmerchants"},
    notes=("Day, time, workload and values of a schedule are rows in connect/schedule. StartDate, Recurrence (Once, Daily, "
           "Weekly) and Interval are globals here. Only ONE Connect run at a time per box: give every schedule its own time."))

# ---------------------------------------------------------------- write the workloads
declare_inputs()
clear_workloads(wl_root)
for name, (folder, w) in sorted(WORKLOADS.items()):
    dump(os.path.join(wl_root, folder, name + '.workload.json'),
         workload(name, w['description'], w['tags'], w['steps'], inputs=w['inputs'], globals_=w['globals'], notes=w['notes'], family=FAM))

# ---------------------------------------------------------------- rounds (plan lines carry values: <workload> Name=Value ...)
rounds = os.path.join(root, 'rounds')
os.makedirs(rounds, exist_ok=True)
RUN = ("# Run: bash ../../tools/runner/run-queue.sh <CrewChief box> {f}  (only ONE box may run Connect at a time)\n"
       "# A line is a workload and the values it gets: <workload> Name=Value\n")
PLUS = "# '+' = runs only when the export above it passed (the import reads what the export wrote).\n"
RETIRED_LINE = re.compile(r'(?m)^\+?\s*connect-(test-)?\d+[km]-')
ROUND_ORDER = ('sql-server', 'databricks', 'synapse', 'snowflake')


def round_file(name, text):
    """A round is a person's file once it exists: written when missing, or when it still names a retired workload."""
    path = os.path.join(rounds, name)
    if os.path.exists(path):
        with open(path, encoding='utf-8') as f:
            if not RETIRED_LINE.search(f.read()):
                return
    with open(path, 'w', encoding='utf-8', newline='\n') as f:
        f.write(text)


def provider_lines(size, threads):
    out = ""
    for p in ROUND_ORDER:
        out += f"connect-{p}-export-run Size={size} Threads={threads}\n+connect-{p}-import-run Size={size} Threads={threads}\n"
    # The test sets up the target first; the target comes from its values (connect reference data, or a lane's).
    return out + f"connect-test-{P2P}-export Size={size} Threads={threads}\n"


round_file('smoke.txt',
    "# Smoke test: one 1K SQL Server export and import at 4 worker threads (about 15 minutes). Use it after moving to a new machine.\n"
    + RUN.format(f='smoke.txt') + "connect-sql-server-export-run Size=1K Threads=4\n+connect-sql-server-import-run Size=1K Threads=4\n")
for _size in ('1K', '1M'):
    _f = _size.lower() + '-4t-round.txt'
    round_file(_f, f"# Connect QA round: every provider at {_size} records, 4 worker threads.\n" + RUN.format(f=_f) + PLUS + "\n"
               + provider_lines(_size, 4))
    _f = _size.lower() + '-round.txt'
    round_file(_f, f"# Connect {_size} round: every provider at 4, 8 and 12 worker threads.\n" + RUN.format(f=_f) + PLUS
               + "".join(f"\n# {t} worker threads\n" + provider_lines(_size, t) for t in (4, 8, 12)))

print(f"connect pack written: {len(WORKLOADS)} workloads, {len(TEMPLATES)} TestAuto workflow templates")
