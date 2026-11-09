"""Builds the whole Matching pack for every size, Connect-pack style.

  internal/<size>/  matching-<size>-scenario1-load, -testauto-create, -scenario1..3c (gen_all.py), matching-<size>-all
  tests/            matching-test-<size>       (what a person starts: the whole chain of one size)
  start/            matching-setup             (TestAuto run profiles + workflows of every size)
  schedule/<size>/  schedule-matching-<size>   (Windows scheduled task that runs matching-<size>-all)

Usage: python gen_sizes.py <packRoot> <connectUpsertBody.ps1>
"""
import copy, json, os, subprocess, sys

root, upsert_path = sys.argv[1], sys.argv[2]
here = os.path.dirname(os.path.abspath(__file__))
SIZES = {'1K': 1000, '10K': 10000, '100K': 100000, '1M': 1000000, '100M': 100000000}
# Weekly start times (Sunday); each size's chain must finish before the next starts on the same Profisee database.
SCHEDULE = {'1K': ('2026-11-08', '00:30', 'Sun'), '10K': ('2026-11-08', '02:00', 'Sun'),
            '100K': ('2026-11-08', '05:00', 'Sun'), '1M': ('2026-11-08', '12:00', 'Sun'),
            # 100M (Gene 11/06: in the pack, data built only where the test server has room) is not measured yet;
            # Saturday keeps it apart from the Sunday sizes. Set the real time once one 100M run is timed.
            '100M': ('2026-11-07', '00:30', 'Sat')}
SERVICE_CONFIG_ID = '320e7ed1-3430-484a-87ce-7a2ee72be085'  # 'ModelSource' service configuration the strategy reads through
STRATEGY_ID = 'c810734f-51a5-4416-aa8b-a6380f5e2a22'  # RetailClientImport in the empty baseline (Connect keeps the id on import)
wl_root = os.path.join(root, 'workloads', 'matching')
ref_dir = os.path.join(root, 'reference-kv', 'matching')


def dump(path, obj):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'w', encoding='utf-8') as f:
        json.dump(obj, f, indent=2)


def read(path):
    with open(path, encoding='utf-8') as f:
        return json.load(f)


# Reference set of display names: every size adds its own keys.
wf_ref_path = os.path.join(ref_dir, 'workflows.json')
wf_ref = read(wf_ref_path)
wf_ref['entries'], wf_ref['keyDescriptions'] = {}, {}
dump(wf_ref_path, wf_ref)

for label in SIZES:
    subprocess.run([sys.executable, os.path.join(here, 'gen_all.py'), root, upsert_path, label], check=True)

# ---- the Connect strategy artifact: RetailClientImport, source table and run-as user as tokens
with open(os.path.join(here, 'retailclientimport-artifact.json'), encoding='utf-8') as f:
    artifact = f.read()
art = json.loads(artifact)
cfg = art['integrationStrategyRecord']['Configuration']
assert art['integrationStrategyRecord']['Id'] == STRATEGY_ID
assert cfg['remoteObjectName'] == '{{SourceTableName}}'
cfg['runAsUser'] = '{{RunAsUser}}'
artifact = json.dumps(art, separators=(',', ':'), ensure_ascii=False)
assert artifact.count('{{SourceTableName}}') >= 1 and '\\\\' not in artifact.replace('{{RunAsUser}}', '')

# ---- the 'ModelSource' service configuration: the Connect pack's SQL Server one (same provider, same settings), so its
# server and database come from reference data (matching/machines:DatabaseServerName, matching/databases:ModelSourceDB)
# and not from whatever the empty baseline was made with.
with open(os.path.join(here, 'modelsource-serviceconfig-artifact.json'), encoding='utf-8') as f:
    sc_artifact = f.read()
assert '{{DatabaseName}}' in sc_artifact and '{{DbServer}}' in sc_artifact and '{{ServiceConfigId}}' in sc_artifact
sc_parameters = {"AuthenticationScheme": "SqlLogon", "CommandTimeout": "120", "ConnectionTimeout": "60",
                 "DatabaseName": "{{ModelSourceDB}}", "DbPassword": "{{$config:UserCredentials:SqlAdminPassword}}",
                 "DbServer": "{{DatabaseServerName}}", "DbUsername": "{{$config:UserCredentials:SqlAdminUser}}",
                 "EncryptEnhanced": "Optional", "ServiceConfigId": SERVICE_CONFIG_ID, "ServiceConfigName": "ModelSource",
                 "ServiceProviderId": "77d91447-e344-4fc1-a49f-1c089210a40a",
                 "ServiceProviderName": "SQL Server Service Provider", "TrustServerCertificate": "True"}
sc_delete_script = "\r\n".join([
    "$ErrorActionPreference = 'Stop'",
    "$connect = '{{ConnExBaseUrl}}'.TrimEnd('/') + '/'",
    "$headers = @{ 'x-api-key' = '{{ConnExApiKey}}'; accept = 'application/json' }",
    "# A Connect import of an id that already exists fails, so the service configuration is removed first (after the strategy that uses it).",
    "$r = Invoke-WebRequest -Method Delete -Uri \"${connect}v1/Connect/Configurations?ConfigurationUids=%s\" -Headers $headers -SkipHttpErrorCheck -TimeoutSec 300" % SERVICE_CONFIG_ID,
    "$code = [int]$r.StatusCode",
    "# A 401 body echoes the API key, so no response body is ever printed.",
    "if ($code -notin 200, 204, 404) { throw \"Deleting the ModelSource service configuration returned HTTP $code.\" }",
    "\"ModelSource service configuration: delete returned HTTP $code (404 = it was not there).\"",
])

template = read(os.path.join(here, 'load-template-1k.workload.json'))
tsteps = {s['label']: s for s in template['steps']}
base = {"parameters": {}, "timeoutSeconds": 600, "continueOnError": False, "retryEnabled": False, "maxRetries": 0,
        "retryDelaySeconds": 5, "workingDirectory": None, "notes": ""}
ADMIN = {"credentialSecretName": None, "credentialUserId": "{{$config:UserCredentials:AdminUser}}",
         "credentialPassword": "{{$config:UserCredentials:AdminPassword}}", "remoteAuthentication": "CredSSP"}

# 11/08: restore + key change needs IIS stopped and started (as the Connect pack's API key workload does); a pool recycle
# left the Data and Connect services rejecting the API user (400 DATA00030, 403 CNX00080).
IIS_WHY = ("Why: {verb} the Windows service so the next steps work on a quiet or a running Profisee instance, as they need. "
           "Success: The service on the target machine ends in the state the action asks for ({action}). If it fails: Check the "
           "service name exists on the target machine (services.msc) and the admin credential (UserCredentials secrets) can manage "
           "services there over CredSSP.")


def iis(name, action, what):
    return {"label": f"{action} {name}", "inline": {**base, "serviceName": name, "action": action,
            "targetComputer": "{{ApplicationServerName}}", **ADMIN, "type": "ServiceControlStep",
            "description": f"What: {what} " + IIS_WHY.format(verb=action, action=action)}}


IIS_STOP = [iis("W3SVC", "Stop", "Stop the World Wide Web Publishing Service on {{ApplicationServerName}} so no worker process keeps the old key."),
            iis("WAS", "Stop", "Stop the Windows Process Activation Service on {{ApplicationServerName}}: every application pool stops with it.")]
IIS_START = [iis("WAS", "Start", "Start the Windows Process Activation Service on {{ApplicationServerName}}."),
             iis("W3SVC", "Start", "Start the World Wide Web Publishing Service on {{ApplicationServerName}}; the application pools start and read the new key.")]

DATA_KEY_DESC = ("What: Prove the Data service accepts the API key as a real user: GET v1/Rules?PageSize=1 must return 200. "
                 "Why: the gateway check (v1/Entities) can pass while the Data and Connect services still reject the user "
                 "(400 DATA00030 \"user is not valid\", 403 CNX00080); that only showed up minutes later inside a test. "
                 "Success: 200. If it fails: 400 DATA00030 or 403 = the key is not set for corp\\speedmerchants in this "
                 "database, IIS was not restarted after the restore and the key change, or the restored backup was "
                 "configured before Profisee Configuration last ran on this application server (stale service sign-in "
                 "ids): start from the size's load, which configures the empty baseline first.")

# Why a REST call failed, from its body; a 401 body echoes the API key and is never shown (11/08).
GET_WHY = [
    "function Get-Why($resp) {",
    "    # Why a call failed, from its body. A 401 body echoes the API key, so it is never shown; ids and keys are masked.",
    "    if ([int]$resp.StatusCode -eq 401) { return '(401 body not shown)' }",
    "    $t = (([string]$resp.Content) -replace '[0-9a-fA-F]{8}-?[0-9a-fA-F]{4}-?[0-9a-fA-F]{4}-?[0-9a-fA-F]{4}-?[0-9a-fA-F]{12}', '<id>' -replace '\\s+', ' ').Trim()",
    "    if ($t.Length -gt 800) { $t = $t.Substring(0, 800) + ' ...' }",
    "    if ($t) { \"Body: $t\" } else { '(empty body)' }",
    "}",
]

delete_script = "\r\n".join([
    "$ErrorActionPreference = 'Stop'",
    "$connect = '{{ConnExBaseUrl}}'.TrimEnd('/') + '/'",
    "$headers = @{ 'x-api-key' = '{{ConnExApiKey}}'; accept = 'application/json' }",
    "# A Connect import of an id that already exists fails (it never updates), so the strategy is removed first. Nothing else is touched.",
    "$r = Invoke-WebRequest -Method Delete -Uri \"${connect}v1/Connect/Strategies?IntegrationStrategyUids={{StrategyId}}\" -Headers $headers -SkipHttpErrorCheck -TimeoutSec 300",
    "$code = [int]$r.StatusCode",
    "# A 401 body echoes the API key, so no response body is ever printed.",
    *GET_WHY,
    "if ($code -notin 200, 204, 404) { throw \"Deleting Connect strategy {{StrategyName}} ({{StrategyId}}) returned HTTP $code. $(Get-Why $r)\" }",
    "\"Connect strategy {{StrategyName}}: delete returned HTTP $code (404 = it was not there).\"",
])


def connex(op, desc, **kw):
    return {**base, "artifactFile": "", "artifactJson": "", "resourceType": "IntegrationStrategy", "operation": op,
            "baseUrl": "{{ConnExBaseUrl}}", "apiKey": "{{ConnExApiKey}}", "returnResult": True,
            "expectedStatusCodes": [200, 201, 204], "resourceId": "", "outputFile": "", "dryRun": False,
            "skipFileWrite": False, "pollIntervalSeconds": 30, "maxWaitMinutes": 720, "pollFailureLimit": 3,
            "batchCode": "", "type": "ConnExStep", "description": desc, **kw}


def run_child(name, what, timeout=172800):
    return {**base, "workloadName": name, "type": "RunWorkloadStep", "timeoutSeconds": timeout,
            "description": (f"What: {what}. Why: Runs the child workload '{name}' so its tested steps are reused here, not repeated. "
                            "Success: The child workload ends with every step Succeeded or Skipped. "
                            f"If it fails: Open the run output of '{name}'; its first failed step says what to check.")}


# Gene 11/08: Profisee Configuration writes new service sign-in ids into the database it runs on AND the application
# server, so only the backup configured last works. Every load (the first run of each Matching test) restores the empty
# baseline and runs Configuration on it; the scenario checkpoints it backs up later in the same test carry those ids.
configure = run_child("install-configure-upgrade", "Run Profisee Configuration on the restored empty baseline", timeout=7500)
configure["description"] = (
    "What: Run Profisee Configuration on the restored empty baseline (install pack building block install-configure-upgrade: "
    "upgrade, keeps the data). Why: Configuration writes this application server's service sign-in ids into the database; a "
    "backup configured earlier makes the Data and Connect services reject the user (400 DATA00030, 403 CNX00080). Success: "
    "The child workload ends with every step Succeeded. If it fails: Open the run output of 'install-configure-upgrade'; "
    "Configuration's log is quoted there.")
# ---- internal/shared/matching-api-key-set (Gene 11/08): the pack standard. The key is set, and IIS restarted so every
# service reads it, before any step queries the gateway; a clean Profisee Configuration issues a new key (gateway 401).
_s1k = {s['label']: s for s in read(os.path.join(wl_root, 'internal', '1k', 'matching-1k-scenario1.workload.json'))['steps']}
_verify_data = copy.deepcopy(tsteps['Verify API Key Through Gateway'])
_verify_data['label'] = "Verify API Key Through Data Service"
_verify_data['inline']['url'] = "{{ProfiseeBaseUrl}}/v1/Rules?PageSize=1"
_verify_data['inline']['description'] = DATA_KEY_DESC
_key_globals = {k: template['globalParameters'][k] for k in (
    "ApplicationServerName", "DatabaseServerName", "ProfiseeInstanceName", "ProfiseeDatabaseName", "ProfiseeBaseUrl",
    "MainHealthUrl", "ProfiseeApiKey", "ApiKeyUserName")}
dump(os.path.join(wl_root, 'internal', 'shared', 'matching-api-key-set.workload.json'), {
    "name": "matching-api-key-set",
    "description": ("What: Stop the Profisee service and IIS on the application server, write the standard API key "
                    "(RestKeys:ProfiseeRestKey) for the API user (ConnectRuntime:ApiKeyUserName) into the Profisee database, start "
                    "IIS and the service, wait for every service, and prove the key through the gateway and the Data service. Why: "
                    "the pack standard: the key is set before any step queries the gateway; a clean Profisee Configuration issues a "
                    "new key, and the services read a key change only after IIS restarts. When: Never run directly; "
                    "matching-preflight and every matching-<size>-scenario1-load run it. Running it alone is safe when no test uses "
                    "this Profisee database. Needs: the API user exists in the Profisee database; no test running on this application "
                    "server. Success: Every step Succeeded or Skipped. If it fails: open the first failed step, whose If it fails text "
                    "names what to check."),
    "tags": ["matching", "internal", "shared", "api-key"], "globalParameters": _key_globals, "globalParametersNotes": "",
    "credentialUserId": None, "credentialPassword": None, "credentialNotes": "",
    "steps": [copy.deepcopy(_s1k['Stop Profisee Service']), *copy.deepcopy(IIS_STOP), copy.deepcopy(tsteps['Set API Key']),
              *copy.deepcopy(IIS_START), copy.deepcopy(_s1k['Start Profisee Service']), copy.deepcopy(tsteps['Start Every Service']),
              copy.deepcopy(tsteps['Verify API Key Through Gateway']), _verify_data]})


def key_set_child():
    return {"label": "Set And Verify API Key", "inline": run_child(
        "matching-api-key-set", "Set the standard API key, restart IIS so every service reads it, and prove it through the "
        "gateway and the Data service", timeout=3600)}


setup_steps = []
for label, n in SIZES.items():
    low = label.lower()
    wl = os.path.join(wl_root, 'internal', low)
    s1 = read(os.path.join(wl, f'matching-{low}-scenario1.workload.json'))
    s1steps = {s['label']: s for s in s1['steps']}

    # ---- load: empty baseline, point RetailClientImport at this size's table, load, back up 'loaded'
    load = copy.deepcopy(template)
    load['name'] = f'matching-{low}-scenario1-load'
    load['tags'] = ["matching", label, "scenario1", "load"]
    load['description'] = (
        f"What: Restore the empty baseline, run Profisee Configuration on it, set the standard API key, warm the instance, point the Connect strategy "
        f"RetailClientImport at {{{{SourceTableName}}}}, load its {n} rows into the empty RetailClient entity, check every Code "
        f"arrived, and back up the {label} 'loaded' checkpoint. Why: Scenario 1 of this size starts from this backup; Scenario 2, 3b and 3c "
        "update records by these Codes. When: once per box and Profisee version for each size, and whenever the empty baseline "
        "changes; a rerun restores and configures the baseline itself. Needs: the install pack on this box "
        "(install-configure-upgrade and its reference data); profisee_Matching_empty.bak (the model, the RetailClient matching "
        "strategy, no records; the load re-creates the ModelSource service configuration) in the SQL Server default backup folder; the machine's "
        "API user exists in Profisee. Success: every step Succeeded. If it fails: the failed step's description says what to fix; rerun the whole workload.")
    g = load['globalParameters']
    g.update({"SourceTableName": f"RetailClient{label}Scenario1", "RecordCount": str(n), "SizeLabel": label,
              "StrategyId": STRATEGY_ID, "RunAsUser": "{{$config:ConnectRuntime:ConnectRunAsUser}}",
              "TestAutoBaseUrl": s1['globalParameters']['TestAutoBaseUrl']})
    restore = copy.deepcopy(s1steps['Restore Loaded'])
    restore['label'] = "Restore Empty Baseline"
    restore['inline']['backupFileName'] = "profisee_Matching_empty.bak"
    restore['inline']['description'] = (
        "What: Restore the empty baseline over the Profisee database WITH REPLACE. The executor takes the database OFFLINE WITH "
        "ROLLBACK IMMEDIATE first and brings it back ONLINE if the restore fails. Why: every size loads into the same empty model. "
        "Success: restored. If it fails: profisee_Matching_empty.bak is missing from the SQL Server default backup folder, or the "
        "CrewChief account is not sysadmin there.")
    run_load = copy.deepcopy(tsteps['Run Scenario 1 Load'])
    wait_load = copy.deepcopy(tsteps['Wait For Scenario 1 Load'])
    wait_load['inline']['maxWaitMinutes'] = 1440
    backup_loaded = copy.deepcopy(tsteps['Back Up Loaded'])
    backup_loaded['inline']['sqlCommandTimeoutSeconds'] = 7200
    backup_loaded['inline']['timeoutSeconds'] = 7300
    after_configure = copy.deepcopy(tsteps['Start Every Service'])
    after_configure['label'] = "Wait For Every Service After Configuration"
    load['steps'] = [
        copy.deepcopy(s1steps['Wait For Interrupted Runs']),
        copy.deepcopy(s1steps['Stop Profisee Service']),
        *copy.deepcopy(IIS_STOP),
        restore,
        *copy.deepcopy(IIS_START),
        copy.deepcopy(s1steps['Start Profisee Service']),
        {"label": "Configure The Restored Baseline", "inline": copy.deepcopy(configure)},
        after_configure,
        key_set_child(),
        {"label": "Check Connect Run-As User", "inline": {**copy.deepcopy(tsteps['Check RetailClient Is Empty']['inline']),
            "sqlScript": ("IF NOT EXISTS (SELECT 1 FROM meta.tUser WHERE [Name] = N'{{RunAsUser}}')\r\n"
                          "    THROW 50013, N'Connect run-as user {{RunAsUser}} (ConnectRuntime:ConnectRunAsUser) is not a Profisee user; the load batch would fail.', 1;\r\n"
                          "PRINT N'Connect run-as user {{RunAsUser}} is a Profisee user.';"),
            "description": ("What: Confirm the Connect run-as account (secret ConnectRuntime:ConnectRunAsUser) is a Profisee user. Why: the "
                            "imported strategy runs its batches as that account; a missing user fails the load after the import. "
                            "Success: the user exists. If it fails: add the account in Profisee (and to the empty baseline) or change the secret.")}},
        {"label": "Remove RetailClientImport", "inline": {
            **base, "executionPolicy": "Bypass", "preferWindowsPowerShell": False, "runAsAdministrator": False,
            "captureVerbose": False, "captureDebug": False, "treatStderrAsError": True, "scriptContent": delete_script,
            "type": "PowerShellStep",
            "description": ("What: Delete the Connect strategy {{StrategyName}} ({{StrategyId}}) when present. Why: a Connect import of an id "
                            "that already exists fails; the import below brings it back pointed at this size's table. Touches nothing else. "
                            "Success: HTTP 200, 204 or 404. If it fails: check the Connect API key (RestClients:Connect:ApiKey) and that "
                            "the gateway answers.")}},
        {"label": "Remove ModelSource Service Configuration", "inline": {
            **base, "executionPolicy": "Bypass", "preferWindowsPowerShell": False, "runAsAdministrator": False,
            "captureVerbose": False, "captureDebug": False, "treatStderrAsError": True, "scriptContent": sc_delete_script,
            "type": "PowerShellStep",
            "description": ("What: Delete the Connect service configuration 'ModelSource' when present. Why: the import below "
                            "brings it back pointed at matching/databases:ModelSourceDB on matching/machines:DatabaseServerName; "
                            "a Connect import of an existing id fails. Touches nothing else. Success: HTTP 200, 204 or 404. "
                            "If it fails: check the Connect API key (RestClients:Connect:ApiKey) and that the gateway answers.")}},
        {"label": "Import ModelSource Service Configuration", "inline": connex(
            "Import",
            ("What: Import the Connect service configuration 'ModelSource' for database {{ModelSourceDB}} on "
             "{{DatabaseServerName}}, signing in with UserCredentials:SqlAdminUser. Why: the source database name and server "
             "come from this box's reference data, not from the empty baseline. Success: Connect accepts the import. "
             "If it fails: 400 'duplicated Id' = the delete above did not remove it; a sign-in error = the UserCredentials secrets."),
            resourceType="ServiceConfiguration", artifactJson=sc_artifact, parameters=sc_parameters)},
        {"label": "Import RetailClientImport", "inline": connex(
            "Import",
            ("What: Import the Connect strategy {{StrategyName}} reading {{ModelSourceDB}}.dbo.{{SourceTableName}} through the ModelSource "
             "service configuration, running as {{RunAsUser}}. Why: one strategy serves every size; only its source table changes. "
             "Success: Connect accepts the import. If it fails: 400 'duplicated Id' = the delete above did not remove it; 'could not "
             "be converted' = the artifact does not fit this Profisee release (export the strategy again)."),
            artifactJson=artifact)},
        {"label": "Enable RetailClientImport", "inline": connex(
            "Enable",
            "What: Enable {{StrategyName}}. Why: an imported strategy starts Disabled and Connect will not run it. "
            "Success: Connect accepts the call. If it fails: check the strategy id {{StrategyId}} exists (the import above).",
            resourceId="{{StrategyId}}")},
        copy.deepcopy(tsteps['Check Strategy Source Table']),
        copy.deepcopy(tsteps['Check RetailClient Is Empty']),
        run_load, wait_load,
        copy.deepcopy(tsteps['Check Loaded Rows And Codes']),
        backup_loaded,
    ]
    dump(os.path.join(wl, f'matching-{low}-scenario1-load.workload.json'), load)

    chain = [(f'matching-{low}-scenario1-load', f"Load {label}", f"Load the {label} Scenario 1 table into the empty model and back up 'loaded'")]
    for scn in ('1', '2', '3a', '3b', '3c'):
        chain.append((f'matching-{low}-scenario{scn}', f"Scenario {scn} {label}", f"Measured run: Matching {label} Scenario {scn}"))
    needs = ", ".join(c[0] for c in chain)

    def chain_steps():
        return [{"label": lab, "inline": run_child(name, what)} for name, lab, what in chain]

    dump(os.path.join(wl, f'matching-{low}-all.workload.json'), {
        "name": f"matching-{low}-all",
        "description": (f"What: The whole {label} Matching chain in order: load, then Scenarios 1, 2, 3a, 3b and 3c, each restoring the "
                        "previous one's checkpoint. Why: A building block of the Matching pack; the test and schedule workloads run it so its "
                        "steps exist once. When: Never run directly once the pack is tested; its parents run it. Running it alone is safe "
                        f"only when its own Needs are met. Needs: matching-setup ran on this box; workloads it runs: {needs}. "
                        "Success: Every step Succeeded or Skipped. If it fails: open the first failed step, whose If it fails text names what to check."),
        "tags": ["matching", label, "all"], "globalParameters": {},
        "globalParametersNotes": "Each child owns its run; a failed run stops the chain.",
        "credentialUserId": None, "credentialPassword": None, "credentialNotes": "", "steps": chain_steps()})

    dump(os.path.join(wl_root, 'tests', f'matching-test-{low}.workload.json'), {
        "name": f"matching-test-{low}",
        "description": (f"What: Runs the Matching test at {label} ({n} records): load, then Scenarios 1, 2, 3a, 3b and 3c, each a measured "
                        "TestAuto run whose results land in TestAuto. Why: This is the test a person starts: one size, every scenario. "
                        "When: Any time after matching-setup has run on this box for the current Profisee version; never at the same time "
                        "as another test on the same Profisee database. Needs: matching-setup; the matching/* reference sets filled in. "
                        "Success: Every run ends Succeeded; each TestAuto execution holds its metrics. If it fails: It stops at the first "
                        "failed run: open that run's output."),
        "tags": ["matching", "tests", label], "globalParameters": {}, "globalParametersNotes": "",
        "credentialUserId": None, "credentialPassword": None, "credentialNotes": "", "steps": chain_steps()})

    date, time, day = SCHEDULE[label]
    task = f"schedule-matching-{low}"
    dump(os.path.join(wl_root, 'schedule', low, f'{task}.workload.json'), {
        "name": task,
        "description": (f"What: Create or update the Windows scheduled task '\\CrewChief\\{task}' that runs matching-{low}-all from the "
                        f"CrewChief CLI on the schedule in the globals (default weekly, {day} {time}, as CORP\\speedmerchants). Run it again "
                        "after changing a global; nothing is scheduled until it runs. Why: Lets the size's runs repeat on a schedule without "
                        "a person. When: Run it once to create or update the Windows scheduled task, and again after changing a schedule "
                        "global. Needs: nothing beyond the box's secrets. Success: Every step Succeeded or Skipped. If it fails: open the "
                        "first failed step, whose If it fails text names what to check."),
        "tags": ["matching", "schedule", label],
        "globalParameters": {"TaskName": task, "TargetWorkload": f"matching-{low}-all",
                             "CliPath": "C:\\Deploy\\CrewChief\\cli\\crewchief.exe", "DataFolder": "C:\\Deploy\\CrewChief\\web\\data",
                             "StartDate": date, "StartTime": time, "Recurrence": "Weekly", "Interval": "1", "DaysOfWeek": day,
                             "RunAsAccount": "CORP\\speedmerchants"},
        "globalParametersNotes": ("Change StartDate, StartTime, Recurrence (Once, Daily, Weekly), Interval and DaysOfWeek, then run this "
                                  "workload. The run-as password is the secret Scheduler:RunAsPassword. Every schedule-matching-* restores "
                                  "the same Profisee database: set each StartTime after measuring that size's chain; overlapping schedules "
                                  "restore the database under each other and ruin both runs (also Connect tests on this box)."),
        "credentialUserId": None, "credentialPassword": None, "credentialNotes": "",
        "steps": [{"label": "Apply Schedule", "inline": {
            "action": "Apply", "taskName": "{{TaskName}}", "targetWorkload": "{{TargetWorkload}}", "cliPath": "{{CliPath}}",
            "dataFolder": "{{DataFolder}}", "startDate": "{{StartDate}}", "startTime": "{{StartTime}}",
            "recurrence": "{{Recurrence}}", "interval": "{{Interval}}", "daysOfWeek": "{{DaysOfWeek}}", "endDate": "",
            "runAsAccount": "{{RunAsAccount}}", "runAsPassword": "{{$config:Scheduler:RunAsPassword}}", "runElevated": True,
            "type": "ScheduleTaskStep", **{k: v for k, v in base.items() if k != 'notes'}, "timeoutSeconds": 120,
            "description": (f"What: Create or update the scheduled task for matching-{low}-all. Why: Puts the run on the Windows Task "
                            "Scheduler so it repeats without a person. Success: Task Scheduler holds the task under \\CrewChief with the "
                            "schedule in the globals. If it fails: Check the run-as account and its password secret "
                            "(Scheduler:RunAsPassword) and that the CrewChief CLI path in the globals exists."),
            "notes": ""}}]})

    setup_steps.append({"label": f"TestAuto Workflows {label}", "inline": run_child(
        f'matching-{low}-testauto-create', f"Create or update the {label} run profiles and TestAuto workflows", timeout=3600)})

dump(os.path.join(wl_root, 'start', 'matching-setup.workload.json'), {
    "name": "matching-setup",
    "description": ("What: Create or update the Matching run profiles and the tagged TestAuto workflows of every size (1K, 10K, 100K, 1M, 100M) "
                    "in the TestAuto repository. Why: every scenario workload finds its workflow by automation tag and the timing steps "
                    "record under the run profiles. When: once per box and Profisee version, and after any change to a workflow spec; "
                    "reruns update in place. Needs: the TestAuto version in matching/environment:ProfiseeVersionCode exists in the "
                    "repository. Success: Every step Succeeded. If it fails: open the first failed step, whose If it fails text names what to check."),
    "tags": ["matching", "setup"], "globalParameters": {}, "globalParametersNotes": "",
    "credentialUserId": None, "credentialPassword": None, "credentialNotes": "", "steps": setup_steps})
print('sizes written:', ', '.join(SIZES))

# ---- start/matching-preflight: checks only (gen_preflight.py)
subprocess.run([sys.executable, os.path.join(here, 'gen_preflight.py'), root], check=True)
