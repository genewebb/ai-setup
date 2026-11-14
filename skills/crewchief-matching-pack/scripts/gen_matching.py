"""Builds the CrewChief Matching pack (CrewChief/packs/matching). One workload per SHAPE; the size is a run value, never
part of a name or a copy of a file (Gene 11/11).

  tests/      matching-test             what a person starts: the whole chain of the Size passed
  internal/   matching-all              the chain: load, then Scenarios 1, 2, 3a, 3b, 3c
              matching-scenario1-load   empty baseline, Configuration, API key, load the size's table, back up 'loaded'
              matching-scenario1        restore 'loaded', measured run, back up 'after-1'
              matching-scenario2 / 3a / 3b / 3c   restore the checkpoint before, continuous matching on, measured run, back up
  start/      matching-preflight, matching-setup, matching-base-create
  schedule/   schedule-matching         one workload; the schedule name passed picks its rows in matching/schedule

  Before: matching-test-1k ... -100m (5), matching-<size>-all, -scenario1-load, -scenario1 ... -3c, -testauto-create (40),
          matching-api-key-set, 5 schedules: 54 workloads, every size a copy.
  After:  matching-test --param Size=1K          12 workloads, whatever the number of sizes.

Adding a size is one row in git, never a workload and never a run of this generator:
  matching/sizes   1K = 1000 ...     (the Size a run passes = the row key; the value = the record count)
then build its source tables (RetailClient<Size>Scenario1, 2, 3b, 3c in the ModelSource database) and run matching-setup
again: its template steps create the run profiles and one TestAuto workflow per scenario for every row.
Every later scenario works on a tenth of the record count (the "slice"); it is computed where it is used, never typed.

The TestAuto workflow keys and run profile codes are the same as before (matching-1k-scenario2,
<version>-RetailClient-Scenario 2-1000-0), so setup updates the existing workflows and their history is not split.

Source of the TestAuto step configs: PROD workflow 10000215 (read 11/05): Scenario 1 = its steps 5-11, written out below;
Scenarios 2 to 3c = its steps 12-44, kept verbatim in wf10000215/NN.json and patched only where the pack requires.
Shared blocks (API key, health, instance stop/start, pools, backup check, tag check) are the common pack's workloads.

Usage: python gen_matching.py <packRoot>      (e.g. C:\\devops\\repos\\speed-merchants\\CrewChief\\packs\\matching)
"""
import json
import os
import re
import sys

root = os.path.abspath(sys.argv[1])
here = os.path.dirname(os.path.abspath(__file__))
FAM = 'matching'
SETUP = 'matching-setup'
ref_dir = os.path.join(root, 'reference-kv', FAM)
wl_root = os.path.join(root, 'workloads', FAM)
sys.path.insert(0, os.environ.get('PACKGEN_TOOLS') or os.path.join(os.path.dirname(root), 'tools'))
from packgen import specs, steps  # noqa: E402
from packgen.values import record_count_input, ref as _ref, size_input, value_input, version_inputs  # noqa: E402
from packgen.workloads import clear_workloads, dump, seed_reference_set, workload  # noqa: E402
from matching_parts import (S1_DETAILS, SCENARIOS, T2, T3B, T3C, VER, checks, continuous_matching_step, later_details,  # noqa: E402
                            monitor_quiet, prelude, table, title)
import matching_parts as parts  # noqa: E402

SERVICE_CONFIG_ID = '320e7ed1-3430-484a-87ce-7a2ee72be085'  # 'ModelSource' service configuration the strategy reads through
STRATEGY_ID = 'c810734f-51a5-4416-aa8b-a6380f5e2a22'  # RetailClientImport in the empty baseline (Connect keeps the id on import)
EMPTY = "profisee_Matching_empty_" + VER + ".bak"


def ref(set_name, key):
    return _ref(FAM, set_name, key)


def checkpoint(name):
    """Backup file of one checkpoint of the chain, for the size and version of the run."""
    return "profisee_Matching_{{Size}}_" + name + "_" + VER + ".bak"




# ---------------------------------------------------------------- pack-owned reference sets (seeded once, then git is the source)
SIZES_TOKEN = "{{$ref:matching/sizes:*}}"
SIZE_ROWS = {"1K": 1000, "10K": 10000, "100K": 100000, "1M": 1000000, "100M": 100000000}
seed_reference_set(os.path.join(ref_dir, 'sizes.json'),
    "Matching pack: the sizes a Matching run can have. Key = the Size a run passes and the word in the source table names "
    "(RetailClient<Size>Scenario1, 2, 3b, 3c in the ModelSource database); value = the record count of Scenario 1, a multiple of "
    "10 (every later scenario works on a tenth of it). Add a size by adding a row here, building its source tables, and running "
    "matching-setup (it creates the run profiles and TestAuto workflows of every row). Kept in git with the pack and restored "
    "to a box with Replace; never edited on a box.",
    {k: str(v) for k, v in SIZE_ROWS.items()},
    {k: f"{v:,} records loaded and matched by Scenario 1; Scenarios 2, 3a, 3b and 3c each work on {v // 10:,}."
        + (" One million records." if k == "1M" else "") for k, v in SIZE_ROWS.items()})
seed_reference_set(os.path.join(ref_dir, 'values.json'),
    "Matching pack: value lists the pack reads. Each row is a list separated by commas. Kept in git with the pack; never "
    "edited on a box.",
    {"OptionalSizes": "1M,100M"},
    {"OptionalSizes": "Sizes (keys of matching/sizes) whose source tables a box may lack: 1M runs at GA only and 100M only "
                      "where the box has room. matching-preflight states a missing table of these sizes and fails on a "
                      "missing table of any other size."})
# Weekly start times; each size's chain must finish before the next starts on the same Profisee database. 100M is not
# measured yet: Saturday keeps it apart from the Sunday sizes.
SCHEDULES = [("1k", "Size=1K", "Sun", "00:30"), ("10k", "Size=10K", "Sun", "02:00"), ("100k", "Size=100K", "Sun", "05:00"),
             ("1m", "Size=1M", "Sun", "12:00"), ("100m", "Size=100M", "Sat", "00:30")]
sched_entries, sched_desc = {}, {}
for sname, vals, day, time in SCHEDULES:
    for field, value, text in (("Target", "matching-test", "the workload the scheduled task runs"),
                               ("Values", vals, "the values it passes to that workload, Name=Value separated by spaces"),
                               ("Days", day, "the weekday(s) it starts, e.g. Sun or Sun,Wed"),
                               ("Time", time, "the start time, HH:mm, 24-hour, local time")):
        sched_entries[f"{sname}.{field}"] = value
        sched_desc[f"{sname}.{field}"] = f"Schedule '{sname}' (Windows task schedule-matching-{sname}): {text}."
seed_reference_set(os.path.join(ref_dir, 'schedule.json'),
    "Matching pack: the schedules schedule-matching can apply. A schedule is four rows named <schedule>.Target, .Values, .Days "
    "and .Time; run schedule-matching with Schedule=<schedule> to create or update its Windows task. Add a schedule by adding "
    "its four rows. Never let two tests on the same Profisee database overlap. Kept in git with the pack; never edited on a box.",
    sched_entries, sched_desc)
for retired in ('workflows.json',):  # display names are composed by the setup templates now
    if os.path.exists(os.path.join(ref_dir, retired)):
        os.remove(os.path.join(ref_dir, retired))

# ---------------------------------------------------------------- box globals (box facts: the matching/* sets a person edits per box)
APP_URL = "https://" + ref('machines', 'ApplicationServerNameFQDN') + "/" + ref('instances', 'ProfiseeInstanceName') + "/rest"
G = {
    "ApplicationServerName": ref('machines', 'ApplicationServerName'),
    "DatabaseServerName": ref('machines', 'DatabaseServerName'),
    "ProfiseeInstanceName": ref('instances', 'ProfiseeInstanceName'),
    "ProfiseeDatabaseName": ref('databases', 'ProfiseeDatabaseName'),
    "ModelSourceDB": ref('databases', 'ModelSourceDB'),
    "EmptySeedBackupFileName": ref('databases', 'EmptySeedBackupFileName'),
    "ProfiseeBaseUrl": APP_URL,
    "ConnExBaseUrl": APP_URL + "/",
    "TestAutoBaseUrl": "https://" + ref('machines', 'TestServerNameFQDN') + ":8443",
    "ScenarioMgtBaseUrl": ref('urls', 'ScenarioMgtBaseUrl'),
    "ScenarioMgtApiKey": "{{$config:RestClients:ScenarioMgt:ApiKey}}",
    "ProfiseeApiKey": "{{$config:RestKeys:ProfiseeRestKey}}",
    "ConnExApiKey": "{{$config:RestClients:Connect:ApiKey}}",
    "RunAsUser": "{{$config:ConnectRuntime:ConnectRunAsUser}}",
    "TestAutoEnvironmentName": ref('machines', 'TestServerName'),
    "TestAutoApplicationServer": ref('machines', 'ApplicationServerName'),
    "TestAutoDatabaseServer": ref('machines', 'DatabaseServerName'),
    "TestAutoSourceDatabase": ref('databases', 'ModelSourceDB'),
}
# What the common pack's workloads read from the workload that runs them.
BOX = ("ApplicationServerName", "DatabaseServerName", "ProfiseeInstanceName", "ProfiseeDatabaseName", "ProfiseeBaseUrl", "TestAutoBaseUrl")


def g(*names, **extra):
    out = {n: G[n] for n in names}
    out.update(extra)
    return out


# ---------------------------------------------------------------- inputs (run values and version: the same form in every workload)
SIZE = size_input(FAM)
RECORD_COUNT = record_count_input(FAM)
VERSION_CODE = version_inputs(FAM, 'ProfiseeVersionCode')
VERSION_BOTH = version_inputs(FAM)
SOURCE_TABLE = value_input('SourceTableName', table('1'),
                           "Source table of the Scenario 1 load in the ModelSource database: RetailClient<Size>Scenario1. Derived; never passed.")


def key(scn):
    """Automation tag key of one scenario's TestAuto workflow, as workload text."""
    return "matching-{{Size|lower}}-scenario" + scn


ALL_KEYS = ",".join(key(s) for s in SCENARIOS)


def emit(folder, name, description, tags, step_list, inputs=None, globals_=None, notes=""):
    dump(os.path.join(wl_root, folder, name + '.workload.json'),
         workload(name, description, [FAM, folder] + tags, step_list, inputs=inputs, globals_=globals_, notes=notes, family=FAM))


clear_workloads(wl_root)

# ---------------------------------------------------------------- TestAuto step configs (matching_parts.py)
# A config is a template: <<Size>>, <<RecordCount>>, <<Slice>> and the like are filled in by matching-setup for every row
# of matching/sizes. Scenario 1 = PROD 10000215 steps 5-11; Scenarios 2 to 3c = its steps 12-44, patched only where the
# pack requires.
DETAILS = {'1': S1_DETAILS, **later_details()}
MEASURES = {
    '1': ("Matching Scenario 1 (match and survive the full load), <<RecordCount>> records",
          "which restores the loaded checkpoint first; running it alone measures nothing useful."),
    '2': (f"Matching Scenario 2 (operational batch: New, Changed with mutated match fields, NoChange) from table {T2}, <<Size>>", None),
    '3a': ("Matching Scenario 3a (lookups of matched records, creates nothing), <<Size>>", None),
    '3b': (f"Matching Scenario 3b (lookup, then create on a miss) from table {T3B}, <<Size>>", None),
    '3c': (f"Matching Scenario 3c (creates with continuous matching) from table {T3C}, <<Size>>", None),
}
LATER_RUNNER = ("which restores the scenario's starting checkpoint and turns continuous matching on first; running it alone "
                "measures nothing useful.")

# PowerShell every template step shares: the numbers a size gets from its row (a slice = a tenth of the record count).
PRELUDE = prelude()
SETS = {"Sizes": SIZES_TOKEN}
SIZE_LOOP = {"Size": specs.set_keys('Sizes')}
DERIVE = "Set-Size $v"
MACHINE_TAG = ref('environment', 'MainMachineTag')
SETUP_FAIL = (" If it fails: the message names the value or the workflow: a size with a bad record count, a step configuration "
              "over 4000 characters, or two workflows with the same tag (untag the copy by hand); any other error names the record.")


def workload_name(scn):
    return "matching-scenario" + scn


def template(scn):
    measures, runner = MEASURES[scn]
    return dict(
        label=f"Upsert Scenario {scn} Workflows", key=f"matching-<<SizeLower>>-scenario{scn}", name=f"Matching <<Size>> Scenario {scn}",
        spec={"PlainTags": f"Matching,{VER},{MACHINE_TAG},<<Size>>,Scenario {scn}",
              "Description": ("Automation ID: <AUTOMATION_ID>. CrewChief finds this workflow by that tag alone; do not edit or remove "
                              "the tag, and to experiment copy the workflow and remove the tag from the copy. "
                              f"Measures: {measures}, RetailClient strategy, on the Profisee version in "
                              f"matching/environment:ProfiseeVersionCode. Run by the CrewChief workload '{workload_name(scn)}', "
                              + (runner or LATER_RUNNER)),
              "Details": DETAILS[scn]})


TEMPLATES = {scn: template(scn) for scn in SCENARIOS}


def template_step(t):
    return specs.template_upsert_step(
        t["label"], t["key"], t["name"], t["spec"], SIZE_LOOP,
        f"What: Create or update the TestAuto workflow '{t['name'].replace('<<Size>>', '<Size>')}' ({len(t['spec']['Details'])} "
        "steps) of every size in matching/sizes, each found by its automation tag. The step holds the workflow once, as a "
        "template; the sizes come from the reference rows, so a new row gives a new workflow and the existing ones are updated "
        "in place. Why: a Matching run finds its workflow by that tag. Success: the last line lists the workflows created or "
        "updated." + SETUP_FAIL,
        setup_name=SETUP, category="Matching", sets=SETS, prelude=PRELUDE, derive=DERIVE)


def key_patterns():
    return [(t["key"], SIZE_LOOP, SETS, PRELUDE, DERIVE) for t in TEMPLATES.values()]


# ---------------------------------------------------------------- run profiles (one per scenario and size)
def profiles_step():
    return parts.profiles_step(FAM, SETUP, SIZE_LOOP, SETS, PRELUDE, DERIVE)


# ---------------------------------------------------------------- shared SQL and scripts (matching_parts.py)
RESTORE_NOTE, STOP_WHY, START_WHY = parts.RESTORE_NOTE, parts.STOP_WHY, parts.START_WHY
CHECKS = checks()


# ---------------------------------------------------------------- internal/matching-scenario1 ... 3c
CHAIN = {'1': ('loaded', 'after-1'), '2': ('after-1', 'after-2'), '3a': ('after-2', 'after-3a'),
         '3b': ('after-3a', 'after-3b'), '3c': ('after-3b', 'after-3c')}
WHATS = {'1': "matching of the full load", '2': "Scenario 2 (operational batch from " + table('2') + ")",
         '3a': "Scenario 3a (lookups only)", '3b': "Scenario 3b (lookup, then create, from " + table('3b') + ")",
         '3c': "Scenario 3c (creates from " + table('3c') + ")"}




def scenario_workload(scn):
    start, end = CHAIN[scn]
    first = scn == '1'
    before = "matching-scenario1-load" if first else workload_name(SCENARIOS[SCENARIOS.index(scn) - 1])
    check_label, check_sql, check_desc = CHECKS[scn]
    step_list = [
        steps.wait_runs(),
        steps.instance_stop_child(STOP_WHY),
        steps.db_step(f"Restore {title(start)}", "RestoreDatabase", checkpoint(start),
            f"What: Restore the '{start}' checkpoint of this size and version over the Profisee database WITH REPLACE. {RESTORE_NOTE} "
            f"Why: every Scenario {scn} run starts from the same state. Success: restored. If it fails: the backup is missing from "
            f"the SQL Server default backup folder (run {before} for this size), or the CrewChief account is not sysadmin there."),
        steps.instance_start_child(START_WHY),
        steps.key_set_child(),
        steps.health_child(),
    ]
    if not first:
        step_list.append(continuous_matching_step())
    step_list += [
        monitor_quiet(),
        steps.testauto(f"Run Matching Scenario {scn}", key(scn), f"Matching Scenario {scn} of the size passed", SETUP),
        steps.sql(check_label, check_sql, check_desc),
        steps.db_step(f"Back Up {title(end)}", "BackupDatabase", checkpoint(end),
            f"What: Back up the Profisee database as the '{end}' checkpoint of this size and version (overwrites the previous one). "
            f"Why: {'the next scenario restores it' if scn != '3c' else 'it keeps the end state of the chain for a later look'}. "
            "Success: SQL Server writes the file in its default backup folder. If it fails: check disk space there and that the "
            "CrewChief account is sysadmin."),
    ]
    extra = {} if first else {"ModelSourceDB": G["ModelSourceDB"], "ProfiseeApiKey": G["ProfiseeApiKey"], "MatchingStrategyName": "RetailClient"}
    emit('internal', workload_name(scn),
         (f"What: For the Size passed: restore the '{start}' checkpoint, set the standard API key, wait for every service, "
          + ("" if first else "turn continuous matching on, ")
          + f"run the TestAuto workflow 'Matching <Size> Scenario {scn}', check the result and back up '{end}'. Why: measures "
          f"{WHATS[scn]}" + ("" if scn == '3c' else f"; the next scenario starts from '{end}'") + f". When: whenever Scenario {scn} "
          f"is measured; a rerun restores its own start. Example: {workload_name(scn)} --param Size=10K. Needs: the '{start}' backup "
          f"of this size ({before}); matching-setup ran on this box for this version; the common pack. Success: Every step "
          "Succeeded or Skipped. If it fails: the failed step's description says what to fix; rerun the whole workload."),
         ["scenario" + scn, "test"] + ([] if scn in ('1', '2') else ["20U"]),  # 3a, 3b and 3c run 20 simulated users
         step_list, inputs=[SIZE, RECORD_COUNT] + VERSION_CODE,
         globals_=g(*BOX, QuietSeconds="60", **extra))


for _scn in SCENARIOS:
    scenario_workload(_scn)

# ---------------------------------------------------------------- internal/matching-scenario1-load
# The Connect strategy artifact: RetailClientImport, source table and run-as user as tokens.
with open(os.path.join(here, 'retailclientimport-artifact.json'), encoding='utf-8') as _f:
    art = json.load(_f)
assert art['integrationStrategyRecord']['Id'] == STRATEGY_ID
assert art['integrationStrategyRecord']['Configuration']['remoteObjectName'] == '{{SourceTableName}}'
art['integrationStrategyRecord']['Configuration']['runAsUser'] = '{{RunAsUser}}'
artifact = json.dumps(art, separators=(',', ':'), ensure_ascii=False)
assert artifact.count('{{SourceTableName}}') >= 1 and '\\\\' not in artifact.replace('{{RunAsUser}}', '')
# The 'ModelSource' service configuration: the Connect pack's SQL Server one (same provider, same settings), so its server
# and database come from reference data and not from whatever the empty baseline was made with.
with open(os.path.join(here, 'modelsource-serviceconfig-artifact.json'), encoding='utf-8') as _f:
    sc_artifact = _f.read()
assert '{{DatabaseName}}' in sc_artifact and '{{DbServer}}' in sc_artifact and '{{ServiceConfigId}}' in sc_artifact
sc_parameters = {"AuthenticationScheme": "SqlLogon", "CommandTimeout": "120", "ConnectionTimeout": "60",
                 "DatabaseName": "{{ModelSourceDB}}", "DbPassword": "{{$config:UserCredentials:SqlAdminPassword}}",
                 "DbServer": "{{DatabaseServerName}}", "DbUsername": "{{$config:UserCredentials:SqlAdminUser}}",
                 "EncryptEnhanced": "Optional", "ServiceConfigId": SERVICE_CONFIG_ID, "ServiceConfigName": "ModelSource",
                 "ServiceProviderId": "77d91447-e344-4fc1-a49f-1c089210a40a",
                 "ServiceProviderName": "SQL Server Service Provider", "TrustServerCertificate": "True"}
CONNECT_HEAD = r"""$ErrorActionPreference = 'Stop'
$connect = '{{ConnExBaseUrl}}'.TrimEnd('/') + '/'
$headers = @{ 'x-api-key' = '{{ConnExApiKey}}'; accept = 'application/json' }
"""
sc_delete_script = CONNECT_HEAD + r"""# A Connect import of an id that already exists fails, so the service configuration is removed first (after the strategy that uses it).
$r = Invoke-WebRequest -Method Delete -Uri "${connect}v1/Connect/Configurations?ConfigurationUids=@@ID@@" -Headers $headers -SkipHttpErrorCheck -TimeoutSec 300
$code = [int]$r.StatusCode
# A 401 body echoes the API key, so no response body is ever printed.
if ($code -notin 200, 204, 404) { throw "Deleting the ModelSource service configuration returned HTTP $code." }
"ModelSource service configuration: delete returned HTTP $code (404 = it was not there)."
""".replace('@@ID@@', SERVICE_CONFIG_ID)
delete_script = CONNECT_HEAD + r"""# A Connect import of an id that already exists fails (it never updates), so the strategy is removed first. Nothing else is touched.
$r = Invoke-WebRequest -Method Delete -Uri "${connect}v1/Connect/Strategies?IntegrationStrategyUids={{StrategyId}}" -Headers $headers -SkipHttpErrorCheck -TimeoutSec 300
$code = [int]$r.StatusCode
# A 401 body echoes the API key, so no response body is ever printed.
""" + steps.GET_WHY + r"""if ($code -notin 200, 204, 404) { throw "Deleting Connect strategy {{StrategyName}} ({{StrategyId}}) returned HTTP $code. $(Get-Why $r)" }
"Connect strategy {{StrategyName}}: delete returned HTTP $code (404 = it was not there)."
"""


def connex(label, op, desc, **kw):
    return {"label": label, "inline": {
        **steps.BASE, "artifactFile": "", "artifactJson": "", "resourceType": "IntegrationStrategy", "operation": op,
        "baseUrl": "{{ConnExBaseUrl}}", "apiKey": "{{ConnExApiKey}}", "returnResult": True,
        "expectedStatusCodes": [200, 201, 204], "resourceId": "", "outputFile": "", "dryRun": False,
        "skipFileWrite": False, "pollIntervalSeconds": 30, "maxWaitMinutes": 720, "pollFailureLimit": 3,
        "batchCode": "", "type": "ConnExStep", "description": desc, **kw}}


RUN_AS_SQL = """IF NOT EXISTS (SELECT 1 FROM meta.tUser WHERE [Name] = N'{{RunAsUser}}')
    THROW 50013, N'Connect run-as user {{RunAsUser}} (ConnectRuntime:ConnectRunAsUser) is not a Profisee user; the load batch would fail.', 1;
PRINT N'Connect run-as user {{RunAsUser}} is a Profisee user.';"""
EMPTY_SQL = """DECLARE @n bigint = (SELECT COUNT_BIG(*) FROM data.tRetailClient);
IF @n <> 0
BEGIN
    DECLARE @msg nvarchar(400) = CONCAT(N'RetailClient already holds ', @n, N' rows; Scenario 1 loads into an empty entity. Restore the empty baseline first.');
    THROW 50004, @msg, 1;
END
PRINT N'RetailClient is empty.';"""
backup_loaded = steps.sql("Back Up Loaded", """DECLARE @bak nvarchar(500) = CAST(SERVERPROPERTY('InstanceDefaultBackupPath') AS nvarchar(400)) + N'\\""" + checkpoint('loaded') + """';
DECLARE @sql nvarchar(max) = N'BACKUP DATABASE ' + QUOTENAME(N'{{ProfiseeDatabaseName}}') + N' TO DISK = N''' + REPLACE(@bak, N'''', N'''''') + N''' WITH INIT, COMPRESSION, CHECKSUM';
EXEC (@sql);
SET @sql = N'RESTORE VERIFYONLY FROM DISK = N''' + REPLACE(@bak, N'''', N'''''') + N''' WITH CHECKSUM';
EXEC (@sql);
PRINT CONCAT(N'Backed up {{ProfiseeDatabaseName}} to ', @bak, N' and verified it.');""",
    "What: Back up the Profisee database as the 'loaded' checkpoint of this size and version (the start of Scenario 1) and verify "
    "the file. Why: every Scenario 1 run restores it. Success: backup written and verified. If it fails: check disk space in the "
    "SQL Server default backup folder.", conn=steps.MASTER, timeout=7200)
backup_loaded["inline"]["timeoutSeconds"] = 7300
wait_load = connex("Wait For Scenario 1 Load", "WaitForBatch",
    "What: Wait for the {{StrategyName}} batch to finish. Why: the checks below need the finished load. Success: the batch reaches "
    "a successful terminal state. If it fails: read the batch errors in Connect.", resourceType="", resourceId="{{StrategyName}}",
    maxWaitMinutes=1440)
# Gene 11/08: Profisee Configuration writes new service sign-in ids into the database it runs on AND the application
# server, so only the backup configured last works. Every load (the first run of each Matching test) restores the empty
# baseline and runs Configuration on it; the scenario checkpoints it backs up later in the same test carry those ids.
configure_baseline = steps.run_child("Configure The Restored Baseline", "install-configure-upgrade", "", timeout=7500, description=(
    "What: Run Profisee Configuration on the restored empty baseline (install pack building block install-configure-upgrade: "
    "upgrade, keeps the data). Why: Configuration writes this application server's service sign-in ids into the database; a "
    "backup configured earlier makes the Data and Connect services reject the user (400 DATA00030, 403 CNX00080). Success: "
    "The child workload ends with every step Succeeded. If it fails: Open the run output of 'install-configure-upgrade'; "
    "Configuration's log is quoted there."))
emit('internal', "matching-scenario1-load",
     ("What: For the Size passed: restore the empty baseline, run Profisee Configuration on it, set the standard API key, point "
      "the Connect strategy RetailClientImport at RetailClient<Size>Scenario1, load its rows (the record count of the row "
      "matching/sizes:<Size>) into the empty RetailClient entity, check every Code arrived, and back up the 'loaded' checkpoint of "
      "this size. Why: Scenario 1 of this size starts from this backup; Scenario 2, 3b and 3c update records by these Codes. "
      "When: at the start of every Matching test of a size (matching-all runs it first); a rerun restores and configures the "
      "baseline itself. Example: matching-scenario1-load --param Size=10K. Needs: the install pack and the common pack on this "
      "box; the empty baseline of this version (made by matching-base-create: the model, the RetailClient matching strategy, no "
      "records; the load re-creates the ModelSource service configuration) in the SQL Server default backup folder; the size's "
      "source table in the ModelSource database; the machine's API user exists in Profisee. Success: Every step Succeeded or "
      "Skipped. If it fails: the failed step's description says what to fix; rerun the whole workload."),
     ["scenario1", "load"],
     [steps.wait_runs(),
      steps.instance_stop_child(STOP_WHY),
      steps.db_step("Restore Empty Baseline", "RestoreDatabase", EMPTY,
          f"What: Restore the empty baseline of this version over the Profisee database WITH REPLACE. {RESTORE_NOTE} Why: every "
          "size loads into the same empty model. Success: restored. If it fails: the empty baseline of this version "
          "(profisee_Matching_empty_<version code>.bak) is missing from the SQL Server default backup folder (run "
          "matching-base-create on this lane), or the CrewChief account is not sysadmin there."),
      steps.instance_start_child("Configuration expects a running instance"),
      configure_baseline,
      steps.health_child("Wait For Every Service After Configuration"),
      steps.key_set_child(),
      steps.sql("Check Connect Run-As User", RUN_AS_SQL,
          "What: Confirm the Connect run-as account (secret ConnectRuntime:ConnectRunAsUser) is a Profisee user. Why: the "
          "imported strategy runs its batches as that account; a missing user fails the load after the import. "
          "Success: the user exists. If it fails: add the account in Profisee (and to the empty baseline) or change the secret."),
      steps.ps("Remove RetailClientImport", delete_script,
          "What: Delete the Connect strategy {{StrategyName}} ({{StrategyId}}) when present. Why: a Connect import of an id "
          "that already exists fails; the import below brings it back pointed at this size's table. Touches nothing else. "
          "Success: HTTP 200, 204 or 404. If it fails: check the Connect API key (RestClients:Connect:ApiKey) and that "
          "the gateway answers."),
      steps.ps("Remove ModelSource Service Configuration", sc_delete_script,
          "What: Delete the Connect service configuration 'ModelSource' when present. Why: the import below "
          "brings it back pointed at matching/databases:ModelSourceDB on matching/machines:DatabaseServerName; "
          "a Connect import of an existing id fails. Touches nothing else. Success: HTTP 200, 204 or 404. "
          "If it fails: check the Connect API key (RestClients:Connect:ApiKey) and that the gateway answers."),
      connex("Import ModelSource Service Configuration", "Import",
          "What: Import the Connect service configuration 'ModelSource' for database {{ModelSourceDB}} on "
          "{{DatabaseServerName}}, signing in with UserCredentials:SqlAdminUser. Why: the source database name and server "
          "come from this box's reference data, not from the empty baseline. Success: Connect accepts the import. "
          "If it fails: 400 'duplicated Id' = the delete above did not remove it; a sign-in error = the UserCredentials secrets.",
          resourceType="ServiceConfiguration", artifactJson=sc_artifact, parameters=sc_parameters),
      connex("Import RetailClientImport", "Import",
          "What: Import the Connect strategy {{StrategyName}} reading {{ModelSourceDB}}.dbo.{{SourceTableName}} through the ModelSource "
          "service configuration, running as {{RunAsUser}}. Why: one strategy serves every size; only its source table changes. "
          "Success: Connect accepts the import. If it fails: 400 'duplicated Id' = the delete above did not remove it; 'could not "
          "be converted' = the artifact does not fit this Profisee release (export the strategy again).", artifactJson=artifact),
      connex("Enable RetailClientImport", "Enable",
          "What: Enable {{StrategyName}}. Why: an imported strategy starts Disabled and Connect will not run it. "
          "Success: Connect accepts the call. If it fails: check the strategy id {{StrategyId}} exists (the import above).",
          resourceId="{{StrategyId}}"),
      steps.sql("Check Strategy Source Table", """DECLARE @actual nvarchar(256) = (SELECT JSON_VALUE([Configuration], '$.RemoteObjectName')
                                 FROM connex.tIntegrationStrategyConfiguration WHERE [Name] = N'{{StrategyName}}');
IF @actual IS NULL THROW 50002, 'Connect strategy {{StrategyName}} is missing on {{ProfiseeDatabaseName}}.', 1;
IF @actual <> N'{{SourceTableName}}'
BEGIN
    DECLARE @msg nvarchar(2048) = CONCAT(N'{{StrategyName}} reads ', @actual, N' but this run loads {{SourceTableName}}.');
    THROW 50003, @msg, 1;
END
PRINT CONCAT(N'{{StrategyName}} reads ', @actual, N'.');""",
          "What: Confirm the Connect strategy reads this size's Scenario 1 table. Why: a strategy pointed at another size loads "
          "the wrong rows silently. Success: RemoteObjectName = {{SourceTableName}}. If it fails: point the strategy at "
          "{{SourceTableName}} or create it."),
      steps.sql("Check RetailClient Is Empty", EMPTY_SQL,
          "What: Refuse to load into a non-empty RetailClient. Why: Scenario 1 measures matching of exactly the loaded rows. "
          "Success: 0 rows. If it fails: restore the empty baseline and rerun."),
      connex("Run Scenario 1 Load", "Execute",
          "What: Start a Connect batch of {{StrategyName}}. Why: Scenario 1 data enters Profisee through Connect. Success: Connect "
          "accepts the call. If it fails: check the Connect address and the API key step above.", resourceId="{{StrategyName}}"),
      wait_load,
      steps.sql("Check Loaded Rows And Codes", """DECLARE @n bigint = (SELECT COUNT_BIG(*) FROM data.tRetailClient);
DECLARE @missing bigint = (SELECT COUNT_BIG(*) FROM [{{ModelSourceDB}}].dbo.[{{SourceTableName}}] s
                           WHERE NOT EXISTS (SELECT 1 FROM data.tRetailClient r WHERE r.Code = s.Code));
IF @n <> {{RecordCount}} OR @missing <> 0
BEGIN
    DECLARE @msg nvarchar(400) = CONCAT(N'RetailClient holds ', @n, N' rows (expected {{RecordCount}}); ', @missing, N' source Codes are missing. Updates by Code need the source Codes kept.');
    THROW 50005, @msg, 1;
END
PRINT CONCAT(N'RetailClient holds ', @n, N' rows; every source Code is present.');""",
          "What: Confirm the load kept every row and its Code. Why: Scenario 2, 3b and 3c update records by Code. Success: "
          "{{RecordCount}} rows, 0 missing Codes. If it fails: check the strategy maps Code to Code and read the batch errors."),
      backup_loaded],
     inputs=[SIZE, RECORD_COUNT, SOURCE_TABLE] + VERSION_BOTH,
     globals_=g(*BOX, "ModelSourceDB", "ConnExBaseUrl", "ConnExApiKey", "RunAsUser", StrategyName="RetailClientImport",
                StrategyId=STRATEGY_ID))

# ---------------------------------------------------------------- internal/matching-all and tests/matching-test
chain = [steps.run_child("Load", "matching-scenario1-load",
                         "Load the size's Scenario 1 table into the empty model and back up 'loaded'")]
chain += [steps.run_child(f"Scenario {scn}", workload_name(scn), f"Measured run: Matching Scenario {scn}") for scn in SCENARIOS]
emit('internal', "matching-all",
     ("What: The whole Matching chain of the Size passed, in order: check the TestAuto workflows of that size exist, load, then "
      "Scenarios 1, 2, 3a, 3b and 3c, each restoring the previous one's checkpoint. Why: a building block of the Matching pack; "
      "matching-test and the schedules run it so its steps exist once. When: Never run directly once the pack is tested; its "
      "parents run it. Needs: matching-setup ran on this box for this version; the size's source tables; workloads it runs: "
      "matching-scenario1-load, " + ", ".join(workload_name(s) for s in SCENARIOS) + ". Success: Every step Succeeded or "
      "Skipped. If it fails: open the first failed step, whose If it fails text names what to check."),
     ["all"],
     [steps.tag_check_child("Workflows For This Size Exist", ALL_KEYS, SETUP)] + chain,
     inputs=[SIZE] + VERSION_BOTH, globals_=g("TestAutoBaseUrl"),
     notes="Each child owns its run; a failed run stops the chain.")
emit('tests', "matching-test",
     ("What: Runs the Matching test at the Size passed (a key of matching/sizes; default 1K): load, then Scenarios 1, 2, 3a, 3b "
      "and 3c, each a measured TestAuto run whose results land in TestAuto. Example: matching-test --param Size=10K. Why: this "
      "is the test a person starts: one size, every scenario. When: any time after matching-setup has run on this box for the "
      "current Profisee version; never at the same time as another test on the same Profisee database. Needs: matching-setup; "
      "the matching/* reference sets filled in; the size's source tables in the ModelSource database. Success: Every run ends "
      "Succeeded; each TestAuto execution holds its metrics. If it fails: it stops at the first failed run: open that run's output."),
     [],
     [steps.run_child("Run The Chain", "matching-all", "Load, then Scenarios 1, 2, 3a, 3b and 3c of the size passed")],
     inputs=[SIZE] + VERSION_BOTH)

# ---------------------------------------------------------------- start/matching-setup
setup_steps = [
    steps.http_get("ScenarioMgt Check", "{{ScenarioMgtBaseUrl}}v1/Records/TestAutoWorkflow?PageSize=1",
                   "What: List one TestAuto workflow. Why: proves the address and key reach the TestAuto repository before anything "
                   "is written. Success: HTTP 200. If it fails: 401 = wrong ScenarioMgt key (RestClients:ScenarioMgt:ApiKey); 404 = "
                   "wrong address in matching/urls:ScenarioMgtBaseUrl.", headers={"x-api-key": "{{ScenarioMgtApiKey}}"}),
    steps.ps("TestAuto Version Exists", "\n".join([
        "$ErrorActionPreference = 'Stop'",
        "$base = '{{ScenarioMgtBaseUrl}}'.TrimEnd('/') + '/'",
        "$headers = @{ 'x-api-key' = '{{ScenarioMgtApiKey}}'; accept = 'application/json' }",
        "$version = '" + VER + "'",
        "$verFilter = [uri]::EscapeDataString(\"[Code] eq '$version'\")",
        "$v = Invoke-RestMethod -Uri \"${base}v1/Records/ProfiseeVersion?Filter=$verFilter\" -Headers $headers",
        "$rows = if ($v -is [array]) { $v } else { @($v.data) }",
        "if (-not $rows) { throw \"TestAuto version '$version' does not exist in the repository; create it (data.tProfiseeVersion) before running matching-setup.\" }",
        "\"TestAuto version $version exists.\""]),
        "What: Check the TestAuto version of this run (matching/environment:ProfiseeVersionCode, or the lane's) exists in the "
        "TestAuto repository. Why: every run profile and workflow step is recorded under it. Success: the version exists. If it "
        "fails: create the version in the repository (data.tProfiseeVersion), then rerun matching-setup."),
    profiles_step(),
] + [template_step(t) for t in TEMPLATES.values()]
emit('start', "matching-setup",
     ("What: Create or update the Matching run profiles and the tagged TestAuto workflows of Scenarios 1, 2, 3a, 3b and 3c for "
      "every size in matching/sizes, from one template per scenario. Why: every scenario workload finds its workflow by "
      "automation tag and the timing steps record under the run profiles. When: once per box and Profisee version; after adding "
      "a size row; after any change to a workflow template. Reruns update in place and never remove a workflow. Needs: the "
      "TestAuto version exists in the repository; TestAuto answers on port 8443. Success: Every step Succeeded; each template "
      "step lists its workflows. If it fails: open the first failed step, whose If it fails text names what to check."),
     ["setup"], setup_steps, inputs=VERSION_CODE,
     globals_=g("ScenarioMgtBaseUrl", "ScenarioMgtApiKey", "TestAutoBaseUrl", "TestAutoEnvironmentName", "TestAutoApplicationServer",
                "TestAutoDatabaseServer", "TestAutoSourceDatabase"))

# ---------------------------------------------------------------- schedule/schedule-matching
def sched(field):
    return "{{$ref:matching/schedule:{{Schedule}}.%s}}" % field


emit('schedule', "schedule-matching",
     ("What: Create or update the Windows scheduled task '\\CrewChief\\schedule-matching-<Schedule>' for the schedule passed "
      "(Schedule, e.g. 1k): the task runs the workload in the row matching/schedule:<Schedule>.Target with the values in "
      "<Schedule>.Values, weekly on <Schedule>.Days at <Schedule>.Time, from the CrewChief CLI. Example: schedule-matching "
      "--param Schedule=10k. Nothing is scheduled until it runs; run it again after changing a row. Why: lets a test repeat "
      "without a person; one workload serves every schedule, so a new schedule is four reference rows. When: once per schedule "
      "to create or update its task, and again after changing its rows or a global. Needs: matching-setup ran on this box; the "
      "secret Scheduler:RunAsPassword. Success: Every step Succeeded or Skipped. If it fails: open the first failed step, whose "
      "If it fails text names what to check."),
     [],
     [{"label": "Apply Schedule", "inline": {
         "action": "Apply", "taskName": "schedule-matching-{{Schedule}}", "targetWorkload": sched('Target'),
         "targetParameters": sched('Values'), "cliPath": "{{CliPath}}", "dataFolder": "{{DataFolder}}", "startDate": "{{StartDate}}",
         "startTime": sched('Time'), "recurrence": "{{Recurrence}}", "interval": "{{Interval}}", "daysOfWeek": sched('Days'),
         "endDate": "", "runAsAccount": "{{RunAsAccount}}", "runAsPassword": "{{$config:Scheduler:RunAsPassword}}",
         "runElevated": True, "type": "ScheduleTaskStep", **steps.BASE, "timeoutSeconds": 120,
         "description": ("What: Create or update the scheduled task of the schedule passed. Why: puts the run on the Windows Task "
                         "Scheduler so it repeats without a person. Success: Task Scheduler holds the task under \\CrewChief with "
                         "the day, time, workload and values of the schedule's rows. If it fails: a row of the schedule is missing "
                         "in matching/schedule (the message names it); or check the run-as account and its password secret "
                         "(Scheduler:RunAsPassword) and that the CrewChief CLI path in the globals exists.")}}],
     inputs=[value_input("Schedule", "1k", "Name of the schedule to apply: the start of its four rows in matching/schedule "
                                           "(<Schedule>.Target, .Values, .Days, .Time).")],
     globals_={"CliPath": "C:\\Deploy\\CrewChief\\cli\\crewchief.exe", "DataFolder": "C:\\Deploy\\CrewChief\\web\\data",
               "StartDate": "2026-11-08", "Recurrence": "Weekly", "Interval": "1", "RunAsAccount": "CORP\\speedmerchants"},
     notes=("Day, time, workload and values of a schedule are rows in matching/schedule. StartDate, Recurrence (Once, Daily, "
            "Weekly) and Interval are globals here. Every Matching, CRUD and Connect schedule restores the same Profisee "
            "database: set each time after measuring that size's chain; overlapping schedules restore the database under each "
            "other and ruin both runs."))

# ---------------------------------------------------------------- start/matching-preflight
BACKUP_SUFFIXES = ['loaded', 'after-1', 'after-2', 'after-3a', 'after-3b', 'after-3c']
SIZE_ROWS_SQL = ("SELECT LTRIM(RTRIM(LEFT(s.value, CHARINDEX(N'=', s.value + N'=') - 1))) AS size "
                 "FROM STRING_SPLIT(N'" + SIZES_TOKEN + "', N',') s WHERE LTRIM(RTRIM(s.value)) <> N''")
checkpoints_sql = """SET NOCOUNT ON;
-- The sizes are the rows of the reference set matching/sizes (written here as key=value pairs separated by commas).
DECLARE @dir nvarchar(400) = CAST(SERVERPROPERTY('InstanceDefaultBackupPath') AS nvarchar(400));
DECLARE @exists int, @f nvarchar(600), @name nvarchar(200), @have nvarchar(max) = N'', @notYet nvarchar(max) = N'';
DECLARE names CURSOR LOCAL FAST_FORWARD FOR
    SELECT CONCAT(z.size, N'_', x.suffix) FROM (@@SIZES@@) z
    CROSS JOIN (VALUES @@SUFFIXES@@) x(n, suffix) ORDER BY z.size, x.n;
OPEN names;
FETCH NEXT FROM names INTO @name;
WHILE @@FETCH_STATUS = 0
BEGIN
    SET @f = @dir + N'\\profisee_Matching_' + @name + N'_{{ProfiseeVersionCode}}.bak';
    EXEC master.dbo.xp_fileexist @f, @exists OUTPUT;
    IF @exists = 1 SET @have += @name + N' ' ELSE SET @notYet += @name + N' ';
    FETCH NEXT FROM names INTO @name;
END
CLOSE names; DEALLOCATE names;
PRINT CONCAT(N'Scenario backups present for version {{ProfiseeVersionCode}}: ', IIF(@have = N'', N'none', @have));
IF @notYet <> N'' PRINT CONCAT(N'Not made yet (each is written by the load or scenario before it; not a failure): ', @notYet);""" \
    .replace('@@SIZES@@', SIZE_ROWS_SQL).replace('@@SUFFIXES@@', ", ".join("(%d, N'%s')" % (i, s) for i, s in enumerate(BACKUP_SUFFIXES)))
tables_sql = """SET NOCOUNT ON;
-- The sizes are the rows of the reference set matching/sizes; a size listed in matching/values:OptionalSizes may lack its tables.
DECLARE @db sysname = N'{{ModelSourceDB}}';
IF DB_ID(@db) IS NULL
BEGIN
    DECLARE @none nvarchar(400) = CONCAT(N'Database ', @db, N' (matching/databases:ModelSourceDB) does not exist on {{DatabaseServerName}}.');
    THROW 50014, @none, 1;
END
DECLARE @optional nvarchar(max) = N',' + REPLACE(N'{{$ref:matching/values:OptionalSizes}}', N' ', N'') + N',';
DECLARE @missing nvarchar(max) = N'', @notBuilt nvarchar(max) = N'', @size nvarchar(50), @part nvarchar(50), @name sysname, @id int, @n bigint, @sql nvarchar(max);
DECLARE names CURSOR LOCAL FAST_FORWARD FOR
    SELECT z.size, x.part FROM (@@SIZES@@) z
    CROSS JOIN (VALUES (1, N'Scenario1'), (2, N'Scenario2'), (3, N'Scenario3b'), (4, N'Scenario3c')) x(n, part) ORDER BY z.size, x.n;
OPEN names;
FETCH NEXT FROM names INTO @size, @part;
WHILE @@FETCH_STATUS = 0
BEGIN
    SET @name = CONCAT(N'RetailClient', @size, @part);
    SET @id = OBJECT_ID(QUOTENAME(@db) + N'.dbo.' + QUOTENAME(@name), N'U');
    IF @id IS NULL
    BEGIN
        IF CHARINDEX(N',' + @size + N',', @optional) > 0 SET @notBuilt += @name + N' ' ELSE SET @missing += @name + N' ';
    END
    ELSE
    BEGIN
        SET @sql = N'SELECT @n = SUM(p.rows) FROM ' + QUOTENAME(@db) + N'.sys.partitions p WHERE p.object_id = @id AND p.index_id IN (0, 1)';
        EXEC sp_executesql @sql, N'@id int, @n bigint OUTPUT', @id = @id, @n = @n OUTPUT;
        PRINT CONCAT(@name, N': ', @n, N' rows');
    END
    FETCH NEXT FROM names INTO @size, @part;
END
CLOSE names; DEALLOCATE names;
IF @notBuilt <> N'' PRINT CONCAT(N'Tables of the optional sizes ({{$ref:matching/values:OptionalSizes}}) not built on this box (needed before a run of that size): ', @notBuilt);
IF @missing <> N''
BEGIN
    DECLARE @msg nvarchar(2048) = CONCAT(N'Source tables missing in ', @db, N': ', @missing, N'. Build them with Build-MatchingScenarioTables.ps1 (see the Matching help pages).');
    THROW 50011, @msg, 1;
END""".replace('@@SIZES@@', SIZE_ROWS_SQL)
HTTP_RESULT = ("Success: The response status is 200. If it fails: 401 = the API key secret is wrong; 404 = the address is wrong; "
               "no response = the server in the URL (matching/urls, matching/machines) is down.")
SQL_FAIL = (" If it fails: read the SQL error text first; then check the database server (matching/machines:DatabaseServerName) "
            "is reachable from this box with Windows authentication.")
emit('start', "matching-preflight",
     ("What: Checks this box is ready for Matching testing: the instance's application pools exist and run, the empty baseline "
      "of this version is on the database server, the source tables of every size in matching/sizes are in the ModelSource "
      "database, the Connect run-as user is a Profisee user, TestAuto and its repository answer, the standard API key is set "
      "and works through the gateway and the Data service (common-api-key-set), and every TestAuto workflow matching-setup "
      "creates for the size rows now in reference data sits on exactly one workflow. CrewChief's own pre-run check first proves "
      "every matching/* reference value it uses is filled in. Why: finds every environment problem in one run, before a test "
      "fails half way through. When: before and after matching-setup, after any reference data change, after a Profisee "
      "upgrade, before every round, and first whenever a test fails; never while a test runs on this application server. "
      "Needs: the matching/* reference sets, the common pack and the box's secrets; the API user exists in the Profisee "
      "database. It changes only two things: the pool step starts a pool that is stopped, and the key step writes the standard "
      "API key and restarts IIS (pack standard: the key is set before any gateway query). Success: Every step Succeeded or "
      "Skipped; before the first matching-setup the workflow step says \"not created yet\", normal. If it fails: each step's "
      "failure text names the reference key, secret or machine to fix; fix reference data or the box, never a workload file."),
     [],
     [steps.pools_child("Application Pools Exist", "Start",
                        "a reset fails half way when the instance has no pools or one will not start; this finds it first"),
      steps.backup_check_child("Baseline Backup Exists", EMPTY, "matching-base-create"),
      steps.sql("Scenario Backups Present", checkpoints_sql,
          "What: List which checkpoint backups of this version (profisee_Matching_<size>_<checkpoint>_<version code>.bak: "
          + ", ".join(BACKUP_SUFFIXES) + ") are in the SQL Server default backup folder, for every size in matching/sizes. Why: "
          "shows how far each size's chain has run on this box; the runs write these themselves, so a missing one is stated, never "
          "failed. Success: two lines list the backups present and not made yet." + SQL_FAIL, conn=steps.MASTER, timeout=120),
      steps.sql("Source Tables Exist", tables_sql,
          "What: Check the database matching/databases:ModelSourceDB holds the source tables every size loads and changes "
          "(RetailClient<Size>Scenario1, Scenario2, Scenario3b and Scenario3c for every size in matching/sizes) and print each "
          "row count. A size listed in matching/values:OptionalSizes may lack its tables on this box: that is stated, not failed. "
          "Why: a load of a size without its tables fails after the restore and Configuration. Success: every table of the "
          "other sizes exists; the output gives each table's row count." + SQL_FAIL, conn=steps.MASTER, timeout=120),
      steps.sql("Connect Run-As User Is A Profisee User", RUN_AS_SQL,
          "What: Check the Connect run-as user (secret ConnectRuntime:ConnectRunAsUser) is a user in the Profisee database "
          "(matching/databases:ProfiseeDatabaseName). Why: every Matching load runs its Connect batch as this user. Success: the "
          "run-as user exists in the Profisee database." + SQL_FAIL, timeout=120),
      steps.http_get("TestAuto Answers", "{{TestAutoBaseUrl}}/api/workflows/by-tag?tag=AUTO%3Apreflight",
          "What: Ask TestAuto on this box (matching/machines:TestServerNameFQDN, port 8443) for workflows tagged with a probe tag. "
          "Why: every Matching run finds its TestAuto workflow by tag through this call. " + HTTP_RESULT, verify_ssl=False, max_time=120),
      steps.http_get("TestAuto Model Answers", "{{ScenarioMgtBaseUrl}}v1/Records/TestAutoWorkflow?PageSize=1",
          "What: Read one TestAuto workflow record from the TestAuto repository (matching/urls:ScenarioMgtBaseUrl) with the "
          "RestClients:ScenarioMgt:ApiKey secret. Why: matching-setup writes the run profiles and workflows through it. " + HTTP_RESULT,
          headers={"x-api-key": "{{ScenarioMgtApiKey}}"}, max_time=120),
      steps.wait_runs(),
      steps.key_set_child(),
      specs.keys_step("List The Workflows Setup Creates", key_patterns(),
          "What: Work out, from the size rows now in reference data (matching/sizes), the key of every TestAuto workflow "
          "matching-setup creates, with the same loops matching-setup uses, into the run parameter SetupTagKeys. Why: the next "
          "step checks each of them; the list is never typed, so it cannot fall behind a new size. Success: one line of keys. If "
          "it fails: a size row is empty or malformed; the message names it.", setup_name=SETUP, output="SetupTagKeys"),
      steps.tag_check_child("Every Workflow Found Once", "{{SetupTagKeys}}", SETUP, allow_none=True)],
     inputs=VERSION_CODE,
     globals_=g(*BOX, "ModelSourceDB", "ScenarioMgtBaseUrl", "ScenarioMgtApiKey", "RunAsUser", SetupTagKeys=""),
     notes="SetupTagKeys is set by the step List The Workflows Setup Creates during the run; it starts blank and is never passed.")

# ---------------------------------------------------------------- start/matching-base-create (D18)
# Makes the empty baseline of one Profisee version: restore the seed (today's unversioned baseline, the same or an older
# version), run Profisee Configuration on it, set and verify the API key, back it up under the versioned name. P1 (Gene
# 11/10): when this version's baseline already exists the workload ends GREEN and touches nothing: a PowerShell step
# captures "true" (baseline missing) or "false" into the run parameter BaseMissing and every step after the check carries
# runWhen {{BaseMissing}} (blank or "false" = skip). BaseMissing starts as "false": a capture that never happens can only
# skip steps, never overwrite a baseline.
check_base_ps = r"""$ErrorActionPreference = 'Stop'
$file = '@EMPTY@'
$c = New-Object System.Data.SqlClient.SqlConnection 'Server={{DatabaseServerName}};Database=master;Integrated Security=True;TrustServerCertificate=True;Connect Timeout=30'
$c.Open()
try {
    $q = $c.CreateCommand()
    $q.CommandText = "DECLARE @dir nvarchar(400) = CAST(SERVERPROPERTY('InstanceDefaultBackupPath') AS nvarchar(400)); DECLARE @exists int, @f nvarchar(600) = @dir + N'\' + @file; EXEC master.dbo.xp_fileexist @f, @exists OUTPUT; SELECT @exists;"
    [void]$q.Parameters.AddWithValue('@file', $file)
    $exists = [int]$q.ExecuteScalar()
}
finally { $c.Close() }
if ($exists -eq 1) { 'false' } else { 'true' }""".replace('@EMPTY@', EMPTY)
report_base_ps = r"""if ('{{BaseMissing}}' -eq 'true') {
    "No Matching base @EMPTY@ for version {{ProfiseeVersionCode}} on {{DatabaseServerName}} yet; it will be made."
} else {
    "Matching base @EMPTY@ for version {{ProfiseeVersionCode}} already exists; nothing done."
}""".replace('@EMPTY@', EMPTY)
SKIP_BASE = "the Matching base of this version already exists (the check step found it), so there is nothing to make"


def when_missing(step_):
    return steps.gated(step_, "{{BaseMissing}}", SKIP_BASE)


configure_seed = steps.run_child("Configure The Restored Seed", "install-configure-upgrade", "", timeout=7500, description=(
    "What: Run Profisee Configuration on the restored seed (install pack building block install-configure-upgrade: upgrade, keeps "
    "the data). Why: the seed may come from an older Profisee version; Configuration upgrades it to the version under test and "
    "writes this application server's service sign-in ids. Success: The child workload ends with every step Succeeded. If it "
    "fails: Open the run output of 'install-configure-upgrade'; Configuration's log is quoted there. A seed from a newer version "
    "than the installed Profisee cannot be used (Configuration only upgrades)."))
emit('start', "matching-base-create",
     ("What: Make the empty Matching baseline of one Profisee version: restore the seed backup "
      "(matching/databases:EmptySeedBackupFileName), run Profisee Configuration on it (install-configure-upgrade), wait for every "
      "service, set and prove the standard API key (common-api-key-set), check the model is empty and back it up under the "
      "versioned name (profisee_Matching_empty_<version code>.bak). When that base already exists it skips everything after the "
      "check, prints that nothing was done and ends green; it never overwrites a base. Why: a lane of a new Profisee version has "
      "no baseline yet; every Matching load restores it. When: once per box and version, after the Profisee of that version is "
      "installed (run it before matching-setup; a round starts it first); matching-preflight says when the base is missing. "
      "Needs: the seed is the empty baseline of the same or an older version (Configuration only upgrades); the install and "
      "common packs on this box; no test running against this Profisee database. Success: Every step Succeeded or Skipped. If it "
      "fails: open the first failed step, whose If it fails text names what to check."),
     ["base-create"],
     [steps.wait_runs(),
      steps.ps("Check Whether The Base Exists", check_base_ps,
          "What: Look for the empty baseline of this version (profisee_Matching_empty_<version code>.bak) in the SQL Server default "
          "backup folder of matching/machines:DatabaseServerName and keep the answer in the run parameter BaseMissing (true = no "
          "base yet). Why: a base is made once and never overwritten; every Matching load restores it, so when it exists every "
          "later step is skipped and the run ends green. Success: the step ends without an error (it does not fail when the base "
          "exists). If it fails: the database server does not answer, or the CrewChief account cannot connect to master there.",
          timeout=120, output="BaseMissing"),
      steps.ps("Report The Base State", report_base_ps,
          "What: Print whether the empty baseline of this version already exists (nothing done) or will be made. Why: the run "
          "output then says plainly why every later step is Skipped. Success: one line is printed. If it fails: the script cannot "
          "fail by itself; open the run output of the check step before it.", timeout=60),
      when_missing(steps.instance_stop_child(STOP_WHY)),
      when_missing(steps.db_step("Restore Seed Backup", "RestoreDatabase", "{{EmptySeedBackupFileName}}",
          f"What: Restore the seed backup (matching/databases:EmptySeedBackupFileName) over the Profisee database WITH REPLACE. "
          f"{RESTORE_NOTE} Why: it holds the empty Matching model (RetailClient matching strategy, API user, no records) of the "
          "same or an older Profisee version. Success: restored. If it fails: the seed is missing from the SQL Server default "
          "backup folder of matching/machines:DatabaseServerName, or the CrewChief account is not sysadmin there.")),
      when_missing(steps.instance_start_child("Configuration expects a running instance")),
      when_missing(configure_seed),
      when_missing(steps.health_child("Wait For Every Service After Configuration")),
      when_missing(steps.key_set_child()),
      when_missing(steps.sql("Check Base State", EMPTY_SQL,
          "What: Confirm the configured database is the empty Matching model: RetailClient holds no rows. Why: the loads fill an "
          "empty entity; a base with records would measure something else. Success: 0 rows. If it fails: the seed was not the "
          "empty baseline; restore the right seed and run matching-base-create again.")),
      when_missing(steps.db_step("Back Up The Empty Baseline", "BackupDatabase", EMPTY,
          "What: Back up the configured database as the empty baseline of this version (profisee_Matching_empty_<version code>.bak). "
          "Why: every Matching load of this version restores it. Success: written (file date now). If it fails: the SQL Server "
          "service account cannot write its default backup folder, or the disk is full."))],
     inputs=VERSION_BOTH,
     globals_=g(*BOX, "EmptySeedBackupFileName", BaseMissing="false"),
     notes=("BaseMissing is set by the check step during the run (true or false); it starts as false so a step that never got its "
            "answer is skipped, never run."))

# ---------------------------------------------------------------- rounds (plan lines carry values: <workload> Name=Value ...)
rounds = os.path.join(root, 'rounds')
os.makedirs(rounds, exist_ok=True)
RUN = ("# Run: bash ../../tools/runner/run-queue.sh <CrewChief box> {f}  (one Matching run at a time per box: every test "
       "restores the same Profisee database)\n# A line is a workload and the values it gets: <workload> Name=Value\n")
RETIRED_LINE = re.compile(r'(?m)^\+?\s*matching-(test-)?\d+[km]\b')


def round_file(name, text):
    """A round is a person's file once it exists: written when missing, or when it still names a retired workload."""
    path = os.path.join(rounds, name)
    if os.path.exists(path):
        with open(path, encoding='utf-8') as f:
            if not RETIRED_LINE.search(f.read()):
                return
    with open(path, 'w', encoding='utf-8', newline='\n') as f:
        f.write(text)


round_file('smoke.txt',
    "# Smoke test: the whole 1K test (load, then Scenarios 1, 2, 3a, 3b, 3c; about 65 minutes). Use it after a move to a new machine.\n"
    + RUN.format(f='smoke.txt') + "\nmatching-test Size=1K\n")
for _size in SIZE_ROWS:
    _f = _size.lower() + '-round.txt'
    round_file(_f,
        f"# Matching {_size} by scenario: the same runs as matching-test Size={_size}, one line each, so a failed scenario can be re-run on its own.\n"
        + ("# 100M needs its source tables built (about 86 GB plus a 120M-row base): only on a box with room.\n" if _size == '100M' else "")
        + RUN.format(f=_f) + "# '+' = runs only when the line before passed (each scenario restores the backup the one before it wrote).\n\n"
        + f"matching-scenario1-load Size={_size}\n" + "".join(f"+{workload_name(s)} Size={_size}\n" for s in SCENARIOS))
round_file('release-round.txt',
    "# Release round (mid-release and GA): 1K, 10K and 100K, every scenario (about 7 hours: 65 + 90 + 255 minutes).\n"
    + RUN.format(f='release-round.txt') + "# No '+': each size starts from the empty baseline, so a failed size does not stop the next one.\n\n"
    + "matching-test Size=1K\nmatching-test Size=10K\nmatching-test Size=100K\n")
round_file('ga-1m-round.txt',
    "# GA only: the 1M test, every scenario (not yet measured; 100K takes about 4 h 15 min).\n"
    + RUN.format(f='ga-1m-round.txt') + "\nmatching-test Size=1M\n")

count = sum(len(files) for _d, _s, files in os.walk(wl_root))
print(f"matching pack written: {count} workloads, {len(TEMPLATES)} TestAuto workflow templates")
