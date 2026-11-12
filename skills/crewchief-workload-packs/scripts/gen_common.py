"""Builds the CrewChief `common` pack (CrewChief/packs/common): the building blocks every pack runs, kept ONCE.

  workloads/common/internal/
    common-api-key-set         set the standard API key, restart the instance, prove the key (gateway and Data service)
    common-health-wait         wait until every health check of the instance is Healthy; restart the instance once when one stays down
    common-instance-stop       stop the instance's Windows service (when it has one) and IIS
    common-instance-start      start IIS and the instance's Windows service (when it has one)
    common-instance-pools      recycle (or start) the instance's application pools, found on the server
    common-base-backup-check   a backup file is in the SQL Server default backup folder
    common-testauto-tag-check  every listed TestAuto workflow key has exactly one workflow for this box and version

The pack holds workloads only: no reference data. Packs on one box can test different Profisee instances, so each
workload takes the box facts (server, instance, database, URLs) as INPUTS WITHOUT A DEFAULT from the pack that runs it; a
child workload reads its parent's values, so a pack whose globals carry these names passes nothing. Never run by hand.

A fix to a shared block is a change to one file here; no pack is regenerated for it.

Usage: python gen_common.py <packRoot>      (e.g. C:\\devops\\repos\\speed-merchants\\CrewChief\\packs\\common)
"""
import os
import sys

root = os.path.abspath(sys.argv[1])
here = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.environ.get('PACKGEN_TOOLS') or os.path.join(os.path.dirname(root), 'tools'))
from packgen import instance, steps  # noqa: E402
from packgen.values import value_input  # noqa: E402
from packgen.workloads import clear_workloads, dump, workload  # noqa: E402

FAM = 'common'
wl_root = os.path.join(root, 'workloads', FAM)
APP = "{{ApplicationServerName}}"
NEVER = "When: Never run by hand; a pack workload runs it and passes the box it works on."

BOX_TEXT = {
    "ApplicationServerName": "Short name of the machine the Profisee instance runs on (the calling pack's machines:ApplicationServerName).",
    "DatabaseServerName": "SQL Server holding the Profisee database (the calling pack's machines:DatabaseServerName).",
    "ProfiseeDatabaseName": "The Profisee database of the instance (the calling pack's databases:ProfiseeDatabaseName).",
    "ProfiseeInstanceName": "IIS application path of the instance, as in https://<server>/<instance> (the calling pack's instances:ProfiseeInstanceName).",
    "ProfiseeBaseUrl": "REST address of the instance: https://<application server FQDN>/<instance>/rest. Its health address is this plus /health.",
    "TestAutoBaseUrl": "Address of TestAuto on this box: https://<test server FQDN>:8443.",
    "ProfiseeVersionCode": "TestAuto version code the automation tags carry (the calling pack's environment:ProfiseeVersionCode, or the lane's version).",
}


def box(*names):
    return [value_input(n, None, BOX_TEXT[n]) for n in names]


def iis(name, action, what):
    return {"label": f"{action} {name}", "inline": {**steps.BASE, "serviceName": name, "action": action, "targetComputer": APP,
            **steps.ADMIN, "type": "ServiceControlStep",
            "description": (f"What: {what} Why: {action} the Windows service so the next steps work on a quiet or a running Profisee "
                            f"instance, as they need. Success: The service on the target machine ends in the state the action asks "
                            f"for ({action}). If it fails: Check the service exists on the target machine (services.msc) and the "
                            "admin credential (UserCredentials secrets) can manage services there over CredSSP.")}}


def service(label, action, what, why):
    return instance.service_step(label, action, APP, what, why)


def emit(name, description, tags, step_list, inputs, globals_=None, notes=""):
    dump(os.path.join(wl_root, 'internal', name + '.workload.json'),
         workload(name, description, ["common", "internal"] + tags, step_list, inputs=inputs, globals_=globals_, notes=notes, family=None))


clear_workloads(wl_root)

# ---------------------------------------------------------------- common-health-wait
with open(os.path.join(here, 'health.ps1'), encoding='utf-8', newline='') as f:
    HEALTH = f.read()
FIRST_WAIT, LAST_WAIT = 3, 8
STUCK = "{{RestartServerName}}"
STUCK_WHY = "every health check was Healthy within the first %d minutes (the step Name The Server To Restart printed nothing)" % FIRST_WAIT
RESTART = {"ApplicationServerName": STUCK, "ProfiseeInstanceName": "{{RestartInstanceName}}"}


def health(mode, minutes):
    """health.ps1 with the two lines that say what it does."""
    return "$Mode = '%s'\n$Minutes = %d\n" % (mode, minutes) + HEALTH


emit("common-health-wait",
     ("What: Ask the health address of the Profisee instance (its REST address plus /health) every 15 seconds until every "
      "health check is Healthy. When a check is still not Healthy after %d minutes, restart the instance once "
      "(common-instance-stop, then common-instance-start, on the server and instance named in the address) and wait again, "
      "for at most %d minutes. Why: services stay cold after a restore, a recycle or a key change; a measured run must not "
      "pay for the warm-up, a check must not hit a service that is still starting, and a service that stays down after a "
      "restore usually comes up after one restart, which a person used to do by hand. " % (FIRST_WAIT, LAST_WAIT) + NEVER +
      " Needs: the instance is started; for the restart, the admin credential (UserCredentials secrets) can manage services "
      "on the application server over CredSSP. Success: all checks Healthy, at once or after the one restart. If it fails: "
      "the last line names the checks that are not Healthy after the restart; open the health address and fix the service "
      "it names."),
     ["health"],
     [steps.ps("Wait For Every Service", health('Wait', FIRST_WAIT),
               "What: Wait until every health check of the instance is Healthy, for at most %d minutes. Why: services stay "
               "cold after a restore and a recycle; a measured run must not pay for the warm-up. Success: all checks Healthy, "
               "or the last line says which are not and that the instance is restarted once. If it fails: the step could not "
               "run at all (PowerShell 7 on this box); a service that is down never fails this step." % FIRST_WAIT,
               timeout=300),
      steps.ps("Name The Server To Restart", health('Server', 0),
               "What: Ask the health address once more; when a check is still not Healthy, print the short name of the "
               "application server, read from the address, into the run value RestartServerName. Nothing is printed when "
               "every check is Healthy. Why: the steps below run only when a name was printed, and the restart must hit the "
               "server that was asked, never another one. Success: one name, or nothing. If it fails: the step could not run "
               "at all (PowerShell 7 on this box).",
               timeout=180, output="RestartServerName"),
      steps.gated(steps.ps("Name The Instance To Restart", health('Instance', 0),
                           "What: Print the instance name, read from the address (https://<application server>/<instance>/rest), "
                           "into the run value RestartInstanceName. Why: the restart finds the instance's Windows service by "
                           "this name. Success: one name. If it fails: the address does not end in /<instance>/rest; correct "
                           "ProfiseeBaseUrl in the calling pack's reference data.",
                           timeout=60, output="RestartInstanceName"), STUCK, STUCK_WHY),
      steps.gated(steps.instance_stop_child("a service that stays down after its warm-up time is restarted once",
                                            parameters=RESTART), STUCK, STUCK_WHY),
      steps.gated(steps.instance_start_child("the services start again and read their state fresh", parameters=RESTART),
                  STUCK, STUCK_WHY),
      steps.gated(steps.ps("Wait Again After The Restart", health('Final', LAST_WAIT),
                           "What: Wait until every health check of the instance is Healthy, for at most %d minutes after the "
                           "restart. Why: the restart is tried once; a service that is still down needs a person. Success: all "
                           "checks Healthy. If it fails: open the health address (the instance's REST address plus /health) "
                           "and fix the service the last line names." % LAST_WAIT,
                           timeout=560), STUCK, STUCK_WHY)],
     box("ProfiseeBaseUrl"),
     globals_={"RestartServerName": "", "RestartInstanceName": ""},
     notes=("RestartServerName and RestartInstanceName are set during the run, and only when a health check stays not Healthy: "
            "they start blank so the restart steps are skipped on a healthy instance."))

# ---------------------------------------------------------------- common-instance-stop / common-instance-start
emit("common-instance-stop",
     ("What: On the application server, find the Windows service of the Profisee instance and stop it (skipped on releases "
      "without one), then stop IIS (the World Wide Web Publishing Service and the Windows Process Activation Service). Why: a "
      "restore or an API key change must not happen under running services: they hold connections and cache the user they "
      "signed in with. " + NEVER + " Needs: the admin credential (UserCredentials secrets) can manage services on the "
      "application server over CredSSP. Success: Every step Succeeded or Skipped. If it fails: open the first failed step, "
      "whose If it fails text names what to check."),
     ["instance"],
     [service("Stop Profisee Service", "Stop", "Stop the Profisee Windows service of the instance.",
              "it holds connections and caches from before the change."),
      iis("W3SVC", "Stop", f"Stop the World Wide Web Publishing Service on {APP} so no worker process keeps old state."),
      iis("WAS", "Stop", f"Stop the Windows Process Activation Service on {APP}: every application pool stops with it.")],
     box("ApplicationServerName", "ProfiseeInstanceName"))

emit("common-instance-start",
     ("What: On the application server, start IIS (the Windows Process Activation Service, then the World Wide Web Publishing "
      "Service), then find the Windows service of the Profisee instance and start it (skipped on releases without one). Why: "
      "brings the instance back after a restore or an API key change; the application pools start and read the new state. "
      + NEVER + " Needs: the admin credential (UserCredentials secrets) can manage services on the application server over "
      "CredSSP. Success: Every step Succeeded or Skipped. If it fails: open the first failed step, whose If it fails text "
      "names what to check."),
     ["instance"],
     [iis("WAS", "Start", f"Start the Windows Process Activation Service on {APP}."),
      iis("W3SVC", "Start", f"Start the World Wide Web Publishing Service on {APP}; the application pools start."),
      service("Start Profisee Service", "Start", "Start the Profisee Windows service of the instance.",
              "it must sign in again against the changed database.")],
     box("ApplicationServerName", "ProfiseeInstanceName"))

# ---------------------------------------------------------------- common-instance-pools
emit("common-instance-pools",
     ("What: On the application server, find the application pools the Profisee instance uses and recycle each of them, or, "
      "when the caller passes PoolAction = Start, start each (a check that changes nothing when they already run). A built-in "
      "pool, or one that also serves something outside the instance, is never touched. Why: services cache what they read "
      "at start (business rules, settings); a recycle makes them read it again, and a start proves the instance has its "
      "pools. " + NEVER + " Needs: the admin credential (UserCredentials secrets) reaches the application server over "
      "CredSSP. Success: every pool found reaches Started. If it fails: open the failed step, whose If it fails text names "
      "what to check."),
     ["instance", "pools"],
     [instance.pools_step("Act On Instance Pools", "{{PoolAction}}", APP, None,
                          "Recycle or start (PoolAction) every application pool of this instance.",
                          "the caller needs the instance's services to read their state again, or to prove the pools exist.")],
     box("ApplicationServerName", "ProfiseeInstanceName") + [
         value_input("PoolAction", "Recycle", "Recycle = recycle every pool of the instance; Start = start each (a no-op when it already runs).")])

# ---------------------------------------------------------------- common-api-key-set
emit("common-api-key-set",
     ("What: Stop the Profisee service and IIS on the application server (common-instance-stop), write the standard API key "
      "(RestKeys:ProfiseeRestKey) for the API user (ConnectRuntime:ApiKeyUserName) into the Profisee database, start IIS and "
      "the service (common-instance-start), wait for every service (common-health-wait), and prove the key through the gateway "
      "and the Data service. Why: the standard of every pack: the key is set before any step queries the gateway; a clean "
      "Profisee Configuration issues a new key, a backup made on another machine may carry another one, and the services read "
      "a key change only after IIS restarts. " + NEVER + " Needs: the API user exists in the Profisee database; no test "
      "running on this application server. Success: Every step Succeeded or Skipped. If it fails: open the first failed step, "
      "whose If it fails text names what to check."),
     ["api-key"],
     [steps.instance_stop_child("the services cache the user they signed in with"),
      {"label": "Set API Key", "inline": {**steps.BASE, "username": "{{ApiKeyUserName}}", "key": "{{ProfiseeApiKey}}",
          "serverName": "{{DatabaseServerName}}", "databaseName": "{{ProfiseeDatabaseName}}", "authMode": "Windows",
          "credentialUserId": "", "credentialPassword": "", "sqlDestinationConnectionSecretName": "", "stripHyphens": True,
          "type": "SetApiKeyStep",
          "description": ("What: Write the standard API key for the machine's API user (ConnectRuntime:ApiKeyUserName) into "
                          "meta.tUser. Why: TestAuto and every check call the gateway with that key; a clean Profisee "
                          "Configuration issues a new key and a backup configured on another machine may carry another one. "
                          "Success: the user row is updated. If it fails: the user is missing from meta.tUser; add it in "
                          "Profisee as a super administrator.")}},
      steps.instance_start_child("every service must read the new key"),
      steps.health_child(),
      steps.http_get("Verify API Key Through Gateway", "{{ProfiseeBaseUrl}}/v1/Entities",
                     "What: Call the gateway with the standard key. Why: proves the key took before anything else uses it. "
                     "Success: HTTP 200. If it fails: 401 means the key did not take; check the user in meta.tUser and run the "
                     "calling workload again.", headers={"x-api-key": "{{ProfiseeApiKey}}"}, retries=4),
      steps.http_get("Verify API Key Through Data Service", "{{ProfiseeBaseUrl}}/v1/Rules?PageSize=1",
                     "What: Prove the Data service accepts the API key as a real user: GET v1/Rules?PageSize=1 must return 200. "
                     "Why: the gateway check (v1/Entities) can pass while the Data and Connect services still reject the user "
                     "(400 DATA00030 \"user is not valid\", 403 CNX00080); that only showed up minutes later inside a test. "
                     "Success: 200. If it fails: 400 DATA00030 or 403 = the key is not set for the API user in this database, "
                     "IIS was not restarted after the restore and the key change, or the restored backup was configured before "
                     "Profisee Configuration last ran on this application server (its service sign-in ids are stale): start "
                     "from the pack's test workload, which configures its base first.",
                     headers={"x-api-key": "{{ProfiseeApiKey}}"}, retries=4)],
     box("ApplicationServerName", "DatabaseServerName", "ProfiseeDatabaseName", "ProfiseeInstanceName", "ProfiseeBaseUrl")
     + [value_input("ProfiseeApiKey", "{{$config:RestKeys:ProfiseeRestKey}}",
                    "The API key to set and prove. Default: the box's standard key (secret RestKeys:ProfiseeRestKey). Only a "
                    "workload that sets the key of a second Profisee instance (a Connect target) passes another secret.")],
     globals_={"ApiKeyUserName": "{{$config:ConnectRuntime:ApiKeyUserName}}"},
     notes="The API user is a secret of the box (ConnectRuntime:ApiKeyUserName), the same for every pack; the key is the box's standard key unless the caller passes ProfiseeApiKey.")

# ---------------------------------------------------------------- common-base-backup-check
backup_sql = """DECLARE @dir nvarchar(400) = CAST(SERVERPROPERTY('InstanceDefaultBackupPath') AS nvarchar(400));
DECLARE @exists int, @f nvarchar(600) = @dir + N'\\{{BackupFileName}}';
EXEC master.dbo.xp_fileexist @f, @exists OUTPUT;
IF @exists = 0 BEGIN DECLARE @msg nvarchar(2048) = N'Backup {{BackupFileName}} is missing from the SQL Server default backup folder of {{DatabaseServerName}}. Run {{FixWorkload}} on this box, or copy the file there.'; THROW 50024, @msg, 1; END
PRINT CONCAT(N'Backup found: ', @f);"""
emit("common-base-backup-check",
     ("What: Check one backup file sits in the SQL Server default backup folder of the database server. Why: a test restores "
      "it; finding it missing before the run costs seconds, finding it missing at the restore step costs the steps before it. "
      + NEVER + " Needs: the CrewChief account can connect to master on the database server. Success: the file is found. If "
      "it fails: the message names the file, the server and the workload that makes the file."),
     ["backup"],
     [steps.sql("Backup File Exists", backup_sql,
                "What: Look for the backup file (BackupFileName) in the SQL Server default backup folder of the database server. "
                "Why: the calling pack restores it. Success: the backup is found. If it fails: run the workload the message "
                "names (FixWorkload) on this box, or copy the file into that folder.", conn=steps.MASTER)],
     box("DatabaseServerName") + [
         value_input("BackupFileName", None, "File name (no folder) of the backup to look for, e.g. the pack's base backup of this version."),
         value_input("FixWorkload", None, "Name of the workload that makes the file when it is missing; the failure message tells the person to run it.")])

# ---------------------------------------------------------------- common-testauto-tag-check
tags_ps = r"""$ErrorActionPreference = 'Stop'
$testAuto = '{{TestAutoBaseUrl}}'.TrimEnd('/')
$version = '{{ProfiseeVersionCode}}'
$setup = '{{SetupName}}'
$allowNone = '{{AllowNone}}' -eq 'true'
# The list: keys separated by commas. Spaces around a key are dropped, blank items are skipped, a repeated key counts once.
$keys = @('{{TagKeys}}' -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ } | Select-Object -Unique)
if ($keys.Count -eq 0) { throw "No workflow key was passed to check (TagKeys is empty): the calling workload must name the TestAuto workflows it needs." }
$missing = @(); $dupes = @(); $ok = 0
foreach ($key in $keys) {
    $tag = "AUTO:{{$env:COMPUTERNAME}}:${version}:$key"
    $found = @((Invoke-RestMethod -Uri "$testAuto/api/workflows/by-tag?tag=$([uri]::EscapeDataString($tag))" -SkipCertificateCheck).data)
    if ($found.Count -eq 0) { $missing += $key }
    elseif ($found.Count -gt 1) { $dupes += "$tag on $(($found | ForEach-Object { "$($_.code) '$($_.name)'" }) -join '; ')" }
    else { $ok++ }
}
if ($dupes) { throw "$($dupes.Count) automation tag(s) sit on more than one TestAuto workflow (remove the tag from the copies): $($dupes -join ' | ')" }
if ($ok -eq 0 -and $allowNone) { "Workflows for $version not created yet on this box (0 of $($keys.Count) found): run $setup. Not a failure before the first setup or after an upgrade."; return }
if ($missing) { throw "$($missing.Count) of $($keys.Count) TestAuto workflow(s) do not exist for this box and version $version, so the run cannot find them: $($missing -join ', '). Run $setup (it creates one workflow per value row in the pack's reference data; a value with no row needs its row first), then run this again." }
"All $($keys.Count) TestAuto workflow(s) found exactly once for $version`: $($keys -join ', ')."
"""
emit("common-testauto-tag-check",
     ("What: Look up each TestAuto workflow key the caller lists (TagKeys) by its automation tag, AUTO:<this box>:<version "
      "code>:<key>: each must sit on exactly one workflow. Why: a run finds its TestAuto workflow by that tag alone; checking "
      "before the first restore turns \"no workflow carries tag\" in the middle of a run into \"run the setup workload\" at "
      "its start. " + NEVER + " Needs: TestAuto answers on this box. Success: the last line lists the keys found. If it "
      "fails: the message names the keys with no workflow (run the setup workload it names; a new size or time needs its "
      "reference row first) or the tags on more than one workflow (remove the tag from the copies)."),
     ["testauto", "check"],
     [steps.ps("Every Workflow Key Found Once", tags_ps,
               "What: For each key in TagKeys, ask TestAuto for the workflows carrying the automation tag of this box, version "
               "and key. Why: each run step finds its workflow by tag. Success: every key has exactly one workflow (or, with "
               "AllowNone = true, none exists yet and the line says so). If it fails: the error names the keys with no "
               "workflow and the setup workload to run, or the tags on more than one workflow.", timeout=600)],
     box("TestAutoBaseUrl", "ProfiseeVersionCode") + [
         value_input("TagKeys", None, "The workflow keys to check, separated by commas (each is the end of an automation tag, e.g. crud-1k-core-br)."),
         value_input("SetupName", None, "Name of the pack's setup workload that creates the workflows; the failure message tells the person to run it."),
         value_input("AllowNone", "false", "true = when not one of the keys has a workflow, say so and end green (a preflight before the first setup); false = any missing key fails.")])

# ---------------------------------------------------------------- pack notes
with open(os.path.join(root, 'README.md'), 'w', encoding='utf-8', newline='\r\n') as f:
    f.write("""# CrewChief common pack

Building blocks every workload pack runs, kept once. Restore `workloads/common` to a box together with the packs.

| Workload | Does |
|---|---|
| `common-api-key-set` | Sets the standard API key, restarts the instance, proves the key through the gateway and the Data service |
| `common-health-wait` | Waits until every health check of the instance is Healthy; still not healthy after 3 minutes = restarts the instance once and waits again |
| `common-instance-stop` | Stops the instance's Windows service (when it has one) and IIS |
| `common-instance-start` | Starts IIS and the instance's Windows service (when it has one) |
| `common-instance-pools` | Recycles (or starts) the instance's application pools, found on the server |
| `common-base-backup-check` | Checks a backup file is in the SQL Server default backup folder |
| `common-testauto-tag-check` | Checks each listed TestAuto workflow key has exactly one workflow for this box and version |

- No reference data: each workload takes the box facts as inputs from the pack that runs it. Never run one by hand.
- Generated by `gen_common.py` (ai-setup, skill `crewchief-workload-packs`). Never edit a workload file: change the generator.
- A pack must not hold its own copy of one of these (lint rule R-shared).
""")
with open(os.path.join(root, 'CLAUDE.md'), 'w', encoding='utf-8', newline='\r\n') as f:
    f.write("""# common pack: rules for an agent

- These workloads are GENERATED by `gen_common.py` in the ai-setup repo (skill `crewchief-workload-packs`, folder `scripts`). Never edit a `*.workload.json` here; change the generator and run it.
- The pack holds workloads only. Never add reference data: box facts belong to the pack that runs a block.
- Inputs here have no default on purpose (the calling pack passes the box). `PoolAction`, `AllowNone` and `ProfiseeApiKey` (the box standard key unless a caller passes another) are the only inputs with a default.
- Every pack calls these by name. Renaming one changes every pack: do not rename.
- A change here needs no pack regeneration; restore `workloads/common` to the boxes.
""")
print("common pack written: %d workloads" % len(os.listdir(os.path.join(wl_root, 'internal'))))
