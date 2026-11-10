"""Builds start/matching-preflight: checks a box is ready for Matching testing and changes nothing.

Shape copied from the Connect pack's connect-preflight (11/06); every value is a matching/* reference key or a
box secret. Checks confirmed by Gene 11/06: service, pools, baseline backup, source tables, Connect run-as user,
TestAuto, TestAuto model, gateway, automation tags.

Usage: python gen_preflight.py <packRoot>     (gen_sizes.py runs it last)
"""
import json, os, sys

root = sys.argv[1]
SIZES = ['1K', '10K', '100K', '1M', '100M']
# Test plan (Gene 11/06): 1K-100K every release mid-point and GA; 1M at GA only. 100M is in the pack, but its
# tables (about 86 GB plus a 120M-row base) are built only on a box with room. Missing tables of these sizes are
# stated, not failed.
GA_ONLY = {'1M', '100M'}
SCENARIO_TABLES = ['Scenario1', 'Scenario2', 'Scenario3b', 'Scenario3c']
BACKUP_SUFFIXES = ['loaded', 'after-1', 'after-2', 'after-3a', 'after-3b', 'after-3c']
POOL_SUFFIXES = ['', '-api', '-attachments', '-workflows', '-auth', '-rest', '-mcp', '-governance', '-connex', '-monitor',
                 '-matching', '-bulkscoring', '-data', '-modeling', '-chatbot', '-analytics', '-scriptrunner',
                 '-portalartifacts', '-proflow', '-taskman']
SCENARIOS = ['scenario1', 'scenario2', 'scenario3a', 'scenario3b', 'scenario3c']

COMMON = {"workingDirectory": None, "maxRetries": 0, "retryDelaySeconds": 5, "retryEnabled": False, "notes": "",
          "parameters": {}, "continueOnError": False, "timeoutSeconds": 600}
ADMIN = {"remoteAuthentication": "CredSSP", "credentialUserId": "{{$config:UserCredentials:AdminUser}}",
         "credentialPassword": "{{$config:UserCredentials:AdminPassword}}"}
MASTER = "Server={{DatabaseServerName}};Database=master;Integrated Security=True;TrustServerCertificate=True"
PROFISEE_DB = "Server={{DatabaseServerName}};Database={{ProfiseeDatabaseName}};Integrated Security=True;TrustServerCertificate=True"
SQL_IF_FAILS = ("If it fails: Read the SQL error text first; then check the database server (matching/machines:DatabaseServerName) "
                "is reachable from this box with Windows authentication and the database named in the connection exists.")
SQL_WHY = "Why: Checks the database directly, where the Profisee API has no call for it or a check must be exact."
PS_WHY = "Why: Does work no single built-in step does (several calls or checks in one place) and stops at the first problem."
PS_RESULT = ("Success: The script finishes without an error; its output lines say what it found. If it fails: Read the last "
             "output line and the error text: the script names the value, server or record it could not handle.")
HTTP_RESULT = ("Success: The response status is one of the expected codes (200). If it fails: 401 = the API key secret is wrong; "
               "404 = the record, entity or address is missing; no response = the server in the URL (matching/urls, "
               "matching/machines) is down.")


def sql_step(label, what, script, conn, result):
    return {"label": label, "inline": {
        "type": "SqlStep", "description": f"What: {what} {SQL_WHY} {result} {SQL_IF_FAILS}",
        "sqlSourceConnectionSecretName": conn, "sqlDestinationConnectionSecretName": conn, "sqlCommandTimeoutSeconds": 120,
        "sqlAllowNonTransactionalBatches": False, "useTransaction": False, "captureScalarResult": False,
        "sqlScript": script.replace('\n', '\r\n'), "autoWrapPassFailCode": True, "dryRun": False, "sqlDropConnections": False,
        **COMMON}}


def ps_step(label, what, script):
    return {"label": label, "inline": {
        "type": "PowerShellStep", "executionPolicy": "Bypass", "description": f"What: {what} {PS_WHY} {PS_RESULT}",
        "captureDebug": False, "captureVerbose": False, "preferWindowsPowerShell": False, "runAsAdministrator": False,
        "treatStderrAsError": True, "scriptContent": script, **COMMON}}


steps = []

steps.append({"label": "Profisee Service Exists", "inline": {
    "type": "ServiceControlStep", "action": "Status", "credentialSecretName": None,
    "description": ("What: Ask the application server (matching/machines:ApplicationServerName) for the state of the Profisee "
                    "Windows service named in matching/environment:MainServiceName. Why: The resets stop and start this service "
                    "around every restore, so it must exist. Success: The step reports the service state. If it fails: Check the "
                    "service name exists on the application server (services.msc) and the admin credential (UserCredentials "
                    "secrets) can manage services there over CredSSP. Skipped when: matching/environment:MainServiceName is "
                    "blank, which is normal on releases that have no Profisee Windows service; the step then "
                    "reports Skipped, not Failed."),
    "targetComputer": "{{ApplicationServerName}}", "serviceName": "{{MainServiceName}}",
    "runWhen": "{{MainServiceName}}", **ADMIN, **COMMON}})

steps.append({"label": "Application Pools Exist", "inline": {
    "type": "AppPoolStep", "action": "Start", "credentialSecretName": None, "staggerSeconds": None,
    "description": ("What: Start (a no-op when already running) the 20 IIS application pools of the instance "
                    "(matching/instances:ProfiseeInstanceName) that every Matching reset recycles. Why: A reset fails half way "
                    "if one of these pools is missing; this finds it first. Success: Every named pool is Started. If it fails: A "
                    "pool that does not exist fails the step: compare matching/instances:ProfiseeInstanceName with IIS Manager on "
                    "the application server (matching/machines:ApplicationServerName)."),
    "appPoolNames": ["{{AnalyticsPoolName}}" if s == "-analytics" else "{{ProfiseeInstanceName}}" + s for s in POOL_SUFFIXES], "targetComputer": "{{ApplicationServerName}}",
    **ADMIN, **COMMON}})

later = ', '.join(f"profisee_Matching_<size>_{s}_<code>.bak" for s in BACKUP_SUFFIXES)
backup_sql = "\n".join([
    "DECLARE @dir nvarchar(400) = CAST(SERVERPROPERTY('InstanceDefaultBackupPath') AS nvarchar(400));",
    "DECLARE @exists int, @f nvarchar(600), @have nvarchar(max) = N'', @notYet nvarchar(max) = N'';",
    "SET @f = @dir + N'\\profisee_Matching_empty_{{ProfiseeVersionCode}}.bak'; EXEC master.dbo.xp_fileexist @f, @exists OUTPUT;",
    "IF @exists = 0 BEGIN DECLARE @msg nvarchar(2048) = N'Matching base profisee_Matching_empty_{{ProfiseeVersionCode}}.bak for version {{ProfiseeVersionCode}} is missing on {{DatabaseServerName}}. Run matching-base-create on this lane.'; THROW 50010, @msg, 1; END",
    "PRINT CONCAT(N'Baseline backup found: ', @f);",
] + [
    f"SET @f = @dir + N'\\profisee_Matching_{size}_{suffix}_{{{{ProfiseeVersionCode}}}}.bak'; EXEC master.dbo.xp_fileexist @f, @exists OUTPUT; "
    f"IF @exists = 1 SET @have += N'{size}_{suffix} ' ELSE SET @notYet += N'{size}_{suffix} ';"
    for size in SIZES for suffix in BACKUP_SUFFIXES
] + [
    "PRINT CONCAT(N'Scenario backups present: ', IIF(@have = N'', N'none', @have));",
    "IF @notYet <> N'' PRINT CONCAT(N'Not made yet (each is written by the load or scenario before it; not a failure): ', @notYet);",
])
steps.append(sql_step(
    "Baseline Backup Exists",
    ("Check the empty baseline of this version (profisee_Matching_empty_<code>.bak) sits in the SQL Server default backup folder of the database server "
     "(matching/machines:DatabaseServerName); every Matching load restores it, and matching-base-create makes it. Also lists which per-size scenario backups "
     f"({later}) already exist; those are written by the runs themselves, so a missing one is stated, not failed."),
    backup_sql, MASTER,
    "Success: The baseline backup exists; the output lists the scenario backups present and not made yet. If it fails: the baseline of this version is missing: run matching-base-create on this lane."))

table_lines = ["DECLARE @missing nvarchar(max) = N'', @gaOnly nvarchar(max) = N'', @n bigint;"]
for size in SIZES:
    for t in SCENARIO_TABLES:
        name = f"RetailClient{size}{t}"
        miss = "@gaOnly" if size in GA_ONLY else "@missing"
        table_lines.append(
            f"IF OBJECT_ID(N'dbo.{name}', N'U') IS NULL SET {miss} += N'{name} ' "
            f"ELSE BEGIN SELECT @n = SUM(p.rows) FROM sys.partitions p WHERE p.object_id = OBJECT_ID(N'dbo.{name}') AND p.index_id IN (0, 1); "
            f"PRINT CONCAT(N'{name}: ', @n, N' rows'); END")
table_lines += [
    "IF @gaOnly <> N'' PRINT CONCAT(N'1M or 100M tables missing (1M runs at GA only; 100M only where the box has room; needed before a run of that size): ', @gaOnly);",
    "IF @missing <> N'' BEGIN DECLARE @msg nvarchar(2048) = CONCAT(N'Source tables missing in {{ModelSourceDB}}: ', @missing, N'. Build them with Build-MatchingScenarioTables.ps1 (see the Matching help pages).'); THROW 50011, @msg, 1; END",
]
steps.append(sql_step(
    "Source Tables Exist",
    ("Check the database matching/databases:ModelSourceDB holds the source tables every size loads and changes: "
     "RetailClient<size>Scenario1, Scenario2, Scenario3b and Scenario3c for 1K, 10K, 100K, 1M and 100M, and print each row count. "
     "1M is run at GA only and 100M only where the box has room, so a missing 1M or 100M table is stated, not failed."),
    "\n".join(table_lines),
    "Server={{DatabaseServerName}};Database={{ModelSourceDB}};Integrated Security=True;TrustServerCertificate=True",
    "Success: Every 1K, 10K and 100K table exists; the output gives each table's row count."))

steps.append(sql_step(
    "Connect Run-As User Is A Profisee User",
    ("Check the Connect run-as user (secret ConnectRuntime:ConnectRunAsUser) is a user in the Profisee database "
     "(matching/databases:ProfiseeDatabaseName); every Matching load runs its Connect batch as this user."),
    "IF NOT EXISTS (SELECT 1 FROM meta.tUser WHERE [Name] = N'{{RunAsUser}}')\n"
    "    THROW 50013, N'Connect run-as user {{RunAsUser}} (ConnectRuntime:ConnectRunAsUser) is not a Profisee user; the load batch would fail.', 1;\n"
    "PRINT N'Connect run-as user {{RunAsUser}} is a Profisee user.';",
    PROFISEE_DB,
    "Success: The run-as user exists in the Profisee database."))

steps.append({"label": "TestAuto Answers", "inline": {
    "type": "HTTP", "method": "GET", "followRedirects": True, "headers": {"accept": "application/json"},
    "expectedStatusCodes": [200], "url": "{{TestAutoBaseUrl}}/api/workflows/by-tag?tag=AUTO%3Apreflight", "body": "",
    "outputFile": "", "verifySsl": False, "maxTimeSeconds": 120,
    "description": ("What: Ask TestAuto on this box (matching/machines:TestServerNameFQDN, port 8443) for workflows tagged with a "
                    "probe tag: proves TestAuto answers and has the by-tag lookup every Matching test uses to find its workflow. "
                    "Why: Each test step finds its TestAuto workflow by tag through this call. " + HTTP_RESULT),
    **COMMON}})

steps.append({"label": "TestAuto Model Answers", "inline": {
    "type": "HTTP", "method": "GET", "followRedirects": True,
    "headers": {"x-api-key": "{{$config:RestClients:ScenarioMgt:ApiKey}}", "accept": "application/json"},
    "expectedStatusCodes": [200], "url": "{{ScenarioMgtBaseUrl}}v1/Records/TestAutoWorkflow?PageSize=1", "body": "",
    "outputFile": "", "verifySsl": True, "maxTimeSeconds": 120,
    "description": ("What: Read one TestAuto workflow record from the shared TestAuto model (matching/urls:ScenarioMgtBaseUrl) "
                    "with the RestClients:ScenarioMgt:ApiKey secret: proves matching-setup can write the run profiles and "
                    "workflows. Why: matching-setup writes them through this model. " + HTTP_RESULT),
    **COMMON}})

# Pack standard (Gene 11/08): the key is set before any gateway query. A clean Profisee Configuration issues a new key,
# so a plain gateway check answered 401; the shared key-set workload sets it, restarts IIS and proves it (200 only).
steps.append({"label": "Wait For Interrupted Runs", "inline": {
    "type": "TestAutoWorkflowStep", "baseUrl": "{{TestAutoBaseUrl}}", "workflowCode": "", "executionCode": "",
    "attachToActiveRun": True, "waitOnly": True, "pollIntervalSeconds": 60, "waitIndefinitely": True,
    "maxConsecutivePollFailures": 30, "ignoreSslErrors": True,
    "description": ("What: Wait for any TestAuto run already in progress on this box. Why: the next step restarts IIS on the "
                    "application server, which would break a running test. Success: no run is active. If it fails: TestAuto is "
                    "unreachable on port 8443."),
    **COMMON}})
steps.append({"label": "Set And Verify API Key", "inline": {
    "type": "RunWorkloadStep", "workloadName": "matching-api-key-set", **COMMON, "timeoutSeconds": 3600,
    "description": ("What: Set the standard API key, restart IIS so every service reads it, and prove it through the gateway and "
                    "the Data service. Why: Runs the child workload 'matching-api-key-set' so its tested steps are reused here, not "
                    "repeated. Success: The child workload ends with every step Succeeded or Skipped. If it fails: Open the run "
                    "output of 'matching-api-key-set'; its first failed step says what to check.")}})

keys = [f"matching-{s.lower()}-{scn}" for s in SIZES for scn in SCENARIOS]
key_lines = ",\n".join(f"    '{k}'" for k in keys)
steps.append(ps_step(
    "Every Automation Tag Found Once",
    (f"Look up all {len(keys)} Matching automation tags of this box and the current version "
     "(matching/environment:ProfiseeVersionCode) in TestAuto: each must sit on exactly one workflow; none at all = "
     "workflows not created yet on this box (stated, not failed: run matching-setup)."),
    "$ErrorActionPreference = 'Stop'\n"
    "$testAuto = '{{TestAutoBaseUrl}}'.TrimEnd('/')\n"
    "$version = '{{ProfiseeVersionCode}}'\n"
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
    "if ($ok -eq 0) { \"Workflows for $version not created yet on this box (0 of $($keys.Count) automation tags found): run matching-setup. Not a failure before the first setup or after an upgrade.\"; return }\n"
    "if ($missing) { throw \"$($missing.Count) of $($keys.Count) automation tags have no TestAuto workflow (run matching-setup again): $($missing -join ', ')\" }\n"
    "\"All $($keys.Count) automation tags for $version found exactly once.\""))

workload = {
    "name": "matching-preflight",
    "description": (
        "What: Checks this box is ready for Matching testing: the Profisee Windows service and application pools exist, the "
        "baseline backup is on the database server, the source tables are in ModelSource, the Connect run-as user is a "
        "Profisee user, TestAuto and its model answer, the standard API key is set and works through the gateway and the Data "
        "service (matching-api-key-set), and every automation tag sits on exactly one workflow. CrewChief's own pre-run check "
        "first proves every matching/* reference value it uses is filled in. Why: Finds every environment problem in one run, "
        "before a test fails half way through. When: Before and after matching-setup, after any reference data change, after "
        "a Profisee upgrade, before every round, and first whenever a test fails; never while a test runs on this application "
        "server. Needs: The matching/* reference sets and the box's secrets; the API user exists in the Profisee database. It "
        "changes only two things: the pool step starts a pool that is stopped, and the key step writes the standard API key "
        "and restarts IIS (pack standard: the key is set before any gateway query). Success: Every step Succeeded or Skipped; "
        "before the first matching-setup the tag step says \"not created yet\", normal. If it fails: Each step's failure text "
        "names the reference key, secret or machine to fix; fix reference data or the box, never a workload file."),
    "tags": ["matching", "start"],
    "globalParameters": {
        "ApplicationServerName": "{{$ref:matching/machines:ApplicationServerName}}",
        "DatabaseServerName": "{{$ref:matching/machines:DatabaseServerName}}",
        "ProfiseeInstanceName": "{{$ref:matching/instances:ProfiseeInstanceName}}",
        "ProfiseeDatabaseName": "{{$ref:matching/databases:ProfiseeDatabaseName}}",
        "ModelSourceDB": "{{$ref:matching/databases:ModelSourceDB}}",
        "TestAutoBaseUrl": "https://{{$ref:matching/machines:TestServerNameFQDN}}:8443",
        "ScenarioMgtBaseUrl": "{{$ref:matching/urls:ScenarioMgtBaseUrl}}",
        "RunAsUser": "{{$config:ConnectRuntime:ConnectRunAsUser}}",
    },
    "globalParametersNotes": "",
    "credentialUserId": None, "credentialPassword": None, "credentialNotes": "",
    "steps": steps,
}

path = os.path.join(root, 'workloads', 'matching', 'start', 'matching-preflight.workload.json')
with open(path, 'w', encoding='utf-8') as f:
    json.dump(workload, f, indent=2)
print('written', path, 'steps', len(steps))
