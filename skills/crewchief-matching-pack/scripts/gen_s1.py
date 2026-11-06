"""Adds the TestAuto create + Scenario 1 run workloads of one size to the matching pack.
Usage: python gen_s1.py <packRoot> <connectUpsertBody.ps1> <SizeLabel: 1K|10K|100K|1M>

Source of the TestAuto step configs: PROD workflow 10000215 steps 5-11 (read 11/05), with
{{STEP:7}} -> {{STEP:3}}, sizes/run profile/version/environment moved to reference data.
"""
import json, os, sys

root = sys.argv[1]
SIZE_LABEL = sys.argv[3] if len(sys.argv) > 3 else '1K'
SIZES = {'1K': 1000, '10K': 10000, '100K': 100000, '1M': 1000000}
N = SIZES[SIZE_LABEL]
LOW = SIZE_LABEL.lower()
ref = os.path.join(root, 'reference-kv', 'matching')
wl = os.path.join(root, 'workloads', 'matching', 'internal', LOW)
os.makedirs(wl, exist_ok=True)
upsert_code = open(sys.argv[2], encoding='utf-8').read()  # Connect pack upsert body (after the spec)


def load(name):
    with open(os.path.join(ref, name + '.json'), encoding='utf-8') as f:
        return json.load(f)


def save(name, obj):
    with open(os.path.join(ref, name + '.json'), 'w', encoding='utf-8') as f:
        json.dump(obj, f, indent=2)


m = load('machines')
m['entries'].update({"TestServerName": "CORPLTR94", "TestServerNameFQDN": "CORPLTR94.corp.profisee.com"})
m['keyDescriptions'].update({
    "TestServerName": "Machine running TestAuto; written into each TestAuto step's environment block.",
    "TestServerNameFQDN": "Fully qualified name of the TestAuto machine; CrewChief calls TestAuto on port 8443 there."})
save('machines', m)
save('urls', {"description": "Matching pack: REST addresses.", "includeInReplacements": True,
              "entries": {"ScenarioMgtBaseUrl": "https://profiseecloud.dev/speedmerchantstest/rest/"},
              "keyDescriptions": {"ScenarioMgtBaseUrl": "REST address of the TestAuto repository (ScenarioMgt) the local TestAuto reads; workflows and run profiles are written there."}})
save('environment', {"description": "Matching pack: what differs between Profisee releases and boxes. Edit after every Profisee upgrade.",
                     "includeInReplacements": True,
                     "entries": {"ProfiseeVersionCode": "26R3T", "MainMachineTag": "CORPLTR94", "MainServiceName": ""},
                     "keyDescriptions": {
                         "ProfiseeVersionCode": "TestAuto version code (data.tProfiseeVersion) the runs are recorded under; also part of every automation tag and run profile code.",
                         "MainMachineTag": "Plain tag naming the machine the runs measure.",
                         "MainServiceName": "Profisee Windows service on the application server, stopped around a restore. Blank on releases with no Windows service; the stop and start steps then report Skipped."},
                     "keyBlankAllowed": {"MainServiceName": True}})
wfr = load('workflows')  # the driver (gen_sizes.py) empties the entries once; each size adds its own
wfr['entries'][f"matching-{LOW}-scenario1"] = f"Matching {SIZE_LABEL} Scenario 1"
wfr['keyDescriptions'][f"matching-{LOW}-scenario1"] = f"Display name of the TestAuto workflow for Matching Scenario 1 (match the full load), {SIZE_LABEL}. Its automation tag is AUTO:<this box>:<ProfiseeVersionCode>:matching-{LOW}-scenario1; the name is free text and only for people."
save('workflows', wfr)

VER = "{{$ref:matching/environment:ProfiseeVersionCode}}"
RUN_PROFILE = VER + f"-RetailClient-Scenario 1-{N}-0"

empty_rest = {"RestUrlBase": "", "RestApiKey": ""}
empty_cs = {"ConnectionString": ""}


def scenario(name, custom, tme="", source="RetailClient", query=None, tid=1, rest_areas=("Profisee", "Metrics", "Connect", "Portal", "Matching", "Monitor")):
    cfg = {
        "ScenarioName": name,
        "MaxHangfireScenarioServersCount": 1,
        "ScenarioTables": {"SourceEntityName": source, "TargetEntityName": "RetailClient"},
        "ScenarioDataShape": {"FreeformAttributes": 0, "DomainAttributes": 0},
        "ScenarioRuntime": {"NumberOfGeneratedTestRecordsPerBatch": 1, "BatchSize": 1, "PageNumber": 1,
                            "MaxHangfireScenarioServersCount": 1, "MaxConcurrentBatchesPerHangfireScenarioServer": 1,
                            "CustomParms": custom},
        "ScenarioTesting": {"TestRecordLimit": 1, "TestOverrideQueueName": ""},
        "ScenarioQuery": query or {"SelectAttributes": "", "SortAttributes": "", "Filter": "", "QueryParameters": {}},
        "ScenarioRestTarget": {"RestUrlBase": None, "RestApiKey": None,
                               "SubjectAreaOverrides": {a: dict(empty_rest) for a in rest_areas}},
        "ScenarioDatabaseConnectionStrings": {"ConnectionString": None, "SubjectAreaOverrides": {
            a: dict(empty_cs) for a in ("Profisee", "Metrics", "Matching", "Connect", "Portal", "Data", "TestAuto")}},
        "ScenarioEnvironment": {"DqRuleCount": 0, "TargetEnvironment": "IaaS",
                                "TargetEnvironmentName": "{{TestAutoEnvironmentName}}", "TargetMetricEntity": tme,
                                "WorkloadExecution": "", "ProfiseeVersion": VER,
                                "TargetApplicationServer": "{{TestAutoApplicationServer}}",
                                "TargetDatabaseServer": "{{TestAutoDatabaseServer}}", "ExecutionMode": "B",
                                "HangfireJob": 0, "SimulatedUserThreadId": tid},
    }
    text = json.dumps(cfg, indent=2).replace('\n', '\r\n')
    # The repository attribute holds 4000 characters; a longer value is stored as NULL without an error.
    if len(text) > 4000:
        text = json.dumps(cfg, separators=(',', ':'))
    assert len(text) <= 4000, f'{name}: configuration is {len(text)} characters even compact; the repository holds 4000'
    return text


def monitor(message, activity, desc):
    return {"GlobalParameters": {"StrategyName": "RetailClient", "ApiVersion": "v1"},
            "Steps": [{"message": message, "type": "MonitorStep", "scriptKey": None,
                       "parameters": {"ActivityType": activity}, "timeoutSeconds": 30, "continueOnError": False,
                       "workingDirectory": None, "description": desc}]}


def snapshot(step):
    return {"MatchingScenarioName": "Scenario 1", "MatchingStrategyName": "RetailClient", "ScenarioStep": step,
            "TargetEntityName": "RetailClient", "SourceRecords": N, "MatchStatusColumnName": "Match Status",
            "MatchStatusEntityName": "MatchStatus", "GoldenRecordColumnName": "Golden Record",
            "UnifiedMatchingScenarioWorkloadExecution": "{%STEP:3%}",
            "UnifiedMatchingApiExecutionRunProfile": RUN_PROFILE}


def curl(url, method, body, desc):
    return {"url": url, "method": method,
            "headers": {"Content-Type": "application/json-patch+json", "x-api-key": "{%$config:RestClients:Profisee:ApiKey%}"},
            "body": body, "bodyFilePath": None, "outputFile": None, "expectedStatusCodes": [200, 201, 204],
            "followRedirects": True, "verifySsl": False, "maxTimeSeconds": None, "customCurlArgs": None,
            "useRestMethod": True, "type": "CurlStep", "scriptKey": None,
            "parameters": {"StrategyName": "RetailClient", "ApiVersion": "v1"}, "timeoutSeconds": 60,
            "continueOnError": False, "workingDirectory": None, "description": desc}


enable_run = {"GlobalParameters": {"StrategyName": "RetailClient", "ApiVersion": "v1"}, "Steps": [
    curl("{%$config:RestClients:Profisee:BaseUrl%}v1/Matching/RetailClient", "PATCH", "{\n  \"status\": 1\n}",
         "Enable RetailClient Matching Strategy"),
    curl("{%$config:RestClients:Profisee:BaseUrl%}v1/Matching/RetailClient/processActions", "POST",
         "{\n  \"actions\": [\n    \"IncludeSurvivorship\"\n  ]\n}", "Run RetailClient Matching Strategy")]}

start_text, end_text = "Start of Scenario 1 for Retail Client", "End of Scenario 1 for Retail Client"
details = [
    ("Write Start of Scenario 1 Monitor Message", "Writes the start marker the timing step measures from.",
     scenario("MultiStepUtilityScenario", monitor("Start of RetailClient Scenario 1", "Start of Scenario", start_text),
              rest_areas=("Profisee", "Metrics", "Connect", "Portal", "Matching"))),
    ("Capture Matching Status Counts for Start of Scenario 1", "Match status counts before matching runs.",
     scenario("MatchingSnapshotCaptureScenario", snapshot("Pre"), tme="UnifiedMatchingApiExecutionMatchGroupResults",
              rest_areas=("Profisee", "Metrics", "ScenarioMgt", "Matching"))),
    ("Enable RetailClient Matching Strategy Then Run", "Enables the RetailClient strategy and runs it with survivorship over the loaded records.",
     scenario("MultiStepUtilityScenario", enable_run, rest_areas=("Profisee", "Metrics", "Connect", "Portal", "Matching"))),
    ("Wait for Matching Scenario To Finish", "Polls the RetailClient strategy until matching is idle.",
     scenario("MatchingStrategyPollingScenario", {"MatchingStrategyName": "RetailClient", "MaxWaitMinutes": 2880, "PollIntervalSeconds": 30},
              tme="Not Used", rest_areas=("Profisee", "Metrics", "ScenarioMgt", "Matching"))),
    ("Write End of Scenario 1 Monitor Message", "Writes the end marker the timing step measures to.",
     scenario("MultiStepUtilityScenario", monitor("End of RetailClient Scenario 1", "End of Scenario", end_text),
              rest_areas=("Profisee", "Metrics", "Connect", "Portal", "Matching"))),
    ("Capture Matching Status Counts for End of Scenario 1", "Match status counts after matching finished.",
     scenario("MatchingSnapshotCaptureScenario", snapshot("Post"), tme="UnifiedMatchingApiExecutionMatchGroupResults",
              rest_areas=("Profisee", "Metrics", "ScenarioMgt", "Matching"))),
    ("Matching Timing Results Scenario 1", "Collects matching timings between the start and end markers.",
     scenario("MatchingResultsScenario",
              {"StartMarkerText": start_text, "EndMarkerText": end_text, "MatchingStrategyName": "RetailClient",
               "MatchingScenarioName": "Scenario 1", "UnifiedMatchingScenarioWorkloadExecution": "{%STEP:3%}",
               "UnifiedMatchingApiExecutionRunProfile": RUN_PROFILE, "ActivityDetailTopN": 10},
              tme="UnifiedMatchingApiExecutionActivities", source="Not Used", tid=0,
              query={"SelectAttributes": "", "SortAttributes": "Code", "Filter": "", "QueryParameters": {"ignoreConstraintRules": "true"}})),
]

KEY = f"matching-{LOW}-scenario1"
spec = {"Key": KEY, "Name": "{{$ref:matching/workflows:" + KEY + "}}", "Category": "Matching",
        "PlainTags": "Matching," + VER + ",{{$ref:matching/environment:MainMachineTag}}," + SIZE_LABEL + ",Scenario 1",
        "Description": "Automation ID: <AUTOMATION_ID>. CrewChief finds this workflow by that tag alone (reference key matching/workflows:" + KEY + "); do not edit or remove the tag, and to experiment copy the workflow and remove the tag from the copy. Measures: Matching Scenario 1 (match and survive the full load), " + str(N) + " records, RetailClient strategy, on the Profisee version in matching/environment:ProfiseeVersionCode. Run by the CrewChief workload '" + KEY + "', which restores the loaded checkpoint first; running it alone measures nothing useful.",
        "Details": [{"Name": n, "Description": d, "ExecutionOrder": i + 1, "ProfiseeVersion": VER, "ScenarioConfiguration": c}
                    for i, (n, d, c) in enumerate(details)]}

upsert_code = upsert_code.replace('connect/environment:ProfiseeVersionCode', 'matching/environment:ProfiseeVersionCode') \
                         .replace('run connect-setup again', f'run matching-{LOW}-testauto-create again') \
                         .replace('$spec = $specJson | ConvertFrom-Json',
                                  "# TestAuto resolves its own step tokens at run time; the spec writes their braces as {% %} so CrewChief leaves them alone.\r\n"
                                  "$specJson = $specJson.Replace('{%', '{{').Replace('%}', '}}')\r\n"
                                  "$spec = $specJson | ConvertFrom-Json")
assert "Replace('{%'" in upsert_code, 'upsert code shape changed'
spec_script = "$specJson = @'\r\n" + json.dumps(spec, ensure_ascii=False) + "\r\n" + upsert_code

base = {"parameters": {}, "timeoutSeconds": 600, "continueOnError": False, "retryEnabled": False, "maxRetries": 0,
        "retryDelaySeconds": 5, "workingDirectory": None, "notes": ""}

run_profile_script = "\r\n".join([
    "$ErrorActionPreference = 'Stop'",
    "$base = '{{ScenarioMgtBaseUrl}}'.TrimEnd('/') + '/'",
    "$headers = @{ 'x-api-key' = '{{ScenarioMgtApiKey}}'; accept = 'application/json' }",
    "$version = '" + VER + "'",
    "$verFilter = [uri]::EscapeDataString(\"[Code] eq '$version'\")",
    "$v = Invoke-RestMethod -Uri \"${base}v1/Records/ProfiseeVersion?Filter=$verFilter\" -Headers $headers",
    "$rows = if ($v -is [array]) { $v } else { @($v.data) }",
    "if (-not $rows) { throw \"TestAuto version '$version' does not exist in the repository; create it (data.tProfiseeVersion) before running this workload.\" }",
    "$profile = [ordered]@{ Code = '" + RUN_PROFILE + "'; ProfiseeVersion = $version; Scenario = 'UnifiedMatchingScenario'",
    "    MatchingStrategy = 'RetailClient'; MatchingScenarioName = 'Scenario 1'; SourceRecordCount = " + str(N) + "",
    "    AttributeCount = 42; DBACount = 5; FreeformCount = 37; IncrementalVolumeCount = 0; RuleCount = 0 }",
    "Invoke-RestMethod -Method Patch -Uri \"${base}v1/Records/UnifiedMatchingApiExecutionRunProfile?IsUpsert=true\" -Headers $headers -ContentType 'application/json' -Body (ConvertTo-Json -Depth 5 -InputObject @($profile)) | Out-Null",
    "\"Run profile $($profile.Code) upserted.\"",
])

create = {
    "name": f"matching-{LOW}-testauto-create",
    "description": f"What: Create or update the {SIZE_LABEL} Matching run profile and the TestAuto workflow 'Matching {SIZE_LABEL} Scenario 1' in the TestAuto repository. Why: the scenario workloads find the workflow by its automation tag and the timing steps record under the run profile. When: once per box and Profisee version, and after any change to the workflow spec; reruns update in place. Needs: the TestAuto version in matching/environment:ProfiseeVersionCode exists in the repository; local TestAuto answers on port 8443. Success: every step Succeeded. If it fails: the failed step's description says what to fix.",
    "tags": ["matching", SIZE_LABEL, "testauto", "setup"],
    "globalParameters": {
        "ScenarioMgtBaseUrl": "{{$ref:matching/urls:ScenarioMgtBaseUrl}}",
        "ScenarioMgtApiKey": "{{$config:RestClients:ScenarioMgt:ApiKey}}",
        "TestAutoBaseUrl": "https://{{$ref:matching/machines:TestServerNameFQDN}}:8443",
        "TestAutoEnvironmentName": "{{$ref:matching/machines:TestServerName}}",
        "TestAutoApplicationServer": "{{$ref:matching/machines:ApplicationServerName}}",
        "TestAutoDatabaseServer": "{{$ref:matching/machines:DatabaseServerName}}",
        "TestAutoSourceDatabase": "{{$ref:matching/databases:ModelSourceDB}}"},
    "globalParametersNotes": "", "credentialUserId": "", "credentialPassword": "", "credentialNotes": "",
    "steps": [
        {"label": "ScenarioMgt Check", "inline": {**base, "url": "{{ScenarioMgtBaseUrl}}v1/Records/TestAutoWorkflow?PageSize=1", "method": "GET",
            "headers": {"x-api-key": "{{ScenarioMgtApiKey}}", "accept": "application/json"}, "body": "", "outputFile": "",
            "expectedStatusCodes": [200], "followRedirects": True, "verifySsl": True, "maxTimeSeconds": 300, "type": "HTTP",
            "description": "What: List one TestAuto workflow. Why: proves the address and key reach the TestAuto repository before anything is written. Success: HTTP 200. If it fails: 401 = wrong ScenarioMgt key; 404 = wrong address in matching/urls:ScenarioMgtBaseUrl."}},
        {"label": "Upsert Run Profile", "inline": {**base, "executionPolicy": "Bypass", "preferWindowsPowerShell": False, "runAsAdministrator": False,
            "captureVerbose": False, "captureDebug": False, "treatStderrAsError": True, "scriptContent": run_profile_script, "type": "PowerShellStep",
            "description": "What: Create or update the run profile " + RUN_PROFILE + ". Why: the snapshot and timing steps record their results under it. Success: the profile is upserted. If it fails: a missing TestAuto version is named in the error; create it in the repository."}},
        {"label": "Upsert Workflow " + KEY, "inline": {**base, "executionPolicy": "Bypass", "preferWindowsPowerShell": False, "runAsAdministrator": False,
            "captureVerbose": False, "captureDebug": False, "treatStderrAsError": True, "scriptContent": spec_script, "type": "PowerShellStep",
            "description": "What: Create or update the TestAuto workflow '" + KEY + "' and its 7 steps, found by its automation tag. Why: CrewChief runs it by that tag. Success: the workflow exists with exactly these steps. If it fails: two workflows with the same tag must be untagged by hand first."}},
    ],
}

H = 'Server={{DatabaseServerName}};Database={{ProfiseeDatabaseName}};Integrated Security=True;TrustServerCertificate=True'
M = 'Server={{DatabaseServerName}};Database=master;Integrated Security=True;TrustServerCertificate=True'


def sql(cs, script, desc, timeout=300):
    return {**base, "sqlSourceConnectionSecretName": cs, "sqlDestinationConnectionSecretName": cs,
            "sqlCommandTimeoutSeconds": timeout, "sqlAllowNonTransactionalBatches": False, "useTransaction": False,
            "captureScalarResult": False, "sqlScript": script, "autoWrapPassFailCode": True, "dryRun": False,
            "sqlDropConnections": False, "type": "SqlStep", "description": desc}


restore = "\r\n".join([
    "DECLARE @bak nvarchar(500) = CAST(SERVERPROPERTY('InstanceDefaultBackupPath') AS nvarchar(400)) + N'\\profisee_Matching_{{SizeLabel}}_{{RestoreSuffix}}.bak';",
    "DECLARE @db sysname = N'{{ProfiseeDatabaseName}}';",
    "DECLARE @disk nvarchar(600) = N'N''' + REPLACE(@bak, N'''', N'''''') + N'''';",
    "DECLARE @sql nvarchar(max) = N'ALTER DATABASE ' + QUOTENAME(@db) + N' SET SINGLE_USER WITH ROLLBACK IMMEDIATE;';",
    "EXEC (@sql);",
    "BEGIN TRY",
    "    SET @sql = N'RESTORE DATABASE ' + QUOTENAME(@db) + N' FROM DISK = ' + @disk + N' WITH REPLACE, CHECKSUM;';",
    "    EXEC (@sql);",
    "END TRY",
    "BEGIN CATCH",
    "    SET @sql = N'ALTER DATABASE ' + QUOTENAME(@db) + N' SET MULTI_USER;';",
    "    EXEC (@sql);",
    "    THROW;",
    "END CATCH",
    "SET @sql = N'ALTER DATABASE ' + QUOTENAME(@db) + N' SET MULTI_USER;';",
    "EXEC (@sql);",
    "PRINT CONCAT(N'Restored ', @db, N' from ', @bak, N'.');",
])
backup = "\r\n".join([
    "DECLARE @bak nvarchar(500) = CAST(SERVERPROPERTY('InstanceDefaultBackupPath') AS nvarchar(400)) + N'\\profisee_Matching_{{SizeLabel}}_{{BackupSuffix}}.bak';",
    "DECLARE @sql nvarchar(max) = N'BACKUP DATABASE ' + QUOTENAME(N'{{ProfiseeDatabaseName}}') + N' TO DISK = N''' + REPLACE(@bak, N'''', N'''''') + N''' WITH INIT, COMPRESSION, CHECKSUM';",
    "EXEC (@sql);",
    "SET @sql = N'RESTORE VERIFYONLY FROM DISK = N''' + REPLACE(@bak, N'''', N'''''') + N''' WITH CHECKSUM';",
    "EXEC (@sql);",
    "PRINT CONCAT(N'Backed up {{ProfiseeDatabaseName}} to ', @bak, N' and verified it.');",
])
with open(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'monitor_quiet.sql'), encoding='utf-8') as _f:
    MONITOR_QUIET_SQL = _f.read().replace(chr(10), chr(13) + chr(10))
check_matched = "\r\n".join([
    "-- Golden records (match status code 10) are created by survivorship; every other row is a loaded record.",
    "DECLARE @golden bigint = (SELECT COUNT_BIG(*) FROM data.tRetailClient r JOIN data.tMatchStatus s ON s.ID = r.[Match Status] WHERE s.Code = N'10');",
    "DECLARE @loaded bigint = (SELECT COUNT_BIG(*) FROM data.tRetailClient) - @golden;",
    "DECLARE @matched bigint = (SELECT COUNT_BIG(*) FROM data.tRetailClient r JOIN data.tMatchStatus s ON s.ID = r.[Match Status] WHERE s.Code <> N'10');",
    "DECLARE @skipped bigint = @loaded - @matched;",
    "IF @loaded <> {{RecordCount}} OR @golden = 0 OR @matched = 0",
    "BEGIN",
    "    DECLARE @msg nvarchar(400) = CONCAT(N'After Scenario 1: ', @loaded, N' loaded rows (expected {{RecordCount}}), ', @matched, N' with a match status, ', @golden, N' golden records; matching did not run or did not finish.');",
    "    THROW 50006, @msg, 1;",
    "END",
    "PRINT CONCAT(N'After Scenario 1: ', @loaded, N' loaded rows, ', @matched, N' with a match status, ', @golden, N' golden records, ', @skipped, N' left unmatched by the strategy (too few match fields).');",
])

pools = ["", "-api", "-attachments", "-workflows", "-auth", "-rest", "-mcp", "-governance", "-connex", "-monitor", "-matching",
         "-bulkscoring", "-data", "-modeling", "-chatbot", "-analytics", "-scriptrunner", "-portalartifacts", "-proflow", "-taskman"]
health = None
with open(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'health.ps1'), encoding='utf-8', newline='') as f:
    health = f.read()


def dbop(operation, file_name, desc):
    return {**base, "serverName": "{{DatabaseServerName}}", "connectionSecretName": "", "authMode": "Windows", "credentialUserId": "",
            "credentialPassword": "", "databaseName": "{{ProfiseeDatabaseName}}", "operation": operation, "snapshotName": "",
            "backupFileName": file_name, "fileUncPath": None, "overwrite": True, "relocateFiles": False, "waitIndefinitely": True,
            "dryRun": False, "type": "DatabaseOperationsStep", "timeoutSeconds": 7200, "description": desc}


def service(action, desc):
    return {**base, "serviceName": "{{$ref:matching/environment:MainServiceName}}", "action": action, "targetComputer": "{{ApplicationServerName}}",
            "credentialSecretName": None, "credentialUserId": "{{$config:UserCredentials:AdminUser}}",
            "credentialPassword": "{{$config:UserCredentials:AdminPassword}}", "remoteAuthentication": "CredSSP", "type": "ServiceControlStep",
            "runWhen": "{{$ref:matching/environment:MainServiceName}}", "description": desc}


SERVICE_FAIL = " If it fails: check the service name exists on the application server (services.msc) and the admin credential (UserCredentials secrets) can manage services there over CredSSP. Skipped when: matching/environment:MainServiceName is blank, normal on releases with no Profisee Windows service."

s1 = {
    "name": KEY,
    "description": f"What: Restore the {SIZE_LABEL} 'loaded' checkpoint, warm the instance, run the TestAuto workflow 'Matching {SIZE_LABEL} Scenario 1' (markers, counts, enable and run the RetailClient strategy, wait, timing), check every record got a match status, and back up 'after-1'. Why: Scenario 1 measures matching of the full load, and Scenario 2 starts from 'after-1'. When: whenever Scenario 1 is measured; a rerun restores its own start. Needs: matching-{LOW}-scenario1-load ran once (the 'loaded' backup exists) and matching-{LOW}-testauto-create ran on this box. Success: every step Succeeded. If it fails: the failed step's description says what to fix; rerun the whole workload.",
    "tags": ["matching", SIZE_LABEL, "scenario1", "test"],
    "globalParameters": {
        "DatabaseServerName": "{{$ref:matching/machines:DatabaseServerName}}",
        "ProfiseeDatabaseName": "{{$ref:matching/databases:ProfiseeDatabaseName}}",
        "ApplicationServerName": "{{$ref:matching/machines:ApplicationServerName}}",
        "ProfiseeInstanceName": "{{$ref:matching/instances:ProfiseeInstanceName}}",
        "MainHealthUrl": "https://{{$ref:matching/machines:ApplicationServerNameFQDN}}/{{$ref:matching/instances:ProfiseeInstanceName}}/rest/health",
        "TestAutoBaseUrl": "https://{{$ref:matching/machines:TestServerNameFQDN}}:8443",
        "RecordCount": str(N), "SizeLabel": SIZE_LABEL, "QuietSeconds": "60"},
    "globalParametersNotes": "", "credentialUserId": "", "credentialPassword": "", "credentialNotes": "",
    "steps": [
        {"label": "Wait For Interrupted Runs", "inline": {**base, "baseUrl": "{{TestAutoBaseUrl}}", "workflowCode": "", "executionCode": "",
            "attachToActiveRun": True, "waitOnly": True, "pollIntervalSeconds": 60, "waitIndefinitely": True, "maxConsecutivePollFailures": 30,
            "ignoreSslErrors": True, "type": "TestAutoWorkflowStep",
            "description": "What: Wait for any TestAuto run already in progress. Why: a restore under a running workflow corrupts both. Success: no run is active. If it fails: TestAuto is unreachable on port 8443."}},
        {"label": "Stop Profisee Service", "inline": service("Stop", "What: Stop the Profisee Windows service before the restore. Why: it holds connections and caches from before the restore. Success: the service is stopped." + SERVICE_FAIL)},
        {"label": "Restore Loaded", "inline": dbop("RestoreDatabase", "profisee_Matching_{{SizeLabel}}_loaded.bak",
            "What: Restore the 'loaded' checkpoint over the Profisee database WITH REPLACE. The executor takes the database OFFLINE WITH ROLLBACK IMMEDIATE first and brings it back ONLINE if the restore fails. Why: every Scenario 1 run starts from the same loaded, unmatched state. Success: restored. If it fails: the backup is missing from the SQL Server default backup folder (run matching-" + LOW + "-scenario1-load), or the CrewChief account is not sysadmin there.")},
        {"label": "Recycle Instance Pools", "inline": {**base, "appPoolNames": ["{{ProfiseeInstanceName}}" + p for p in pools], "action": "Recycle",
            "staggerSeconds": None, "targetComputer": "{{ApplicationServerName}}", "credentialSecretName": None,
            "credentialUserId": "{{$config:UserCredentials:AdminUser}}", "credentialPassword": "{{$config:UserCredentials:AdminPassword}}",
            "remoteAuthentication": "CredSSP", "type": "AppPoolStep",
            "description": "What: Recycle every application pool of this instance. Why: services keep caches from before the restore; only this instance's pools are touched because other instances may share IIS. Success: every pool recycles. If it fails: a pool name does not exist; compare matching/instances:ProfiseeInstanceName with IIS Manager."}},
        {"label": "Start Profisee Service", "inline": service("Start", "What: Start the Profisee Windows service after the pools recycle. Why: it must read the restored database. Success: the service is running." + SERVICE_FAIL)},
        {"label": "Start Every Service", "inline": {**base, "executionPolicy": "Bypass", "preferWindowsPowerShell": False, "runAsAdministrator": False,
            "captureVerbose": False, "captureDebug": False, "treatStderrAsError": True, "scriptContent": health, "type": "PowerShellStep", "timeoutSeconds": 900,
            "description": "What: Wait until every health check is Healthy. Why: services stay cold after a restore and recycle. Success: all checks Healthy within 10 minutes. If it fails: open the health URL and fix the service it names."}},
        {"label": "Wait For Monitor Quiet", "inline": sql(H, MONITOR_QUIET_SQL,
            "What: Wait until the Activity Monitor has no outstanding task (every monitor.tActivity row in a finished status) and no "
            "new task has started for {{QuietSeconds}} seconds. Why: setup (restore, pool recycle, continuous matching on) can start "
            "monitor tasks; the workflow's start marker must come after them so the scenario window holds only the scenario's own work. "
            "Success: the monitor is quiet. If it fails: after 30 minutes a task is still outstanding; the error names it, check it "
            "in the portal's Activity Monitor.", timeout=1900)},
        {"label": f"Run Matching {SIZE_LABEL} Scenario 1", "inline": {**base, "baseUrl": "{{TestAutoBaseUrl}}", "workflowCode": "",
            "workflowTag": "AUTO:{{$env:COMPUTERNAME}}:{{$ref:matching/environment:ProfiseeVersionCode}}:" + KEY, "executionCode": "",
            "attachToActiveRun": True, "waitOnly": False, "pollIntervalSeconds": 60, "waitIndefinitely": True, "maxConsecutivePollFailures": 30,
            "ignoreSslErrors": True, "type": "TestAutoWorkflowStep",
            "description": f"What: Run the TestAuto workflow tagged for Matching {SIZE_LABEL} Scenario 1 and wait for it. Why: TestAuto measures the scenario. Success: the workflow run Succeeded. If it fails: open the run in TestAuto; no workflow with the tag means matching-{LOW}-testauto-create has not run on this box."}},
        {"label": "Check Matching Ran", "inline": sql(H, check_matched,
            "What: Confirm matching ran over the load: {{RecordCount}} loaded rows, some with a match status and some golden records. Records with too few match fields stay without a match status by design; their count is printed. Why: Scenario 2 needs a matched starting point. Success: the counts line prints. If it fails: matching did not run or did not finish; check the RetailClient strategy and the matching service.")},
        {"label": "Back Up After Scenario 1", "inline": dbop("BackupDatabase", "profisee_Matching_{{SizeLabel}}_after-1.bak",
            "What: Back up the Profisee database as the 'after-1' checkpoint (overwrites the previous one). Why: Scenario 2 restores it. Success: SQL Server writes the file in its default backup folder. If it fails: check disk space there and that the CrewChief account is sysadmin.")},
    ],
}

for wobj in (create, s1):
    with open(os.path.join(wl, wobj['name'] + '.workload.json'), 'w', encoding='utf-8') as f:
        json.dump(wobj, f, indent=2)
print('written')
