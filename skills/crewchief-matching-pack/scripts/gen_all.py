"""Adds Matching scenarios 2, 3a, 3b, 3c (1K) to the matching pack, on top of gen_s1.py's output.

TestAuto step configs are PROD workflow 10000215 steps 12-44 (read 11/05 into wf10000215/NN.json), copied verbatim
and patched only where the rewrite requires: box/version from reference data, size 1K, run profiles per scenario,
{{STEP:n}} renumbered, stale WorkloadExecution blanked, and (2/3b/3c) the ScenarioTable record source from the
Scenario 2 mutation plan. TestAuto runtime tokens are written as {%...%} (see gen_s1.py).
Usage: python gen_all.py <packRoot> <connectUpsertBody.ps1>
"""
import copy, json, os, subprocess, sys

root, upsert_path = sys.argv[1], sys.argv[2]
here = os.path.dirname(os.path.abspath(__file__))
subprocess.run([sys.executable, os.path.join(here, 'gen_s1.py'), root, upsert_path], check=True)

wl_dir = os.path.join(root, 'workloads', 'matching', 'internal', '1k')
ref_dir = os.path.join(root, 'reference-kv', 'matching')
src = os.path.join(here, 'wf10000215')
VER = "{{$ref:matching/environment:ProfiseeVersionCode}}"
SIZE_RECORDS, SIZE_LABEL, SLICE = 1000, '1K', 100   # Scenario1 count; every later scenario = 10% (N/10)
TRANSFORM_SEED = 350
MUTATION = {  # plan 2026-11-04-matching-scenario2-mutation-plan.md, D5 with NoChange 3 (Gene 11/05)
    "MaxAttributeChanges": 2,
    "RuleDefinitions": {
        "FirstName": {"Rules": ["NoChange", "Typo", "SwapWindow", "CaseToggle", "NicknameSwap"], "Weights": [3, 0.25, 0.25, 0.25, 0.25]},
        "LastName": {"Rules": ["NoChange", "Typo", "SwapWindow", "CaseToggle"], "Weights": [3, 0.3333, 0.3333, 0.3333]},
        "IDNumber": {"Rules": ["NoChange", "Typo"], "Weights": [3, 1]},
        "DateOfBirth": {"Rules": ["NoChange", "DobShift"], "Weights": [3, 1]},
        "AddressLine1": {"Rules": ["NoChange", "AddressDigit", "StreetSynonym", "Typo"], "Weights": [3, 0.3333, 0.3333, 0.3333]},
        "PostalCode": {"Rules": ["NoChange", "PostalDigit"], "Weights": [3, 1]},
        "Phone Number": {"Rules": ["NoChange", "PhoneDigit", "PhoneFormat"], "Weights": [3, 0.5, 0.5]},
        "HomeEmail": {"Rules": ["NoChange", "EmailVariant", "EmailDomainSwap", "Typo"], "Weights": [3, 0.3333, 0.3333, 0.3333]},
    },
}
TABLE_DROP_KEYS = ["NewSourceSystems", "ChangedSourceSystems", "SourceSystemNewOffsets", "SourceSystemDistribution",
                   "SelectedNewSourceCodes", "SelectedChangedSourceCodes", "UpdateVariationLevel",
                   # wizard state only (read by TestAuto.Web's editor, not at run time); keeps the config under 4000 characters
                   "ModelSourceDefaults", "SelectedLookupAttributeCodes", "SelectedScenarioTemplate"]


def run_profile(scn):
    return f"{VER}-RetailClient-Scenario {scn}-{SIZE_RECORDS}-0"


def prod(n):
    with open(os.path.join(src, f'{n:02d}.json'), encoding='utf-8-sig') as f:
        return json.load(f)


def finish(cfg):
    env = cfg['ScenarioEnvironment']
    env.update({"TargetEnvironmentName": "{{TestAutoEnvironmentName}}", "ProfiseeVersion": VER, "WorkloadExecution": "",
                "TargetApplicationServer": "{{TestAutoApplicationServer}}", "TargetDatabaseServer": "{{TestAutoDatabaseServer}}"})
    text = json.dumps(cfg, indent=2)
    for t in ("{{$config:", "{{STEP:"):
        assert t not in text or True
    text = text.replace('{{$config:', '{%$config:').replace('{{STEP:', '{%STEP:')
    # close the swapped tokens: every {%... must end with %}
    out, i = [], 0
    while True:
        j = text.find('{%', i)
        if j < 0:
            out.append(text[i:]); break
        k = text.find('}}', j)
        out.append(text[i:k]); out.append('%}'); i = k + 2
    text = ''.join(out).replace('\n', '\r\n')
    # The repository attribute holds 4000 characters; a longer value is stored as NULL without an error.
    if len(text) > 4000:
        text = json.dumps(json.loads(text), separators=(',', ':'))
    assert len(text) <= 4000, f"{cfg['ScenarioName']}: {len(text)} characters even compact"
    assert '{{$config' not in text and '{{STEP' not in text, 'unescaped TestAuto token left'
    return text


def step(n, name, desc, patch=None):
    cfg = prod(n)
    if patch:
        patch(cfg)
    return (name, desc, finish(cfg))


def custom(cfg):
    return cfg['ScenarioRuntime']['CustomParms']


def marker_patch(scn):
    return None  # markers carry no size, version or box value


def snapshot_patch(scn, link):
    def p(cfg):
        c = custom(cfg)
        c.update({"SourceRecords": SIZE_RECORDS, "UnifiedMatchingScenarioWorkloadExecution": "{{STEP:%d}}" % link,
                  "UnifiedMatchingApiExecutionRunProfile": run_profile(scn)})
    return p


def timing_patch(scn, link):
    def p(cfg):
        custom(cfg).update({"UnifiedMatchingScenarioWorkloadExecution": "{{STEP:%d}}" % link,
                            "UnifiedMatchingApiExecutionRunProfile": run_profile(scn)})
    return p


def scenario_table_patch(scn, table, iteration_limit):
    def p(cfg):
        c = custom(cfg)
        for k in TABLE_DROP_KEYS:
            c.pop(k, None)
        c.update({"RecordSource": "ScenarioTable", "UnifiedMatchingApiExecutionRunProfile": run_profile(scn),
                  "NewRecordStartingOffset": 0, "ChangedRecordStartingOffset": 0, "TransformSeed": TRANSFORM_SEED,
                  "MatchFieldMutationSettings": MUTATION, "IterationLimit": iteration_limit,
                  "MatchingStrategyName": "RetailClient"})
        cfg['ScenarioTables']['SourceEntityName'] = table
        cfg['ScenarioTesting']['TestRecordLimit'] = SLICE
    return p


def lookup_patch(scn):
    def p(cfg):
        c = custom(cfg)
        c.update({"UnifiedMatchingApiExecutionRunProfile": run_profile(scn), "IterationLimit": SLICE})
        cfg['ScenarioTesting']['TestRecordLimit'] = SLICE
        # TestAuto rejects every batch when the distribution does not sum to TestRecordLimit; PROD's is sized for 100K.
        dist = c.get('SourceSystemDistribution')
        if dist:
            total = sum(dist.values())
            scaled = {k: v * SLICE // total for k, v in dist.items()}
            first = next(iter(scaled))
            scaled[first] += SLICE - sum(scaled.values())
            c['SourceSystemDistribution'] = scaled
    return p


def polling(n, before):
    return step(n, "Wait for Matching To Be Idle" + (" Before Start" if before else ""),
                "Polls the RetailClient strategy until matching is idle." + (" Setup, before the start marker: not measured." if before else ""))


def markers(scn, start_n, end_n):
    s = (f"Write Start of Scenario {scn} Monitor Message", f"Writes the start marker the timing step measures from.")
    e = (f"Write End of Scenario {scn} Monitor Message", f"Writes the end marker the timing step measures to.")
    return step(start_n, *s), step(end_n, *e)



def enable_run(n, scn):
    return step(n, "Enable RetailClient Matching Strategy Then Run",
                f"Enables the RetailClient strategy (saving it with continuous matching on disabled it) and runs it with survivorship, "
                f"inside the Scenario {scn} markers as the production workflow does.")

T2 = f"RetailClient{SIZE_LABEL}Scenario2"
T3B = f"RetailClient{SIZE_LABEL}Scenario3b"
T3C = f"RetailClient{SIZE_LABEL}Scenario3c"

workflows = {}
# Scenario 2: idle, start, counts, run (4), wait, end, counts, timing
s, e = markers('2', 12, 18)
workflows['matching-1k-scenario2'] = ('2', "Matching Scenario 2 (operational batch: New, Changed with mutated match fields, NoChange) from table " + T2, [
    s,
    step(13, "Capture Matching Status Counts for Start of Scenario 2", "Match status counts before the batch.", snapshot_patch('2', 4)),
    enable_run(15, "2"),
    step(16, "Matching Scenario 2 Incremental Batch Load", f"Sends every row of {T2} as a batch load: New rows create, Changed rows are mutated on their strategy fields and PATCHed by Code, NoChange rows are PATCHed as they are.", scenario_table_patch('2', T2, 0)),
    polling(17, False), e,
    step(19, "Capture Matching Status Counts for End of Scenario 2", "Match status counts after matching finished.", snapshot_patch('2', 4)),
    step(20, "Matching Timing Results Scenario 2", "Collects matching timings between the start and end markers.", timing_patch('2', 4)),
])
# Scenario 3a: idle, start, lookups, end (no counts, no timing: the lookup scenario records its own metrics)
s, e = markers('3a', 21, 25)
workflows['matching-1k-scenario3a'] = ('3a', "Matching Scenario 3a (lookups of matched records, creates nothing)", [
    s, enable_run(23, "3a"),
    step(24, "Matching Scenario 3a Lookup Before Create", f"Looks up {SLICE} existing AutoApproved records through the matching lookup; creates nothing.", lookup_patch('3a')),
    e,
])
# Scenario 3b: idle, start, counts, run (4), wait, end, counts, timing
s, e = markers('3b', 26, 32)
workflows['matching-1k-scenario3b'] = ('3b', "Matching Scenario 3b (lookup, then create on a miss) from table " + T3B, [
    s,
    step(27, "Capture Matching Status Counts for Start of Scenario 3b", "Match status counts before the run.", snapshot_patch('3b', 4)),
    enable_run(29, "3b"),
    step(30, "Matching Scenario 3b Continuous Matching", f"Sends every row of {T3B}: a timed lookup, then a create when nothing matches.", scenario_table_patch('3b', T3B, SLICE)),
    polling(31, False), e,
    step(33, "Capture Matching Status Counts for End of Scenario 3b", "Match status counts after matching finished.", snapshot_patch('3b', 4)),
    step(34, "Matching Timing Results Scenario 3b", "Collects matching timings between the start and end markers.", timing_patch('3b', 4)),
])
# Scenario 3c: idle, start, counts, run (4), wait, end, post-run collection, counts, timing
s, e = markers('3c', 35, 41)


def postrun_patch(cfg):
    custom(cfg)["SourceWorkloadExecution"] = "{{STEP:4}}"


workflows['matching-1k-scenario3c'] = ('3c', "Matching Scenario 3c (creates with continuous matching) from table " + T3C, [
    s,
    step(36, "Capture Matching Status Counts for Start of Scenario 3c", "Match status counts before the run.", snapshot_patch('3c', 4)),
    enable_run(38, "3c"),
    step(39, "Matching Scenario 3c Continuous Matching", f"Creates every row of {T3C} one record per call with continuous matching on.", scenario_table_patch('3c', T3C, SLICE)),
    polling(40, False), e,
    step(42, "Matching Scenario 3c Post-Run Metric Collection", "Collects golden record times for the records the run created.", postrun_patch),
    step(43, "Capture Matching Status Counts for End of Scenario 3c", "Match status counts after matching finished.", snapshot_patch('3c', 4)),
    step(44, "Matching Timing Results Scenario 3c", "Collects matching timings between the start and end markers.", timing_patch('3c', 4)),
])

# ---- reference data: display names
wf_ref_path = os.path.join(ref_dir, 'workflows.json')
with open(wf_ref_path, encoding='utf-8') as f:
    wf_ref = json.load(f)
for key, (scn, what, _) in workflows.items():
    wf_ref['entries'][key] = f"Matching {SIZE_LABEL} Scenario {scn}"
    wf_ref['keyDescriptions'][key] = (f"Display name of the TestAuto workflow for {what}, {SIZE_LABEL}. Its automation tag is "
                                      f"AUTO:<this box>:<ProfiseeVersionCode>:{key}; the name is free text and only for people.")
with open(wf_ref_path, 'w', encoding='utf-8') as f:
    json.dump(wf_ref, f, indent=2)

# ---- create workload: run profiles for every scenario + one upsert step per workflow
create_path = os.path.join(wl_dir, 'matching-1k-testauto-create.workload.json')
with open(create_path, encoding='utf-8') as f:
    create = json.load(f)
s1_upsert = create['steps'][2]['inline']['scriptContent']
upsert_body = s1_upsert[s1_upsert.index("\r\n'@"):]  # starts with the newline that closes the here-string

profiles = [("1", 0), ("2", SLICE), ("3a", 0), ("3b", SLICE), ("3c", SLICE)]  # IncrementalVolumeCount as PROD's 26R3 profiles
profile_lines = ",\r\n".join(
    "    [ordered]@{ Code = '%s'; ProfiseeVersion = $version; Scenario = 'UnifiedMatchingScenario'; MatchingStrategy = 'RetailClient'; "
    "MatchingScenarioName = 'Scenario %s'; SourceRecordCount = %d; AttributeCount = 42; DBACount = 5; FreeformCount = 37; "
    "IncrementalVolumeCount = %d; RuleCount = 0 }" % (run_profile(scn), scn, SIZE_RECORDS, inc) for scn, inc in profiles)
create['steps'][1]['inline']['scriptContent'] = "\r\n".join([
    "$ErrorActionPreference = 'Stop'",
    "$base = '{{ScenarioMgtBaseUrl}}'.TrimEnd('/') + '/'",
    "$headers = @{ 'x-api-key' = '{{ScenarioMgtApiKey}}'; accept = 'application/json' }",
    "$version = '" + VER + "'",
    "$verFilter = [uri]::EscapeDataString(\"[Code] eq '$version'\")",
    "$v = Invoke-RestMethod -Uri \"${base}v1/Records/ProfiseeVersion?Filter=$verFilter\" -Headers $headers",
    "$rows = if ($v -is [array]) { $v } else { @($v.data) }",
    "if (-not $rows) { throw \"TestAuto version '$version' does not exist in the repository; create it (data.tProfiseeVersion) before running this workload.\" }",
    "$profiles = @(",
    profile_lines,
    ")",
    "Invoke-RestMethod -Method Patch -Uri \"${base}v1/Records/UnifiedMatchingApiExecutionRunProfile?IsUpsert=true&recordsAreSameShape=true\" -Headers $headers -ContentType 'application/json' -Body (ConvertTo-Json -Depth 5 -InputObject $profiles) | Out-Null",
    "\"Run profiles upserted: $(($profiles | ForEach-Object { $_.Code }) -join ' | ')\"",
])
create['steps'][1]['label'] = "Upsert Run Profiles"
create['steps'][1]['inline']['description'] = (
    f"What: Create or update the {SIZE_LABEL} Matching run profiles of Scenarios 1, 2, 3a, 3b and 3c "
    f"(<ProfiseeVersionCode>-RetailClient-Scenario <x>-{SIZE_RECORDS}-0). Why: the snapshot, lookup and timing steps record "
    "their results under them. Success: the profiles are upserted. If it fails: a missing TestAuto version is named in the error; create it in the repository.")
create['steps'] = create['steps'][:3]
base_step = create['steps'][2]
for key, (scn, what, details) in workflows.items():
    spec = {"Key": key, "Name": "{{$ref:matching/workflows:" + key + "}}", "Category": "Matching",
            "PlainTags": f"Matching,{VER},{{{{$ref:matching/environment:MainMachineTag}}}},{SIZE_LABEL},Scenario {scn}",
            "Description": (f"Automation ID: <AUTOMATION_ID>. CrewChief finds this workflow by that tag alone (reference key matching/workflows:{key}); "
                            "do not edit or remove the tag, and to experiment copy the workflow and remove the tag from the copy. "
                            f"Measures: {what}, {SIZE_LABEL}, RetailClient strategy, on the Profisee version in matching/environment:ProfiseeVersionCode. "
                            f"Run by the CrewChief workload '{key}', which restores the scenario's starting checkpoint and turns continuous matching on first; running it alone measures nothing useful."),
            "Details": [{"Name": n, "Description": d, "ExecutionOrder": i + 1, "ProfiseeVersion": VER, "ScenarioConfiguration": c}
                        for i, (n, d, c) in enumerate(details)]}
    st = copy.deepcopy(base_step)
    st['label'] = "Upsert Workflow " + key
    st['inline']['scriptContent'] = "$specJson = @'\r\n" + json.dumps(spec, ensure_ascii=False) + upsert_body
    st['inline']['description'] = (f"What: Create or update the TestAuto workflow '{key}' and its {len(details)} steps, found by its automation tag. "
                                   "Why: CrewChief runs it by that tag. Success: the workflow exists with exactly these steps. "
                                   "If it fails: two workflows with the same tag must be untagged by hand first.")
    create['steps'].append(st)
create['description'] = create['description'].replace(
    "Create or update the 1K Matching run profile and the TestAuto workflow 'Matching 1K Scenario 1'",
    "Create or update the 1K Matching run profiles and the TestAuto workflows for Scenarios 1, 2, 3a, 3b and 3c")
with open(create_path, 'w', encoding='utf-8') as f:
    json.dump(create, f, indent=2)

# ---- scenario workloads, cloned from matching-1k-scenario1
with open(os.path.join(wl_dir, 'matching-1k-scenario1.workload.json'), encoding='utf-8') as f:
    s1 = json.load(f)

cm_script = "\r\n".join([
    "$ErrorActionPreference = 'Stop'",
    "$base = '{{ProfiseeBaseUrl}}'.TrimEnd('/')",
    "$headers = @{ 'x-api-key' = '{{ProfiseeApiKey}}'; accept = 'application/json' }",
    "$uri = \"$base/v1/Matching/strategies/$([uri]::EscapeDataString('{{MatchingStrategyName}}'))\"",
    "$s = @((Invoke-RestMethod -Uri $uri -Headers $headers -SkipCertificateCheck).data)[0]",
    "if (-not $s) { throw \"Matching strategy '{{MatchingStrategyName}}' not found.\" }",
    "# PUT takes the strategy configuration plus its header; only autoMatch and autoSurvive change (continuous matching).",
    "$body = [ordered]@{ name = $s.name; code = $s.code; entity = [ordered]@{ id = $s.entityUid; name = $s.entityName }",
    "    status = 1; lockStatus = $s.lockStatus; includeMatching = $true; autoMatch = $true; includeSurvivorship = $true; autoSurvive = $true }",
    "foreach ($p in $s.configuration.PSObject.Properties) { if ($p.Name -ne 'artifactVersion') { $body[$p.Name] = $p.Value } }",
    "Invoke-RestMethod -Method Put -Uri \"$base/v1/Matching/strategies\" -Headers $headers -ContentType 'application/json' -SkipCertificateCheck -Body (ConvertTo-Json -Depth 30 -InputObject @($body)) | Out-Null",
    "$after = @((Invoke-RestMethod -Uri $uri -Headers $headers -SkipCertificateCheck).data)[0]",
    "if ([int]$after.autoMatch -ne 1 -or [int]$after.autoSurvive -ne 1) { throw \"Continuous matching is still off for '{{MatchingStrategyName}}' (autoMatch=$($after.autoMatch), autoSurvive=$($after.autoSurvive)).\" }",
    "# Saving the strategy leaves it disabled (status 0). The TestAuto workflow enables and runs it right after its start marker,",
    "# as the production Matching workflow does, so that activity falls inside the scenario.",
    "\"Continuous matching on for '{{MatchingStrategyName}}' (autoMatch and autoSurvive = 1); the workflow enables and runs it.\""
])
cm_step = {"label": "Turn Continuous Matching On", "inline": {
    **{k: v for k, v in s1['steps'][5]['inline'].items() if k not in ('scriptContent', 'description')},
    "timeoutSeconds": 300, "scriptContent": cm_script,
    "description": ("What: Turn continuous matching on for the RetailClient strategy (read it, set autoMatch and autoSurvive, PUT it back). "
                    "Why: Scenarios 2, 3a, 3b and 3c measure records matched as they arrive; the checkpoint from Scenario 1 has it off. Saving the "
                    "strategy disables it; the TestAuto workflow enables and runs it after its start marker, so that work is measured. "
                    "Success: the strategy reads back with autoMatch and autoSurvive on. "
                    "If it fails: 401 = the API key; 404 = the strategy name in this workload's MatchingStrategyName.")}}

GOLDEN = ("DECLARE @golden bigint = (SELECT COUNT_BIG(*) FROM data.tRetailClient r JOIN data.tMatchStatus s ON s.ID = r.[Match Status] WHERE s.Code = N'10');\r\n"
          "DECLARE @loaded bigint = (SELECT COUNT_BIG(*) FROM data.tRetailClient) - @golden;\r\n")


def present(table, action=None):
    w = f" WHERE t.RecordAction = N'{action}'" if action else ""
    return (f"(SELECT COUNT_BIG(*) FROM [{{{{ModelSourceDB}}}}].dbo.{table} t JOIN data.tRetailClient r ON r.Code = t.Code{w})")


def created_since(scn):
    # Records a scenario creates get a Profisee-assigned Code, so count non-golden records entered after its start marker (both UTC).
    return "\r\n".join([
        f"DECLARE @start datetime2 = (SELECT MAX(StartedTime) FROM monitor.tActivity WHERE Name = N'Start of Scenario {scn} for Retail Client');",
        f"IF @start IS NULL THROW 50012, N'Scenario {scn} start marker not found in monitor.tActivity.', 1;",
        "DECLARE @created bigint, @createdMatched bigint;",
        "SELECT @created = COUNT_BIG(*), @createdMatched = COUNT_BIG(s.Code) FROM data.tRetailClient r LEFT JOIN data.tMatchStatus s ON s.ID = r.[Match Status] "
        "WHERE r.[$EnterDTM] >= @start AND (s.Code IS NULL OR s.Code <> N'10');"])


checks = {
    'matching-1k-scenario2': ("Check Scenario 2 Landed", "\r\n".join([
        GOLDEN.rstrip(),
        f"DECLARE @updates bigint = (SELECT COUNT_BIG(*) FROM [{{{{ModelSourceDB}}}}].dbo.{T2} WHERE RecordAction <> N'New');",
        f"DECLARE @present bigint = {present(T2)};",
        f"DECLARE @new bigint = (SELECT COUNT_BIG(*) FROM [{{{{ModelSourceDB}}}}].dbo.{T2} WHERE RecordAction = N'New');",
        "-- New rows are created without their source Code (Profisee assigns one), so they are the loaded rows outside Scenario 1.",
        f"DECLARE @newMatched bigint = (SELECT COUNT_BIG(*) FROM data.tRetailClient r JOIN data.tMatchStatus s ON s.ID = r.[Match Status] "
        f"WHERE s.Code <> N'10' AND NOT EXISTS (SELECT 1 FROM [{{{{ModelSourceDB}}}}].dbo.RetailClient{SIZE_LABEL}Scenario1 t WHERE t.Code = r.Code));",
        f"IF @present <> @updates OR @loaded <> {SIZE_RECORDS} + @new OR @newMatched = 0",
        "BEGIN",
        f"    DECLARE @msg nvarchar(400) = CONCAT(N'After Scenario 2: ', @present, N' of ', @updates, N' Changed/NoChange codes present; ', @loaded, N' loaded rows (expected {SIZE_RECORDS} + ', @new, N' new); ', @newMatched, N' new rows matched (continuous matching must match at least one).');",
        "    THROW 50007, @msg, 1;",
        "END",
        f"PRINT CONCAT(N'After Scenario 2: ', @present, N' Changed/NoChange codes present, ', @new, N' new rows created (', @newMatched, N' matched), ', @loaded, N' loaded rows, ', @golden, N' golden records.');"]),
        f"What: Confirm the batch landed: every Changed/NoChange row of {T2} is in RetailClient, the New rows added records, and continuous matching matched new rows. "
        f"Why: Scenario 3a starts from this state, and an unmatched batch means the strategy was not running. Success: the counts line prints. "
        "If it fails: open the TestAuto run log; zero new rows matched = check the strategy is enabled with continuous matching on."),
    'matching-1k-scenario3a': ("Check Scenario 3a Created Nothing", "\r\n".join([
        GOLDEN.rstrip(),
        f"DECLARE @new bigint = (SELECT COUNT_BIG(*) FROM [{{{{ModelSourceDB}}}}].dbo.{T2} WHERE RecordAction = N'New');",
        f"IF @loaded <> {SIZE_RECORDS} + @new",
        "BEGIN",
        f"    DECLARE @msg nvarchar(400) = CONCAT(N'After Scenario 3a: ', @loaded, N' loaded rows (expected {SIZE_RECORDS} + ', @new, N' from Scenario 2); lookups must not create records.');",
        "    THROW 50008, @msg, 1;",
        "END",
        "PRINT CONCAT(N'After Scenario 3a: ', @loaded, N' loaded rows, unchanged by the lookups; ', @golden, N' golden records.');"]),
        "What: Confirm the lookups created no records. Why: 3a is lookups only. Success: the loaded row count is unchanged from Scenario 2. "
        "If it fails: the lookup scenario created records; check its OperationType in TestAuto."),
    'matching-1k-scenario3b': ("Check Scenario 3b Ran", "\r\n".join([
        created_since('3b'),
        f"IF @created = 0 OR @created > {SLICE}",
        "BEGIN",
        f"    DECLARE @msg nvarchar(400) = CONCAT(N'After Scenario 3b: ', @created, N' records created since the start marker (expected 1 to {SLICE}); the lookup-then-create run must create the rows whose lookup missed.');",
        "    THROW 50009, @msg, 1;",
        "END",
        f"PRINT CONCAT(N'After Scenario 3b: ', @created, N' of {SLICE} {T3B} rows created (', @createdMatched, N' matched); the rest found an existing record at lookup.');"]),
        f"What: Confirm the run created records for the rows whose lookup found no match. Why: 3b is lookup, then create on a miss. "
        f"Created records get a Profisee-assigned Code, so they are counted as non-golden records entered after the Scenario 3b start marker. "
        f"Success: 1 to {SLICE} created; the count is printed. If it fails: open the TestAuto run log."),
    'matching-1k-scenario3c': ("Check Scenario 3c Created Every Row", "\r\n".join([
        created_since('3c'),
        f"IF @created <> {SLICE}",
        "BEGIN",
        f"    DECLARE @msg nvarchar(400) = CONCAT(N'After Scenario 3c: ', @created, N' of {SLICE} {T3C} rows created since the start marker.');",
        "    THROW 50010, @msg, 1;",
        "END",
        f"PRINT CONCAT(N'After Scenario 3c: all {SLICE} {T3C} rows created (', @createdMatched, N' matched).');"]),
        f"What: Confirm every {T3C} row was created. Why: 3c is create only. Created records get a Profisee-assigned Code, so they are "
        f"counted as non-golden records entered after the Scenario 3c start marker. Success: {SLICE} created. If it fails: open the TestAuto run log."),
}
chain = {'matching-1k-scenario2': ('after-1', 'after-2'), 'matching-1k-scenario3a': ('after-2', 'after-3a'),
         'matching-1k-scenario3b': ('after-3a', 'after-3b'), 'matching-1k-scenario3c': ('after-3b', 'after-3c')}
whats = {'matching-1k-scenario2': "Scenario 2 (operational batch from " + T2 + ")",
         'matching-1k-scenario3a': "Scenario 3a (lookups only)",
         'matching-1k-scenario3b': "Scenario 3b (lookup, then create, from " + T3B + ")",
         'matching-1k-scenario3c': "Scenario 3c (creates from " + T3C + ")"}

for key, (start, end) in chain.items():
    w = copy.deepcopy(s1)
    scn = workflows[key][0]
    w['name'] = key
    w['tags'] = ["matching", "1k", "scenario" + scn, "test"]
    w['globalParameters'].update({
        "ModelSourceDB": "{{$ref:matching/databases:ModelSourceDB}}",
        "ProfiseeBaseUrl": "https://{{$ref:matching/machines:ApplicationServerNameFQDN}}/{{$ref:matching/instances:ProfiseeInstanceName}}/rest",
        "ProfiseeApiKey": "{{$config:RestKeys:ProfiseeRestKey}}",
        "MatchingStrategyName": "RetailClient"})
    w['description'] = (f"What: Restore the {SIZE_LABEL} '{start}' checkpoint, warm the instance, turn continuous matching on, run the TestAuto "
                        f"workflow 'Matching {SIZE_LABEL} Scenario {scn}', check the result and back up '{end}'. Why: measures {whats[key]}; "
                        f"the next scenario starts from '{end}'. When: whenever Scenario {scn} is measured; a rerun restores its own start. "
                        f"Needs: the '{start}' backup (the previous scenario workload) and matching-1k-testauto-create on this box. "
                        "Success: every step Succeeded. If it fails: the failed step's description says what to fix; rerun the whole workload.")
    steps = []
    for st in w['steps']:
        lab = st['label']
        inl = st['inline']
        if lab == 'Restore Loaded':
            st['label'] = f"Restore {start.title().replace('-', ' ')}"
            inl['backupFileName'] = f"profisee_Matching_{{{{SizeLabel}}}}_{start}.bak"
            inl['description'] = inl['description'].replace("the 'loaded' checkpoint", f"the '{start}' checkpoint") \
                .replace("every Scenario 1 run starts from the same loaded, unmatched state", f"every Scenario {scn} run starts from the same state") \
                .replace("(run matching-1k-scenario1-load)", "(run the previous scenario workload)")
        if lab == 'Run Matching 1K Scenario 1':
            st['label'] = f"Run Matching {SIZE_LABEL} Scenario {scn}"
            inl['workflowTag'] = inl['workflowTag'].replace('matching-1k-scenario1', key)
            inl['description'] = inl['description'].replace('Matching 1K Scenario 1', f"Matching {SIZE_LABEL} Scenario {scn}")
        if lab == 'Check Matching Ran':
            label, sql, desc = checks[key]
            st['label'] = label
            inl['sqlScript'] = sql
            inl['description'] = desc
        if lab == 'Back Up After Scenario 1':
            st['label'] = f"Back Up {end.title().replace('-', ' ')}"
            inl['backupFileName'] = f"profisee_Matching_{{{{SizeLabel}}}}_{end}.bak"
            inl['description'] = inl['description'].replace("'after-1'", f"'{end}'").replace("Scenario 2 restores it", "the next scenario restores it")
        steps.append(st)
        if lab == 'Start Every Service':
            steps.append(copy.deepcopy(cm_step))
    w['steps'] = steps
    with open(os.path.join(wl_dir, key + '.workload.json'), 'w', encoding='utf-8') as f:
        json.dump(w, f, indent=2)
print('written', list(workflows))
