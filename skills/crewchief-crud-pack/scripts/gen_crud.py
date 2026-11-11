"""Builds the CrewChief CRUD pack (CrewChief/packs/crud). One workload per SHAPE; size, minutes, iterations and business
rules are run values, never part of a name or a copy of a file (Gene 11/11).

  tests/      crud-test           core run then stewardship, for the Size, Minutes (or Iterations) and BusinessRules passed
              crud-test-release   the release load: one restore, 18 steps (core, 12 stewardship steps of 60 minutes, delete)
  internal/   crud-run-start      once per test: restore the base, Configuration, API key, back up the run-start copy
              crud-base-reset     before each measured run: restore the run-start copy, API key, base check
              crud-rules-remove   delete every TDATA/ZDATA business rule through REST
              crud-core           measured run: Create, Update, Get x3, Delete on ZDATA
              crud-stewardship    measured run: 12 stewardship steps on TDATA, by time or by count
              crud-release        measured run: the 18-step release workflow
  start/      crud-preflight, crud-setup, crud-base-create
  schedule/   schedule-crud       one workload; the schedule name passed picks its rows in crud/schedule

  Before: crud-test-1k-br, crud-test-10k-nobr, ... (8 tests), crud-1k-core-br ... (8), crud-steward-5min-br ... (16),
          crud-testauto-*-create (13), 8 schedules.
  After:  crud-test --param Size=1K --param Minutes=1 --param BusinessRules=false

Adding a size or a time is a change to reference rows in git, never to a workload and never a run of this generator:
  crud/sizes            1K = 1000 ...            (a new size: one row here, one in crud/default-minutes)
  crud/default-minutes  1K = 1 ...               (stewardship minutes when a run passes no Minutes)
  crud/values           StewardMinutes = 1,5,15,30,60   StewardIterations = 10,100,1000   ReleaseSizes = 1M
then run crud-setup again: its three template steps create one TestAuto workflow per row (existing ones are untouched).

The TestAuto workflow keys are the same as before (crud-1k-core-br, crud-steward-5min-nobr, crud-1m-release-br), so setup
updates the existing workflows and their history is not split.

Source of the TestAuto step configs: PROD workflows 10000195 (no rules) and 10000197 (with rules), read 11/07/2026.
Shared blocks (API key, health, instance stop/start, pools, backup check, tag check) are the common pack's workloads.

Usage: python gen_crud.py <packRoot>      (e.g. C:\\devops\\repos\\speed-merchants\\CrewChief\\packs\\crud)
"""
import os
import re
import sys

root = os.path.abspath(sys.argv[1])
FAM = 'crud'
SETUP = 'crud-setup'
ref_dir = os.path.join(root, 'reference-kv', FAM)
wl_root = os.path.join(root, 'workloads', FAM)
sys.path.insert(0, os.environ.get('PACKGEN_TOOLS') or os.path.join(os.path.dirname(root), 'tools'))
from packgen import specs, steps  # noqa: E402
from packgen.values import (record_count_input, ref as _ref, rules_input, rules_key_input, size_input, value_input,  # noqa: E402
                            version_inputs)
from packgen.workloads import clear_workloads, dump, seed_reference_set, workload  # noqa: E402

WIDTHS = [(15, 10, 5), (30, 20, 10), (60, 40, 20), (120, 70, 50)]  # (attributes, freeform, domain-based)
USERS = [1, 10, 100]
MIN_TDATA = 10000000
VER = "{{ProfiseeVersionCode}}"


def ref(set_name, key):
    return _ref(FAM, set_name, key)


# ---------------------------------------------------------------- pack-owned reference sets (seeded once, then git is the source)
SIZES_TOKEN = "{{$ref:crud/sizes:*}}"
seed_reference_set(os.path.join(ref_dir, 'sizes.json'),
    "CRUD pack: the sizes a CRUD run can have. Key = the Size a run passes; value = the record count. Add a size by adding a row here "
    "and one in crud/default-minutes, then run crud-setup (it creates the core TestAuto workflows of every row). Kept in git with "
    "the pack and restored to a box with Replace; never edited on a box.",
    {"1K": "1000", "10K": "10000", "100K": "100000", "1M": "1000000"},
    {"1K": "1,000 ZDATA records created, updated, read and deleted by the core run.",
     "10K": "10,000 ZDATA records created, updated, read and deleted by the core run.",
     "100K": "100,000 ZDATA records created, updated, read and deleted by the core run.",
     "1M": "1,000,000 ZDATA records (one million; never one minute): the release size."})
seed_reference_set(os.path.join(ref_dir, 'default-minutes.json'),
    "CRUD pack: stewardship minutes per step when a run passes a Size and no Minutes. Key = Size; value = minutes (1 to 60). A "
    "Minutes value passed to the run always wins. Kept in git with the pack; never edited on a box.",
    {"1K": "1", "10K": "5", "100K": "30", "1M": "60"},
    {"1K": "A 1K run does 1-minute stewardship steps (12 steps, about 12 minutes).",
     "10K": "A 10K run does 5-minute stewardship steps (about 1 hour).",
     "100K": "A 100K run does 30-minute stewardship steps (about 6 hours).",
     "1M": "A 1M run does 60-minute stewardship steps (about 12 hours)."})
seed_reference_set(os.path.join(ref_dir, 'values.json'),
    "CRUD pack: the value lists crud-setup creates TestAuto workflows for. Each row is a list separated by commas. Add a value to "
    "a list, then run crud-setup; a run that passes a value with no workflow is stopped at its start and told to run crud-setup. "
    "Kept in git with the pack; never edited on a box.",
    {"StewardMinutes": "1,5,15,30,60", "StewardIterations": "10,100,1000", "ReleaseSizes": "1M"},
    {"StewardMinutes": "Minutes per stewardship step a run may pass as Minutes (1 to 60). One TestAuto workflow per value, with and without business rules.",
     "StewardIterations": "Iterations per stewardship step a run may pass as Iterations (stewardship by count instead of by time). One TestAuto workflow per value, with and without business rules.",
     "ReleaseSizes": "Sizes (keys of crud/sizes) crud-test-release can run: one 18-step release TestAuto workflow per size, with and without business rules."})

# Schedules: one workload, schedule-crud; the Schedule name passed picks four rows here. Weekly defaults, Monday-Friday:
# Matching schedules use Sunday and Connect's Saturday 02:00, and every pack restores the same Profisee database.
SCHEDULES = [("1k-br", "crud-test", "Size=1K BusinessRules=true", "Mon", "18:00"),
             ("1k-nobr", "crud-test", "Size=1K BusinessRules=false", "Mon", "20:00"),
             ("10k-br", "crud-test", "Size=10K BusinessRules=true", "Mon", "22:00"),
             ("10k-nobr", "crud-test", "Size=10K BusinessRules=false", "Tue", "18:00"),
             ("100k-br", "crud-test", "Size=100K BusinessRules=true", "Tue", "22:00"),
             ("100k-nobr", "crud-test", "Size=100K BusinessRules=false", "Wed", "18:00"),
             ("1m-br", "crud-test-release", "Size=1M BusinessRules=true", "Thu", "06:00"),
             ("1m-nobr", "crud-test-release", "Size=1M BusinessRules=false", "Fri", "06:00")]
sched_entries, sched_desc = {}, {}
for sname, target, vals, day, time in SCHEDULES:
    for field, value, text in (("Target", target, "the workload the scheduled task runs"),
                               ("Values", vals, "the values it passes to that workload, Name=Value separated by spaces"),
                               ("Days", day, "the weekday(s) it starts, e.g. Mon or Mon,Thu"),
                               ("Time", time, "the start time, HH:mm, 24-hour, local time")):
        sched_entries[f"{sname}.{field}"] = value
        sched_desc[f"{sname}.{field}"] = f"Schedule '{sname}' (Windows task schedule-crud-{sname}): {text}."
seed_reference_set(os.path.join(ref_dir, 'schedule.json'),
    "CRUD pack: the schedules schedule-crud can apply. A schedule is four rows named <schedule>.Target, .Values, .Days and .Time; "
    "run schedule-crud with Schedule=<schedule> to create or update its Windows task. Add a schedule by adding its four rows. "
    "Never let two tests on the same Profisee database overlap. Kept in git with the pack; never edited on a box.",
    sched_entries, sched_desc)
RETIRED_SETS = ('workflows.json',)  # display names are composed by the setup templates now
for name in RETIRED_SETS:
    if os.path.exists(os.path.join(ref_dir, name)):
        os.remove(os.path.join(ref_dir, name))

# ---------------------------------------------------------------- box globals (box facts: the crud/* sets a person edits per box)
G = {
    "ApplicationServerName": ref('machines', 'ApplicationServerName'),
    "DatabaseServerName": ref('machines', 'DatabaseServerName'),
    "ProfiseeInstanceName": ref('instances', 'ProfiseeInstanceName'),
    "ProfiseeDatabaseName": ref('databases', 'ProfiseeDatabaseName'),
    "BaseSeedBackupFileName": ref('databases', 'BaseSeedBackupFileName'),
    "ProfiseeBaseUrl": "https://" + ref('machines', 'ApplicationServerNameFQDN') + "/" + ref('instances', 'ProfiseeInstanceName') + "/rest",
    "TestAutoBaseUrl": "https://" + ref('machines', 'TestServerNameFQDN') + ":8443",
    "ScenarioMgtBaseUrl": ref('urls', 'ScenarioMgtBaseUrl'),
    "ScenarioMgtApiKey": "{{$config:RestClients:ScenarioMgt:ApiKey}}",
    "ProfiseeApiKey": "{{$config:RestKeys:ProfiseeRestKey}}",
    # Gene 11/07: CRUD rows name the application server as their environment, as the release CRUD history does.
    "TestAutoEnvironmentName": ref('machines', 'ApplicationServerName'),
    "TestAutoApplicationServer": ref('machines', 'ApplicationServerName'),
    "TestAutoDatabaseServer": ref('machines', 'DatabaseServerName'),
}
# What the common pack's workloads read from the workload that runs them.
BOX = ("ApplicationServerName", "DatabaseServerName", "ProfiseeInstanceName", "ProfiseeDatabaseName", "ProfiseeBaseUrl", "TestAutoBaseUrl")


def g(*names, **extra):
    out = {n: G[n] for n in names}
    out.update(extra)
    return out


# ---------------------------------------------------------------- inputs (run values and version: the same form in every workload)
SIZE = size_input(FAM)
RELEASE_SIZE = size_input(FAM, default='1M')
RECORD_COUNT = record_count_input(FAM)
RULES = rules_input()
RULES_KEY = rules_key_input()
MINUTES = value_input('Minutes', "{{$ref:crud/default-minutes:{{Size}}}}",
                      "Minutes per stewardship step (1 to 60; one of crud/values:StewardMinutes). Default: the row crud/default-minutes:<Size>. "
                      "Ignored when Iterations is not 0.")
ITERATIONS = value_input('Iterations', "0",
                         "Iterations per stewardship step (one of crud/values:StewardIterations) to run stewardship by count; 0 = by time (Minutes).")
VERSION_CODE = version_inputs(FAM, 'ProfiseeVersionCode')
VERSION_BOTH = version_inputs(FAM)
BASE_BACKUP = value_input('BaseBackupFileName', ref('databases', 'BaseBackupStem') + "_" + VER + ".bak",
                          "File name of the CRUD base backup of this version: crud/databases:BaseBackupStem, an underscore, the version code, .bak.")
RUN_START_BACKUP = value_input('RunStartBackupFileName', ref('databases', 'RunStartBackupStem') + "_" + VER + ".bak",
                               "File name of the run-start backup of this version: crud/databases:RunStartBackupStem, an underscore, the version code, .bak.")
NO_RULES_WHEN = "{{BusinessRules|map:true=false,false=true}}"
NO_RULES_REASON = "the run keeps the business rules (BusinessRules = true)"

CORE_KEY = "crud-{{Size|lower}}-core-{{RulesKey}}"
STEWARD_KEY = "crud-steward-{{StewardForm}}-{{RulesKey}}"
RELEASE_KEY = "crud-{{Size|lower}}-release-{{RulesKey}}"


def emit(folder, name, description, tags, step_list, inputs=None, globals_=None, notes=""):
    dump(os.path.join(wl_root, folder, name + '.workload.json'),
         workload(name, description, [FAM, folder] + tags, step_list, inputs=inputs, globals_=globals_, notes=notes, family=FAM))


clear_workloads(wl_root)

# ---------------------------------------------------------------- TestAuto step configs (PROD 10000195/10000197 shape)
REST_AREAS = ("Profisee", "Metrics", "Connect", "Portal", "Matching")
CS_AREAS = ("Profisee", "Metrics", "Matching", "Connect", "Portal", "Data", "TestAuto")
DEFAULT_QUERY = {"SelectAttributes": "", "SortAttributes": "", "Filter": "", "QueryParameters": {}}
N = specs.number('RecordCount')
DQ = specs.number('DqRuleCount')


def scenario(name, src, tgt, ff, da, batch, users, custom, limit, tme="RecordApiExecution", query=None):
    return specs.scenario_text({
        "ScenarioName": name,
        "MaxHangfireScenarioServersCount": 1,
        "ScenarioTables": {"SourceEntityName": src, "TargetEntityName": tgt},
        "ScenarioDataShape": {"FreeformAttributes": ff, "DomainAttributes": da},
        "ScenarioRuntime": {"NumberOfGeneratedTestRecordsPerBatch": 1, "BatchSize": batch, "PageNumber": 1,
                            "MaxHangfireScenarioServersCount": users, "MaxConcurrentBatchesPerHangfireScenarioServer": 1,
                            "CustomParms": custom},
        "ScenarioTesting": {"TestRecordLimit": limit, "TestOverrideQueueName": ""},
        "ScenarioQuery": query or dict(DEFAULT_QUERY),
        "ScenarioRestTarget": {"RestUrlBase": None, "RestApiKey": None,
                               "SubjectAreaOverrides": {a: {"RestUrlBase": "", "RestApiKey": ""} for a in REST_AREAS}},
        "ScenarioDatabaseConnectionStrings": {"ConnectionString": None,
                                              "SubjectAreaOverrides": {a: {"ConnectionString": ""} for a in CS_AREAS}},
        "ScenarioEnvironment": {"DqRuleCount": DQ, "TargetEnvironment": "IaaS",
                                "TargetEnvironmentName": "{{TestAutoEnvironmentName}}", "TargetMetricEntity": tme,
                                "WorkloadExecution": "", "ProfiseeVersion": VER,
                                "TargetApplicationServer": "{{TestAutoApplicationServer}}",
                                "TargetDatabaseServer": "{{TestAutoDatabaseServer}}", "ExecutionMode": "B",
                                "HangfireJob": 0, "SimulatedUserThreadId": 0},
    })


def core_details():
    """The six core steps, as a template: <<RecordCount>>, <<DqRuleCount>> and <<RulesText>> are filled in per size and rules."""
    users_txt = {1: "1 User", 10: "10 Users", 100: "100 Users"}
    d = [("CreateRecordsByPageAndBatch",
          "Create <<RecordCount>> ZDATA records from TDATA through the REST API, 1000 per batch, one user.",
          scenario("CreateRecordsByPageAndBatchScenario", "TDATA", "ZDATA", 70, 50, 1000, 1,
                   {"OffsetCode": False, "OffsetCodeBy": 0}, N)),
         ("UpdateRecordsByPageAndBatch",
          "Update the ZDATA records: 10% changed (Name gets '_Changed'), 5% new (Code ends '_New'), Name and Code otherwise kept.",
          scenario("UpdateRecordsByPageAndBatchScenario", "TDATA", "ZDATA", 70, 50, 1000, 1,
                   {"UpdateRecordPercent": "10", "NewRecordPercent": "5", "UseMutationHelper": "false",
                    "MutationStrategy": "Not Used", "UpdateIncludedAttributes": [], "UpdateExcludedAttributes": ["Name", "Code"],
                    "TransformSeed": 12345}, N))]
    for u in USERS:
        d.append((f"GetRecordsByPageAndBatchSeqScenario {users_txt[u]} <<RulesText>>",
                  f"Read the ZDATA records page by page through the REST API with {u} simulated user(s).",
                  scenario("GetRecordsByPageAndBatchSeqScenario", "TDATA", "ZDATA", 70, 50, 1000, u, {}, N)))
    d.append(("DeleteRecordsByPageAndBatch",
              "Delete the ZDATA records the update touched (Code contains '_New' or Name contains '_Changed'), 500 per batch.",
              scenario("DeleteRecordsByPageAndBatchScenario", "ZDATA", "ZDATA", 70, 50, 500, 1, {}, N,
                       query={"SelectAttributes": "", "SortAttributes": "",
                              "Filter": "Contains([Code], '_New') OR Contains([Name], '_Changed')", "QueryParameters": {}})))
    return d


def stew_details():
    """The twelve stewardship steps, as a template: <<TimeLimit>>, <<IterationLimit>>, <<FormSpan>>, <<RulesText>>, <<DqRuleCount>>."""
    out = []
    for u in USERS:
        for attrs, ff, da in WIDTHS:
            custom = {"CreateNewRecords": True, "DeleteRecordPercent": 5, "DeleteRecords": True, "HighBatchSize": 1000,
                      "IterationLimit": "<<IterationLimit>>", "LowBatchSize": 500, "NewRecordPercent": 35, "NumberOfRandomReads": 3,
                      "SleepMaxMs": "1000", "SleepMinMs": "1000", "TimeLimit": "<<TimeLimit>>", "TransformSeed": "12345",
                      "UpdateExistingRecords": True, "UpdateRecordPercent": 60, "UpdateRecordsAvailable": 10000000}
            users = "1 User" if u == 1 else f"{u} Users"
            out.append((f"StewardshipFilterScenario <<RulesText>> {attrs} Attributes {users}",
                        f"Interactive stewardship on TDATA <<FormSpan>>:{attrs} attributes ({ff} freeform, {da} domain-based), "
                        f"{u} simulated user(s) reading, creating, updating and deleting records.",
                        scenario("StewardshipFilterScenario", "TDATA", "TDATA", ff, da, 1000, u, custom, 2,
                                 tme="RecordInteractiveApiExecution",
                                 query={"SelectAttributes": "", "SortAttributes": "Code", "Filter": "[MyNumeric001] gt 1",
                                        "QueryParameters": {"ignoreConstraintRules": "true"}})))
    return out


# PowerShell the three template steps share: the words and numbers a workflow gets from its loop values.
PRELUDE = r"""function Set-Rules($v) {
    if ($v.Rules -eq 'br') { $v.RulesText = 'With Business Rules'; $v.DqRuleCount = '10' }
    elseif ($v.Rules -eq 'nobr') { $v.RulesText = 'No Business Rules'; $v.DqRuleCount = '0' }
    else { throw "Rules value '$($v.Rules)' is not br or nobr." }
    $v.RulesLower = $v.RulesText.ToLower()
}
function Set-Size($v) {
    $v.SizeLower = $v.Size.ToLower()
    $v.RecordCount = Get-SetValue 'Sizes' $v.Size
    if ($v.RecordCount -notmatch '^[1-9]\d*$') { throw "crud/sizes:$($v.Size) is '$($v.RecordCount)'; a record count is a whole number above 0." }
}
function Set-Form($v) {
    # A stewardship form: <minutes>min (time per step) or <count>it (iterations per step).
    if ($v.Form -match '^(\d+)min$') {
        $m = [int]$Matches[1]
        if ($m -lt 1 -or $m -gt 60) { throw "Stewardship minutes '$m' (crud/values:StewardMinutes): 1 to 60 minutes per step are supported." }
        $v.Form = "${m}min"
        $v.TimeLimit = if ($m -eq 60) { '00:59:59' } else { '00:{0:00}:00' -f $m }
        $v.IterationLimit = '0'
        $v.FormShort = "$m min"
        $v.FormLong = "$m minute(s) per step, about $(12 * $m) minutes in all"
        $v.FormSpan = "for $m minute(s)"
    }
    elseif ($v.Form -match '^(\d+)it$') {
        $n = [int]$Matches[1]
        if ($n -lt 1) { throw "Stewardship iterations '$n' (crud/values:StewardIterations): at least 1." }
        $v.Form = "${n}it"
        $v.TimeLimit = '00:00:00'
        $v.IterationLimit = "$n"
        $v.FormShort = "$n iterations"
        $v.FormLong = "$n iterations per step (each: one page read, one create, update or delete, a 1 second pause)"
        $v.FormSpan = "for $n iterations"
    }
    else { throw "Stewardship value '$($v.Form)' is not a whole number of minutes or iterations (crud/values:StewardMinutes, StewardIterations)." }
}
"""
SETS = {"Sizes": SIZES_TOKEN}
RULES_LOOP = specs.items('br,nobr')
MACHINE_TAG = ref('environment', 'MainMachineTag')
SETUP_FAIL = (" If it fails: the message names the value or the workflow: a value with no reference row, a step configuration over "
              "4000 characters, or two workflows with the same tag (untag the copy by hand); any other error names the record.")


def spec_description(measures, runner):
    return ("Automation ID: <AUTOMATION_ID>. CrewChief finds this workflow by that tag alone; do not edit or remove the tag, and to "
            f"experiment copy the workflow and remove the tag from the copy. Measures: {measures}, on the Profisee version in "
            f"{FAM}/environment:ProfiseeVersionCode. Run by the CrewChief workload '{runner}', which restores the CRUD base backup "
            "first; running it alone measures a model in an unknown state.")


_release_core = core_details()
TEMPLATES = {
    "core": dict(
        label="Upsert Core Workflows", key="crud-<<SizeLower>>-core-<<Rules>>", name="CRUD <<Size>> Core <<RulesText>>",
        spec={"PlainTags": f"CRUD,{VER},{MACHINE_TAG},<<Size>>",
              "Description": spec_description("CRUD core <<Size>> (<<RecordCount>> records) <<RulesLower>>: Create, Update, Get with 1, "
                                              "10 and 100 users, Delete on ZDATA", "crud-core"),
              "Details": core_details()},
        loops={"Size": specs.set_keys('Sizes'), "Rules": RULES_LOOP}, derive="Set-Size $v\nSet-Rules $v",
        what=("the core workflow (Create, Update, Get with 1, 10 and 100 users, Delete; 6 steps) of every size in crud/sizes, with "
              "and without business rules")),
    "stewardship": dict(
        label="Upsert Stewardship Workflows", key="crud-steward-<<Form>>-<<Rules>>", name="CRUD Stewardship <<FormShort>> <<RulesText>>",
        spec={"PlainTags": f"CRUD,{VER},{MACHINE_TAG},Stewardship",
              "Description": spec_description("CRUD stewardship <<RulesLower>> on TDATA, 12 steps, <<FormLong>>: 15, 30, 60 and 120 "
                                              "attributes with 1, 10 and 100 users", "crud-stewardship"),
              "Details": stew_details()},
        loops={"Form": [specs.items(ref('values', 'StewardMinutes'), 'min'), specs.items(ref('values', 'StewardIterations'), 'it')],
               "Rules": RULES_LOOP},
        derive="Set-Form $v\nSet-Rules $v",
        what=("the stewardship workflow (12 steps on TDATA) of every minutes value in crud/values:StewardMinutes and every "
              "iterations value in crud/values:StewardIterations, with and without business rules")),
    "release": dict(
        label="Upsert Release Workflows", key="crud-<<SizeLower>>-release-<<Rules>>", name="CRUD <<Size>> Release <<RulesText>>",
        spec={"PlainTags": f"CRUD,{VER},{MACHINE_TAG},<<Size>>,Release",
              "Description": spec_description("the release CRUD load <<RulesLower>>, <<Size>> records: Create, Update, Get with 1, 10 "
                                              "and 100 users, 12 stewardship steps of 60 minutes on TDATA, then Delete, all on one "
                                              "model state", "crud-release"),
              # Gene 11/07: the release CRUD workflows step for step, one restore, Delete after stewardship.
              "Details": _release_core[:5] + stew_details() + _release_core[5:]},
        loops={"Size": specs.items(ref('values', 'ReleaseSizes')), "Rules": RULES_LOOP},
        derive="Set-Size $v\n$v.Form = '60min'\nSet-Form $v\nSet-Rules $v",
        what=("the release workflow (18 steps: core, 12 stewardship steps of 60 minutes, Delete last) of every size in "
              "crud/values:ReleaseSizes, with and without business rules")),
}
assert len(TEMPLATES["release"]["spec"]["Details"]) == 18


def template_step(t):
    return specs.template_upsert_step(
        t["label"], t["key"], t["name"], t["spec"], t["loops"],
        f"What: Create or update {t['what']}: one TestAuto workflow per combination, each found by its automation tag. The step "
        "holds the workflow once, as a template; the sizes, minutes and iterations come from the reference rows, so a new row "
        "gives a new workflow and the existing ones are updated in place. Why: a CRUD run finds its workflow by that tag. "
        "Success: the last line lists the workflows created or updated." + SETUP_FAIL,
        setup_name=SETUP, category="CRUD", sets=SETS, prelude=PRELUDE, derive=t["derive"])


def key_patterns():
    return [(t["key"], t["loops"], SETS, PRELUDE, t["derive"]) for t in TEMPLATES.values()]


# ---------------------------------------------------------------- shared SQL and scripts
check_base = f"""DECLARE @tdata bigint = (SELECT SUM(p.rows) FROM sys.partitions p WHERE p.object_id = OBJECT_ID(N'data.tTDATA') AND p.index_id IN (0, 1));
DECLARE @zdata bigint = (SELECT COUNT_BIG(*) FROM data.tZDATA);
DECLARE @rulesT int = (SELECT COUNT(*) FROM [rule].vDQRule WHERE Entity = N'TDATA');
DECLARE @rulesZ int = (SELECT COUNT(*) FROM [rule].vDQRule WHERE Entity = N'ZDATA');
DECLARE @msg nvarchar(2048);
IF ISNULL(@tdata, 0) < {MIN_TDATA} OR @zdata <> 0 OR @rulesT = 0 OR @rulesZ = 0
BEGIN
    SET @msg = CONCAT(N'The restored database is not the CRUD base: TDATA ', ISNULL(@tdata, 0), N' rows (need at least {MIN_TDATA}), ZDATA ', @zdata,
        N' rows (need 0), business rules TDATA ', @rulesT, N' and ZDATA ', @rulesZ, N' (need at least 1 each). Check the backup named in crud/databases:BaseBackupStem with the version code.');
    THROW 50020, @msg, 1;
END
PRINT CONCAT(N'CRUD base state: TDATA ', @tdata, N' rows, ZDATA empty, business rules TDATA ', @rulesT, N', ZDATA ', @rulesZ, N'.');"""


def check_base_step():
    return steps.sql("Check Base State", check_base,
        "What: Confirm the restored database is the CRUD base: TDATA holds at least 10M rows, ZDATA is empty, and TDATA and ZDATA "
        "each carry business rules. Why: a run on another starting state measures something else. Success: the state line prints. "
        "If it fails: the error gives the counts; the backup named in crud/databases:BaseBackupStem with the version code is not the CRUD base.")


check_core = """DECLARE @total bigint = (SELECT COUNT_BIG(*) FROM data.tZDATA);
DECLARE @left bigint = (SELECT COUNT_BIG(*) FROM data.tZDATA WHERE Code LIKE N'%\\_New%' ESCAPE N'\\' OR [Name] LIKE N'%\\_Changed%' ESCAPE N'\\');
DECLARE @msg nvarchar(1000);
IF @total = 0 BEGIN SET @msg = N'ZDATA is empty after the run: Create wrote nothing (check the TestAuto run).'; THROW 50022, @msg, 1; END
IF @left > 0 BEGIN SET @msg = CONCAT(N'ZDATA still holds ', @left, N' rows the Delete step should have removed (Code ''_New'' or Name ''_Changed'').'); THROW 50023, @msg, 1; END
PRINT CONCAT(N'ZDATA after the {{Size}} run: ', @total, N' rows (created {{RecordCount}}, then 5% new added and the 15% the update touched deleted); none left with ''_New'' or ''_Changed''.');"""


def check_core_step():
    return steps.sql("Check Core Results", check_core,
        "What: Confirm the run left ZDATA as expected: rows created, and none left that the Delete step targets. Why: a TestAuto "
        "run can end Succeeded with nothing written. Success: the ZDATA line prints. If it fails: the error says which step did "
        "not do its work; open that step's run in TestAuto.")


# The stewardship form of a run: <Minutes>min, or <Iterations>it when Iterations is not 0. CrewChief tokens have no "if", so
# one small step works it out, checks the values a person typed, and hands the form to the steps after it (StewardForm).
decide_form = r"""$ErrorActionPreference = 'Stop'
$rules = '{{BusinessRules}}'.Trim(); $minutes = '{{Minutes}}'.Trim(); $iterations = '{{Iterations}}'.Trim()
if ($rules -notin 'true', 'false') { throw "BusinessRules is '$rules'; pass true (keep the business rules) or false (delete them first)." }
if ($iterations -notmatch '^\d+$') { throw "Iterations is '$iterations'; pass a whole number (0 = stewardship by time, Minutes)." }
if ([int]$iterations -gt 0) { "$([int]$iterations)it"; return }
if ($minutes -notmatch '^\d+$' -or [int]$minutes -lt 1 -or [int]$minutes -gt 60) { throw "Minutes is '$minutes'; pass a whole number from 1 to 60 (minutes per stewardship step), or Iterations for stewardship by count." }
"$([int]$minutes)min"
"""


def decide_form_step():
    return steps.ps("Decide The Stewardship Form", decide_form,
        "What: Check the values of the run (BusinessRules true or false, Iterations a whole number, Minutes 1 to 60) and work out "
        "the stewardship form: <Minutes>min, or <Iterations>it when Iterations is not 0. The form goes into the run parameter "
        "StewardForm, which the TestAuto workflow key carries. Why: one workload serves every time and count, so the form is a "
        "value worked out at the start, and a mistyped value stops the run here, before any restore. Success: one line, e.g. "
        "5min or 10it. If it fails: the message names the value and what it may be.", timeout=60, output="StewardForm")


FORM_NOTE = ("StewardForm is set by the step Decide The Stewardship Form during the run (e.g. 5min or 10it); it starts blank and is "
             "never passed.")


def reset_child():
    return steps.run_child("Reset To CRUD Base", "crud-base-reset", "Restore the run-start backup, set the API key and check the base state")


def rules_remove_child():
    return steps.gated(steps.run_child("Remove Business Rules", "crud-rules-remove",
                                       "Delete every business rule on TDATA and ZDATA through REST"),
                       NO_RULES_WHEN, NO_RULES_REASON)


def run_start_child():
    return steps.run_child("Prepare Run Start", "crud-run-start",
                           "Restore the CRUD base, run Configuration on it, set the API key and back up the run-start copy every "
                           "measured run restores", timeout=14400)


# ---------------------------------------------------------------- internal/crud-base-reset
RESTORE_NOTE = ("The executor takes the database OFFLINE WITH ROLLBACK IMMEDIATE first and brings it back ONLINE if the restore fails.")
emit('internal', "crud-base-reset",
     ("What: Stop the instance, restore the run-start backup over the Profisee database, set the standard API key (which starts "
      "the instance, waits for every service and proves the key through the gateway and the Data service), and check the base "
      "state (TDATA full, ZDATA empty, business rules on both). Why: every CRUD run starts from the same model, so runs compare. "
      "When: Never run directly; every measured CRUD workload runs it first. Needs: crud-run-start ran at the start of this test "
      "(it writes the run-start backup); no other test running against this Profisee database. Success: Every step Succeeded or "
      "Skipped. If it fails: open the first failed step, whose If it fails text names what to check."),
     ["reset"],
     [steps.wait_runs(),
      steps.instance_stop_child("a restore must not run under services that hold connections and caches"),
      steps.db_step("Restore Run-Start Backup", "RestoreDatabase", "{{RunStartBackupFileName}}",
          "What: Restore the run-start backup (crud/databases:RunStartBackupStem with the version code) over the Profisee database WITH REPLACE. "
          + RESTORE_NOTE + " Why: every measured CRUD run starts from the same model (TDATA full, ZDATA empty, business rules on "
          "both), configured on this application server at the start of this test by crud-run-start. Success: restored (about 6 "
          "minutes). If it fails: the run-start backup is missing (run the test from crud-test or crud-test-release, which write "
          "it first), or the CrewChief account is not sysadmin on crud/machines:DatabaseServerName."),
      steps.key_set_child(),
      check_base_step()],
     inputs=VERSION_CODE + [RUN_START_BACKUP], globals_=g(*BOX))

# ---------------------------------------------------------------- internal/crud-run-start (Gene 11/08)
# Profisee Configuration writes new service sign-in ids into the database it runs on AND into the application server, so
# only the base configured last works (11/08: the CRUD base, configured before the Matching base, got 400 DATA00030).
# Every test therefore configures the base once at its start and backs up a run-start copy; resets restore that copy.
configure_run = steps.run_child("Configure The Restored Base", "install-configure-upgrade", "", timeout=7500, description=(
    "What: Run Profisee Configuration on the restored CRUD base (install pack building block install-configure-upgrade: "
    "upgrade, keeps the data). Why: Configuration writes this application server's service sign-in ids into the database; a "
    "base configured earlier makes the Data service reject the user (400 DATA00030). Success: The child workload ends with "
    "every step Succeeded. If it fails: Open the run output of 'install-configure-upgrade'; Configuration's log is quoted there."))
emit('internal', "crud-run-start",
     ("What: Stop the instance, restore the CRUD base backup, start the instance, run Profisee Configuration on it "
      "(install-configure-upgrade), confirm every service is Healthy, set and prove the standard API key, check the base state, "
      "and back up the result as the run-start backup. Why: Configuration writes this application server's service sign-in ids "
      "into the database; only a base configured after the last Configuration on this server works. When: Never run directly; "
      "crud-test and crud-test-release run it first. Needs: the install pack and the common pack on this box; the base backup "
      "(crud/databases:BaseBackupStem with the version code) in the SQL Server default backup folder; no other test running "
      "against this Profisee database. Success: Every step Succeeded or Skipped. If it fails: open the first failed step, whose "
      "If it fails text names what to check."),
     ["run-start"],
     [steps.wait_runs(),
      steps.instance_stop_child("a restore must not run under services that hold connections and caches"),
      steps.db_step("Restore CRUD Base", "RestoreDatabase", "{{BaseBackupFileName}}",
          "What: Restore the CRUD base backup (crud/databases:BaseBackupStem with the version code) over the Profisee database WITH REPLACE. "
          + RESTORE_NOTE + " Why: Configuration runs on it next. Success: restored (about 6 minutes). If it fails: the backup is "
          "missing from the SQL Server default backup folder of crud/machines:DatabaseServerName (run crud-base-create), or the "
          "CrewChief account is not sysadmin there."),
      steps.instance_start_child("Configuration expects a running instance"),
      configure_run,
      steps.health_child("Wait For Every Service After Configuration"),
      steps.key_set_child(),
      check_base_step(),
      steps.db_step("Back Up Run-Start", "BackupDatabase", "{{RunStartBackupFileName}}",
          "What: Back up the configured database over the run-start file (crud/databases:RunStartBackupStem with the version code). Why: every "
          "measured run of this test restores it (crud-base-reset), so Configuration runs once per test, not once per run. The "
          "base backup itself is never overwritten. Success: written (file date now). If it fails: the SQL Server service account "
          "cannot write its default backup folder, or the disk is full.")],
     inputs=VERSION_BOTH + [BASE_BACKUP, RUN_START_BACKUP], globals_=g(*BOX))

# ---------------------------------------------------------------- internal/crud-rules-remove
rules_remove = r"""$ErrorActionPreference = 'Stop'
$base = '{{ProfiseeBaseUrl}}'.TrimEnd('/')
$headers = @{ 'x-api-key' = '{{ProfiseeApiKey}}'; accept = 'application/json' }
$entities = @('TDATA', 'ZDATA')
""" + steps.GET_WHY + r"""# Never print a 401 body: it echoes the API key (Get-Why leaves it out).
function Get-EntityRules {
    $r = Invoke-WebRequest -Uri "$base/v1/Rules?PageSize=1000" -Headers $headers -SkipCertificateCheck -SkipHttpErrorCheck -TimeoutSec 300
    if ([int]$r.StatusCode -ne 200) { throw "Listing business rules returned HTTP $([int]$r.StatusCode) at $base/v1/Rules. $(Get-Why $r)" }
    $page = $r.Content | ConvertFrom-Json
    if ($page.totalPages -gt 1) { throw "More than 1000 business rules in the model; this step reads one page only." }
    @($page.data | Where-Object { $_.entity -in $entities })
}
$rules = Get-EntityRules
if (-not $rules) { 'No business rules on TDATA or ZDATA: nothing to delete.'; return }
foreach ($e in $entities) { "$e has $(@($rules | Where-Object entity -eq $e).Count) business rule(s): $((@($rules | Where-Object entity -eq $e) | ForEach-Object attribute) -join ', ')" }
$ids = ($rules | ForEach-Object id) -join ','
$r = Invoke-WebRequest -Method Delete -Uri "$base/v1/Rules?RuleIds=$([uri]::EscapeDataString($ids))" -Headers $headers -SkipCertificateCheck -SkipHttpErrorCheck -TimeoutSec 600
if ([int]$r.StatusCode -notin 200, 204) { throw "Deleting $($rules.Count) business rule(s) returned HTTP $([int]$r.StatusCode). $(Get-Why $r)" }
$left = Get-EntityRules
if ($left) { throw "$($left.Count) business rule(s) still on TDATA or ZDATA after the delete: $(($left | ForEach-Object name) -join ', ')." }
"Deleted $($rules.Count) business rule(s) from TDATA and ZDATA; none left."
"""
check_no_rules = """DECLARE @n int = (SELECT COUNT(*) FROM [rule].vDQRule WHERE Entity IN (N'TDATA', N'ZDATA'));
IF @n <> 0 BEGIN DECLARE @msg nvarchar(400) = CONCAT(N'Business rules still on TDATA or ZDATA in the database: ', @n, N'.'); THROW 50021, @msg, 1; END
PRINT N'No business rules on TDATA or ZDATA.';"""
emit('internal', "crud-rules-remove",
     ("What: Delete every business rule on TDATA and ZDATA through the Profisee REST API (never SQL), recycle the instance's pools "
      "and wait for every service, then confirm none is left in the database. Why: a run without business rules measures the same "
      "model without them; the next base restore brings the rules back. When: Never run directly; a measured CRUD workload runs "
      "it right after crud-base-reset when the run passes BusinessRules = false. Needs: crud-base-reset ran just before (the "
      "standard API key is set). Success: Every step Succeeded or Skipped. If it fails: open the first failed step, whose If it "
      "fails text names what to check."),
     ["rules"],
     [steps.ps("Delete Business Rules", rules_remove,
          "What: List the business rules (GET v1/Rules), delete every one on TDATA and ZDATA (DELETE v1/Rules?RuleIds=...), and list "
          "again to prove none is left. Why: the REST API removes a rule with everything Profisee keeps for it; SQL would not. "
          "Success: the last line says none is left (or there was nothing to delete). If it fails: an HTTP code is named: 401 = the "
          "API key (RestKeys:ProfiseeRestKey) is not the one in the database (run crud-base-reset first)."),
      steps.pools_child("Recycle Instance Pools", "Recycle", "services cache the rule set; the run must not apply deleted rules"),
      steps.health_child(),
      steps.sql("Check No Business Rules", check_no_rules,
          "What: Count the business rules left on TDATA and ZDATA in the database. Why: proves the run measures a model without "
          "rules. Success: none left. If it fails: the count is named; rerun the measured workload, which restores its own start.")],
     globals_=g("ApplicationServerName", "DatabaseServerName", "ProfiseeInstanceName", "ProfiseeDatabaseName", "ProfiseeBaseUrl",
                "ProfiseeApiKey"))

# ---------------------------------------------------------------- internal measured runs
RUN_NEEDS = ("Needs: crud-setup ran on this box for this version and these values; the run-start backup of this test exists "
             "(crud-run-start). Success: Every step Succeeded or Skipped. If it fails: open the first failed step, whose If it fails "
             "text names what to check; rerun the whole workload, which restores its own start.")
emit('internal', "crud-core",
     ("What: Restore the run-start backup, delete the business rules when the run passes BusinessRules = false, run the core "
      "TestAuto workflow of the Size passed (Create that many ZDATA records from TDATA, Update 10% and add 5%, Get with 1, 10 and "
      "100 users, Delete what the update touched) and check ZDATA. Why: measures the REST API record operations at one size, with "
      "or without business rules. One workload serves every size: the record count is the row crud/sizes:<Size>, and the workflow "
      "is found by the key crud-<size>-core-<br or nobr>. When: from crud-test; a rerun restores its own start. " + RUN_NEEDS),
     ["core"],
     [reset_child(), rules_remove_child(),
      steps.testauto("Run CRUD Core", CORE_KEY, "the CRUD core run of this size and business-rule mode", SETUP),
      check_core_step()],
     inputs=[SIZE, RULES, RULES_KEY, RECORD_COUNT] + VERSION_CODE + [RUN_START_BACKUP],
     globals_=g(*BOX))

emit('internal', "crud-stewardship",
     ("What: Work out the stewardship form from the values passed (Minutes per step, or Iterations per step when Iterations is "
      "not 0), restore the run-start backup, delete the business rules when the run passes BusinessRules = false, and run the "
      "stewardship TestAuto workflow of that form: 12 interactive stewardship steps on TDATA (15, 30, 60 and 120 attributes with "
      "1, 10 and 100 users). Why: measures interactive record work through the REST API. One workload serves every time and "
      "count: the workflow is found by the key crud-steward-<minutes>min-<br or nobr> or crud-steward-<count>it-<br or nobr>. "
      "When: from crud-test; a rerun restores its own start. " + RUN_NEEDS),
     ["stewardship"],
     [decide_form_step(), reset_child(), rules_remove_child(),
      steps.testauto("Run CRUD Stewardship", STEWARD_KEY, "CRUD stewardship of this time or count and business-rule mode", SETUP)],
     inputs=[SIZE, MINUTES, ITERATIONS, RULES, RULES_KEY] + VERSION_CODE + [RUN_START_BACKUP],
     globals_=g(*BOX, StewardForm=""), notes=FORM_NOTE)

emit('internal', "crud-release",
     ("What: Restore the run-start backup, delete the business rules when the run passes BusinessRules = false, and run the "
      "release TestAuto workflow of the Size passed: the release CRUD load step for step (Create the ZDATA records, Update, Get "
      "with 1, 10 and 100 users, 12 stewardship steps of 60 minutes on TDATA, Delete last) on one model state, then check ZDATA. "
      "Why: the release measurement, comparable with earlier releases. The workflow is found by the key crud-<size>-release-<br "
      "or nobr>; crud/values:ReleaseSizes lists the sizes that have one. When: from crud-test-release; a rerun restores its own "
      "start. " + RUN_NEEDS),
     ["release"],
     [reset_child(), rules_remove_child(),
      steps.testauto("Run CRUD Release", RELEASE_KEY, "the CRUD release run of this size and business-rule mode", SETUP),
      check_core_step()],
     inputs=[RELEASE_SIZE, RULES, RULES_KEY, RECORD_COUNT] + VERSION_CODE + [RUN_START_BACKUP],
     globals_=g(*BOX))

# ---------------------------------------------------------------- start/crud-setup
setup_steps = [
    steps.http_get("ScenarioMgt Check", "{{ScenarioMgtBaseUrl}}v1/Records/TestAutoWorkflow?PageSize=1",
                   "What: List one TestAuto workflow. Why: proves the address and key reach the TestAuto repository before anything "
                   "is written. Success: HTTP 200. If it fails: 401 = wrong ScenarioMgt key (RestClients:ScenarioMgt:ApiKey); 404 = "
                   "wrong address in crud/urls:ScenarioMgtBaseUrl.", headers={"x-api-key": "{{ScenarioMgtApiKey}}"}),
    steps.ps("TestAuto Version Exists", "\n".join([
        "$ErrorActionPreference = 'Stop'",
        "$base = '{{ScenarioMgtBaseUrl}}'.TrimEnd('/') + '/'",
        "$headers = @{ 'x-api-key' = '{{ScenarioMgtApiKey}}'; accept = 'application/json' }",
        "$version = '" + VER + "'",
        "$verFilter = [uri]::EscapeDataString(\"[Code] eq '$version'\")",
        "$v = Invoke-RestMethod -Uri \"${base}v1/Records/ProfiseeVersion?Filter=$verFilter\" -Headers $headers",
        "$rows = if ($v -is [array]) { $v } else { @($v.data) }",
        "if (-not $rows) { throw \"TestAuto version '$version' does not exist in the repository; create it (data.tProfiseeVersion) before running crud-setup.\" }",
        "\"TestAuto version $version exists.\""]),
        "What: Check the TestAuto version of this run (crud/environment:ProfiseeVersionCode, or the lane's) exists in the TestAuto "
        "repository. Why: every workflow step records its results under it. Success: the version exists. If it fails: create the "
        "version in the repository (data.tProfiseeVersion), then rerun crud-setup."),
] + [template_step(t) for t in TEMPLATES.values()]
emit('start', "crud-setup",
     ("What: Create or update the tagged CRUD TestAuto workflows in the TestAuto repository, from three templates and the value "
      "rows in reference data: the core workflow of every size (crud/sizes), the stewardship workflow of every minutes and "
      "iterations value (crud/values:StewardMinutes, StewardIterations) and the release workflow of every release size "
      "(crud/values:ReleaseSizes), each with and without business rules. Why: every CRUD run finds its workflow by automation "
      "tag. When: once per box and Profisee version; after adding a size, a minutes or an iterations row; after any change to a "
      "workflow template. Reruns update in place and never remove a workflow. Needs: the TestAuto version exists in the "
      "repository; TestAuto answers on port 8443. Success: Every step Succeeded; each template step lists its workflows. If it "
      "fails: open the first failed step, whose If it fails text names what to check."),
     ["setup"], setup_steps, inputs=VERSION_CODE,
     globals_=g("ScenarioMgtBaseUrl", "ScenarioMgtApiKey", "TestAutoBaseUrl", "TestAutoEnvironmentName", "TestAutoApplicationServer",
                "TestAutoDatabaseServer"))

# ---------------------------------------------------------------- tests
TEST_TAIL = ("It starts with crud-run-start (restore the base, Profisee Configuration, API key, run-start backup); every measured run "
             "restores that run-start backup. When: Any time after crud-setup has run on this box for this Profisee version; never at "
             "the same time as another test on the same Profisee database (Connect and Matching restore it too). Needs: crud-setup; "
             "the crud/* reference sets filled in; the common and install packs on this box; crud-preflight green. Success: Every "
             "run ends Succeeded; each TestAuto execution holds its metrics. If it fails: It stops at the first failed step: open "
             "that step's output.")
emit('tests', "crud-test",
     ("What: Runs the CRUD test for the values passed: the core run at Size (Create, Update, Get with 1, 10 and 100 users, Delete) "
      "and then stewardship (12 steps) for Minutes per step, or for Iterations per step when Iterations is not 0, with or without "
      "business rules (BusinessRules), each from a fresh restore. Example: crud-test --param Size=1K --param Minutes=1 --param "
      "BusinessRules=false. With no values it runs 1K with business rules and the minutes of crud/default-minutes. Before any "
      "restore it checks the values and that the two TestAuto workflows they need exist. Why: This is the test a person, a "
      "schedule or a round starts; one workload serves every size, time and rule mode, so a new size or time is a reference row, "
      "never a new workload. " + TEST_TAIL),
     [],
     [decide_form_step(),
      steps.tag_check_child("Workflows For These Values Exist", CORE_KEY + "," + STEWARD_KEY, SETUP),
      run_start_child(),
      steps.run_child("Core", "crud-core", "Measured run: CRUD core at the Size passed"),
      steps.run_child("Stewardship", "crud-stewardship", "Measured run: CRUD stewardship for the Minutes or Iterations passed")],
     inputs=[SIZE, MINUTES, ITERATIONS, RULES, RULES_KEY] + VERSION_BOTH + [BASE_BACKUP, RUN_START_BACKUP],
     globals_=g(*BOX, StewardForm=""), notes=FORM_NOTE)

emit('tests', "crud-test-release",
     ("What: Runs the CRUD release test for the values passed: one restore of the CRUD base, then the release CRUD load step for "
      "step at Size (default 1M: Create the ZDATA records, Update, Get with 1, 10 and 100 users, 12 stewardship steps of 60 "
      "minutes, Delete last), with or without business rules (BusinessRules). Example: crud-test-release --param "
      "BusinessRules=false. Before any restore it checks the release TestAuto workflow for these values exists. Why: This is the "
      "release measurement a person starts; the same steps and order as earlier releases' CRUD runs, so results compare. "
      + TEST_TAIL),
     ["release"],
     [steps.tag_check_child("Workflow For These Values Exists", RELEASE_KEY, SETUP),
      run_start_child(),
      steps.run_child("Release", "crud-release", "Measured run: the CRUD release load at the Size passed (18 steps, one restore)")],
     inputs=[RELEASE_SIZE, RULES, RULES_KEY] + VERSION_BOTH + [BASE_BACKUP, RUN_START_BACKUP],
     globals_=g(*BOX))

# ---------------------------------------------------------------- schedule/schedule-crud
def sched(field):
    return "{{$ref:crud/schedule:{{Schedule}}.%s}}" % field


emit('schedule', "schedule-crud",
     ("What: Create or update the Windows scheduled task '\\CrewChief\\schedule-crud-<Schedule>' for the schedule passed "
      "(Schedule, e.g. 1k-br): the task runs the workload in the row crud/schedule:<Schedule>.Target with the values in "
      "<Schedule>.Values, weekly on <Schedule>.Days at <Schedule>.Time, from the CrewChief CLI. Example: schedule-crud --param "
      "Schedule=10k-nobr. Nothing is scheduled until it runs; run it again after changing a row. Why: lets a test repeat without "
      "a person; one workload serves every schedule, so a new schedule is four reference rows. When: once per schedule to create "
      "or update its task, and again after changing its rows or a global. Needs: crud-setup ran on this box; the secret "
      "Scheduler:RunAsPassword. Success: Every step Succeeded or Skipped. If it fails: open the first failed step, whose If it "
      "fails text names what to check."),
     [],
     [{"label": "Apply Schedule", "inline": {
         "action": "Apply", "taskName": "schedule-crud-{{Schedule}}", "targetWorkload": sched('Target'),
         "targetParameters": sched('Values'), "cliPath": "{{CliPath}}", "dataFolder": "{{DataFolder}}", "startDate": "{{StartDate}}",
         "startTime": sched('Time'), "recurrence": "{{Recurrence}}", "interval": "{{Interval}}", "daysOfWeek": sched('Days'),
         "endDate": "", "runAsAccount": "{{RunAsAccount}}", "runAsPassword": "{{$config:Scheduler:RunAsPassword}}",
         "runElevated": True, "type": "ScheduleTaskStep", **steps.BASE, "timeoutSeconds": 120,
         "description": ("What: Create or update the scheduled task of the schedule passed. Why: puts the run on the Windows Task "
                         "Scheduler so it repeats without a person. Success: Task Scheduler holds the task under \\CrewChief with "
                         "the day, time, workload and values of the schedule's rows. If it fails: a row of the schedule is missing "
                         "in crud/schedule (the message names it); or check the run-as account and its password secret "
                         "(Scheduler:RunAsPassword) and that the CrewChief CLI path in the globals exists.")}}],
     inputs=[value_input("Schedule", "1k-br", "Name of the schedule to apply: the start of its four rows in crud/schedule "
                                              "(<Schedule>.Target, .Values, .Days, .Time).")],
     globals_={"CliPath": "C:\\Deploy\\CrewChief\\cli\\crewchief.exe", "DataFolder": "C:\\Deploy\\CrewChief\\web\\data",
               "StartDate": "2026-11-09", "Recurrence": "Weekly", "Interval": "1", "RunAsAccount": "CORP\\speedmerchants"},
     notes=("Day, time, workload and values of a schedule are rows in crud/schedule. StartDate, Recurrence (Once, Daily, Weekly) "
            "and Interval are globals here. Every CRUD, Connect and Matching schedule restores the same Profisee database: "
            "defaults are Monday-Friday (Matching takes Sunday, Connect Saturday 02:00); never let two overlap, and start no "
            "manual run while one is due."))

# ---------------------------------------------------------------- start/crud-preflight
state_sql = """DECLARE @tdata bigint = (SELECT SUM(p.rows) FROM sys.partitions p WHERE p.object_id = OBJECT_ID(N'data.tTDATA') AND p.index_id IN (0, 1));
DECLARE @zdata bigint = (SELECT SUM(p.rows) FROM sys.partitions p WHERE p.object_id = OBJECT_ID(N'data.tZDATA') AND p.index_id IN (0, 1));
IF @tdata IS NULL OR @zdata IS NULL BEGIN PRINT N'TDATA or ZDATA does not exist: the Profisee database holds another pack''s model now (normal after a Connect or Matching run). Every CRUD run restores the base backup first.'; RETURN; END
DECLARE @rulesT int = (SELECT COUNT(*) FROM [rule].vDQRule WHERE Entity = N'TDATA');
DECLARE @rulesZ int = (SELECT COUNT(*) FROM [rule].vDQRule WHERE Entity = N'ZDATA');
PRINT CONCAT(N'Profisee database now: TDATA ', @tdata, N' rows, ZDATA ', @zdata, N' rows, business rules TDATA ', @rulesT, N', ZDATA ', @rulesZ, N'. Every CRUD run restores the base first, so a dirty state here is not a failure.');"""
HTTP_RESULT = ("Success: The response status is 200. If it fails: 401 = the API key secret is wrong; 404 = the address is wrong; "
               "no response = the server in the URL (crud/urls, crud/machines) is down.")
emit('start', "crud-preflight",
     ("What: Checks this box is ready for CRUD testing: the instance's application pools exist and run, the CRUD base backup of "
      "this version is on the database server, the current Profisee database state, TestAuto and its repository answer, the "
      "standard API key is set and works through the gateway and the Data service (common-api-key-set), and every TestAuto "
      "workflow crud-setup creates for the value rows now in reference data sits on exactly one workflow. CrewChief's own pre-run "
      "check first proves every crud/* reference value it uses is filled in. Why: finds every environment problem in one run, "
      "before a test fails half way through. When: before and after crud-setup, after any reference data change, after a "
      "Profisee upgrade, before every round, and first whenever a test fails; never while a test runs on this application "
      "server. Needs: the crud/* reference sets, the common pack and the box's secrets; the API user exists in the Profisee "
      "database. It changes only two things: the pool step starts a pool that is stopped, and the key step writes the standard "
      "API key and restarts IIS (pack standard: the key is set before any gateway query). Only one test may use this application "
      "server's Profisee database at a time: Connect, Matching and CRUD all restore it. Success: Every step Succeeded or Skipped; "
      "before the first crud-setup the workflow step says \"not created yet\", normal. If it fails: each step's failure text "
      "names the reference key, secret or machine to fix; fix reference data or the box, never a workload file."),
     [],
     [steps.pools_child("Application Pools Exist", "Start",
                        "a reset fails half way when the instance has no pools or one will not start; this finds it first"),
      steps.backup_check_child("CRUD Base Backup Exists", "{{BaseBackupFileName}}", "crud-base-create"),
      steps.sql("Profisee Database State", state_sql,
          "What: Print the current TDATA and ZDATA row counts and business rule counts of the Profisee database, or say it holds "
          "another pack's model. Why: shows what a person would find in the portal; the runs restore the base anyway, so this "
          "step informs and never fails on the model state. Success: one line says what the database holds. If it fails: the "
          "database server (crud/machines:DatabaseServerName) or the Profisee database is unreachable with Windows authentication."),
      steps.http_get("TestAuto Answers", "{{TestAutoBaseUrl}}/api/workflows/by-tag?tag=AUTO%3Apreflight",
          "What: Ask TestAuto on this box (crud/machines:TestServerNameFQDN, port 8443) for workflows tagged with a probe tag. "
          "Why: every CRUD run finds its TestAuto workflow by tag through this call. " + HTTP_RESULT, verify_ssl=False, max_time=120),
      steps.http_get("TestAuto Model Answers", "{{ScenarioMgtBaseUrl}}v1/Records/TestAutoWorkflow?PageSize=1",
          "What: Read one TestAuto workflow record from the TestAuto repository (crud/urls:ScenarioMgtBaseUrl) with the "
          "RestClients:ScenarioMgt:ApiKey secret. Why: crud-setup writes the workflows through it. " + HTTP_RESULT,
          headers={"x-api-key": "{{ScenarioMgtApiKey}}"}, max_time=120),
      steps.wait_runs(),
      steps.key_set_child(),
      specs.keys_step("List The Workflows Setup Creates", key_patterns(),
          "What: Work out, from the value rows now in reference data (crud/sizes, crud/values), the key of every TestAuto workflow "
          "crud-setup creates, with the same loops crud-setup uses, into the run parameter SetupTagKeys. Why: the next step checks "
          "each of them; the list is never typed, so it cannot fall behind a new size or time. Success: one line of keys. If it "
          "fails: a value row is empty or malformed; the message names it.", setup_name=SETUP, output="SetupTagKeys"),
      steps.tag_check_child("Every Workflow Found Once", "{{SetupTagKeys}}", SETUP, allow_none=True)],
     inputs=VERSION_CODE + [BASE_BACKUP],
     globals_=g(*BOX, "ScenarioMgtBaseUrl", "ScenarioMgtApiKey", SetupTagKeys=""),
     notes="SetupTagKeys is set by the step List The Workflows Setup Creates during the run; it starts blank and is never passed.")

# ---------------------------------------------------------------- start/crud-base-create (D18)
# Makes the base of a Profisee version: restore the seed (the same or an older version), run Profisee Configuration on it, back
# it up under the versioned name. P1 (Gene 11/10): when this version's base already exists the workload ends GREEN and touches
# nothing: a PowerShell step captures "true" (base missing) or "false" into the run parameter BaseMissing and every step after
# the check carries runWhen {{BaseMissing}} (blank or "false" = skip). BaseMissing starts as "false": a capture that never
# happens can only skip steps, never overwrite a base.
check_base_ps = r"""$ErrorActionPreference = 'Stop'
$file = '{{BaseBackupFileName}}'
$c = New-Object System.Data.SqlClient.SqlConnection 'Server={{DatabaseServerName}};Database=master;Integrated Security=True;TrustServerCertificate=True;Connect Timeout=30'
$c.Open()
try {
    $q = $c.CreateCommand()
    $q.CommandText = "DECLARE @dir nvarchar(400) = CAST(SERVERPROPERTY('InstanceDefaultBackupPath') AS nvarchar(400)); DECLARE @exists int, @f nvarchar(600) = @dir + N'\' + @file; EXEC master.dbo.xp_fileexist @f, @exists OUTPUT; SELECT @exists;"
    [void]$q.Parameters.AddWithValue('@file', $file)
    $exists = [int]$q.ExecuteScalar()
}
finally { $c.Close() }
if ($exists -eq 1) { 'false' } else { 'true' }"""
report_base_ps = r"""if ('{{BaseMissing}}' -eq 'true') {
    "No CRUD base {{BaseBackupFileName}} for version {{ProfiseeVersionCode}} on {{DatabaseServerName}} yet; it will be made."
} else {
    "CRUD base {{BaseBackupFileName}} for version {{ProfiseeVersionCode}} already exists; nothing done."
}"""
SKIP_BASE = "the CRUD base of this version already exists (the check step found it), so there is nothing to make"


def when_missing(step):
    return steps.gated(step, "{{BaseMissing}}", SKIP_BASE)


configure_seed = steps.run_child("Configure The Restored Seed", "install-configure-upgrade", "", timeout=7500, description=(
    "What: Run Profisee Configuration on the restored seed (install pack building block install-configure-upgrade: upgrade, "
    "keeps the data). Why: the seed may come from an older Profisee version; Configuration upgrades it to the version under test "
    "and writes this application server's service sign-in ids. Success: The child workload ends with every step Succeeded. "
    "If it fails: Open the run output of 'install-configure-upgrade'; Configuration's log is quoted there. A seed from a newer "
    "version than the installed Profisee cannot be used (Configuration only upgrades)."))
emit('start', "crud-base-create",
     ("What: Make the CRUD base of one Profisee version: restore the seed backup (crud/databases:BaseSeedBackupFileName), run "
      "Profisee Configuration on it (install-configure-upgrade), wait for every service, set and prove the API key "
      "(common-api-key-set), check the base state and back it up under the versioned name (crud/databases:BaseBackupStem, the "
      "version code, .bak). When that base already exists it skips everything after the check, prints that nothing was done and "
      "ends green; it never overwrites a base. Why: a lane of a new Profisee version has no base yet; every CRUD test restores "
      "it. When: once per box and version, after the Profisee of that version is installed (run it before crud-setup; a round "
      "starts it first); crud-preflight says when the base is missing. Needs: the seed is the CRUD base of the same or an older "
      "version (Configuration only upgrades); the install and common packs on this box; no test running against this Profisee "
      "database. Success: Every step Succeeded or Skipped. If it fails: open the first failed step, whose If it fails text names "
      "what to check."),
     ["base-create"],
     [steps.wait_runs(),
      steps.ps("Check Whether The Base Exists", check_base_ps,
          "What: Look for the CRUD base of this version (crud/databases:BaseBackupStem, the version code, .bak) in the SQL Server default "
          "backup folder of crud/machines:DatabaseServerName and keep the answer in the run parameter BaseMissing (true = no base yet). "
          "Why: a base is made once and never overwritten; every test restores it, so when it exists every later step is skipped and the "
          "run ends green. Success: the step ends without an error (it does not fail when the base exists). If it fails: the database "
          "server does not answer, or the CrewChief account cannot connect to master there.", timeout=120, output="BaseMissing"),
      steps.ps("Report The Base State", report_base_ps,
          "What: Print whether the CRUD base of this version already exists (nothing done) or will be made. Why: the run output then says "
          "plainly why every later step is Skipped. Success: one line is printed. If it fails: the script cannot fail by itself; open the "
          "run output of the check step before it.", timeout=60),
      when_missing(steps.instance_stop_child("a restore must not run under services that hold connections and caches")),
      when_missing(steps.db_step("Restore Seed Backup", "RestoreDatabase", "{{BaseSeedBackupFileName}}",
          "What: Restore the seed backup (crud/databases:BaseSeedBackupFileName) over the Profisee database WITH REPLACE. "
          + RESTORE_NOTE + " Why: it holds the CRUD model (TDATA full, ZDATA empty, business rules on both) of the same or an older "
          "version. Success: restored (about 6 minutes). If it fails: the seed is missing from the SQL Server default backup folder "
          "of crud/machines:DatabaseServerName, or the CrewChief account is not sysadmin there.")),
      when_missing(steps.instance_start_child("Configuration expects a running instance")),
      when_missing(configure_seed),
      when_missing(steps.health_child("Wait For Every Service After Configuration")),
      when_missing(steps.key_set_child()),
      when_missing(check_base_step()),
      when_missing(steps.db_step("Back Up The Base", "BackupDatabase", "{{BaseBackupFileName}}",
          "What: Back up the configured database as the CRUD base of this version (crud/databases:BaseBackupStem, the version code, .bak). "
          "Why: every CRUD test of this version restores it. Success: written (file date now). If it fails: the SQL Server service "
          "account cannot write its default backup folder, or the disk is full."))],
     inputs=VERSION_BOTH + [BASE_BACKUP],
     globals_=g(*BOX, "BaseSeedBackupFileName", BaseMissing="false"),
     notes=("BaseMissing is set by the check step during the run (true or false); it starts as false so a step that never got its "
            "answer is skipped, never run."))

# ---------------------------------------------------------------- rounds (plan lines carry values: <workload> Name=Value ...)
rounds = os.path.join(root, 'rounds')
os.makedirs(rounds, exist_ok=True)
RUN = "# Run: bash ../../tools/runner/run-queue.sh <CrewChief box> {f}  (one test at a time per Profisee database: Connect, Matching and CRUD all restore it)\n"
RETIRED_LINE = re.compile(r'(?m)^\+?\s*crud-test-(smoke|proof|\d+[km]-)')


def round_file(name, text):
    """A round is a person's file once it exists: written when missing, or when it still names a retired workload."""
    path = os.path.join(rounds, name)
    if os.path.exists(path) and not RETIRED_LINE.search(open(path, encoding='utf-8').read()):
        return
    with open(path, 'w', encoding='utf-8', newline='\n') as f:
        f.write(text)


NO_PLUS = "# No '+': each test restores the base, so a failed one does not stop the next.\n\n"
round_file('smoke.txt',
    "# Smoke test: 1K core and 1-minute stewardship without business rules, so the rule removal runs too. Use it after a move to a new machine or an upgrade.\n"
    + RUN.format(f='smoke.txt') + "# A line is a workload and the values it gets: <workload> Name=Value Name=Value\n\n"
    "crud-test Size=1K Minutes=1 BusinessRules=false\n")
round_file('proof-round.txt',
    "# Proof round: every form at 1K (core, then stewardship 1 minute or 10 iterations; each with and without business rules). Use it after a pack or TestAuto change.\n"
    + RUN.format(f='proof-round.txt') + NO_PLUS
    + "".join(f"crud-test Size=1K {form} BusinessRules={r}\n" for form in ("Minutes=1", "Iterations=10") for r in ("true", "false")))
round_file('check-round.txt',
    "# Mid-release check: 1K, 10K and 100K, with and without business rules (each core run plus stewardship for the minutes in crud/default-minutes).\n"
    + RUN.format(f='check-round.txt') + NO_PLUS
    + "".join(f"crud-test Size={s} BusinessRules={r}\n" for s in ("1K", "10K", "100K") for r in ("true", "false")))
round_file('release-round.txt',
    "# Release round: 1M with and without business rules (core plus 60-minute stewardship, one restore each), the release CRUD load.\n"
    + RUN.format(f='release-round.txt') + NO_PLUS
    + "crud-test-release Size=1M BusinessRules=true\ncrud-test-release Size=1M BusinessRules=false\n")

count = sum(len(files) for _d, _s, files in os.walk(wl_root))
print(f"crud pack written: {count} workloads, {len(TEMPLATES)} TestAuto workflow templates")
