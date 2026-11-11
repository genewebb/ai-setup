"""Builds the whole CrewChief CRUD pack (CrewChief/packs/crud) on the Matching pack blueprint.

  reference-kv/crud/       machines, instances, databases, environment, urls, workflows
  start/                   crud-preflight (checks only), crud-setup (the 18 tagged TestAuto workflows)
  internal/shared/         crud-run-start (once per test: restore profisee_CRUD_base.bak, Configuration, key, checks,
                           back up profisee_CRUD_run-start.bak), crud-base-reset (restore the run-start backup, key,
                           IIS restart, health, base check),
                           crud-rules-remove (delete every TDATA/ZDATA business rule through REST)
  internal/<size>/         crud-<size>-core-{br,nobr}: Create, Update, Get 1/10/100 users, Delete on ZDATA
  internal/steward/        crud-steward-<form>-{br,nobr}: 12 stewardship steps (form = 1/5/15/30/60min or 10/100/1000it) on TDATA (4 widths x 1/10/100 users)
  tests/                   crud-test-<size>-{br,nobr} (core + stewardship), crud-test-smoke
  rounds/                  smoke.txt, check-round.txt, release-round.txt

Source of the TestAuto step configs: PROD workflows 10000195 (no rules) and 10000197 (with rules), read 11/07/2026:
18 steps (Create, Update, Get x3, Stewardship x12, Delete). Changes: sizes, stewardship duration (TimeLimit), every
stewardship step reads TDATA (PROD steps 10-13 read PDATA), WorkloadExecution blank, version and machines from
reference data. Business rules: the base backup carries 10 rules on TDATA and 10 on ZDATA; a no-rules run restores
it and deletes them through REST (DqRuleCount 0 vs 10, as PROD records them).

Usage: python gen_crud.py <packRoot>      (e.g. C:\\devops\\repos\\speed-merchants\\CrewChief\\packs\\crud)
"""
import copy, json, os, sys

root = sys.argv[1]
here = os.path.dirname(os.path.abspath(__file__))
FAM = 'crud'
ref_dir = os.path.join(root, 'reference-kv', FAM)
wl_root = os.path.join(root, 'workloads', FAM)
# Service and pool steps (Gene 11/10): found on the server, never named; one shared builder for every pack.
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(root)), 'tools'))
import instance_steps  # noqa: E402

SIZES = {'1K': 1000, '10K': 10000, '100K': 100000, '1M': 1000000}
# Stewardship forms: each of the 12 steps runs for a time (TimeLimit) or for a set number of iterations (TimeLimit 0,
# IterationLimit N; Gene 11/07: counts 10, 100 and 1000). key suffix -> (TimeLimit, IterationLimit, short text, long text)
STEWARD_FORMS = {}
for _d in (1, 5, 15, 30, 60):
    STEWARD_FORMS[f"{_d}min"] = ("00:59:59" if _d == 60 else f"00:{_d:02d}:00", "0", f"{_d} min",
                                 f"{_d} minute(s) per step, about {12 * _d} minutes in all")
for _n in (10, 100, 1000):
    STEWARD_FORMS[f"{_n}it"] = ("00:00:00", str(_n), f"{_n} iterations",
                                f"{_n} iterations per step (each: one page read, one create, update or delete, a 1 second pause)")
# The stewardship form each size's test pairs with: short sizes give a short test, 1M is the 18-step release run.
TEST_FORM = {'1K': '5min', '10K': '15min', '100K': '30min', '1M': '60min'}
MODES = {'br': ('With Business Rules', 10), 'nobr': ('No Business Rules', 0)}
WIDTHS = [(15, 10, 5), (30, 20, 10), (60, 40, 20), (120, 70, 50)]  # (attributes, freeform, domain-based)
USERS = [1, 10, 100]
MIN_TDATA = 10000000


def dump(path, obj):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'w', encoding='utf-8') as f:
        json.dump(obj, f, indent=2)


def ref(s, k):
    return "{{$ref:%s/%s:%s}}" % (FAM, s, k)


# Version keys (decisions D11, D12): a root (a workload no workload runs) reads each from reference data in its own global
# of the same name, or takes it from the caller (a TestAutoManager lane passes it as --param); every workload below a root
# declares the ones it uses as inputs and gets the value from its parent. Backup names are composed in the roots.
VER = "{{ProfiseeVersionCode}}"
ENV_KEYS = ("ProfiseeVersionCode", "ProfiseeVersionNumber")
VERSION_GLOBALS = {k: ref('environment', k) for k in ENV_KEYS}
BACKUP_GLOBALS = {"BaseBackupFileName": ref('databases', 'BaseBackupStem') + "_" + VER + ".bak",
                  "RunStartBackupFileName": ref('databases', 'RunStartBackupStem') + "_" + VER + ".bak"}
INPUT_TEXT = {
    "ProfiseeVersionCode": "TestAuto version code (data.tProfiseeVersion) the runs are recorded under and the automation tags carry. Passed by the test that runs this one (crud/environment:ProfiseeVersionCode, or the lane's version).",
    "ProfiseeVersionNumber": "Product version of the release under test (n.n.n), handed to install-configure-upgrade. Passed by the test that runs this one (crud/environment:ProfiseeVersionNumber, or the lane's version).",
    "BaseBackupFileName": "File name of the CRUD base backup of this version (crud/databases:BaseBackupStem, an underscore, the version code, .bak). Composed by the test that runs this one.",
    "RunStartBackupFileName": "File name of the run-start backup of this version (crud/databases:RunStartBackupStem, an underscore, the version code, .bak). Composed by the test that runs this one.",
}


# Hand runs (Gene 11/10): every input carries a "default" (used only when no caller supplies the value): the reference data the
# roots read, and the same composition for the backup names (the version code inside resolves after the input itself).
INPUT_DEFAULTS = {**VERSION_GLOBALS, **BACKUP_GLOBALS}


def inputs_for(*names):
    return [(n, INPUT_TEXT[n]) for n in names]


def root_globals(*names):
    """Root globals for the version keys (and composed backup names) a root or its tree uses."""
    out = {}
    for n in names:
        out[n] = VERSION_GLOBALS[n] if n in VERSION_GLOBALS else BACKUP_GLOBALS[n]
    return out

# ---------------------------------------------------------------- reference sets
def core_key(low, m): return f"crud-{low}-core-{m}"
def stew_key(f, m): return f"crud-steward-{f}-{m}"
def release_key(m): return f"crud-1m-release-{m}"


wf_entries, wf_desc = {}, {}
for label in SIZES:
    for m, (mtext, _) in MODES.items():
        k = core_key(label.lower(), m)
        wf_entries[k] = f"CRUD {label} Core {mtext}"
        wf_desc[k] = (f"Display name of the TestAuto workflow for the {label} CRUD core run {mtext.lower()} (Create, Update, Get with "
                      f"1, 10 and 100 users, Delete on ZDATA). Its automation tag is AUTO:<this box>:<ProfiseeVersionCode>:{k}; "
                      "the name is free text and only for people.")
for m, (mtext, _) in MODES.items():
    k = release_key(m)
    wf_entries[k] = f"CRUD 1M Release {mtext}"
    wf_desc[k] = (f"Display name of the TestAuto workflow for the 1M CRUD release run {mtext.lower()}: the release CRUD load step for "
                  "step (Create, Update, Get with 1, 10 and 100 users, 12 stewardship steps of 60 minutes, Delete last) on one model "
                  f"state. Its automation tag is AUTO:<this box>:<ProfiseeVersionCode>:{k}; the name is free text and only for people.")
for f, (_, _, short, long_) in STEWARD_FORMS.items():
    for m, (mtext, _) in MODES.items():
        k = stew_key(f, m)
        wf_entries[k] = f"CRUD Stewardship {short} {mtext}"
        wf_desc[k] = (f"Display name of the TestAuto workflow for CRUD stewardship {mtext.lower()}: 12 steps on TDATA (15, 30, 60 and "
                      f"120 attributes with 1, 10 and 100 users), {long_}. Its automation tag is "
                      f"AUTO:<this box>:<ProfiseeVersionCode>:{k}; the name is free text and only for people.")

REF_SETS = {
    'machines': {"description": "CRUD pack: machine names. Short name for SQL; FQDN for HTTPS. One application server, one test server and one database server; CRUD never crosses servers.",
                 "includeInReplacements": True,
                 "entries": {"ApplicationServerName": "SMVM1", "ApplicationServerNameFQDN": "smvm1.corp.profisee.com",
                             "DatabaseServerName": "smvmdb1", "TestServerName": "smvmtr1", "TestServerNameFQDN": "smvmtr1.corp.profisee.com"},
                 "keyDescriptions": {
                     "ApplicationServerName": "Short name of the machine the Profisee portal under test runs on; application pool and service steps target it, and TestAuto records it as the application server.",
                     "ApplicationServerNameFQDN": "Fully qualified name of the Profisee application server; HTTPS calls (gateway, health, rules) use it.",
                     "DatabaseServerName": "SQL Server holding the Profisee database under test; the base backup is restored there from its default backup folder.",
                     "TestServerName": "Machine running TestAuto (short name). CRUD writes the application server, not this, as each TestAuto step's environment name, as the release CRUD history does.",
                     "TestServerNameFQDN": "Fully qualified name of the TestAuto machine; CrewChief calls TestAuto on port 8443 there."}},
    'instances': {"description": "CRUD pack: Profisee instance name (the IIS application path).", "includeInReplacements": True,
                  "entries": {"ProfiseeInstanceName": "profisee"},
                  "keyDescriptions": {"ProfiseeInstanceName": "IIS application path of the instance under test, as in https://<server>/<instance>; also the prefix of its application pools."}},
    'databases': {"description": "CRUD pack: database and backup names. CRUD has no source database: its source entity TDATA (10M rows) lives in the Profisee database itself.",
                  "includeInReplacements": True,
                  "entries": {"ProfiseeDatabaseName": "Profisee", "BaseBackupStem": "profisee_CRUD_base",
                              "RunStartBackupStem": "profisee_CRUD_run-start",
                              "BaseSeedBackupFileName": "profisee_CRUD_base.bak"},
                  "keyDescriptions": {
                      "ProfiseeDatabaseName": "The Profisee database of the instance under test; every CRUD test restores it (base backup once per test run, then the run-start backup before each measured run).",
                      "BaseBackupStem": "Start of the file name (no folder) of the CRUD base backup of a Profisee version: the pack adds an underscore, the version code and .bak (profisee_CRUD_base_<code>.bak) and looks for it in the SQL Server default backup folder of the database server: TDATA with at least 10M rows, ZDATA empty, 10 business rules on each. Never overwritten: every test run restores it, runs Profisee Configuration on it and backs up a run-start copy (crud-run-start). Made once per version by crud-base-create.",
                      "RunStartBackupStem": "Start of the file name (no folder) of the run-start copy of a Profisee version (profisee_CRUD_run-start_<code>.bak) crud-run-start writes in the SQL Server default backup folder at the start of every CRUD test: the base after Configuration on this application server and the standard API key. crud-base-reset restores it before each measured run of that test. Rewritten by every test; never copy it to another box.",
                      "BaseSeedBackupFileName": "File name (no folder) of the backup crud-base-create restores to make the base of a new version: the CRUD base of the same or an older Profisee version (Configuration only upgrades). Today's unversioned base file; it is only read, never written."}},
    'environment': {"description": "CRUD pack: what differs between Profisee releases and boxes. Edit after every Profisee upgrade.",
                    "includeInReplacements": True,
                    "entries": {"ProfiseeVersionCode": "26R3T", "MainMachineTag": "SMVM1",
                                "ProfiseeVersionNumber": "26.3.0"},
                    "keyDescriptions": {
                        "ProfiseeVersionNumber": "Product version of the release under test (n.n.n); crud-run-start passes it to the install pack's install-configure-upgrade, which finds the Configuration program under it. A TestAutoManager lane passes its own.",
                        "ProfiseeVersionCode": "TestAuto version code (data.tProfiseeVersion) the runs are recorded under; also part of every automation tag.",
                        "MainMachineTag": "Plain tag naming the machine the runs measure; added to every CRUD TestAuto workflow."}},
    'urls': {"description": "CRUD pack: REST addresses.", "includeInReplacements": True,
             "entries": {"ScenarioMgtBaseUrl": "https://profiseecloud.dev/speedmerchantstest/rest/"},
             "keyDescriptions": {"ScenarioMgtBaseUrl": "REST address of the TestAuto repository (ScenarioMgt) the local TestAuto reads; crud-setup writes the workflows there."}},
    'workflows': {"description": "CRUD pack: display names of the tagged TestAuto workflows (one key per workflow; the key is the end of its automation tag).",
                  "includeInReplacements": True, "entries": wf_entries, "keyDescriptions": wf_desc},
}
for name, obj in REF_SETS.items():
    dump(os.path.join(ref_dir, name + '.json'), obj)

# ---------------------------------------------------------------- TestAuto step configs (PROD 10000195/10000197 shape)
REST_AREAS = ("Profisee", "Metrics", "Connect", "Portal", "Matching")
CS_AREAS = ("Profisee", "Metrics", "Matching", "Connect", "Portal", "Data", "TestAuto")
DEFAULT_QUERY = {"SelectAttributes": "", "SortAttributes": "", "Filter": "", "QueryParameters": {}}


def scenario(name, src, tgt, ff, da, batch, users, custom, limit, dq, tme="RecordApiExecution", query=None):
    cfg = {
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
        "ScenarioEnvironment": {"DqRuleCount": dq, "TargetEnvironment": "IaaS",
                                "TargetEnvironmentName": "{{TestAutoEnvironmentName}}", "TargetMetricEntity": tme,
                                "WorkloadExecution": "", "ProfiseeVersion": VER,
                                "TargetApplicationServer": "{{TestAutoApplicationServer}}",
                                "TargetDatabaseServer": "{{TestAutoDatabaseServer}}", "ExecutionMode": "B",
                                "HangfireJob": 0, "SimulatedUserThreadId": 0},
    }
    text = json.dumps(cfg, indent=2).replace('\n', '\r\n')
    # The repository attribute holds 4000 characters; a longer value is stored as NULL without an error.
    if len(text) > 4000:
        text = json.dumps(cfg, separators=(',', ':'))
    assert len(text) <= 4000, f'{name}: configuration is {len(text)} characters even compact; the repository holds 4000'
    return text


def core_details(n, m):
    mtext, dq = MODES[m]
    users_txt = {1: "1 User", 10: "10 Users", 100: "100 Users"}
    d = [("CreateRecordsByPageAndBatch",
          f"Create {n} ZDATA records from TDATA through the REST API, 1000 per batch, one user.",
          scenario("CreateRecordsByPageAndBatchScenario", "TDATA", "ZDATA", 70, 50, 1000, 1,
                   {"OffsetCode": False, "OffsetCodeBy": 0}, n, dq)),
         ("UpdateRecordsByPageAndBatch",
          "Update the ZDATA records: 10% changed (Name gets '_Changed'), 5% new (Code ends '_New'), Name and Code otherwise kept.",
          scenario("UpdateRecordsByPageAndBatchScenario", "TDATA", "ZDATA", 70, 50, 1000, 1,
                   {"UpdateRecordPercent": "10", "NewRecordPercent": "5", "UseMutationHelper": "false",
                    "MutationStrategy": "Not Used", "UpdateIncludedAttributes": [], "UpdateExcludedAttributes": ["Name", "Code"],
                    "TransformSeed": 12345}, n, dq))]
    for u in USERS:
        d.append((f"GetRecordsByPageAndBatchSeqScenario {users_txt[u]} {mtext}",
                  f"Read the ZDATA records page by page through the REST API with {u} simulated user(s).",
                  scenario("GetRecordsByPageAndBatchSeqScenario", "TDATA", "ZDATA", 70, 50, 1000, u, {}, n, dq)))
    d.append(("DeleteRecordsByPageAndBatch",
              "Delete the ZDATA records the update touched (Code contains '_New' or Name contains '_Changed'), 500 per batch.",
              scenario("DeleteRecordsByPageAndBatchScenario", "ZDATA", "ZDATA", 70, 50, 500, 1, {}, n, dq,
                       query={"SelectAttributes": "", "SortAttributes": "",
                              "Filter": "Contains([Code], '_New') OR Contains([Name], '_Changed')", "QueryParameters": {}})))
    return d


def stew_details(form, m):
    mtext, dq = MODES[m]
    limit, iterations, _, _ = STEWARD_FORMS[form]
    span = f"for {iterations} iterations" if iterations != "0" else f"for {STEWARD_FORMS[form][2].replace(' min', '')} minute(s)"
    out = []
    for u in USERS:
        for attrs, ff, da in WIDTHS:
            custom = {"CreateNewRecords": True, "DeleteRecordPercent": 5, "DeleteRecords": True, "HighBatchSize": 1000,
                      "IterationLimit": iterations, "LowBatchSize": 500, "NewRecordPercent": 35, "NumberOfRandomReads": 3,
                      "SleepMaxMs": "1000", "SleepMinMs": "1000", "TimeLimit": limit, "TransformSeed": "12345",
                      "UpdateExistingRecords": True, "UpdateRecordPercent": 60, "UpdateRecordsAvailable": 10000000}
            users = "1 User" if u == 1 else f"{u} Users"
            out.append((f"StewardshipFilterScenario {mtext} {attrs} Attributes {users}",
                        f"Interactive stewardship on TDATA {span}:{attrs} attributes ({ff} freeform, {da} domain-based), "
                        f"{u} simulated user(s) reading, creating, updating and deleting records.",
                        scenario("StewardshipFilterScenario", "TDATA", "TDATA", ff, da, 1000, u, custom, 2, dq,
                                 tme="RecordInteractiveApiExecution",
                                 query={"SelectAttributes": "", "SortAttributes": "Code", "Filter": "[MyNumeric001] gt 1",
                                        "QueryParameters": {"ignoreConstraintRules": "true"}})))
    return out


with open(os.path.join(here, 'connect_upsert_body.ps1.txt'), encoding='utf-8') as f:
    upsert_code = f.read()
upsert_code = upsert_code.replace('{{$ref:connect/environment:ProfiseeVersionCode}}', '{{ProfiseeVersionCode}}') \
                         .replace('connect/environment:ProfiseeVersionCode', f'{FAM}/environment:ProfiseeVersionCode') \
                         .replace('run connect-setup again', 'run crud-setup again') \
                         .replace('$spec = $specJson | ConvertFrom-Json',
                                  "# TestAuto resolves its own step tokens at run time; a spec writes their braces as {% %} so CrewChief leaves them alone.\r\n"
                                  "$specJson = $specJson.Replace('{%', '{{').Replace('%}', '}}')\r\n"
                                  "$spec = $specJson | ConvertFrom-Json")
assert "Replace('{%'" in upsert_code and '{{ProfiseeVersionCode}}' in upsert_code and '$ref:' not in upsert_code, 'upsert code shape changed'


def spec_script(key, plain_tags, measures, runner, details):
    spec = {"Key": key, "Name": ref('workflows', key), "Category": "CRUD", "PlainTags": plain_tags,
            "Description": ("Automation ID: <AUTOMATION_ID>. CrewChief finds this workflow by that tag alone (reference key "
                            f"{FAM}/workflows:{key}); do not edit or remove the tag, and to experiment copy the workflow and remove the "
                            f"tag from the copy. Measures: {measures}, on the Profisee version in {FAM}/environment:ProfiseeVersionCode. "
                            f"Run by the CrewChief workload '{runner}', which restores the CRUD base backup first; running it alone "
                            "measures a model in an unknown state."),
            "Details": [{"Name": n, "Description": d, "ExecutionOrder": i + 1, "ProfiseeVersion": VER, "ScenarioConfiguration": c}
                        for i, (n, d, c) in enumerate(details)]}
    return "$specJson = @'\r\n" + json.dumps(spec, ensure_ascii=False) + "\r\n" + upsert_code


# ---------------------------------------------------------------- step builders
base = {"parameters": {}, "timeoutSeconds": 600, "continueOnError": False, "retryEnabled": False, "maxRetries": 0,
        "retryDelaySeconds": 5, "workingDirectory": None, "notes": ""}
ADMIN = {"credentialSecretName": None, "credentialUserId": "{{$config:UserCredentials:AdminUser}}",
         "credentialPassword": "{{$config:UserCredentials:AdminPassword}}", "remoteAuthentication": "CredSSP"}
PROFISEE_DB = 'Server={{DatabaseServerName}};Database={{ProfiseeDatabaseName}};Integrated Security=True;TrustServerCertificate=True'
MASTER = 'Server={{DatabaseServerName}};Database=master;Integrated Security=True;TrustServerCertificate=True'
with open(os.path.join(here, 'health.ps1'), encoding='utf-8', newline='') as f:
    HEALTH = f.read()


def sql(label, script, desc, conn=PROFISEE_DB, timeout=300):
    return {"label": label, "inline": {**base, "sqlSourceConnectionSecretName": conn, "sqlDestinationConnectionSecretName": conn,
            "sqlCommandTimeoutSeconds": timeout, "sqlAllowNonTransactionalBatches": False, "useTransaction": False,
            "captureScalarResult": False, "sqlScript": script.replace('\r\n', '\n').replace('\n', '\r\n'),
            "autoWrapPassFailCode": True, "dryRun": False, "sqlDropConnections": False, "type": "SqlStep", "description": desc}}


def ps(label, script, desc, timeout=600, output=None):
    """output = name of the run parameter that receives the step's standard output (PowerShellStep outputParameterName)."""
    step = {"label": label, "inline": {**base, "executionPolicy": "Bypass", "preferWindowsPowerShell": False,
            "runAsAdministrator": False, "captureVerbose": False, "captureDebug": False, "treatStderrAsError": True,
            "scriptContent": script.replace('\r\n', '\n').replace('\n', '\r\n'), "type": "PowerShellStep",
            "timeoutSeconds": timeout, "description": desc}}
    if output:
        step["inline"]["outputParameterName"] = output
    return step


def service(label, action, desc):
    """The instance's Windows service, as found by the step Find The Instance Service (added by workload()); desc holds What,
    Why and Success, the failure and skip text is the shared one. No service found = Skipped."""
    return {"label": label, "inline": {**base, "serviceName": instance_steps.SERVICE_TOKEN, "action": action,
            "targetComputer": "{{ApplicationServerName}}", **ADMIN, "type": "ServiceControlStep",
            "runWhen": instance_steps.SERVICE_TOKEN,
            "description": desc + " " + instance_steps.SERVICE_FAILS + " " + instance_steps.SERVICE_SKIPPED}}


def pools(label, action, what, why):
    """The instance's application pools, found on the application server at run time (never a typed list)."""
    return instance_steps.pools_step(label, action, "{{ApplicationServerName}}", FAM, what, why)


IIS_WHY = ("Why: {verb} the Windows service so the next steps work on a quiet or a running Profisee instance, as they need. "
           "Success: The service on the target machine ends in the state the action asks for ({action}). If it fails: Check the "
           "service name exists on the target machine (services.msc) and the admin credential (UserCredentials secrets) can manage "
           "services there over CredSSP.")


def iis(name, action, what):
    """IIS service stop/start, as the Connect pack's API key workload (11/08: a pool recycle left services on the old user)."""
    return {"label": f"{action} {name}", "inline": {**base, "serviceName": name, "action": action,
            "targetComputer": "{{ApplicationServerName}}", **ADMIN, "type": "ServiceControlStep",
            "description": f"What: {what} " + IIS_WHY.format(verb=action, action=action)}}


IIS_STOP = [iis("W3SVC", "Stop", "Stop the World Wide Web Publishing Service on {{ApplicationServerName}} so no worker process keeps the old key."),
            iis("WAS", "Stop", "Stop the Windows Process Activation Service on {{ApplicationServerName}}: every application pool stops with it.")]
IIS_START = [iis("WAS", "Start", "Start the Windows Process Activation Service on {{ApplicationServerName}}."),
             iis("W3SVC", "Start", "Start the World Wide Web Publishing Service on {{ApplicationServerName}}; the application pools start and read the new key.")]

# Why a REST call failed, from its body; shared by every PowerShell step that calls Profisee REST (11/08).
GET_WHY = r"""function Get-Why($resp) {
    # Why a call failed, from its body. A 401 body echoes the API key, so it is never shown; ids and keys are masked.
    if ([int]$resp.StatusCode -eq 401) { return '(401 body not shown)' }
    $t = (([string]$resp.Content) -replace '[0-9a-fA-F]{8}-?[0-9a-fA-F]{4}-?[0-9a-fA-F]{4}-?[0-9a-fA-F]{4}-?[0-9a-fA-F]{12}', '<id>' -replace '\s+', ' ').Trim()
    if ($t.Length -gt 800) { $t = $t.Substring(0, 800) + ' ...' }
    if ($t) { "Body: $t" } else { '(empty body)' }
}
"""


def verify_data_key():
    return {"label": "Verify API Key Through Data Service", "inline": {**base, "retryEnabled": True, "maxRetries": 4, "retryDelaySeconds": 30,
        "url": "{{ProfiseeBaseUrl}}/v1/Rules?PageSize=1", "method": "GET", "headers": {"x-api-key": "{{ProfiseeApiKey}}", "accept": "application/json"},
        "body": "", "outputFile": "", "expectedStatusCodes": [200], "followRedirects": True, "verifySsl": True, "maxTimeSeconds": 300,
        "type": "HTTP",
        "description": ("What: Prove the Data service accepts the API key as a real user: GET v1/Rules?PageSize=1 must return 200. "
                        "Why: the gateway check (v1/Entities) can pass while the Data and Connect services still reject the user "
                        "(400 DATA00030 \"user is not valid\", 403 CNX00080); that only showed up minutes later inside a test. "
                        "Success: 200. If it fails: 400 DATA00030 or 403 = the key is not set for corp\\speedmerchants in this "
                        "database, IIS was not restarted after the restore and the key change, or the restored backup was "
                        "configured before Profisee Configuration last ran on this application server (its service sign-in ids "
                        "are stale): start the run from a crud-test-* workload, whose crud-run-start configures the base first.")}}


def health(label="Start Every Service"):
    return ps(label, HEALTH,
              "What: Wait until every health check of the instance is Healthy. Why: services stay cold after a restore and "
              "recycle; a measured run must not pay for the warm-up. Success: all checks Healthy within 10 minutes. If it fails: "
              "open the health URL ({{MainHealthUrl}}) and fix the service it names.", timeout=900)


def wait_runs():
    return {"label": "Wait For Interrupted Runs", "inline": {**base, "baseUrl": "{{TestAutoBaseUrl}}", "workflowCode": "",
            "executionCode": "", "attachToActiveRun": True, "waitOnly": True, "pollIntervalSeconds": 60, "waitIndefinitely": True,
            "maxConsecutivePollFailures": 30, "ignoreSslErrors": True, "type": "TestAutoWorkflowStep",
            "description": "What: Wait for any TestAuto run already in progress on this box. Why: a restore under a running "
                           "workflow corrupts both. Success: no run is active. If it fails: TestAuto is unreachable on port 8443."}}


def run_tag(label, key, what):
    return {"label": label, "inline": {**base, "baseUrl": "{{TestAutoBaseUrl}}", "workflowCode": "",
            "workflowTag": "AUTO:{{$env:COMPUTERNAME}}:" + VER + ":" + key, "executionCode": "", "attachToActiveRun": True,
            "waitOnly": False, "pollIntervalSeconds": 60, "waitIndefinitely": True, "maxConsecutivePollFailures": 30,
            "ignoreSslErrors": True, "type": "TestAutoWorkflowStep",
            "description": (f"What: Run the TestAuto workflow tagged {key} ({what}) and wait for it. Why: TestAuto measures the run "
                            "and records its metrics. Success: the workflow run Succeeded. If it fails: open the run in TestAuto; "
                            "no workflow with the tag means crud-setup has not run on this box for this version.")}}


def run_child(label, name, what, timeout=172800):
    return {"label": label, "inline": {**base, "workloadName": name, "type": "RunWorkloadStep", "timeoutSeconds": timeout,
            "description": (f"What: {what}. Why: Runs the child workload '{name}' so its tested steps are reused here, not repeated. "
                            "Success: The child workload ends with every step Succeeded or Skipped. "
                            f"If it fails: Open the run output of '{name}'; its first failed step says what to check.")}}


def workload(name, desc, tags, globals_, steps, notes="", inputs=None):
    w = {"name": name, "description": desc, "tags": tags, "globalParameters": globals_, "globalParametersNotes": notes,
         "credentialUserId": None, "credentialPassword": None, "credentialNotes": "", "steps": steps}
    if inputs:
        w["inputs"] = [{"name": n, "description": d, "default": INPUT_DEFAULTS[n]} for n, d in inputs]
    instance_steps.add_service_discovery(w, FAM)
    return w


G = {
    "ApplicationServerName": ref('machines', 'ApplicationServerName'),
    "DatabaseServerName": ref('machines', 'DatabaseServerName'),
    "ProfiseeInstanceName": ref('instances', 'ProfiseeInstanceName'),
    "ProfiseeDatabaseName": ref('databases', 'ProfiseeDatabaseName'),
    "BaseSeedBackupFileName": ref('databases', 'BaseSeedBackupFileName'),
    "ProfiseeBaseUrl": "https://" + ref('machines', 'ApplicationServerNameFQDN') + "/" + ref('instances', 'ProfiseeInstanceName') + "/rest",
    "MainHealthUrl": "https://" + ref('machines', 'ApplicationServerNameFQDN') + "/" + ref('instances', 'ProfiseeInstanceName') + "/rest/health",
    "TestAutoBaseUrl": "https://" + ref('machines', 'TestServerNameFQDN') + ":8443",
    "ScenarioMgtBaseUrl": ref('urls', 'ScenarioMgtBaseUrl'),
    "ScenarioMgtApiKey": "{{$config:RestClients:ScenarioMgt:ApiKey}}",
    "ProfiseeApiKey": "{{$config:RestKeys:ProfiseeRestKey}}",
    "ApiKeyUserName": "{{$config:ConnectRuntime:ApiKeyUserName}}",
    # Gene 11/07: CRUD rows name the application server as their environment, as the release CRUD history does.
    "TestAutoEnvironmentName": ref('machines', 'ApplicationServerName'),
    "TestAutoApplicationServer": ref('machines', 'ApplicationServerName'),
    "TestAutoDatabaseServer": ref('machines', 'DatabaseServerName'),
}


def g(*names, **extra):
    out = {n: G[n] for n in names}
    out.update(extra)
    return out


# ---------------------------------------------------------------- internal/shared/crud-base-reset
def db_step(label, operation, file_token, desc):
    return {"label": label, "inline": {**base, "serverName": "{{DatabaseServerName}}", "connectionSecretName": "", "authMode": "Windows",
        "credentialUserId": "", "credentialPassword": "", "databaseName": "{{ProfiseeDatabaseName}}", "operation": operation,
        "snapshotName": "", "backupFileName": file_token, "fileUncPath": None, "overwrite": True, "relocateFiles": False,
        "waitIndefinitely": True, "dryRun": False, "type": "DatabaseOperationsStep", "timeoutSeconds": 7200, "description": desc}}


def restore_step(label, file_token, desc):
    return db_step(label, "RestoreDatabase", file_token, desc)


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

# ---------------------------------------------------------------- internal/shared/crud-api-key-set (Gene 11/08)
# Standard of every pack: set the standard API key (and restart IIS so every service reads it) before any step queries the
# gateway. A clean Profisee Configuration issues a new key, so a gateway query without this answers 401.
key_set_steps = [
    service("Stop Profisee Service", "Stop", "What: Stop the Profisee Windows service before the key change. Why: it caches the user it signed in with. Success: the service is stopped."),
    *IIS_STOP,
    {"label": "Set API Key", "inline": {**base, "username": "{{ApiKeyUserName}}", "key": "{{ProfiseeApiKey}}", "serverName": "{{DatabaseServerName}}",
        "databaseName": "{{ProfiseeDatabaseName}}", "authMode": "Windows", "credentialUserId": "", "credentialPassword": "",
        "sqlDestinationConnectionSecretName": "", "stripHyphens": True, "type": "SetApiKeyStep",
        "description": ("What: Write the standard API key for the machine's API user (ConnectRuntime:ApiKeyUserName) into meta.tUser. "
                        "Why: TestAuto, the rule removal and every check call the gateway with that key; a clean Profisee Configuration "
                        "issues a new key and a base backup configured on another machine may carry another one. Success: the user row "
                        "is updated. If it fails: the user is missing from meta.tUser; add it in Profisee as a super administrator.")}},
    *IIS_START,
    service("Start Profisee Service", "Start", "What: Start the Profisee Windows service after IIS starts. Why: it must read the new key. Success: the service is running."),
    health(),
    {"label": "Verify API Key Through Gateway", "inline": {**base, "retryEnabled": True, "maxRetries": 4, "retryDelaySeconds": 30,
        "url": "{{ProfiseeBaseUrl}}/v1/Entities", "method": "GET", "headers": {"x-api-key": "{{ProfiseeApiKey}}", "accept": "application/json"},
        "body": "", "outputFile": "", "expectedStatusCodes": [200], "followRedirects": True, "verifySsl": True, "maxTimeSeconds": 300,
        "type": "HTTP",
        "description": "What: Call the gateway with the standard key. Why: proves the key took before anything else uses it. Success: HTTP 200. If it fails: 401 means the key did not take; check the user in meta.tUser and rerun this workload."}},
    verify_data_key(),
]
dump(os.path.join(wl_root, 'internal', 'shared', 'crud-api-key-set.workload.json'), workload(
    "crud-api-key-set",
    ("What: Stop the Profisee service and IIS on the application server, write the standard API key (RestKeys:ProfiseeRestKey) "
     "for the API user (ConnectRuntime:ApiKeyUserName) into the Profisee database, start IIS and the service, wait for every "
     "service, and prove the key through the gateway and the Data service. Why: the pack standard: the key is set before any "
     "step queries the gateway; a clean Profisee Configuration issues a new key, and the services read a key change only after "
     "IIS restarts. When: Never run directly; crud-preflight, crud-run-start and crud-base-reset run it. Running it alone is "
     "safe when no test uses this Profisee database. Needs: the API user exists in the Profisee database; no test running on "
     "this application server. Success: Every step Succeeded or Skipped. If it fails: open the first failed step, whose If it "
     "fails text names what to check."),
    ["crud", "internal", "shared", "api-key"],
    g("ApplicationServerName", "DatabaseServerName", "ProfiseeInstanceName", "ProfiseeDatabaseName", "ProfiseeBaseUrl",
      "MainHealthUrl", "ProfiseeApiKey", "ApiKeyUserName"),
    key_set_steps))
KEY_SET_WHAT = "Set the standard API key, restart IIS so every service reads it, and prove it through the gateway and the Data service"


def key_set_child():
    return run_child("Set And Verify API Key", "crud-api-key-set", KEY_SET_WHAT, timeout=3600)


reset_steps = [
    wait_runs(),
    service("Stop Profisee Service", "Stop", "What: Stop the Profisee Windows service before the restore. Why: it holds connections and caches from before the restore. Success: the service is stopped."),
    *IIS_STOP,
    restore_step("Restore Run-Start Backup", "{{RunStartBackupFileName}}",
        "What: Restore the run-start backup (crud/databases:RunStartBackupStem with the version code) over the Profisee database WITH REPLACE. "
        "The executor takes the database OFFLINE WITH ROLLBACK IMMEDIATE first and brings it back ONLINE if the restore fails. "
        "Why: every measured CRUD run starts from the same model (TDATA full, ZDATA empty, business rules on both), configured on "
        "this application server at the start of this test by crud-run-start. Success: restored (about 6 minutes). If it fails: "
        "the run-start backup is missing (run the test from its crud-test-* workload, which writes it first), or the CrewChief "
        "account is not sysadmin on crud/machines:DatabaseServerName."),
    key_set_child(),
    sql("Check Base State", check_base,
        "What: Confirm the restored database is the CRUD base: TDATA holds at least 10M rows, ZDATA is empty, and TDATA and ZDATA "
        "each carry business rules. Why: a run on another starting state measures something else. Success: the state line prints. "
        "If it fails: the error gives the counts; the backup named in crud/databases:BaseBackupStem with the version code is not the CRUD base."),
]
dump(os.path.join(wl_root, 'internal', 'shared', 'crud-base-reset.workload.json'), workload(
    "crud-base-reset",
    ("What: Restore the run-start backup over the Profisee database, set the standard API key, restart IIS, wait for every "
     "service, check the API key through the gateway and the Data service, and check the base state (TDATA full, ZDATA empty, "
     "business rules on both). Why: every CRUD run starts from the same model, so runs compare. When: Never run directly; every "
     "CRUD core and stewardship workload runs it first. Needs: crud-run-start ran at the start of this test (it writes "
     "crud/databases:RunStartBackupStem with the version code); no other test running against this Profisee database. Success: Every step Succeeded or Skipped. If it fails: open the first failed step, whose If "
     "it fails text names what to check."),
    ["crud", "internal", "shared"],
    g("ApplicationServerName", "DatabaseServerName", "ProfiseeInstanceName", "ProfiseeDatabaseName",
      "ProfiseeBaseUrl", "MainHealthUrl", "TestAutoBaseUrl", "ProfiseeApiKey", "ApiKeyUserName"),
    reset_steps, inputs=inputs_for("ProfiseeVersionCode", "RunStartBackupFileName")))

# ---------------------------------------------------------------- internal/shared/crud-run-start (Gene 11/08)
# Profisee Configuration writes new service sign-in ids into the database it runs on AND into the application server, so
# only the base configured last works (11/08: the CRUD base, configured before the Matching base, got 400 DATA00030).
# Every test therefore configures the base once at its start and backs up a run-start copy; resets restore that copy.
reset_by_label = {st["label"]: st for st in reset_steps}
configure_child = run_child("Configure The Restored Base", "install-configure-upgrade",
                            "Run Profisee Configuration on the restored base", timeout=7500)
# The key install-configure-upgrade takes (ProfiseeVersionNumber) reaches it as this workload's input: a child reads its
# parent's merged values, so the step passes nothing.
configure_child["inline"]["description"] = (
    "What: Run Profisee Configuration on the restored CRUD base (install pack building block install-configure-upgrade: "
    "upgrade, keeps the data). Why: Configuration writes this application server's service sign-in ids into the database; a "
    "base configured earlier makes the Data service reject the user (400 DATA00030). Success: The child workload ends with "
    "every step Succeeded. If it fails: Open the run output of 'install-configure-upgrade'; Configuration's log is quoted there.")
run_start_steps = [
    wait_runs(),
    service("Stop Profisee Service", "Stop", "What: Stop the Profisee Windows service before the restore. Why: it holds connections and caches from before the restore. Success: the service is stopped."),
    *IIS_STOP,
    restore_step("Restore CRUD Base", "{{BaseBackupFileName}}",
        "What: Restore the CRUD base backup (crud/databases:BaseBackupStem with the version code) over the Profisee database WITH REPLACE. "
        "The executor takes the database OFFLINE WITH ROLLBACK IMMEDIATE first and brings it back ONLINE if the restore fails. "
        "Why: Configuration runs on it next. Success: restored (about 6 minutes). If it fails: the backup is missing from the "
        "SQL Server default backup folder of crud/machines:DatabaseServerName, or the CrewChief account is not sysadmin there."),
    *IIS_START,
    service("Start Profisee Service", "Start", "What: Start the Profisee Windows service after the restore. Why: Configuration expects a running instance. Success: the service is running."),
    configure_child,
    health("Wait For Every Service After Configuration"),
    key_set_child(),
    reset_by_label["Check Base State"],
    db_step("Back Up Run-Start", "BackupDatabase", "{{RunStartBackupFileName}}",
        "What: Back up the configured database over the run-start file (crud/databases:RunStartBackupStem with the version code). Why: every "
        "measured run of this test restores it (crud-base-reset), so Configuration runs once per test, not once per run. The "
        "base backup itself is never overwritten. Success: written (file date now). If it fails: the SQL Server service account "
        "cannot write its default backup folder, or the disk is full."),
]
dump(os.path.join(wl_root, 'internal', 'shared', 'crud-run-start.workload.json'), workload(
    "crud-run-start",
    ("What: Restore the CRUD base backup, run Profisee Configuration on it (install-configure-upgrade), confirm every service is "
     "Healthy, set the standard API key, restart IIS, check the key through the gateway and the Data service, check the base "
     "state, and back up the result as the run-start backup. Why: Configuration writes this application server's service "
     "sign-in ids into the database; only a base configured after the last Configuration on this server works. When: Never "
     "run directly; every crud-test-* workload runs it first. Needs: the install pack on this box (install-configure-upgrade "
     "and its reference data); the base backup (crud/databases:BaseBackupStem with the version code) in the SQL Server default backup folder; no "
     "other test running against this Profisee database. Success: Every step Succeeded or Skipped. If it fails: open the first "
     "failed step, whose If it fails text names what to check."),
    ["crud", "internal", "shared", "run-start"],
    g("ApplicationServerName", "DatabaseServerName", "ProfiseeInstanceName", "ProfiseeDatabaseName",
      "ProfiseeBaseUrl", "MainHealthUrl", "TestAutoBaseUrl", "ProfiseeApiKey", "ApiKeyUserName"),
    run_start_steps, inputs=inputs_for("ProfiseeVersionCode", "BaseBackupFileName", "RunStartBackupFileName",
                                       "ProfiseeVersionNumber")))

# ---------------------------------------------------------------- internal/shared/crud-rules-remove
rules_remove = r"""$ErrorActionPreference = 'Stop'
$base = '{{ProfiseeBaseUrl}}'.TrimEnd('/')
$headers = @{ 'x-api-key' = '{{ProfiseeApiKey}}'; accept = 'application/json' }
$entities = @('TDATA', 'ZDATA')
""" + GET_WHY + r"""# Never print a 401 body: it echoes the API key (Get-Why leaves it out).
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
dump(os.path.join(wl_root, 'internal', 'shared', 'crud-rules-remove.workload.json'), workload(
    "crud-rules-remove",
    ("What: Delete every business rule on TDATA and ZDATA through the Profisee REST API (never SQL), recycle the instance's pools "
     "and wait for every service, then confirm none is left in the database. Why: the no-rules runs measure the same model "
     "without business rules; the next base restore brings the rules back. When: Never run directly; the no-rules CRUD workloads "
     "run it right after crud-base-reset. Needs: crud-base-reset ran just before (the standard API key is set). Success: Every step "
     "Succeeded or Skipped. If it fails: open the first failed step, whose If it fails text names what to check."),
    ["crud", "internal", "shared", "rules"],
    g("ApplicationServerName", "DatabaseServerName", "ProfiseeInstanceName", "ProfiseeDatabaseName", "ProfiseeBaseUrl",
      "MainHealthUrl", "ProfiseeApiKey"),
    steps=[ps("Delete Business Rules", rules_remove,
        "What: List the business rules (GET v1/Rules), delete every one on TDATA and ZDATA (DELETE v1/Rules?RuleIds=...), and list "
        "again to prove none is left. Why: the REST API removes a rule with everything Profisee keeps for it; SQL would not. "
        "Success: the last line says none is left (or there was nothing to delete). If it fails: an HTTP code is named: 401 = the "
        "API key (RestKeys:ProfiseeRestKey) is not the one in the database (run crud-base-reset first)."),
     pools("Recycle Instance Pools", "Recycle", "Recycle every application pool of this instance.",
           "services cache the rule set; the run must not apply deleted rules."),
     health(),
     sql("Check No Business Rules", check_no_rules,
         "What: Count the business rules left on TDATA and ZDATA in the database. Why: proves the run measures a model without "
         "rules. Success: none left. If it fails: the count is named; rerun this workload after crud-base-reset.")]))

# ---------------------------------------------------------------- core and stewardship workloads + setup specs
setup_steps = [
    {"label": "ScenarioMgt Check", "inline": {**base, "url": "{{ScenarioMgtBaseUrl}}v1/Records/TestAutoWorkflow?PageSize=1", "method": "GET",
        "headers": {"x-api-key": "{{ScenarioMgtApiKey}}", "accept": "application/json"}, "body": "", "outputFile": "",
        "expectedStatusCodes": [200], "followRedirects": True, "verifySsl": True, "maxTimeSeconds": 300, "type": "HTTP",
        "description": "What: List one TestAuto workflow. Why: proves the address and key reach the TestAuto repository before anything is written. Success: HTTP 200. If it fails: 401 = wrong ScenarioMgt key (RestClients:ScenarioMgt:ApiKey); 404 = wrong address in crud/urls:ScenarioMgtBaseUrl."}},
    ps("TestAuto Version Exists", "\n".join([
        "$ErrorActionPreference = 'Stop'",
        "$base = '{{ScenarioMgtBaseUrl}}'.TrimEnd('/') + '/'",
        "$headers = @{ 'x-api-key' = '{{ScenarioMgtApiKey}}'; accept = 'application/json' }",
        "$version = '" + VER + "'",
        "$verFilter = [uri]::EscapeDataString(\"[Code] eq '$version'\")",
        "$v = Invoke-RestMethod -Uri \"${base}v1/Records/ProfiseeVersion?Filter=$verFilter\" -Headers $headers",
        "$rows = if ($v -is [array]) { $v } else { @($v.data) }",
        "if (-not $rows) { throw \"TestAuto version '$version' does not exist in the repository; create it (data.tProfiseeVersion) before running crud-setup.\" }",
        "\"TestAuto version $version exists.\""]),
       "What: Check the TestAuto version in crud/environment:ProfiseeVersionCode exists in the TestAuto repository. Why: every "
       "workflow step records its results under it. Success: the version exists. If it fails: create the version in the "
       "repository (data.tProfiseeVersion), then rerun crud-setup."),
]
SETUP_FAIL = " If it fails: two workflows with the same tag must be untagged by hand first; any other error names the record."

def check_core_sql(label):
    return f"""DECLARE @total bigint = (SELECT COUNT_BIG(*) FROM data.tZDATA);
DECLARE @left bigint = (SELECT COUNT_BIG(*) FROM data.tZDATA WHERE Code LIKE N'%\\_New%' ESCAPE N'\\' OR [Name] LIKE N'%\\_Changed%' ESCAPE N'\\');
DECLARE @msg nvarchar(1000);
IF @total = 0 BEGIN SET @msg = N'ZDATA is empty after the run: Create wrote nothing (check the TestAuto run).'; THROW 50022, @msg, 1; END
IF @left > 0 BEGIN SET @msg = CONCAT(N'ZDATA still holds ', @left, N' rows the Delete step should have removed (Code ''_New'' or Name ''_Changed'').'); THROW 50023, @msg, 1; END
PRINT CONCAT(N'ZDATA after the {label} run: ', @total, N' rows (created {{{{RecordCount}}}}, then 5% new added and the 15% the update touched deleted); none left with ''_New'' or ''_Changed''.');"""


def run_inputs(mode):
    """Inputs of a measured run: the tag's version code, and what crud-base-reset (and, without rules, crud-rules-remove) takes."""
    names = ["ProfiseeVersionCode", "RunStartBackupFileName"]
    return inputs_for(*names)


core_names, stew_names, release_names = {}, {}, {}
child_steps = {}  # TestAuto workflow upserts, one child workload per size and per stewardship duration (keeps each file small)
for label, n in SIZES.items():
    low = label.lower()
    for m, (mtext, dq) in MODES.items():
        key = core_key(low, m)
        details = core_details(n, m)
        child_steps.setdefault(f"crud-testauto-{low}-create", []).append(ps(f"Upsert Workflow {key}",
            spec_script(key, f"CRUD,{VER}," + ref('environment', 'MainMachineTag') + f",{label}",
                        f"CRUD core {label} ({n} records) {mtext.lower()}: Create, Update, Get with 1, 10 and 100 users, Delete on ZDATA",
                        key, details),
            f"What: Create or update the TestAuto workflow '{key}' and its {len(details)} steps, found by its automation tag. Why: "
            f"CrewChief runs it by that tag. Success: the workflow exists with exactly these steps." + SETUP_FAIL))
        steps =[run_child("Reset To CRUD Base", "crud-base-reset", "Restore the CRUD base backup and warm the instance")]
        if m == 'nobr':
            steps.append(run_child("Remove Business Rules", "crud-rules-remove", "Delete every business rule on TDATA and ZDATA through REST"))
        steps += [run_tag(f"Run CRUD {label} Core", key, f"CRUD {label} core {mtext.lower()}"),
                  sql("Check Core Results", check_core_sql(label),
                      f"What: Confirm the run left ZDATA as expected: rows created, and none left that the Delete step targets. Why: "
                      f"a TestAuto run can end Succeeded with nothing written. Success: the ZDATA line prints. If it fails: the error "
                      f"says which step did not do its work; open that step's run in TestAuto.")]
        name = key
        core_names[(label, m)] = name
        dump(os.path.join(wl_root, 'internal', low, name + '.workload.json'), workload(
            name,
            (f"What: Restore the CRUD base, {'delete the business rules, ' if m == 'nobr' else ''}run the TestAuto workflow "
             f"'CRUD {label} Core {mtext}' (Create {n} ZDATA records from TDATA, Update 10% and add 5%, Get with 1, 10 and 100 "
             f"users, Delete what the update touched) and check ZDATA. Why: measures the REST API record operations at {label} "
             f"{mtext.lower()}; the {'no-rules' if m == 'nobr' else 'with-rules'} half of the {label} comparison. When: from a "
             f"crud-test-* parent; a rerun restores its own start. Needs: crud-setup ran on this box for the current version; the "
             f"base backup is in place (crud-preflight). Success: Every step Succeeded or Skipped. If it fails: open the first "
             f"failed step, whose If it fails text names what to check; rerun the whole workload."),
            ["crud", "internal", label, m], g("DatabaseServerName", "ProfiseeDatabaseName", "TestAutoBaseUrl", RecordCount=str(n)),
            steps, inputs=run_inputs(m)))

for d, (_, _, dshort, dlong) in STEWARD_FORMS.items():
    for m, (mtext, dq) in MODES.items():
        key = stew_key(d, m)
        details = stew_details(d, m)
        child_steps.setdefault(f"crud-testauto-steward-{d}-create", []).append(ps(f"Upsert Workflow {key}",
            spec_script(key, f"CRUD,{VER}," + ref('environment', 'MainMachineTag') + ",Stewardship",
                        f"CRUD stewardship {mtext.lower()} on TDATA, 12 steps, {dlong}: 15, 30, 60 and 120 attributes with 1, 10 and 100 users",
                        key, details),
            f"What: Create or update the TestAuto workflow '{key}' and its {len(details)} steps, found by its automation tag. Why: "
            f"CrewChief runs it by that tag. Success: the workflow exists with exactly these steps." + SETUP_FAIL))
        steps = [run_child("Reset To CRUD Base", "crud-base-reset", "Restore the CRUD base backup and warm the instance")]
        if m == 'nobr':
            steps.append(run_child("Remove Business Rules", "crud-rules-remove", "Delete every business rule on TDATA and ZDATA through REST"))
        steps.append(run_tag(f"Run CRUD Stewardship {dshort}", key, f"CRUD stewardship {dshort} {mtext.lower()}"))
        stew_names[(d, m)] = key
        dump(os.path.join(wl_root, 'internal', 'steward', key + '.workload.json'), workload(
            key,
            (f"What: Restore the CRUD base, {'delete the business rules, ' if m == 'nobr' else ''}and run the TestAuto workflow "
             f"'CRUD Stewardship {dshort} {mtext}': 12 interactive stewardship steps on TDATA (15, 30, 60 and 120 attributes with 1, "
             f"10 and 100 users), {dlong}. Why: measures interactive record work through "
             f"the REST API {mtext.lower()}. When: from a crud-test-* parent; a rerun restores its own start. Needs: crud-setup ran on "
             f"this box for the current version; the base backup is in place (crud-preflight). Success: Every step Succeeded or "
             f"Skipped. If it fails: open the first failed step, whose If it fails text names what to check; rerun the whole workload."),
            ["crud", "internal", "steward", m], g("TestAutoBaseUrl"), steps, inputs=run_inputs(m)))

# 1M release (Gene 11/07): the release CRUD workflows step for step, one restore, Delete after stewardship.
for m, (mtext, dq) in MODES.items():
    key = release_key(m)
    core = core_details(SIZES['1M'], m)
    details = core[:5] + stew_details('60min', m) + core[5:]
    assert len(details) == 18
    child_steps.setdefault("crud-testauto-1m-create", []).append(ps(f"Upsert Workflow {key}",
        spec_script(key, f"CRUD,{VER}," + ref('environment', 'MainMachineTag') + ",1M,Release",
                    f"the release CRUD load {mtext.lower()}, 1M records: Create, Update, Get with 1, 10 and 100 users, 12 stewardship "
                    "steps of 60 minutes on TDATA, then Delete, all on one model state", key, details),
        f"What: Create or update the TestAuto workflow '{key}' and its 18 steps, found by its automation tag. Why: CrewChief runs it "
        "by that tag. Success: the workflow exists with exactly these steps." + SETUP_FAIL))
    steps = [run_child("Reset To CRUD Base", "crud-base-reset", "Restore the CRUD base backup and warm the instance")]
    if m == 'nobr':
        steps.append(run_child("Remove Business Rules", "crud-rules-remove", "Delete every business rule on TDATA and ZDATA through REST"))
    steps += [run_tag("Run CRUD 1M Release", key, f"CRUD 1M release {mtext.lower()}"),
              sql("Check Core Results", check_core_sql('1M'),
                  "What: Confirm the run left ZDATA as expected: rows created, and none left that the Delete step targets. Why: a "
                  "TestAuto run can end Succeeded with nothing written. Success: the ZDATA line prints. If it fails: the error says "
                  "which step did not do its work; open that step's run in TestAuto.")]
    release_names[m] = key
    dump(os.path.join(wl_root, 'internal', '1m', key + '.workload.json'), workload(
        key,
        (f"What: Restore the CRUD base, {'delete the business rules, ' if m == 'nobr' else ''}and run the TestAuto workflow "
         f"'CRUD 1M Release {mtext}': the release CRUD load step for step (Create 1M ZDATA records, Update, Get with 1, 10 and 100 "
         "users, 12 stewardship steps of 60 minutes on TDATA, Delete last) on one model state, then check ZDATA. Why: the "
         f"release measurement {mtext.lower()}, comparable with earlier releases. When: from crud-test-1m-{m}; a rerun restores its "
         "own start. Needs: crud-setup ran on this box for the current version; the base backup is in place (crud-preflight). "
         "Success: Every step Succeeded or Skipped. If it fails: open the first failed step, whose If it fails text names what to "
         "check; rerun the whole workload."),
        ["crud", "internal", "1M", m, "release"],
        g("DatabaseServerName", "ProfiseeDatabaseName", "TestAutoBaseUrl", RecordCount=str(SIZES['1M'])), steps, inputs=run_inputs(m)))

TA_GLOBALS = ("ScenarioMgtBaseUrl", "ScenarioMgtApiKey", "TestAutoBaseUrl", "TestAutoEnvironmentName", "TestAutoApplicationServer",
              "TestAutoDatabaseServer")
for cname, csteps in child_steps.items():
    what = cname[len('crud-testauto-'):-len('-create')]
    keys = [st['label'][len('Upsert Workflow '):] for st in csteps]
    dump(os.path.join(wl_root, 'internal', 'testauto', cname + '.workload.json'), workload(
        cname,
        (f"What: Create or update the tagged CRUD TestAuto workflows {', '.join(keys)} in the TestAuto repository. Why: their "
         "run workloads find them by automation tag; one small workload per size or stewardship form keeps each file small. "
         "When: Never run directly; crud-setup runs it. Running it alone is safe and updates in place. Needs: the TestAuto "
         "version in crud/environment:ProfiseeVersionCode exists in the repository (crud-setup checks it first). Success: Every "
         "step Succeeded. If it fails: open the first failed step, whose If it fails text names what to check."),
        ["crud", "internal", "testauto"], g(*TA_GLOBALS), csteps, inputs=inputs_for("ProfiseeVersionCode")))
    setup_steps.append(run_child(f"TestAuto Workflows {what}", cname, f"Create or update the CRUD {what} TestAuto workflows", timeout=3600))

dump(os.path.join(wl_root, 'start', 'crud-setup.workload.json'), workload(
    "crud-setup",
    (f"What: Create or update the "
     f"{len(wf_entries)} tagged CRUD TestAuto workflows in the TestAuto repository: core per size (1K, "
     "10K, 100K, 1M), stewardship per form (1, 5, 15, 30, 60 minutes per step, or 10, 100, 1000 iterations per step) and the 1M release run (the release CRUD load step for "
     "step), each with and without business rules. Why: every "
     "CRUD workload finds its workflow by automation tag. When: once per box and Profisee version, and after any change to a "
     "workflow spec; reruns update in place. Needs: the TestAuto version in "
     "crud/environment:ProfiseeVersionCode exists in the repository; TestAuto answers on port 8443. Success: Every step Succeeded. If it fails: open the first failed step, whose If "
     "it fails text names what to check."),
    ["crud", "start", "setup"], g("ScenarioMgtBaseUrl", "ScenarioMgtApiKey", **root_globals("ProfiseeVersionCode")), setup_steps))

# ---------------------------------------------------------------- tests
ROOT_TEST_GLOBALS = root_globals(*ENV_KEYS, "BaseBackupFileName", "RunStartBackupFileName")
for label in SIZES:
    d = TEST_FORM[label]
    dmin = int(d[:-3])
    for m, (mtext, dq) in MODES.items():
        name = f"crud-test-{label.lower()}-{m}"
        if label == '1M':
            what = (f"What: Runs the CRUD release test {mtext.lower()}: one restore of the CRUD base, then the release CRUD load step "
                    "for step (Create 1M ZDATA records, Update, Get with 1, 10 and 100 users, 12 stewardship steps of 60 minutes, "
                    "Delete last). Why: This is the release measurement a person starts; the same steps and order as earlier "
                    "releases' CRUD runs, so results compare. ")
            run_steps = [run_child("Prepare Run Start", "crud-run-start", "Restore the CRUD base, run Configuration on it, set the API key and back up the run-start copy every measured run restores", timeout=14400),
                         run_child("Release 1M", release_names[m], f"Measured run: CRUD 1M release {mtext.lower()} (18 steps, one restore)")]
        else:
            what = (f"What: Runs the CRUD test at {label} {mtext.lower()}: the core run (Create, Update, Get with 1, 10 and 100 users, "
                    f"Delete; {SIZES[label]} records) and then {dmin}-minute stewardship (12 steps, about {12 * dmin} minutes), each from a "
                    "fresh restore of the CRUD base. Why: This is the test a person starts: one size, one business-rule mode. ")
            run_steps = [run_child("Prepare Run Start", "crud-run-start", "Restore the CRUD base, run Configuration on it, set the API key and back up the run-start copy every measured run restores", timeout=14400),
                         run_child(f"Core {label}", core_names[(label, m)], f"Measured run: CRUD {label} core {mtext.lower()}"),
                         run_child(f"Stewardship {dmin} min", stew_names[(d, m)], f"Measured run: CRUD stewardship {dmin} min {mtext.lower()}")]
        dump(os.path.join(wl_root, 'tests', name + '.workload.json'), workload(
            name,
            (what +
             "It starts with crud-run-start (restore the base, Profisee Configuration, API key, run-start backup); every measured run "
             "restores that run-start backup. When: Any time after crud-setup has run on this box for the current Profisee version; never at the same time as "
             "another test on the same Profisee database (Connect and Matching restore it too). Needs: crud-setup; the crud/* "
             "reference sets filled in; crud-preflight green. Success: Every run ends Succeeded; each TestAuto execution holds its "
             "metrics. If it fails: It stops at the first failed run: open that run's output."),
            ["crud", "tests", label, m], dict(ROOT_TEST_GLOBALS), run_steps))

dump(os.path.join(wl_root, 'tests', 'crud-test-smoke.workload.json'), workload(
    "crud-test-smoke",
    ("What: The shortest CRUD test that touches every part of the pack: the 1K core run with business rules, then 1-minute "
     "stewardship without business rules (so the rule removal runs too), each from a fresh restore of the CRUD base; about 50 "
     "minutes. Why: proves a box is ready after a move or an upgrade before a long test. When: after crud-setup on a new box or "
     "version, or after a pack change. Needs: crud-setup; crud-preflight green. Success: Every run ends Succeeded. If it fails: It "
     "stops at the first failed run: open that run's output."),
    ["crud", "tests", "1K", "br", "nobr"], dict(ROOT_TEST_GLOBALS),
    [run_child("Prepare Run Start", "crud-run-start", "Restore the CRUD base, run Configuration on it, set the API key and back up the run-start copy every measured run restores", timeout=14400),
     run_child("Core 1K With Rules", core_names[('1K', 'br')], "Measured run: CRUD 1K core with business rules"),
     run_child("Stewardship 1 min No Rules", stew_names[('1min', 'nobr')], "Measured run: CRUD stewardship 1 min without business rules")]))

PROOF = [("Core 1K With Rules", core_names[('1K', 'br')], "CRUD 1K core with business rules"),
         ("Core 1K No Rules", core_names[('1K', 'nobr')], "CRUD 1K core without business rules"),
         ("Stewardship 10 iterations With Rules", stew_names[('10it', 'br')], "CRUD stewardship 10 iterations with business rules"),
         ("Stewardship 10 iterations No Rules", stew_names[('10it', 'nobr')], "CRUD stewardship 10 iterations without business rules"),
         ("Stewardship 1 min With Rules", stew_names[('1min', 'br')], "CRUD stewardship 1 min with business rules"),
         ("Stewardship 1 min No Rules", stew_names[('1min', 'nobr')], "CRUD stewardship 1 min without business rules")]
dump(os.path.join(wl_root, 'tests', 'crud-test-proof.workload.json'), workload(
    "crud-test-proof",
    ("What: Proves every CRUD form works at the smallest size: the 1K core run with and without business rules, stewardship "
     "by count (10 iterations per step) with and without, and stewardship by time (1 minute per step) with and without, each "
     "from a fresh restore of the CRUD base; about 160 minutes (measured 11/07). Why: a change to the pack or to TestAuto must be shown to work "
     "for every form without paying for the 1M or 60-minute runs. When: after crud-setup on a new box or version, or after a "
     "pack or TestAuto change. Needs: crud-setup; crud-preflight green. Success: Every run ends Succeeded. If it fails: It "
     "stops at the first failed run: open that run's output."),
    ["crud", "tests", "1K", "br", "nobr"], dict(ROOT_TEST_GLOBALS),
    [run_child("Prepare Run Start", "crud-run-start", "Restore the CRUD base, run Configuration on it, set the API key and back up the run-start copy every measured run restores", timeout=14400)] + [run_child(lbl, wl, f"Measured run: {txt}") for lbl, wl, txt in PROOF]))

# ---------------------------------------------------------------- schedules (Gene 11/07: wanted, like Matching)
# Weekly defaults, Monday-Friday: Matching schedules use Sunday and Connect's Saturday 02:00, and every pack restores the
# same Profisee database. Each start leaves room for the one before it (1K about 75 min, 10K 3.5 h, 100K 7 h, 1M 16-18 h).
SCHEDULE = {('1K', 'br'): ('Mon', '18:00'), ('1K', 'nobr'): ('Mon', '20:00'), ('10K', 'br'): ('Mon', '22:00'),
            ('10K', 'nobr'): ('Tue', '18:00'), ('100K', 'br'): ('Tue', '22:00'), ('100K', 'nobr'): ('Wed', '18:00'),
            ('1M', 'br'): ('Thu', '06:00'), ('1M', 'nobr'): ('Fri', '06:00')}
for (label, m), (day, time) in SCHEDULE.items():
    low, mtext = label.lower(), MODES[m][0]
    task, target = f"schedule-crud-{low}-{m}", f"crud-test-{low}-{m}"
    dump(os.path.join(wl_root, 'schedule', low, task + '.workload.json'), workload(
        task,
        (f"What: Create or update the Windows scheduled task '\\CrewChief\\{task}' that runs {target} (CRUD {label} "
         f"{mtext.lower()}) from the CrewChief CLI on the schedule in the globals (default weekly, {day} {time}, as "
         "CORP\\speedmerchants). Run it again after changing a global; nothing is scheduled until it runs. Why: lets the test "
         "repeat without a person. When: once to create or update the task, and again after changing a schedule global. "
         "Needs: crud-setup ran on this box; the secret Scheduler:RunAsPassword. Success: Every step Succeeded or Skipped. "
         "If it fails: open the first failed step, whose If it fails text names what to check."),
        ["crud", "schedule", label, m],
        {"TaskName": task, "TargetWorkload": target, "CliPath": "C:\\Deploy\\CrewChief\\cli\\crewchief.exe",
         "DataFolder": "C:\\Deploy\\CrewChief\\web\\data", "StartDate": "2026-11-09", "StartTime": time, "Recurrence": "Weekly",
         "Interval": "1", "DaysOfWeek": day, "RunAsAccount": "CORP\\speedmerchants"},
        [{"label": "Apply Schedule", "inline": {
            "action": "Apply", "taskName": "{{TaskName}}", "targetWorkload": "{{TargetWorkload}}", "cliPath": "{{CliPath}}",
            "dataFolder": "{{DataFolder}}", "startDate": "{{StartDate}}", "startTime": "{{StartTime}}",
            "recurrence": "{{Recurrence}}", "interval": "{{Interval}}", "daysOfWeek": "{{DaysOfWeek}}", "endDate": "",
            "runAsAccount": "{{RunAsAccount}}", "runAsPassword": "{{$config:Scheduler:RunAsPassword}}", "runElevated": True,
            "type": "ScheduleTaskStep", **base, "timeoutSeconds": 120,
            "description": (f"What: Create or update the scheduled task for {target}. Why: puts the run on the Windows Task "
                            "Scheduler so it repeats without a person. Success: Task Scheduler holds the task under \\CrewChief "
                            "with the schedule in the globals. If it fails: check the run-as account and its password secret "
                            "(Scheduler:RunAsPassword) and that the CrewChief CLI path in the globals exists.")}}],
        notes=("Change StartDate, StartTime, Recurrence (Once, Daily, Weekly), Interval and DaysOfWeek, then run this workload. "
               "Every CRUD, Connect and Matching schedule restores the same Profisee database: defaults are Monday-Friday "
               "(Matching takes Sunday, Connect Saturday 02:00); never let two overlap, and start no manual run while one is due.")))

# ---------------------------------------------------------------- preflight
backup_sql = """DECLARE @dir nvarchar(400) = CAST(SERVERPROPERTY('InstanceDefaultBackupPath') AS nvarchar(400));
DECLARE @exists int, @f nvarchar(600) = @dir + N'\\{{BaseBackupFileName}}';
EXEC master.dbo.xp_fileexist @f, @exists OUTPUT;
IF @exists = 0 BEGIN DECLARE @msg nvarchar(2048) = N'CRUD base {{BaseBackupFileName}} for version {{ProfiseeVersionCode}} is missing on {{DatabaseServerName}}. Run crud-base-create on this lane.'; THROW 50024, @msg, 1; END
PRINT CONCAT(N'CRUD base backup found: ', @f);"""
state_sql = """DECLARE @tdata bigint = (SELECT SUM(p.rows) FROM sys.partitions p WHERE p.object_id = OBJECT_ID(N'data.tTDATA') AND p.index_id IN (0, 1));
DECLARE @zdata bigint = (SELECT SUM(p.rows) FROM sys.partitions p WHERE p.object_id = OBJECT_ID(N'data.tZDATA') AND p.index_id IN (0, 1));
IF @tdata IS NULL OR @zdata IS NULL BEGIN PRINT N'TDATA or ZDATA does not exist: the Profisee database holds another pack''s model now (normal after a Connect or Matching run). Every CRUD run restores the base backup first.'; RETURN; END
DECLARE @rulesT int = (SELECT COUNT(*) FROM [rule].vDQRule WHERE Entity = N'TDATA');
DECLARE @rulesZ int = (SELECT COUNT(*) FROM [rule].vDQRule WHERE Entity = N'ZDATA');
PRINT CONCAT(N'Profisee database now: TDATA ', @tdata, N' rows, ZDATA ', @zdata, N' rows, business rules TDATA ', @rulesT, N', ZDATA ', @rulesZ, N'. Every CRUD run restores the base first, so a dirty state here is not a failure.');"""
pre_keys = list(wf_entries)
key_lines = ",\n".join(f"    '{k}'" for k in pre_keys)
tags_ps = ("$ErrorActionPreference = 'Stop'\n"
           "$testAuto = '{{TestAutoBaseUrl}}'.TrimEnd('/')\n"
           "$version = '" + VER + "'\n"
           f"$keys = @(\n{key_lines}\n)\n"
           "$missing = @(); $dupes = @(); $ok = 0\n"
           "foreach ($key in $keys) {\n"
           "    $tag = \"AUTO:{{$env:COMPUTERNAME}}:${version}:$key\"\n"
           "    $found = @((Invoke-RestMethod -Uri \"$testAuto/api/workflows/by-tag?tag=$([uri]::EscapeDataString($tag))\" -SkipCertificateCheck).data)\n"
           "    if ($found.Count -eq 0) { $missing += $tag }\n"
           "    elseif ($found.Count -gt 1) { $dupes += \"$tag on $(($found | ForEach-Object { \"$($_.code) '$($_.name)'\" }) -join '; ')\" }\n"
           "    else { $ok++ }\n"
           "}\n"
           "if ($dupes) { throw \"$($dupes.Count) automation tag(s) sit on more than one TestAuto workflow (remove the tag from the copies): $($dupes -join ' | ')\" }\n"
           "if ($ok -eq 0) { \"Workflows for $version not created yet on this box (0 of $($keys.Count) automation tags found): run crud-setup. Not a failure before the first setup or after an upgrade.\"; return }\n"
           "if ($missing) { throw \"$($missing.Count) of $($keys.Count) automation tags have no TestAuto workflow (run crud-setup again): $($missing -join ', ')\" }\n"
           "\"All $($keys.Count) automation tags for $version found exactly once.\"")
HTTP_RESULT = ("Success: The response status is 200. If it fails: 401 = the API key secret is wrong; 404 = the address is wrong; "
               "no response = the server in the URL (crud/urls, crud/machines) is down.")
pre_steps = [
    service("Profisee Service Exists", "Status",
            "What: Ask the application server (crud/machines:ApplicationServerName) for the state of the Windows service of this "
            "Profisee instance, as the step before found it. Why: every reset stops and starts it. Success: the service is running "
            "(Status changes nothing)."),
    pools("Application Pools Exist", "Start",
          "Start the IIS application pools of the instance (crud/instances:ProfiseeInstanceName), the ones every CRUD reset recycles.",
          "a reset fails half way when the instance has no pools or one will not start; this finds it first."),
    sql("CRUD Base Backup Exists", backup_sql,
        "What: Check the CRUD base backup of this version (crud/databases:BaseBackupStem, the version code, .bak) sits in the SQL Server default backup folder of "
        "crud/machines:DatabaseServerName. Why: every CRUD run restores it. Success: the backup is found. If it fails: run crud-base-create on this lane "
        "to make the base of this version from the seed backup (crud/databases:BaseSeedBackupFileName), or copy the base there.", conn=MASTER),
    sql("Profisee Database State", state_sql,
        "What: Print the current TDATA and ZDATA row counts and business rule counts of the Profisee database, or say it holds "
        "another pack's model. Why: shows what a person would find in the portal; the runs restore the base anyway, so this "
        "step informs and never fails on the model state. Success: one line says what the database holds. If it fails: the "
        "database server (crud/machines:DatabaseServerName) or the Profisee database is unreachable with Windows authentication."),
    {"label": "TestAuto Answers", "inline": {**base, "type": "HTTP", "method": "GET", "followRedirects": True,
        "headers": {"accept": "application/json"}, "expectedStatusCodes": [200],
        "url": "{{TestAutoBaseUrl}}/api/workflows/by-tag?tag=AUTO%3Apreflight", "body": "", "outputFile": "", "verifySsl": False,
        "maxTimeSeconds": 120,
        "description": ("What: Ask TestAuto on this box (crud/machines:TestServerNameFQDN, port 8443) for workflows tagged with a "
                        "probe tag. Why: every CRUD run finds its TestAuto workflow by tag through this call. " + HTTP_RESULT)}},
    {"label": "TestAuto Model Answers", "inline": {**base, "type": "HTTP", "method": "GET", "followRedirects": True,
        "headers": {"x-api-key": "{{ScenarioMgtApiKey}}", "accept": "application/json"}, "expectedStatusCodes": [200],
        "url": "{{ScenarioMgtBaseUrl}}v1/Records/TestAutoWorkflow?PageSize=1", "body": "", "outputFile": "", "verifySsl": True,
        "maxTimeSeconds": 120,
        "description": ("What: Read one TestAuto workflow record from the TestAuto repository (crud/urls:ScenarioMgtBaseUrl) with the "
                        "RestClients:ScenarioMgt:ApiKey secret. Why: crud-setup writes the workflows through it. " + HTTP_RESULT)}},
    wait_runs(),
    key_set_child(),
    ps("Every Automation Tag Found Once", tags_ps,
       f"What: Look up all {len(pre_keys)} CRUD automation tags of this box and the current version "
       "(crud/environment:ProfiseeVersionCode) in TestAuto: each must sit on exactly one workflow; none at all = workflows not "
       "created yet (stated, not failed: run crud-setup). Why: each run step finds its workflow by tag. Success: the script ends "
       "without an error. If it fails: the error names the tags with no workflow (run crud-setup) or on more than one (remove "
       "the tag from the copies)."),
]
dump(os.path.join(wl_root, 'start', 'crud-preflight.workload.json'), workload(
    "crud-preflight",
    ("What: Checks this box is ready for CRUD testing: the Profisee Windows service and application pools exist, the CRUD base "
     "backup is on the database server, the current Profisee database state, TestAuto and its repository answer, the standard "
     "API key is set and works through the gateway and the Data service (crud-api-key-set), and every automation tag sits on "
     "exactly one workflow. CrewChief's own pre-run check first proves every crud/* reference value it uses is filled in. Why: "
     "finds every environment problem in one run, before a test fails half way through. When: before and after crud-setup, "
     "after any reference data change, after a Profisee upgrade, before every round, and first whenever a test fails; never "
     "while a test runs on this application server. Needs: the crud/* reference sets and the box's secrets; the API user exists "
     "in the Profisee database. It changes only two things: the pool step starts a pool that is stopped, and the key step "
     "writes the standard API key and restarts IIS (pack standard: the key is set before any gateway query). Only one test may use this "
     "application server's Profisee database at a time: Connect, Matching and CRUD all restore it. Success: Every step Succeeded "
     "or Skipped; before the first crud-setup the tag step says \"not created yet\", normal. If it fails: each step's failure "
     "text names the reference key, secret or machine to fix; fix reference data or the box, never a workload file."),
    ["crud", "start"],
    g("ApplicationServerName", "DatabaseServerName", "ProfiseeInstanceName", "ProfiseeDatabaseName",
      "TestAutoBaseUrl", "ScenarioMgtBaseUrl", "ScenarioMgtApiKey",
      **root_globals("ProfiseeVersionCode", "BaseBackupFileName")),
    pre_steps))

# ---------------------------------------------------------------- start/crud-base-create (D18)
# Makes the base of a Profisee version: restore the seed (today's base file, the same or an older version), run Profisee
# Configuration on it, back it up under the versioned name. When the base exists it does nothing and ends green (P1, below). Not in the catalog.
# P1 (Gene 11/10): when this version's base already exists the workload ends GREEN and touches nothing. Mechanism: a PowerShell step
# captures "true" (base missing) or "false" into the run parameter BaseMissing (PowerShellStep outputParameterName: the step's
# trimmed standard output becomes a run parameter later steps read as {{BaseMissing}}); every step after the check carries
# runWhen {{BaseMissing}}, which the engine reads as blank or "false" = skip. runWhen is one token string (no AND), so a second
# captured flag, ServiceStepsOn, is true only when the base is missing AND the step Find The Instance Service found a service
# (InstanceServiceName; the service steps already skipped on a blank name). Both flags are declared as globals defaulting to "false": a capture that never happens can only
# skip steps, never overwrite a base. Steps are found by label, never by index.
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
service_gate_ps = r"""if ('{{BaseMissing}}' -eq 'true' -and -not [string]::IsNullOrWhiteSpace('{{InstanceServiceName}}')) { 'true' } else { 'false' }"""
SKIP_BASE = "the CRUD base of this version already exists (the check step found it), so there is nothing to make"


def gated(step, flag="BaseMissing"):
    """Copy of step that runs only when run parameter `flag` is true; its description gets the reason (a step that already
    has a 'Skipped when:' sentence, like the service steps, gets it added)."""
    st = copy.deepcopy(step)
    st["inline"]["runWhen"] = "{{%s}}" % flag
    d = st["inline"]["description"]
    st["inline"]["description"] = d + (f" Also skipped when {SKIP_BASE}." if "Skipped when:" in d else f" Skipped when: {SKIP_BASE}.")
    return st


create_configure = run_child("Configure The Restored Seed", "install-configure-upgrade",
                             "Run Profisee Configuration on the restored seed", timeout=7500)
create_configure["inline"]["description"] = (
    "What: Run Profisee Configuration on the restored seed (install pack building block install-configure-upgrade: upgrade, "
    "keeps the data). Why: the seed may come from an older Profisee version; Configuration upgrades it to the version under test "
    "and writes this application server's service sign-in ids. Success: The child workload ends with every step Succeeded. "
    "If it fails: Open the run output of 'install-configure-upgrade'; Configuration's log is quoted there. A seed from a newer "
    "version than the installed Profisee cannot be used (Configuration only upgrades).")
base_create_steps = [
    wait_runs(),
    ps("Check Whether The Base Exists", check_base_ps,
       "What: Look for the CRUD base of this version (crud/databases:BaseBackupStem, the version code, .bak) in the SQL Server default "
       "backup folder of crud/machines:DatabaseServerName and keep the answer in the run parameter BaseMissing (true = no base yet). "
       "Why: a base is made once and never overwritten; every test restores it, so when it exists every later step is skipped and the "
       "run ends green. Success: the step ends without an error (it does not fail when the base exists). If it fails: the database "
       "server does not answer, or the CrewChief account cannot connect to master there.", timeout=120, output="BaseMissing"),
    ps("Report The Base State", report_base_ps,
       "What: Print whether the CRUD base of this version already exists (nothing done) or will be made. Why: the run output then says "
       "plainly why every later step is Skipped. Success: one line is printed. If it fails: the script cannot fail by itself; open the "
       "run output of the check step before it.", timeout=60),
    ps("Decide The Service Steps", service_gate_ps,
       "What: Keep in the run parameter ServiceStepsOn whether the Profisee Windows service steps run: true only when the base is "
       "missing and the step Find The Instance Service found the instance's Windows service. Why: a step can test only one value, so the two conditions are combined "
       "here. Success: the line says true or false. If it fails: the script cannot fail by itself; open the run output of the check "
       "step before it.", timeout=60, output="ServiceStepsOn"),
    gated(service("Stop Profisee Service", "Stop", "What: Stop the Profisee Windows service before the restore. Why: it holds connections and caches from before the restore. Success: the service is stopped."), "ServiceStepsOn"),
    *[gated(x) for x in IIS_STOP],
    gated(restore_step("Restore Seed Backup", "{{BaseSeedBackupFileName}}",
        "What: Restore the seed backup (crud/databases:BaseSeedBackupFileName) over the Profisee database WITH REPLACE. "
        "The executor takes the database OFFLINE WITH ROLLBACK IMMEDIATE first and brings it back ONLINE if the restore fails. "
        "Why: it holds the CRUD model (TDATA full, ZDATA empty, business rules on both) of the same or an older version. "
        "Success: restored (about 6 minutes). If it fails: the seed is missing from the SQL Server default backup folder of "
        "crud/machines:DatabaseServerName, or the CrewChief account is not sysadmin there.")),
    *[gated(x) for x in IIS_START],
    gated(service("Start Profisee Service", "Start", "What: Start the Profisee Windows service after the restore. Why: Configuration expects a running instance. Success: the service is running."), "ServiceStepsOn"),
    gated(create_configure),
    gated(health("Wait For Every Service After Configuration")),
    gated(key_set_child()),
    gated(reset_by_label["Check Base State"]),
    gated(db_step("Back Up The Base", "BackupDatabase", "{{BaseBackupFileName}}",
        "What: Back up the configured database as the CRUD base of this version (crud/databases:BaseBackupStem, the version code, .bak). "
        "Why: every CRUD test of this version restores it. Success: written (file date now). If it fails: the SQL Server service "
        "account cannot write its default backup folder, or the disk is full.")),
]
dump(os.path.join(wl_root, 'start', 'crud-base-create.workload.json'), workload(
    "crud-base-create",
    ("What: Make the CRUD base of one Profisee version: restore the seed backup (crud/databases:BaseSeedBackupFileName), run "
     "Profisee Configuration on it (install-configure-upgrade), wait for every service, set and prove the API key (crud-api-key-set), check the base state and back it up "
     "under the versioned name (crud/databases:BaseBackupStem, the version code, .bak). When that base already exists it skips "
     "everything after the check, prints that nothing was done and ends green; it never overwrites a base. Why: a lane of a new "
     "Profisee version has no base yet; every CRUD test restores it. When: once per box and version, after the Profisee of that "
     "version is installed (run it before crud-setup; a round starts it first); crud-preflight says when the base is missing. Needs: the seed is "
     "the CRUD base of the same or an older version (Configuration only upgrades); the install pack on this box; no test running "
     "against this Profisee database. Success: Every step Succeeded or Skipped. If it fails: open the "
     "first failed step, whose If it fails text names what to check."),
    ["crud", "start", "base-create"],
    g("ApplicationServerName", "DatabaseServerName", "ProfiseeInstanceName", "ProfiseeDatabaseName", "BaseSeedBackupFileName",
      "ProfiseeBaseUrl", "MainHealthUrl", "TestAutoBaseUrl",
      **root_globals("ProfiseeVersionCode", "ProfiseeVersionNumber", "BaseBackupFileName"),
      BaseMissing="false", ServiceStepsOn="false"),
    base_create_steps,
    notes=("BaseMissing and ServiceStepsOn are set by the check steps during the run (true or false); they start as false so a step that "
           "never got its answer is skipped, never run.")))

# ---------------------------------------------------------------- rounds
rounds = os.path.join(root, 'rounds')
os.makedirs(rounds, exist_ok=True)
RUN = "# Run: bash ../../tools/runner/run-queue.sh <CrewChief box> {f}  (one test at a time per Profisee database: Connect, Matching and CRUD all restore it)\n"
with open(os.path.join(rounds, 'smoke.txt'), 'w', encoding='utf-8', newline='\n') as f:
    f.write("# Smoke test: 1K core with business rules, then 1-minute stewardship without (about 50 minutes). Use it after a move to a new machine or an upgrade.\n"
            + RUN.format(f='smoke.txt') + "crud-test-smoke\n")
with open(os.path.join(rounds, 'proof-round.txt'), 'w', encoding='utf-8', newline='\n') as f:
    f.write("# Proof round: every form at 1K (core, stewardship by count 10 iterations, stewardship 1 minute; each with and without business rules; about 160 minutes). Use it after a pack or TestAuto change.\n"
            + RUN.format(f='proof-round.txt') + "crud-test-proof\n")
with open(os.path.join(rounds, 'check-round.txt'), 'w', encoding='utf-8', newline='\n') as f:
    f.write("# Mid-release check: 1K, 10K and 100K, with and without business rules (each core run plus 5, 15 or 30 minute stewardship).\n"
            + RUN.format(f='check-round.txt') + "# No '+': each test restores the base, so a failed one does not stop the next.\n\n"
            + "".join(f"crud-test-{s}-{m}\n" for s in ('1k', '10k', '100k') for m in ('br', 'nobr')))
with open(os.path.join(rounds, 'release-round.txt'), 'w', encoding='utf-8', newline='\n') as f:
    f.write("# Release round: 1M with and without business rules (core plus 60-minute stewardship; about 16 hours without rules and 18 hours with them on 26R3-class timings), the release CRUD load.\n"
            + RUN.format(f='release-round.txt') + "# No '+': each test restores the base, so a failed one does not stop the next.\n\n"
            "crud-test-1m-br\ncrud-test-1m-nobr\n")
print(f"crud pack written: {len(wf_entries)} workflows, {len(core_names)} core, {len(stew_names)} stewardship workloads")
