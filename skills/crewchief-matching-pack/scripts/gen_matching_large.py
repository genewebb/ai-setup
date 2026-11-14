"""Builds the CrewChief Matching Large pack (CrewChief/packs/matching-large): finish a Scenario 1 that was run outside the
pack on a large instance, then run Scenarios 2, 3a, 3b and 3c forward from it (Gene 11/14/2026).

Why a separate pack: the first 100M Scenario 1 ran by hand on CORPVMHA1 / CORPSQL03 Profisee100M (Connect load and
matching started by hand, Start of Scenario 1 marker inserted by hand, 11/03-11/07). The Matching pack always starts
from its own load and its own single-file checkpoints, and its box facts belong to the SMVM3 Matching lane on the same
CrewChief box. This pack has its own reference family (matching-large), its own TestAuto workflow keys
(matching-large-<size>-...) and its own checkpoint names, so it never touches the Matching pack or the lane.

  start/      matching-large-preflight     checks only (and the standard API key)
              matching-large-setup         run profiles + 5 tagged TestAuto workflows per size row
  tests/      matching-large-continue      Scenario 1 finish, then Scenarios 2, 3a, 3b, 3c
  internal/   matching-large-scenario1-finish   End marker after the last matching activity, counts + timing, back up after-1
              matching-large-scenario2 / 3a / 3b / 3c   restore the checkpoint before, continuous matching on, run, back up

What differs from the Matching pack (everything else is matching_parts.py, shared):
  - no load: the Profisee database already holds the matched Scenario 1;
  - the slice (records each later scenario works on) is a reference row, <family>/values:<Size>.Slice, not a tenth;
  - checkpoints are striped over the folders in <family>/databases:BackupFolders (one file per folder, the same name in
    each), COPY_ONLY, COMPRESSION, CHECKSUM and verified; restores read every stripe;
  - TestAuto limits for days-long runs: 'Wait for Matching To Be Idle' 1440 minutes, 3b/3c TimeLimit none (exact slice);
  - after each TestAuto run a check proves its markers landed in THIS Profisee database (the box's TestAuto must point
    at this instance for the run; it serves the SMVM3 lane otherwise).

Usage: python gen_matching_large.py <packRoot>      (e.g. C:\\devops\\repos\\speed-merchants\\CrewChief\\packs\\matching-large)
"""
import os
import sys

root = os.path.abspath(sys.argv[1])
FAM = 'matching-large'
SETUP = 'matching-large-setup'
ref_dir = os.path.join(root, 'reference-kv', FAM)
wl_root = os.path.join(root, 'workloads', FAM)
sys.path.insert(0, os.environ.get('PACKGEN_TOOLS') or os.path.join(os.path.dirname(root), 'tools'))
from packgen import specs, steps  # noqa: E402
from packgen.values import record_count_input, ref as _ref, size_input, value_input, version_inputs  # noqa: E402
from packgen.workloads import clear_workloads, dump, seed_reference_set, workload  # noqa: E402
import matching_parts as parts  # noqa: E402
from matching_parts import (SCENARIOS, T2, T3B, T3C, VER, Timing, checks, continuous_matching_step, later_details,  # noqa: E402
                            monitor_quiet, prelude, s1_counts, s1_timing, table)

LATER = SCENARIOS[1:]  # '2', '3a', '3b', '3c'
# Days-long runs (300M template 10000185, Gene 11/14): idle wait one day; 3b/3c create every row (no time limit).
TIMING = Timing(max_wait_minutes=1440, time_limit="00:00:00")


def ref(set_name, key):
    return _ref(FAM, set_name, key)


def checkpoint_file(name):
    """File name (no folder) of one checkpoint; every folder in BackupFolders holds one stripe under this name. The prefix
    differs from the Matching pack's (profisee_Matching_...) so the two never overwrite each other."""
    return "profisee_MatchingLarge_{{Size}}_" + name + "_" + VER + ".bak"


# ---------------------------------------------------------------- reference sets (seeded once; then the files in git are the source)
SIZE_ROWS = {"100M": 100000000}
SLICES = {"100M": 1000000}
seed_reference_set(os.path.join(ref_dir, 'sizes.json'),
    "Matching Large pack: the sizes a run can have. Key = the Size a run passes and the word in the source table names "
    "(RetailClient<Size>Scenario1, 2, 3b, 3c in the ModelSource database); value = the record count Scenario 1 matched. Each "
    "size also needs its slice row in matching-large/values (<Size>.Slice). Kept in git with the pack and restored to a box "
    "with Replace; never edited on a box.",
    {k: str(v) for k, v in SIZE_ROWS.items()},
    {k: f"{v:,} records loaded and matched by Scenario 1 (run outside the pack); the later scenarios work on the slice in "
        f"matching-large/values:{k}.Slice." for k, v in SIZE_ROWS.items()})
seed_reference_set(os.path.join(ref_dir, 'values.json'),
    "Matching Large pack: values the pack reads. <Size>.Slice = the records Scenarios 2, 3a, 3b and 3c each work on at that "
    "size (Scenario 2: 85% NoChange, 10% Changed, 5% New rows; 3a: lookups; 3b and 3c: creates); a multiple of 100. Kept in "
    "git with the pack; never edited on a box.",
    {f"{k}.Slice": str(v) for k, v in SLICES.items()},
    {f"{k}.Slice": f"Size {k}: Scenarios 2, 3a, 3b and 3c each work on {v:,} records (Gene 11/14: 1M per scenario at 100M, "
                   "as the 300M template)." for k, v in SLICES.items()})
# Box facts: what a box points at. Restored with --add-missing-keys, so a value set on a box is never overwritten.
seed_reference_set(os.path.join(ref_dir, 'environment.json'),
    "Matching Large pack: the Profisee release the runs are recorded under. Edit after a Profisee upgrade of the instance.",
    {"ProfiseeVersionCode": "26R3", "MainMachineTag": "CORPVMHA1"},
    {"ProfiseeVersionCode": "TestAuto version code (data.tProfiseeVersion) the runs are recorded under; also part of every "
                            "automation tag, run profile code and checkpoint name.",
     "MainMachineTag": "Plain tag naming the machine the runs measure (the application server)."})
seed_reference_set(os.path.join(ref_dir, 'machines.json'),
    "Matching Large pack: machine names. Short name for SQL; FQDN for HTTPS.",
    {"ApplicationServerName": "CORPVMHA1", "ApplicationServerNameFQDN": "corpvmha1.corp.profisee.com",
     "DatabaseServerName": "CORPSQL03", "TestServerName": "SMVMTR3", "TestServerNameFQDN": "SMVMTR3.corp.profisee.com"},
    {"ApplicationServerName": "Short name of the machine the Profisee portal runs on; the instance and pool steps target it.",
     "ApplicationServerNameFQDN": "Fully qualified name of the machine the Profisee portal runs on; HTTPS calls use it.",
     "DatabaseServerName": "SQL Server holding the Profisee database, the ModelSource database and the checkpoint stripes.",
     "TestServerName": "Machine running TestAuto (the CrewChief box); written into each TestAuto step's environment block.",
     "TestServerNameFQDN": "Fully qualified name of the TestAuto machine; CrewChief calls TestAuto on port 8443 there."})
seed_reference_set(os.path.join(ref_dir, 'instances.json'),
    "Matching Large pack: Profisee instance name (the IIS application path).",
    {"ProfiseeInstanceName": "profisee"},
    {"ProfiseeInstanceName": "IIS application path of the instance under test, as in https://<server>/<instance>."})
seed_reference_set(os.path.join(ref_dir, 'databases.json'),
    "Matching Large pack: database names and where the checkpoint stripes go.",
    {"ProfiseeDatabaseName": "Profisee100M", "ModelSourceDB": "ModelSourceMatching",
     "BackupFolders": "D:\\DBBackup,F:\\DBBackup,G:\\DBBackup,H:\\DBBackup,I:\\DBBackup"},
    {"ProfiseeDatabaseName": "The Profisee database of the instance under test; holds the Scenario 1 that was run outside the pack.",
     "ModelSourceDB": "Database (on the database server) holding RetailClient<Size>Scenario1, 2, 3b and 3c and SourceSystem, "
                      "built by Build-MatchingScenarioTables.ps1 -Slice from the rows Scenario 1 loaded.",
     "BackupFolders": "Folders on the database server, separated by commas: every checkpoint is written as one stripe per folder "
                      "(the same file name in each). Put them on different drives; a restore needs every stripe."})
seed_reference_set(os.path.join(ref_dir, 'urls.json'),
    "Matching Large pack: REST addresses.",
    {"ScenarioMgtBaseUrl": "https://profiseecloud.dev/speedmerchantstest/rest/"},
    {"ScenarioMgtBaseUrl": "REST address of the TestAuto repository (ScenarioMgt) the local TestAuto reads; workflows and run "
                           "profiles are written there."})

# ---------------------------------------------------------------- box globals
APP_URL = "https://" + ref('machines', 'ApplicationServerNameFQDN') + "/" + ref('instances', 'ProfiseeInstanceName') + "/rest"
G = {
    "ApplicationServerName": ref('machines', 'ApplicationServerName'),
    "DatabaseServerName": ref('machines', 'DatabaseServerName'),
    "ProfiseeInstanceName": ref('instances', 'ProfiseeInstanceName'),
    "ProfiseeDatabaseName": ref('databases', 'ProfiseeDatabaseName'),
    "ModelSourceDB": ref('databases', 'ModelSourceDB'),
    "BackupFolders": ref('databases', 'BackupFolders'),
    "ProfiseeBaseUrl": APP_URL,
    "TestAutoBaseUrl": "https://" + ref('machines', 'TestServerNameFQDN') + ":8443",
    "ScenarioMgtBaseUrl": ref('urls', 'ScenarioMgtBaseUrl'),
    "ScenarioMgtApiKey": "{{$config:RestClients:ScenarioMgt:ApiKey}}",
    "ProfiseeApiKey": "{{$config:RestKeys:ProfiseeRestKey}}",
    "TestAutoEnvironmentName": ref('machines', 'TestServerName'),
    "TestAutoApplicationServer": ref('machines', 'ApplicationServerName'),
    "TestAutoDatabaseServer": ref('machines', 'DatabaseServerName'),
    "TestAutoSourceDatabase": ref('databases', 'ModelSourceDB'),
}
BOX = ("ApplicationServerName", "DatabaseServerName", "ProfiseeInstanceName", "ProfiseeDatabaseName", "ProfiseeBaseUrl", "TestAutoBaseUrl")


def g(*names, **extra):
    out = {n: G[n] for n in names}
    out.update(extra)
    return out


SIZE = size_input(FAM, default='100M')
RECORD_COUNT = record_count_input(FAM)
SLICE_INPUT = value_input('Slice', "{{$ref:%s/values:{{Size}}.Slice}}" % FAM, (
    "Records each of Scenarios 2, 3a, 3b and 3c works on: the row %s/values:<Size>.Slice. Never typed: change the row." % FAM))
VERSION_CODE = version_inputs(FAM, 'ProfiseeVersionCode')
SCENARIO_INPUTS = [SIZE, RECORD_COUNT, SLICE_INPUT] + VERSION_CODE


def key(scn):
    """Automation tag key of one scenario's TestAuto workflow, as workload text."""
    return "matching-large-{{Size|lower}}-scenario" + scn


FINISH_KEY = key('1-finish')
ALL_KEYS = ",".join([FINISH_KEY] + [key(s) for s in LATER])


def workload_name(scn):
    return "matching-large-scenario" + scn


def emit(folder, name, description, tags, step_list, inputs=None, globals_=None, notes=""):
    dump(os.path.join(wl_root, folder, name + '.workload.json'),
         workload(name, description, ["matching", FAM, folder] + tags, step_list, inputs=inputs, globals_=globals_, notes=notes,
                  family=FAM))


clear_workloads(wl_root)

# ---------------------------------------------------------------- TestAuto workflow templates
# Scenario 1 finish: the end marker is written by CrewChief at the time matching really ended (a TestAuto marker step
# would stamp the time of the run, days later); the workflow records the end counts and the timings between the markers.
# Both steps file their rows under step 1's WorkloadExecution (every step's code exists once the workflow is queued).
DETAILS = {'1-finish': [s1_counts("End", "{{STEP:1}}"), s1_timing("{{STEP:1}}")], **later_details(TIMING)}
SLICE_PS = r"""    $slice = [long](Get-SetValue 'Values' "$($v.Size).Slice")
    if ($slice -le 0 -or $slice % 100 -ne 0) { throw "matching-large/values:$($v.Size).Slice is '$slice'; a slice is a whole number above 0 and a multiple of 100." }
    if ($v.RecordCount -notmatch '^[1-9]\d*$') { throw "matching-large/sizes:$($v.Size) is '$($v.RecordCount)'; a record count is a whole number above 0." }"""
PRELUDE = prelude(SLICE_PS)
SETS = {"Sizes": "{{$ref:%s/sizes:*}}" % FAM, "Values": "{{$ref:%s/values:*}}" % FAM}
SIZE_LOOP = {"Size": specs.set_keys('Sizes')}
DERIVE = "Set-Size $v"
MACHINE_TAG = ref('environment', 'MainMachineTag')
SETUP_FAIL = (" If it fails: the message names the value or the workflow: a size with a bad record count or slice, a step "
              "configuration over 4000 characters, or two workflows with the same tag (untag the copy by hand); any other error "
              "names the record.")
MEASURES = {
    '1-finish': ("the end of Matching Scenario 1 (match and survive the full load) of <<RecordCount>> records that ran outside "
                 "the pack: end match status counts and the timings between the Scenario 1 markers",
                 "which writes the End of Scenario 1 marker after the last matching activity first; running it alone measures "
                 "nothing useful."),
    '2': (f"Matching Scenario 2 (operational batch: New, Changed with mutated match fields, NoChange) from table {T2}, <<Slice>> "
          "records on <<Size>>", None),
    '3a': ("Matching Scenario 3a (<<Slice>> lookups of matched records, creates nothing) on <<Size>>", None),
    '3b': (f"Matching Scenario 3b (lookup, then create on a miss) from table {T3B}, <<Slice>> records on <<Size>>", None),
    '3c': (f"Matching Scenario 3c (creates with continuous matching) from table {T3C}, <<Slice>> records on <<Size>>", None),
}
LATER_RUNNER = ("which restores the scenario's starting checkpoint and turns continuous matching on first; running it alone "
                "measures nothing useful.")


def template(scn):
    measures, runner = MEASURES[scn]
    label_scn = "1 Finish" if scn == '1-finish' else scn
    run_by = "matching-large-scenario1-finish" if scn == '1-finish' else workload_name(scn)
    return dict(
        label=f"Upsert Scenario {label_scn} Workflows", key=f"matching-large-<<SizeLower>>-scenario{scn}",
        name=f"Matching Large <<Size>> Scenario {label_scn}",
        spec={"PlainTags": f"Matching,{VER},{MACHINE_TAG},<<Size>>,Scenario {'1' if scn == '1-finish' else scn}",
              "Description": ("Automation ID: <AUTOMATION_ID>. CrewChief finds this workflow by that tag alone; do not edit or remove "
                              "the tag, and to experiment copy the workflow and remove the tag from the copy. "
                              f"Measures: {measures}, RetailClient strategy, on the Profisee version in "
                              f"{FAM}/environment:ProfiseeVersionCode. Run by the CrewChief workload '{run_by}' (Matching Large "
                              "pack), " + (runner or LATER_RUNNER)),
              "Details": DETAILS[scn]})


TEMPLATES = {scn: template(scn) for scn in ('1-finish',) + LATER}


def template_step(t):
    return specs.template_upsert_step(
        t["label"], t["key"], t["name"], t["spec"], SIZE_LOOP,
        f"What: Create or update the TestAuto workflow '{t['name'].replace('<<Size>>', '<Size>')}' ({len(t['spec']['Details'])} "
        f"steps) of every size in {FAM}/sizes, each found by its automation tag. The step holds the workflow once, as a "
        "template; the sizes and slices come from the reference rows, so a new row gives a new workflow and the existing ones "
        "are updated in place. Why: a Matching Large run finds its workflow by that tag. Success: the last line lists the "
        "workflows created or updated." + SETUP_FAIL,
        setup_name=SETUP, category="Matching", sets=SETS, prelude=PRELUDE, derive=DERIVE)


def key_patterns():
    return [(t["key"], SIZE_LOOP, SETS, PRELUDE, DERIVE) for t in TEMPLATES.values()]


# ---------------------------------------------------------------- striped checkpoints (SQL on master of the database server)
STRIPES = """DECLARE @db sysname = N'{{ProfiseeDatabaseName}}';
DECLARE @file nvarchar(260) = N'@@FILE@@';
-- One stripe per folder of {family}/databases:BackupFolders, the same file name in each.
DECLARE @stripes TABLE (n int IDENTITY(1, 1), folder nvarchar(400), path nvarchar(700));
INSERT @stripes (folder, path)
SELECT f, f + IIF(RIGHT(f, 1) = N'\\', N'', N'\\') + @file
FROM (SELECT LTRIM(RTRIM(value)) AS f FROM STRING_SPLIT(N'{{BackupFolders}}', N',')) x WHERE f <> N'';
IF NOT EXISTS (SELECT 1 FROM @stripes) THROW 50020, N'{family}/databases:BackupFolders names no folder.', 1;
DECLARE @disks nvarchar(max) = (SELECT STRING_AGG(CAST(N'DISK = N''' + REPLACE(path, N'''', N'''''') + N'''' AS nvarchar(max)), N', ')
                                WITHIN GROUP (ORDER BY n) FROM @stripes);
DECLARE @count int = (SELECT COUNT(*) FROM @stripes);""".replace('{family}', FAM)


def backup_sql(name):
    return STRIPES.replace('@@FILE@@', checkpoint_file(name)) + """
DECLARE @folder nvarchar(400);
DECLARE folders CURSOR LOCAL FAST_FORWARD FOR SELECT folder FROM @stripes ORDER BY n;
OPEN folders; FETCH NEXT FROM folders INTO @folder;
WHILE @@FETCH_STATUS = 0
BEGIN
    EXEC master.dbo.xp_create_subdir @folder;  -- no-op when the folder exists
    FETCH NEXT FROM folders INTO @folder;
END
CLOSE folders; DEALLOCATE folders;
-- COPY_ONLY: the database's own backup chain (its log backups) is left as it is.
DECLARE @sql nvarchar(max) = N'BACKUP DATABASE ' + QUOTENAME(@db) + N' TO ' + @disks + N' WITH FORMAT, INIT, COPY_ONLY, COMPRESSION, CHECKSUM, STATS = 5';
EXEC (@sql);
SET @sql = N'RESTORE VERIFYONLY FROM ' + @disks + N' WITH CHECKSUM';
EXEC (@sql);
PRINT CONCAT(N'Backed up ', @db, N' as ', @count, N' stripes of ', @file, N' and verified them.');"""


def restore_sql(name):
    return STRIPES.replace('@@FILE@@', checkpoint_file(name)) + """
DECLARE @path nvarchar(700), @exists int, @missing nvarchar(max) = N'';
DECLARE paths CURSOR LOCAL FAST_FORWARD FOR SELECT path FROM @stripes ORDER BY n;
OPEN paths; FETCH NEXT FROM paths INTO @path;
WHILE @@FETCH_STATUS = 0
BEGIN
    EXEC master.dbo.xp_fileexist @path, @exists OUTPUT;
    IF @exists <> 1 SET @missing += @path + N' ';
    FETCH NEXT FROM paths INTO @path;
END
CLOSE paths; DEALLOCATE paths;
IF @missing <> N''
BEGIN
    DECLARE @msg nvarchar(2048) = CONCAT(N'Checkpoint stripe(s) missing, nothing was restored: ', @missing);
    THROW 50021, @msg, 1;
END
-- OFFLINE first (as CrewChief's restore step does): every connection is dropped and none can come back during the restore.
DECLARE @sql nvarchar(max);
IF DB_ID(@db) IS NOT NULL
BEGIN
    SET @sql = N'ALTER DATABASE ' + QUOTENAME(@db) + N' SET OFFLINE WITH ROLLBACK IMMEDIATE';
    EXEC (@sql);
END
BEGIN TRY
    SET @sql = N'RESTORE DATABASE ' + QUOTENAME(@db) + N' FROM ' + @disks + N' WITH REPLACE, CHECKSUM, STATS = 5';
    EXEC (@sql);
END TRY
BEGIN CATCH
    IF EXISTS (SELECT 1 FROM sys.databases WHERE name = @db AND state_desc = N'OFFLINE')
    BEGIN
        SET @sql = N'ALTER DATABASE ' + QUOTENAME(@db) + N' SET ONLINE';
        EXEC (@sql);
    END;
    THROW;
END CATCH
PRINT CONCAT(N'Restored ', @db, N' from ', @count, N' stripes of ', @file, N'.');"""


BACKUP_TIMEOUT = 43200   # 12 hours: write and verify every stripe of a database of hundreds of GB
RESTORE_TIMEOUT = 28800  # 8 hours


def backup_step(name, why):
    st = steps.sql(f"Back Up {parts.title(name)}", backup_sql(name),
        f"What: Back up the Profisee database as the '{name}' checkpoint of this size and version, one stripe per folder of "
        f"{FAM}/databases:BackupFolders ({checkpoint_file(name).replace('{{', '<').replace('}}', '>')} in each; overwrites the "
        "previous one), COPY_ONLY, compressed, with checksums, then RESTORE VERIFYONLY of every stripe. Why: " + why +
        " Success: the last line names the stripes written and verified. If it fails: a folder is missing a drive or the disk is "
        "full (matching-large-preflight prints the free space), or the CrewChief account is not sysadmin on the database server.",
        conn=steps.MASTER, timeout=BACKUP_TIMEOUT)
    st["inline"]["timeoutSeconds"] = BACKUP_TIMEOUT + 300
    return st


def restore_step(name, before):
    st = steps.sql(f"Restore {parts.title(name)}", restore_sql(name),
        f"What: Restore the '{name}' checkpoint of this size and version over the Profisee database WITH REPLACE from every "
        f"stripe in {FAM}/databases:BackupFolders. It takes the database OFFLINE WITH ROLLBACK IMMEDIATE first and brings it "
        "back ONLINE if the restore fails; it restores nothing when a stripe is missing. Why: every run of this scenario starts "
        f"from the same state. Success: restored. If it fails: a stripe is missing (run {before} for this size), or the "
        "CrewChief account is not sysadmin on the database server.", conn=steps.MASTER, timeout=RESTORE_TIMEOUT)
    st["inline"]["timeoutSeconds"] = RESTORE_TIMEOUT + 300
    return st


def landed_step(scn):
    """After a TestAuto run: its start and end markers are in THIS Profisee database. The checkpoint the scenario restored
    holds no marker of the scenario, so both markers can only come from this run."""
    return steps.sql(f"Check Scenario {scn} Ran Here", f"""DECLARE @start datetime2 = (SELECT MAX(StartedTime) FROM monitor.tActivity WHERE Name = N'Start of Scenario {scn} for Retail Client');
DECLARE @end datetime2 = (SELECT MAX(StartedTime) FROM monitor.tActivity WHERE Name = N'End of Scenario {scn} for Retail Client');
IF @start IS NULL OR @end IS NULL OR @end < @start
BEGIN
    DECLARE @msg nvarchar(600) = CONCAT(N'The Scenario {scn} markers are not in {{{{ProfiseeDatabaseName}}}} (start ', ISNULL(CONVERT(nvarchar(30), @start, 126), N'none'), N', end ', ISNULL(CONVERT(nvarchar(30), @end, 126), N'none'), N'): TestAuto on this box ran against another Profisee instance. Point its RestClients:Profisee and SourceRecordDB settings at this instance, then rerun this workload.');
    THROW 50022, @msg, 1;
END
PRINT CONCAT(N'Scenario {scn} ran here: markers ', CONVERT(nvarchar(30), @start, 126), N' to ', CONVERT(nvarchar(30), @end, 126), N' UTC.');""",
        f"What: Confirm the Start and End of Scenario {scn} markers are in this Profisee database. Why: the box's TestAuto "
        "serves another instance when it is not pointed at this one; its run would then land elsewhere and this checkpoint "
        "would measure nothing. Success: both markers are found. If it fails: point TestAuto's Profisee settings at this "
        "instance (see the Matching Large help page) and rerun the workload.", timeout=300)


# ---------------------------------------------------------------- internal/matching-large-scenario1-finish
START1, END1 = parts.start_text, parts.end_text
FINISHED = "N'Succeeded', N'Failed', N'Canceled', N'Cancelled', N'Completed', N'Warning', N'Skipped'"  # as monitor_quiet.sql
GUARD_SQL = f"""DECLARE @start datetime2 = (SELECT MAX(StartedTime) FROM monitor.tActivity WHERE Name = N'{START1}');
IF @start IS NULL THROW 50030, N'No Start of Scenario 1 marker in {{{{ProfiseeDatabaseName}}}}: this database holds no Scenario 1 to finish.', 1;
IF EXISTS (SELECT 1 FROM monitor.tActivity WHERE Name LIKE N'Start of Scenario [23]% for Retail Client')
    THROW 50031, N'{{{{ProfiseeDatabaseName}}}} already holds a later scenario marker: it is past Scenario 1. Its after-1 checkpoint must not be taken from it; run the later scenarios (each restores its own start).', 1;
IF EXISTS (SELECT 1 FROM monitor.tActivity WHERE Service = N'Matching' AND StartedTime >= @start AND (CompletedTime IS NULL OR Status NOT IN ({FINISHED})))
    THROW 50032, N'Matching is still running after the Start of Scenario 1 marker (an activity is not finished); wait until it ends.', 1;
PRINT CONCAT(N'Scenario 1 started ', CONVERT(nvarchar(30), @start, 126), N' UTC; no later scenario; matching has finished.');"""
CODES_SQL = """-- Scenario 1 loaded exactly the rows of the Scenario 1 table, so updates by Code (Scenario 2) find their records and
-- the New rows of Scenarios 2, 3b and 3c are not loaded yet.
DECLARE @s1Missing bigint = (SELECT COUNT_BIG(*) FROM [{{ModelSourceDB}}].dbo.[RetailClient{{Size}}Scenario1] t WHERE NOT EXISTS (SELECT 1 FROM data.tRetailClient r WHERE r.Code = t.Code));
DECLARE @s2Missing bigint = (SELECT COUNT_BIG(*) FROM [{{ModelSourceDB}}].dbo.[RetailClient{{Size}}Scenario2] t WHERE t.RecordAction <> N'New' AND NOT EXISTS (SELECT 1 FROM data.tRetailClient r WHERE r.Code = t.Code));
DECLARE @newPresent bigint =
      (SELECT COUNT_BIG(*) FROM [{{ModelSourceDB}}].dbo.[RetailClient{{Size}}Scenario2] t WHERE t.RecordAction = N'New' AND EXISTS (SELECT 1 FROM data.tRetailClient r WHERE r.Code = t.Code))
    + (SELECT COUNT_BIG(*) FROM [{{ModelSourceDB}}].dbo.[RetailClient{{Size}}Scenario3b] t WHERE EXISTS (SELECT 1 FROM data.tRetailClient r WHERE r.Code = t.Code))
    + (SELECT COUNT_BIG(*) FROM [{{ModelSourceDB}}].dbo.[RetailClient{{Size}}Scenario3c] t WHERE EXISTS (SELECT 1 FROM data.tRetailClient r WHERE r.Code = t.Code));
IF @s1Missing <> 0 OR @s2Missing <> 0 OR @newPresent <> 0
BEGIN
    DECLARE @msg nvarchar(600) = CONCAT(N'The source tables do not fit what Scenario 1 loaded: ', @s1Missing, N' Scenario 1 Codes missing in RetailClient, ', @s2Missing, N' Scenario 2 Changed/NoChange Codes missing, ', @newPresent, N' New Codes (Scenario 2, 3b, 3c) already loaded. Build the tables from the rows Scenario 1 loaded (Build-MatchingScenarioTables.ps1 -SourceDatabase, same base and order).');
    THROW 50033, @msg, 1;
END
PRINT N'Source tables fit the load: every Scenario 1 and Scenario 2 update Code is in RetailClient; no New Code is.';"""
END_MARKER_SQL = f"""DECLARE @start datetime2, @user int;
SELECT TOP (1) @start = StartedTime, @user = [$EnterUserID] FROM monitor.tActivity WHERE Name = N'{START1}' ORDER BY StartedTime DESC;
IF @start IS NULL THROW 50030, N'No Start of Scenario 1 marker in {{{{ProfiseeDatabaseName}}}}.', 1;
DECLARE @have datetime2 = (SELECT MAX(StartedTime) FROM monitor.tActivity WHERE Name = N'{END1}' AND StartedTime >= @start);
-- The marker rule: the end marker comes about one second after the last matching activity of the scenario ends.
DECLARE @last datetime2 = (SELECT MAX(CompletedTime) FROM monitor.tActivity WHERE Service = N'Matching' AND StartedTime >= @start);
DECLARE @end datetime2 = DATEADD(second, 1, @last);
IF @have IS NOT NULL
    PRINT CONCAT(N'End of Scenario 1 marker already present at ', CONVERT(nvarchar(30), @have, 126), N' UTC; nothing written.');
ELSE IF @last IS NULL
    THROW 50034, N'No matching activity after the Start of Scenario 1 marker: matching never ran.', 1;
ELSE
BEGIN
INSERT monitor.tActivity (Name, Code, [$EnterDTM], [$EnterUserID], [$LastChgDTM], [$LastChgUserID], [$LastChgTypeID],
                          Properties, ActivityType, Service, Status, StartedTime, CompletedTime)
VALUES (N'{END1}', LOWER(CONVERT(nvarchar(36), NEWID())), @end, @user, @end, @user, 1,
        N'{{"Message":"End of RetailClient Scenario 1"}}', N'End of Scenario', N'TestAuto', N'Succeeded', @end, DATEADD(millisecond, 500, @end));
PRINT CONCAT(N'End of Scenario 1 marker written at ', CONVERT(nvarchar(30), @end, 126), N' UTC (last matching activity ended ', CONVERT(nvarchar(30), @last, 126), N').');
END"""
CHECKS = checks("DECLARE @slice bigint = {{Slice}};  -- the records each later scenario works on (matching-large/values:<Size>.Slice)",
                "{{Slice}}")
SLOW_SQL = 14400  # checks that read every RetailClient row of a 100M database

check1 = steps.sql(*CHECKS['1'][:2], CHECKS['1'][2], timeout=SLOW_SQL)
check1["inline"]["timeoutSeconds"] = SLOW_SQL + 300
codes = steps.sql("Check Source Tables Fit The Load", CODES_SQL,
    "What: Confirm the scenario tables were built from what Scenario 1 loaded: every Code of RetailClient<Size>Scenario1 and "
    "every Changed/NoChange Code of Scenario2 is in RetailClient, and no New Code of Scenario2, 3b or 3c is. Why: Scenario 1 "
    "was loaded outside the pack; Scenario 2 updates records by Code and 3b/3c create new ones. Success: one line says the "
    "tables fit. If it fails: rebuild the tables from the base Scenario 1 loaded (Build-MatchingScenarioTables.ps1 "
    "-SourceDatabase, the Matching Large help page).", timeout=SLOW_SQL)
codes["inline"]["timeoutSeconds"] = SLOW_SQL + 300
emit('internal', "matching-large-scenario1-finish",
     ("What: For the Size passed, finish the Scenario 1 that ran outside the pack on this instance: refuse when the database is "
      "already past Scenario 1 or matching still runs, check the load and the source tables fit, write the End of Scenario 1 "
      "marker one second after the last matching activity (once; a rerun keeps it), set the standard API key, run the TestAuto "
      "workflow 'Matching Large <Size> Scenario 1 Finish' (end counts and the Scenario 1 timings) and back up the striped "
      "'after-1' checkpoint, verified. Why: Scenario 2 starts from after-1; the Scenario 1 timings are only kept in the "
      "Activity Monitor until its retention removes them. When: once, before the first matching-large-scenario2 of the size; "
      "rerun only while the database is still at the end of Scenario 1. Example: matching-large-scenario1-finish --param "
      "Size=100M. Needs: matching-large-setup ran on this box for this version; the source tables of the size; TestAuto on "
      "this box pointed at this instance; the common pack. Success: Every step Succeeded or Skipped. If it fails: the failed "
      "step's description says what to fix; rerun the whole workload."),
     ["scenario1", "test"],
     [steps.wait_runs(),
      steps.sql("Check Scenario 1 Can Be Finished", GUARD_SQL,
          "What: Refuse when the Profisee database has no Start of Scenario 1 marker, already holds a Scenario 2 or 3 marker, or a "
          "matching activity after the start marker is not finished. Why: after-1 must be taken from the end of Scenario 1 and "
          "nothing else; a database already past it would overwrite the checkpoint with a later state. Success: one line states "
          "the start time. If it fails: the message names which of the three it is; a later marker means run the later "
          "scenarios instead (each restores its own start).", timeout=600),
      check1,
      codes,
      steps.sql("Write End Of Scenario 1 Marker", END_MARKER_SQL,
          "What: Insert the 'End of Scenario 1 for Retail Client' marker into monitor.tActivity at one second after the last "
          "matching activity that started after the Start of Scenario 1 marker ended (UTC), as TestAuto writes it; skipped when "
          "the marker is already there. Why: the Scenario 1 timings are measured between the two markers; a TestAuto marker step "
          "would stamp today's time. Success: one line gives the marker time. If it fails: no Start marker, or no matching "
          "activity after it.", timeout=600),
      steps.key_set_child(),
      steps.health_child(),
      monitor_quiet(),
      steps.testauto("Record Scenario 1 Counts And Timings", FINISH_KEY, "end counts and timings of Scenario 1 of the size passed", SETUP),
      backup_step('after-1', "Scenario 2 restores it, every run."),
      ],
     inputs=SCENARIO_INPUTS,
     globals_=g(*BOX, "ModelSourceDB", "BackupFolders", QuietSeconds="60"))

# ---------------------------------------------------------------- internal/matching-large-scenario2 ... 3c
CHAIN = {'2': ('after-1', 'after-2'), '3a': ('after-2', 'after-3a'), '3b': ('after-3a', 'after-3b'), '3c': ('after-3b', 'after-3c')}
WHATS = {'2': "Scenario 2 (operational batch from " + table('2') + ")", '3a': "Scenario 3a (lookups only)",
         '3b': "Scenario 3b (lookup, then create, from " + table('3b') + ")", '3c': "Scenario 3c (creates from " + table('3c') + ")"}


def scenario_workload(scn):
    start, end = CHAIN[scn]
    before = "matching-large-scenario1-finish" if scn == '2' else workload_name(LATER[LATER.index(scn) - 1])
    check_label, check_sql, check_desc = CHECKS[scn]
    check = steps.sql(check_label, check_sql, check_desc, timeout=SLOW_SQL)
    check["inline"]["timeoutSeconds"] = SLOW_SQL + 300
    step_list = [
        steps.wait_runs(),
        steps.instance_stop_child(parts.STOP_WHY),
        restore_step(start, before),
        steps.instance_start_child(parts.START_WHY),
        steps.key_set_child(),
        steps.health_child(),
        continuous_matching_step(),
        monitor_quiet(),
        steps.testauto(f"Run Matching Scenario {scn}", key(scn), f"Matching Scenario {scn} of the size passed", SETUP),
        landed_step(scn),
        check,
        backup_step(end, "the next scenario restores it." if scn != '3c' else "it keeps the end state of the chain for a later look."),
    ]
    emit('internal', workload_name(scn),
         (f"What: For the Size passed: restore the striped '{start}' checkpoint, set the standard API key, wait for every service, "
          f"turn continuous matching on, run the TestAuto workflow 'Matching Large <Size> Scenario {scn}', check it ran here and "
          f"its result, and back up the striped '{end}' checkpoint, verified. Why: measures {WHATS[scn]} on the slice of the size "
          f"(matching-large/values:<Size>.Slice)" + ("" if scn == '3c' else f"; the next scenario starts from '{end}'") + ". When: "
          f"after {before}; a rerun restores its own start. Example: {workload_name(scn)} --param Size=100M. Needs: the '{start}' "
          f"checkpoint of this size ({before}); matching-large-setup ran on this box for this version; TestAuto on this box "
          "pointed at this instance; the common pack. Success: Every step Succeeded or Skipped. If it fails: the failed step's "
          "description says what to fix; rerun the whole workload."),
         ["scenario" + scn, "test"] + ([] if scn == '2' else ["20U"]),  # 3a, 3b and 3c run 20 simulated users
         step_list, inputs=SCENARIO_INPUTS,
         globals_=g(*BOX, "ModelSourceDB", "BackupFolders", "ProfiseeApiKey", QuietSeconds="60", MatchingStrategyName="RetailClient"))


for _scn in LATER:
    scenario_workload(_scn)

# ---------------------------------------------------------------- tests/matching-large-continue
chain = [steps.tag_check_child("Workflows For This Size Exist", ALL_KEYS, SETUP),
         steps.run_child("Scenario 1 Finish", "matching-large-scenario1-finish",
                         "End marker, end counts and timings of the Scenario 1 run outside the pack, then the after-1 checkpoint")]
chain += [steps.run_child(f"Scenario {scn}", workload_name(scn), f"Measured run: Matching Scenario {scn}") for scn in LATER]
emit('tests', "matching-large-continue",
     ("What: Continues the large Matching run at the Size passed (a key of matching-large/sizes; default 100M) from the "
      "Scenario 1 that ran outside the pack: Scenario 1 finish (end marker, counts, timings, after-1), then Scenarios 2, 3a, 3b "
      "and 3c, each a measured TestAuto run on the slice of the size, each restoring the checkpoint before it. Example: "
      "matching-large-continue --param Size=100M. Why: this is the run a person starts. When: once the Scenario 1 matching has "
      "finished, after matching-large-preflight and matching-large-setup, with TestAuto on this box pointed at this instance; "
      "it takes days; nothing else may run on this Profisee database meanwhile. Needs: matching-large-setup; the source tables "
      "of the size; the matching-large reference sets filled in. Success: Every run ends Succeeded; each TestAuto execution "
      "holds its metrics. If it fails: it stops at the first failed run; rerun from that scenario with the lines of "
      "rounds/100m-continue-round.txt (each scenario restores its own start). Scenario 1 finish refuses once Scenario 2 started."),
     [],
     chain,
     inputs=[SIZE] + VERSION_CODE,
     globals_=g("TestAutoBaseUrl"),
     notes="Each child owns its run; a failed run stops the chain.")

# ---------------------------------------------------------------- start/matching-large-setup
setup_steps = [parts.scenariomgt_check_step(FAM), parts.version_exists_step(FAM, SETUP),
               parts.profiles_step(FAM, SETUP, SIZE_LOOP, SETS, PRELUDE, DERIVE)] + [template_step(t) for t in TEMPLATES.values()]
emit('start', SETUP,
     ("What: Create or update the Matching run profiles and the tagged TestAuto workflows of Scenario 1 Finish, 2, 3a, 3b and 3c "
      "for every size in matching-large/sizes, from one template per scenario (the slice from matching-large/values). Why: "
      "every scenario workload finds its workflow by automation tag and the timing steps record under the run profiles. When: "
      "once per box and Profisee version; after adding a size row or changing a slice; after any change to a workflow template. "
      "Reruns update in place and never remove a workflow. Needs: the TestAuto version exists in the repository; TestAuto "
      "answers on port 8443. Success: Every step Succeeded; each template step lists its workflows. If it fails: open the "
      "first failed step, whose If it fails text names what to check."),
     ["setup"], setup_steps, inputs=VERSION_CODE,
     globals_=g("ScenarioMgtBaseUrl", "ScenarioMgtApiKey", "TestAutoBaseUrl", "TestAutoEnvironmentName", "TestAutoApplicationServer",
                "TestAutoDatabaseServer", "TestAutoSourceDatabase"))

# ---------------------------------------------------------------- start/matching-large-preflight
CHECKPOINTS = ['after-1', 'after-2', 'after-3a', 'after-3b', 'after-3c']
SIZES_TOKEN = "{{$ref:%s/sizes:*}}" % FAM
VALUES_TOKEN = "{{$ref:%s/values:*}}" % FAM
SIZE_ROWS_SQL = ("SELECT LTRIM(RTRIM(LEFT(s.value, CHARINDEX(N'=', s.value + N'=') - 1))) AS size, "
                 "LTRIM(RTRIM(SUBSTRING(s.value, CHARINDEX(N'=', s.value + N'=') + 1, 400))) AS records "
                 "FROM STRING_SPLIT(N'" + SIZES_TOKEN + "', N',') s WHERE LTRIM(RTRIM(s.value)) <> N''")
SIZE_KEYS_SQL = ("SELECT LTRIM(RTRIM(LEFT(s.value, CHARINDEX(N'=', s.value + N'=') - 1))) AS size "
                 "FROM STRING_SPLIT(N'" + SIZES_TOKEN + "', N',') s WHERE LTRIM(RTRIM(s.value)) <> N''")
SLICE_ROWS_SQL = ("SELECT LTRIM(RTRIM(LEFT(s.value, CHARINDEX(N'.Slice=', s.value) - 1))) AS size, "
                  "LTRIM(RTRIM(SUBSTRING(s.value, CHARINDEX(N'.Slice=', s.value) + 7, 400))) AS slice "
                  "FROM STRING_SPLIT(N'" + VALUES_TOKEN + "', N',') s WHERE CHARINDEX(N'.Slice=', s.value) > 0")
STATE_SQL = """SET NOCOUNT ON;
DECLARE @rows bigint = (SELECT SUM(p.rows) FROM sys.partitions p WHERE p.object_id = OBJECT_ID(N'data.tRetailClient') AND p.index_id IN (0, 1));
IF @rows IS NULL THROW 50040, N'data.tRetailClient not found in {{ProfiseeDatabaseName}}: not a Matching model.', 1;
PRINT CONCAT(N'{{ProfiseeDatabaseName}}: RetailClient holds about ', @rows, N' rows (golden records included).');
DECLARE @line nvarchar(400);
DECLARE markers CURSOR LOCAL FAST_FORWARD FOR
    SELECT CONCAT(Name, N': ', CONVERT(nvarchar(30), StartedTime, 126), N' UTC') FROM monitor.tActivity
    WHERE ActivityType IN (N'Start of Scenario', N'End of Scenario') ORDER BY StartedTime;
OPEN markers; FETCH NEXT FROM markers INTO @line;
IF @@FETCH_STATUS <> 0 PRINT N'No scenario marker in monitor.tActivity.';
WHILE @@FETCH_STATUS = 0 BEGIN PRINT @line; FETCH NEXT FROM markers INTO @line; END
CLOSE markers; DEALLOCATE markers;
DECLARE @running int = (SELECT COUNT(*) FROM monitor.tActivity WHERE Status NOT IN (""" + FINISHED + """));
IF @running > 0 PRINT CONCAT(@running, N' monitor activities not finished yet (matching may still run).');"""
CHECKPOINTS_SQL = """SET NOCOUNT ON;
-- Every checkpoint of every size: each stripe (one per folder of matching-large/databases:BackupFolders) present or not.
DECLARE @stripes TABLE (n int IDENTITY(1, 1), folder nvarchar(400));
INSERT @stripes (folder) SELECT f + IIF(RIGHT(f, 1) = N'\\', N'', N'\\')
FROM (SELECT LTRIM(RTRIM(value)) AS f FROM STRING_SPLIT(N'{{BackupFolders}}', N',')) x WHERE f <> N'';
IF NOT EXISTS (SELECT 1 FROM @stripes) THROW 50020, N'matching-large/databases:BackupFolders names no folder.', 1;
DECLARE @count int = (SELECT COUNT(*) FROM @stripes);
DECLARE @size nvarchar(50), @cp nvarchar(50), @file nvarchar(260), @folder nvarchar(400), @path nvarchar(700), @exists int, @found int;
DECLARE @have nvarchar(max) = N'', @notYet nvarchar(max) = N'', @partial nvarchar(max) = N'';
DECLARE cps CURSOR LOCAL FAST_FORWARD FOR
    SELECT z.size, x.cp FROM (@@SIZES@@) z CROSS JOIN (VALUES @@CHECKPOINTS@@) x(n, cp) ORDER BY z.size, x.n;
OPEN cps; FETCH NEXT FROM cps INTO @size, @cp;
WHILE @@FETCH_STATUS = 0
BEGIN
    SET @file = CONCAT(N'profisee_MatchingLarge_', @size, N'_', @cp, N'_{{ProfiseeVersionCode}}.bak');
    SET @found = 0;
    DECLARE folders CURSOR LOCAL FAST_FORWARD FOR SELECT folder FROM @stripes;
    OPEN folders; FETCH NEXT FROM folders INTO @folder;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @path = @folder + @file;
        EXEC master.dbo.xp_fileexist @path, @exists OUTPUT;
        SET @found += @exists;
        FETCH NEXT FROM folders INTO @folder;
    END
    CLOSE folders; DEALLOCATE folders;
    IF @found = @count SET @have += CONCAT(@size, N'_', @cp, N' ')
    ELSE IF @found = 0 SET @notYet += CONCAT(@size, N'_', @cp, N' ')
    ELSE SET @partial += CONCAT(@size, N'_', @cp, N' (', @found, N' of ', @count, N') ');
    FETCH NEXT FROM cps INTO @size, @cp;
END
CLOSE cps; DEALLOCATE cps;
PRINT CONCAT(N'Checkpoints present for version {{ProfiseeVersionCode}} (every stripe): ', IIF(@have = N'', N'none', @have));
IF @notYet <> N'' PRINT CONCAT(N'Not made yet (each is written by the workload before it; not a failure): ', @notYet);
IF @partial <> N''
BEGIN
    DECLARE @msg nvarchar(2048) = CONCAT(N'Checkpoints with stripes missing (a restore of them fails; rerun the workload that writes them): ', @partial);
    THROW 50041, @msg, 1;
END""".replace('@@SIZES@@', SIZE_KEYS_SQL).replace('@@CHECKPOINTS@@', ", ".join("(%d, N'%s')" % (i, c) for i, c in enumerate(CHECKPOINTS)))
ROOM_SQL = """SET NOCOUNT ON;
-- Room for one checkpoint: the used space of the Profisee database (uncompressed, so the estimate is on the safe side)
-- split over the stripes, on the drive of each folder.
DECLARE @usedMB bigint;
DECLARE @sql nvarchar(max) = N'USE ' + QUOTENAME(N'{{ProfiseeDatabaseName}}') + N'; SELECT @u = SUM(CAST(FILEPROPERTY(name, ''SpaceUsed'') AS bigint)) * 8 / 1024 FROM sys.database_files WHERE type = 0;';
EXEC sp_executesql @sql, N'@u bigint OUTPUT', @u = @usedMB OUTPUT;
DECLARE @stripes TABLE (folder nvarchar(400));
INSERT @stripes SELECT LTRIM(RTRIM(value)) FROM STRING_SPLIT(N'{{BackupFolders}}', N',') WHERE LTRIM(RTRIM(value)) <> N'';
DECLARE @count int = (SELECT COUNT(*) FROM @stripes);
IF @count = 0 THROW 50020, N'matching-large/databases:BackupFolders names no folder.', 1;
DECLARE @drives TABLE (drive char(1), freeMB bigint);
INSERT @drives EXEC master.dbo.xp_fixeddrives;
DECLARE @need bigint = @usedMB / @count + 1;
DECLARE @line nvarchar(400), @short nvarchar(max) = N'';
DECLARE d CURSOR LOCAL FAST_FORWARD FOR
    SELECT CONCAT(s.folder, N': ', ISNULL(CAST(dr.freeMB / 1024 AS nvarchar(20)), N'?'), N' GB free'),
           IIF(dr.freeMB IS NULL OR dr.freeMB < @need, s.folder + N' ', N'')
    FROM @stripes s LEFT JOIN @drives dr ON dr.drive = LEFT(s.folder, 1);
DECLARE @s nvarchar(400);
OPEN d; FETCH NEXT FROM d INTO @line, @s;
WHILE @@FETCH_STATUS = 0 BEGIN PRINT @line; SET @short += @s; FETCH NEXT FROM d INTO @line, @s; END
CLOSE d; DEALLOCATE d;
PRINT CONCAT(N'{{ProfiseeDatabaseName}} uses ', @usedMB / 1024, N' GB; one checkpoint needs up to ', @need / 1024, N' GB per stripe (less when compressed); the old stripes of a checkpoint are overwritten in place.');
IF @short <> N''
BEGIN
    DECLARE @msg nvarchar(2048) = CONCAT(N'Not enough room for one more checkpoint stripe (', @need / 1024, N' GB) in: ', @short);
    THROW 50042, @msg, 1;
END"""
TABLES_SQL = """SET NOCOUNT ON;
DECLARE @db sysname = N'{{ModelSourceDB}}';
IF DB_ID(@db) IS NULL
BEGIN
    DECLARE @none nvarchar(400) = CONCAT(N'Database ', @db, N' (matching-large/databases:ModelSourceDB) does not exist on {{DatabaseServerName}}; create it and build the tables (Matching Large help page).');
    THROW 50043, @none, 1;
END
-- Each size: Scenario1 holds its record count, Scenario2, 3b and 3c each hold its slice.
DECLARE @problems nvarchar(max) = N'', @size nvarchar(50), @records bigint, @slice bigint, @part nvarchar(50), @name sysname, @id int, @n bigint, @want bigint, @sql nvarchar(max);
DECLARE names CURSOR LOCAL FAST_FORWARD FOR
    SELECT z.size, TRY_CAST(z.records AS bigint), TRY_CAST(sl.slice AS bigint), x.part
    FROM (@@SIZES@@) z LEFT JOIN (@@SLICES@@) sl ON sl.size = z.size
    CROSS JOIN (VALUES (1, N'Scenario1'), (2, N'Scenario2'), (3, N'Scenario3b'), (4, N'Scenario3c')) x(n, part) ORDER BY z.size, x.n;
OPEN names; FETCH NEXT FROM names INTO @size, @records, @slice, @part;
WHILE @@FETCH_STATUS = 0
BEGIN
    SET @name = CONCAT(N'RetailClient', @size, @part);
    SET @want = IIF(@part = N'Scenario1', @records, @slice);
    SET @id = OBJECT_ID(QUOTENAME(@db) + N'.dbo.' + QUOTENAME(@name), N'U');
    IF @want IS NULL SET @problems += CONCAT(@name, N' (no slice row ', @size, N'.Slice in matching-large/values) ')
    ELSE IF @id IS NULL SET @problems += CONCAT(@name, N' (missing) ')
    ELSE
    BEGIN
        SET @sql = N'SELECT @n = SUM(p.rows) FROM ' + QUOTENAME(@db) + N'.sys.partitions p WHERE p.object_id = @id AND p.index_id IN (0, 1)';
        EXEC sp_executesql @sql, N'@id int, @n bigint OUTPUT', @id = @id, @n = @n OUTPUT;
        PRINT CONCAT(@name, N': ', @n, N' rows (expected ', @want, N')');
        IF @n <> @want SET @problems += CONCAT(@name, N' (', @n, N' rows, expected ', @want, N') ');
    END
    FETCH NEXT FROM names INTO @size, @records, @slice, @part;
END
CLOSE names; DEALLOCATE names;
IF OBJECT_ID(QUOTENAME(@db) + N'.dbo.SourceSystem', N'U') IS NULL SET @problems += N'SourceSystem (missing) ';
IF @problems <> N''
BEGIN
    DECLARE @msg nvarchar(2048) = CONCAT(N'Source tables in ', @db, N' not ready: ', @problems, N'. Build them with Build-MatchingScenarioTables.ps1 -Slice (Matching Large help page).');
    THROW 50044, @msg, 1;
END""".replace('@@SIZES@@', SIZE_ROWS_SQL).replace('@@SLICES@@', SLICE_ROWS_SQL)
SQL_FAIL = (" If it fails: read the SQL error text first; then check the database server (matching-large/machines:DatabaseServerName) "
            "is reachable from this box with Windows authentication.")
HTTP_RESULT = ("Success: The response status is 200. If it fails: 401 = the API key secret is wrong; 404 = the address is wrong; "
               "no response = the server in the URL (matching-large/urls, matching-large/machines) is down.")
emit('start', "matching-large-preflight",
     ("What: Checks this box is ready to continue a large Matching run: the instance's application pools exist and run, the "
      "Profisee database and its scenario markers (printed), which striped checkpoints exist (a checkpoint with a stripe "
      "missing fails), room for one more checkpoint in every backup folder, the source tables of every size in "
      "matching-large/sizes with the expected row counts, TestAuto and its repository answer, the standard API key is set and "
      "works through the gateway and the Data service (common-api-key-set), and every TestAuto workflow matching-large-setup "
      "creates sits on exactly one workflow. Why: finds every environment problem in one run, before a days-long run fails "
      "half way. When: before and after matching-large-setup, after any reference data change, and first whenever a run "
      "fails; never while a run works on this Profisee database (the key step restarts IIS). It cannot see where TestAuto on "
      "this box points: each scenario checks its markers landed here. Needs: the matching-large reference sets, the common "
      "pack and the box's secrets. It changes only two things: the pool step starts a pool that is stopped, and the key step "
      "writes the standard API key and restarts IIS. Success: Every step Succeeded or Skipped; before the first "
      "matching-large-setup the workflow step says \"not created yet\", normal. If it fails: each step's failure text names "
      "the reference key, secret or machine to fix; fix reference data or the box, never a workload file."),
     [],
     [steps.pools_child("Application Pools Exist", "Start",
                        "a run fails half way when the instance has no pools or one will not start; this finds it first"),
      steps.sql("Profisee Database State", STATE_SQL,
          "What: Print the RetailClient row count of the Profisee database (matching-large/databases:ProfiseeDatabaseName), every "
          "scenario marker in its Activity Monitor and how many activities are not finished. Why: shows how far the run got "
          "before anything is started. Success: the lines print." + SQL_FAIL, timeout=300),
      steps.sql("Checkpoints Present", CHECKPOINTS_SQL,
          "What: For every size in matching-large/sizes, list which striped checkpoints (" + ", ".join(CHECKPOINTS) + ") of this "
          "version have every stripe in the folders of matching-large/databases:BackupFolders. Why: shows how far each chain has "
          "run; a checkpoint with some stripes missing cannot be restored. Success: two lines list the checkpoints present and not "
          "made yet; a checkpoint with a stripe missing fails the step." + SQL_FAIL, conn=steps.MASTER, timeout=300),
      steps.sql("Room For A Checkpoint", ROOM_SQL,
          "What: Print the free space of every backup folder's drive and fail when one has less than the used space of the "
          "Profisee database divided by the number of stripes. Why: a checkpoint of a 100M database is hundreds of GB; a full "
          "drive fails the backup after the scenario already ran. Success: every folder has room." + SQL_FAIL,
          conn=steps.MASTER, timeout=300),
      steps.sql("Source Tables Exist", TABLES_SQL,
          "What: Check the database matching-large/databases:ModelSourceDB holds SourceSystem and, for every size in "
          "matching-large/sizes, RetailClient<Size>Scenario1 with the record count and Scenario2, 3b and 3c with the slice "
          "(matching-large/values:<Size>.Slice) rows. Why: the scenarios read them through TestAuto and the checks compare with "
          "them. Success: every table prints its row count as expected." + SQL_FAIL, conn=steps.MASTER, timeout=300),
      steps.http_get("TestAuto Answers", "{{TestAutoBaseUrl}}/api/workflows/by-tag?tag=AUTO%3Apreflight",
          "What: Ask TestAuto on this box (matching-large/machines:TestServerNameFQDN, port 8443) for workflows tagged with a "
          "probe tag. Why: every run finds its TestAuto workflow by tag through this call. " + HTTP_RESULT, verify_ssl=False,
          max_time=120),
      steps.http_get("TestAuto Model Answers", "{{ScenarioMgtBaseUrl}}v1/Records/TestAutoWorkflow?PageSize=1",
          "What: Read one TestAuto workflow record from the TestAuto repository (matching-large/urls:ScenarioMgtBaseUrl) with the "
          "RestClients:ScenarioMgt:ApiKey secret. Why: matching-large-setup writes the run profiles and workflows through it. "
          + HTTP_RESULT, headers={"x-api-key": "{{ScenarioMgtApiKey}}"}, max_time=120),
      steps.wait_runs(),
      steps.key_set_child(),
      specs.keys_step("List The Workflows Setup Creates", key_patterns(),
          "What: Work out, from the size rows now in reference data (matching-large/sizes and values), the key of every TestAuto "
          "workflow matching-large-setup creates, with the same loops it uses, into the run parameter SetupTagKeys. Why: the next "
          "step checks each of them; the list is never typed. Success: one line of keys. If it fails: a size or slice row is "
          "empty or malformed; the message names it.", setup_name=SETUP, output="SetupTagKeys"),
      steps.tag_check_child("Every Workflow Found Once", "{{SetupTagKeys}}", SETUP, allow_none=True)],
     inputs=VERSION_CODE,
     globals_=g(*BOX, "ModelSourceDB", "BackupFolders", "ScenarioMgtBaseUrl", "ScenarioMgtApiKey", SetupTagKeys=""),
     notes="SetupTagKeys is set by the step List The Workflows Setup Creates during the run; it starts blank and is never passed.")

# ---------------------------------------------------------------- rounds
rounds = os.path.join(root, 'rounds')
os.makedirs(rounds, exist_ok=True)
for _size in SIZE_ROWS:
    _f = _size.lower() + '-continue-round.txt'
    _path = os.path.join(rounds, _f)
    if not os.path.exists(_path):  # a round is a person's file once it exists
        with open(_path, 'w', encoding='utf-8', newline='\n') as _o:
            _o.write(
                f"# Matching Large {_size}, one scenario per line, so a failed scenario can be rerun on its own (from its line down).\n"
                f"# Starts from the Scenario 1 that ran outside the pack on matching-large/databases:ProfiseeDatabaseName.\n"
                f"# Run: bash ../../tools/runner/run-queue.sh <CrewChief box> {_f}  (nothing else on that Profisee database meanwhile)\n"
                "# A line is a workload and the values it gets: <workload> Name=Value\n"
                "# '+' = runs only when the line before passed (each scenario restores the checkpoint the one before it wrote).\n\n"
                f"matching-large-scenario1-finish Size={_size}\n" + "".join(f"+{workload_name(s)} Size={_size}\n" for s in LATER))

count = sum(len(files) for _d, _s, files in os.walk(wl_root))
print(f"matching-large pack written: {count} workloads, {len(TEMPLATES)} TestAuto workflow templates")
