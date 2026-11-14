"""The parts every Matching pack generator shares: the TestAuto step configurations of Scenarios 1 to 3c, the size
prelude of the setup templates, the run profile upsert, the scenario checks and the continuous-matching and
monitor-quiet steps. Written once here; gen_matching.py (the Matching pack) and gen_matching_large.py (the large-size
pack that continues a run made outside the pack) build their workloads from them.

Nothing here writes a file or knows a reference family: every value that differs between the packs is an argument
whose default is the Matching pack's own, so gen_matching.py's output does not change.

Import after packgen is on sys.path (each generator puts it there first).
"""
import json
import os
import re

from packgen import specs, steps

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, 'wf10000215')

VER = "{{ProfiseeVersionCode}}"
SCENARIOS = ('1', '2', '3a', '3b', '3c')
TRANSFORM_SEED = 350


def table(scn):
    """Source table of one scenario in the ModelSource database, as workload text ({{Size}} is the run value)."""
    return "RetailClient{{Size}}Scenario" + scn


# ---------------------------------------------------------------- TestAuto step configs
# A config is a template: <<Size>>, <<RecordCount>>, <<Slice>> and the like are filled in by the setup workload for every
# row of the pack's sizes. TestAuto's own run-time tokens are written {% %} so CrewChief leaves them alone.
N = specs.number('RecordCount')
SLICE = specs.number('Slice')
MARGIN = 150  # values can be longer than their placeholders (a nine-digit count); keep the indented form clear of 4000
RUNTIME_TOKEN = re.compile(r'\{\{(\$config:[^}]*|STEP:[^}]*)\}\}')


def run_profile(scn):
    return VER + "-RetailClient-Scenario " + scn + "-<<RecordCount>>-0"


def runtime_tokens(value):
    """TestAuto run-time tokens ({{$config:...}}, {{STEP:n}}) written {%...%} in every string of a config."""
    if isinstance(value, dict):
        return {k: runtime_tokens(v) for k, v in value.items()}
    if isinstance(value, list):
        return [runtime_tokens(v) for v in value]
    if isinstance(value, str):
        return RUNTIME_TOKEN.sub(r'{%\1%}', value)
    return value


def config_text(cfg):
    text = specs.scenario_text(runtime_tokens(cfg), margin=MARGIN)
    assert '{{$config' not in text and '{{STEP' not in text, 'unescaped TestAuto token left'
    return text


# ---- Scenario 1 (PROD 10000215 steps 5-11, with {{STEP:7}} -> {{STEP:3}})
def scenario(name, custom, tme="", source="RetailClient", query=None, tid=1,
             rest_areas=("Profisee", "Metrics", "Connect", "Portal", "Matching", "Monitor")):
    return config_text({
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
                               "SubjectAreaOverrides": {a: {"RestUrlBase": "", "RestApiKey": ""} for a in rest_areas}},
        "ScenarioDatabaseConnectionStrings": {"ConnectionString": None, "SubjectAreaOverrides": {
            a: {"ConnectionString": ""} for a in ("Profisee", "Metrics", "Matching", "Connect", "Portal", "Data", "TestAuto")}},
        "ScenarioEnvironment": {"DqRuleCount": 0, "TargetEnvironment": "IaaS",
                                "TargetEnvironmentName": "{{TestAutoEnvironmentName}}", "TargetMetricEntity": tme,
                                "WorkloadExecution": "", "ProfiseeVersion": VER,
                                "TargetApplicationServer": "{{TestAutoApplicationServer}}",
                                "TargetDatabaseServer": "{{TestAutoDatabaseServer}}", "ExecutionMode": "B",
                                "HangfireJob": 0, "SimulatedUserThreadId": tid},
    })


def monitor(message, activity, desc):
    return {"GlobalParameters": {"StrategyName": "RetailClient", "ApiVersion": "v1"},
            "Steps": [{"message": message, "type": "MonitorStep", "scriptKey": None,
                       "parameters": {"ActivityType": activity}, "timeoutSeconds": 30, "continueOnError": False,
                       "workingDirectory": None, "description": desc}]}


def snapshot(step, link="{{STEP:3}}"):
    """CustomParms of a Scenario 1 match status count. link = the step whose WorkloadExecution the counts are filed under."""
    return {"MatchingScenarioName": "Scenario 1", "MatchingStrategyName": "RetailClient", "ScenarioStep": step,
            "TargetEntityName": "RetailClient", "SourceRecords": N, "MatchStatusColumnName": "Match Status",
            "MatchStatusEntityName": "MatchStatus", "GoldenRecordColumnName": "Golden Record",
            "UnifiedMatchingScenarioWorkloadExecution": link,
            "UnifiedMatchingApiExecutionRunProfile": run_profile('1')}


def curl(url, method, body, desc):
    return {"url": url, "method": method,
            "headers": {"Content-Type": "application/json-patch+json", "x-api-key": "{{$config:RestClients:Profisee:ApiKey}}"},
            "body": body, "bodyFilePath": None, "outputFile": None, "expectedStatusCodes": [200, 201, 204],
            "followRedirects": True, "verifySsl": False, "maxTimeSeconds": None, "customCurlArgs": None,
            "useRestMethod": True, "type": "CurlStep", "scriptKey": None,
            "parameters": {"StrategyName": "RetailClient", "ApiVersion": "v1"}, "timeoutSeconds": 60,
            "continueOnError": False, "workingDirectory": None, "description": desc}


S1_UTILITY = ("Profisee", "Metrics", "Connect", "Portal", "Matching")
S1_MATCHING = ("Profisee", "Metrics", "ScenarioMgt", "Matching")
enable_run_s1 = {"GlobalParameters": {"StrategyName": "RetailClient", "ApiVersion": "v1"}, "Steps": [
    curl("{{$config:RestClients:Profisee:BaseUrl}}v1/Matching/RetailClient", "PATCH", "{\n  \"status\": 1\n}",
         "Enable RetailClient Matching Strategy"),
    curl("{{$config:RestClients:Profisee:BaseUrl}}v1/Matching/RetailClient/processActions", "POST",
         "{\n  \"actions\": [\n    \"IncludeSurvivorship\"\n  ]\n}", "Run RetailClient Matching Strategy")]}
start_text, end_text = "Start of Scenario 1 for Retail Client", "End of Scenario 1 for Retail Client"


def s1_counts(when, link="{{STEP:3}}"):
    """Scenario 1 match status counts: when = Start (Pre) or End (Post)."""
    return (f"Capture Matching Status Counts for {when} of Scenario 1",
            "Match status counts before matching runs." if when == "Start" else "Match status counts after matching finished.",
            scenario("MatchingSnapshotCaptureScenario", snapshot("Pre" if when == "Start" else "Post", link),
                     tme="UnifiedMatchingApiExecutionMatchGroupResults", rest_areas=S1_MATCHING))


def s1_timing(link="{{STEP:3}}"):
    return ("Matching Timing Results Scenario 1", "Collects matching timings between the start and end markers.",
            scenario("MatchingResultsScenario",
                     {"StartMarkerText": start_text, "EndMarkerText": end_text, "MatchingStrategyName": "RetailClient",
                      "MatchingScenarioName": "Scenario 1", "UnifiedMatchingScenarioWorkloadExecution": link,
                      "UnifiedMatchingApiExecutionRunProfile": run_profile('1'), "ActivityDetailTopN": 10},
                     tme="UnifiedMatchingApiExecutionActivities", source="Not Used", tid=0,
                     query={"SelectAttributes": "", "SortAttributes": "Code", "Filter": "",
                            "QueryParameters": {"ignoreConstraintRules": "true"}}))


S1_DETAILS = [
    ("Write Start of Scenario 1 Monitor Message", "Writes the start marker the timing step measures from.",
     scenario("MultiStepUtilityScenario", monitor("Start of RetailClient Scenario 1", "Start of Scenario", start_text),
              rest_areas=S1_UTILITY)),
    s1_counts("Start"),
    ("Enable RetailClient Matching Strategy Then Run", "Enables the RetailClient strategy and runs it with survivorship over the loaded records.",
     scenario("MultiStepUtilityScenario", enable_run_s1, rest_areas=S1_UTILITY)),
    ("Wait for Matching Scenario To Finish", "Polls the RetailClient strategy until matching is idle.",
     scenario("MatchingStrategyPollingScenario", {"MatchingStrategyName": "RetailClient", "MaxWaitMinutes": 2880, "PollIntervalSeconds": 30},
              tme="Not Used", rest_areas=S1_MATCHING)),
    ("Write End of Scenario 1 Monitor Message", "Writes the end marker the timing step measures to.",
     scenario("MultiStepUtilityScenario", monitor("End of RetailClient Scenario 1", "End of Scenario", end_text),
              rest_areas=S1_UTILITY)),
    s1_counts("End"),
    s1_timing(),
]

# ---- Scenarios 2, 3a, 3b, 3c (PROD 10000215 steps 12-44, verbatim, patched only where the pack requires)
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
# Wizard state only (read by TestAuto.Web's editor, not at run time); dropping it keeps the configs under 4000 characters.
WIZARD_KEYS = ["ModelSourceDefaults", "SelectedLookupAttributeCodes", "SelectedScenarioTemplate"]
TABLE_DROP_KEYS = ["NewSourceSystems", "ChangedSourceSystems", "SourceSystemNewOffsets", "SourceSystemDistribution",
                   "SelectedNewSourceCodes", "SelectedChangedSourceCodes", "UpdateVariationLevel"] + WIZARD_KEYS
DISTRIBUTION = {}  # source system -> PROD weight of the Scenario 3a lookup mix; filled by lookup_patch, read by the setup script


def prod(n):
    with open(os.path.join(SRC, f'{n:02d}.json'), encoding='utf-8-sig') as f:
        return json.load(f)


def custom(cfg):
    return cfg['ScenarioRuntime']['CustomParms']


class Timing:
    """Run limits a pack may set on the later scenarios. None = PROD 10000215's own value (what the Matching pack runs).

    max_wait_minutes: MaxWaitMinutes of every 'Wait for Matching To Be Idle' step.
    time_limit:       TimeLimit (hh:mm:ss, 00:00:00 = none) of the 3b and 3c create runs."""

    def __init__(self, max_wait_minutes=None, time_limit=None):
        self.max_wait_minutes = max_wait_minutes
        self.time_limit = time_limit


def step(n, name, desc, patch=None):
    cfg = prod(n)
    if patch:
        patch(cfg)
    cfg['ScenarioEnvironment'].update({
        "TargetEnvironmentName": "{{TestAutoEnvironmentName}}", "ProfiseeVersion": VER, "WorkloadExecution": "",
        "TargetApplicationServer": "{{TestAutoApplicationServer}}", "TargetDatabaseServer": "{{TestAutoDatabaseServer}}"})
    return (name, desc, config_text(cfg))


def snapshot_patch(scn, link):
    def p(cfg):
        custom(cfg).update({"SourceRecords": N, "UnifiedMatchingScenarioWorkloadExecution": "{{STEP:%d}}" % link,
                            "UnifiedMatchingApiExecutionRunProfile": run_profile(scn)})
    return p


def timing_patch(scn, link):
    def p(cfg):
        custom(cfg).update({"UnifiedMatchingScenarioWorkloadExecution": "{{STEP:%d}}" % link,
                            "UnifiedMatchingApiExecutionRunProfile": run_profile(scn), "ActivityDetailTopN": 10})
        # Timing rows go to the Activities entity (phase 2, 2026-11-05); the Timings entity is kept but no longer written.
        cfg['ScenarioEnvironment']['TargetMetricEntity'] = "UnifiedMatchingApiExecutionActivities"
    return p


def scenario_table_patch(scn, iteration_limit, time_limit=None):
    def p(cfg):
        c = custom(cfg)
        for k in TABLE_DROP_KEYS:
            c.pop(k, None)
        c.update({"RecordSource": "ScenarioTable", "UnifiedMatchingApiExecutionRunProfile": run_profile(scn),
                  "NewRecordStartingOffset": 0, "ChangedRecordStartingOffset": 0, "TransformSeed": TRANSFORM_SEED,
                  "MatchFieldMutationSettings": MUTATION, "IterationLimit": iteration_limit,
                  "MatchingStrategyName": "RetailClient", "SourceDatabaseName": "{{TestAutoSourceDatabase}}"})
        if time_limit is not None:
            assert 'TimeLimit' in c, 'the create step no longer carries a TimeLimit'
            c['TimeLimit'] = time_limit
        cfg['ScenarioTables']['SourceEntityName'] = "RetailClient<<Size>>Scenario" + scn
        cfg['ScenarioTesting']['TestRecordLimit'] = SLICE
    return p


def lookup_patch(scn):
    def p(cfg):
        c = custom(cfg)
        for k in WIZARD_KEYS:
            c.pop(k, None)
        # SourceDatabaseName: the record pool's database (<family>/databases:ModelSourceDB); TestAuto defaults to
        # ModelSource when it is missing.
        c.update({"UnifiedMatchingApiExecutionRunProfile": run_profile(scn), "IterationLimit": SLICE,
                  "SourceDatabaseName": "{{TestAutoSourceDatabase}}"})
        cfg['ScenarioTesting']['TestRecordLimit'] = SLICE
        # TestAuto rejects every batch when the distribution does not sum to TestRecordLimit; PROD's is sized for 100K.
        # The setup script scales PROD's weights to the slice of each size (the first source system takes the remainder).
        dist = c.get('SourceSystemDistribution')
        assert dist and all(re.fullmatch(r'[A-Za-z0-9]+', k) for k in dist), 'lookup distribution shape changed'
        DISTRIBUTION.update(dist)
        c['SourceSystemDistribution'] = {k: specs.number('Dist' + k) for k in dist}
    return p


def postrun_patch(cfg):
    custom(cfg)["SourceWorkloadExecution"] = "{{STEP:4}}"


def polling(n, timing=None):
    def p(cfg):
        if timing and timing.max_wait_minutes is not None:
            assert 'MaxWaitMinutes' in custom(cfg), 'the polling step no longer carries MaxWaitMinutes'
            custom(cfg)['MaxWaitMinutes'] = timing.max_wait_minutes
    return step(n, "Wait for Matching To Be Idle", "Polls the RetailClient strategy until matching is idle.", p)


def markers(scn, start_n, end_n):
    return (step(start_n, f"Write Start of Scenario {scn} Monitor Message", "Writes the start marker the timing step measures from."),
            step(end_n, f"Write End of Scenario {scn} Monitor Message", "Writes the end marker the timing step measures to."))


def enable_run(n, scn):
    return step(n, "Enable RetailClient Matching Strategy Then Run",
                "Enables the RetailClient strategy (saving it with continuous matching on disabled it) and runs it with survivorship, "
                f"inside the Scenario {scn} markers as the production workflow does.")


def counts(n, scn, when):
    return step(n, f"Capture Matching Status Counts for {when} of Scenario {scn}",
                "Match status counts before the %s." % ("batch" if scn == '2' else "run") if when == "Start"
                else "Match status counts after matching finished.", snapshot_patch(scn, 4))


def timing_step(n, scn):
    return step(n, f"Matching Timing Results Scenario {scn}", "Collects matching timings between the start and end markers.",
                timing_patch(scn, 4))


T2, T3B, T3C = "RetailClient<<Size>>Scenario2", "RetailClient<<Size>>Scenario3b", "RetailClient<<Size>>Scenario3c"


def later_details(timing=None):
    """The TestAuto steps of Scenarios 2, 3a, 3b and 3c, keyed by scenario. timing = run limits (Timing); None = PROD's."""
    time_limit = timing.time_limit if timing else None
    s2, e2 = markers('2', 12, 18)
    s3a, e3a = markers('3a', 21, 25)
    s3b, e3b = markers('3b', 26, 32)
    s3c, e3c = markers('3c', 35, 41)
    return {
        # Scenario 2: start, counts, enable and run, batch, wait, end, counts, timing
        '2': [s2, counts(13, '2', "Start"), enable_run(15, "2"),
              step(16, "Matching Scenario 2 Incremental Batch Load",
                   f"Sends every row of {T2} as a batch load: New rows create, Changed rows are mutated on their strategy fields and "
                   "PATCHed by Code, NoChange rows are PATCHed as they are.", scenario_table_patch('2', 0)),
              polling(17, timing), e2, counts(19, '2', "End"), timing_step(20, '2')],
        # Scenario 3a: start, enable and run, lookups, end (no counts, no timing: the lookup scenario records its own metrics)
        '3a': [s3a, enable_run(23, "3a"),
               step(24, "Matching Scenario 3a Lookup Before Create",
                    "Looks up <<Slice>> existing AutoApproved records through the matching lookup; creates nothing.", lookup_patch('3a')),
               e3a],
        # Scenario 3b: start, counts, enable and run, lookup then create, wait, end, counts, timing
        '3b': [s3b, counts(27, '3b', "Start"), enable_run(29, "3b"),
               step(30, "Matching Scenario 3b Continuous Matching",
                    f"Sends every row of {T3B}: a timed lookup, then a create when nothing matches.",
                    scenario_table_patch('3b', SLICE, time_limit)),
               polling(31, timing), e3b, counts(33, '3b', "End"), timing_step(34, '3b')],
        # Scenario 3c: start, counts, enable and run, creates, wait, end, post-run collection, counts, timing
        '3c': [s3c, counts(36, '3c', "Start"), enable_run(38, "3c"),
               step(39, "Matching Scenario 3c Continuous Matching",
                    f"Creates every row of {T3C} one record per call with continuous matching on.",
                    scenario_table_patch('3c', SLICE, time_limit)),
               polling(40, timing), e3c,
               step(42, "Matching Scenario 3c Post-Run Metric Collection", "Collects golden record times for the records the run created.",
                    postrun_patch),
               counts(43, '3c', "End"), timing_step(44, '3c')],
    }


# ---------------------------------------------------------------- the size prelude of every setup template step
# PowerShell every template step shares: the numbers a size gets from its row. @@SLICE@@ = how the slice is found.
PRELUDE_TEMPLATE = r"""function Set-Size($v) {
    $v.SizeLower = $v.Size.ToLower()
    $v.RecordCount = Get-SetValue 'Sizes' $v.Size
@@SLICE@@
    $v.Slice = "$slice"
    # Scenario 3a's lookup mix: the production weights scaled to the slice; the first source system takes the remainder,
    # because TestAuto rejects a mix that does not add up to the record limit.
    $weights = [ordered]@{ @@WEIGHTS@@ }
    $total = 0; foreach ($w in $weights.Values) { $total += $w }
    $sum = 0; $parts = [ordered]@{}
    foreach ($name in $weights.Keys) { $parts[$name] = [long][math]::Floor($weights[$name] * $slice / $total); $sum += $parts[$name] }
    $first = @($weights.Keys)[0]
    $parts[$first] += $slice - $sum
    foreach ($name in $parts.Keys) { $v["Dist$name"] = "$($parts[$name])" }
}
"""
# The Matching pack: every later scenario works on a tenth of the record count.
SLICE_TENTH = r"""    if ($v.RecordCount -notmatch '^[1-9]\d*0$') { throw "matching/sizes:$($v.Size) is '$($v.RecordCount)'; a record count is a whole number above 0 that ends in 0 (every later scenario works on a tenth of it)." }
    # The slice: a tenth of the record count, the number of records Scenarios 2, 3a, 3b and 3c each work on.
    $slice = [long]$v.RecordCount / 10"""


def prelude(slice_ps=SLICE_TENTH):
    """The Set-Size function of the setup templates. Call after later_details() (it reads the 3a lookup weights)."""
    assert DISTRIBUTION, 'the Scenario 3a lookup step no longer carries a source system distribution'
    return (PRELUDE_TEMPLATE.replace('@@SLICE@@', slice_ps)
            .replace('@@WEIGHTS@@', '; '.join("%s = %d" % (k, v) for k, v in DISTRIBUTION.items())))


# ---------------------------------------------------------------- run profiles (one per scenario and size)
# IncrementalVolumeCount as PROD's 26R3 profiles: the slice for Scenarios 2, 3b and 3c, 0 for 1 and 3a.
PROFILE_TEMPLATE = json.dumps([
    {"Code": run_profile(scn), "Scenario": "UnifiedMatchingScenario", "MatchingStrategy": "RetailClient",
     "MatchingScenarioName": "Scenario " + scn, "SourceRecordCount": "<<RecordCount>>", "AttributeCount": 42, "DBACount": 5,
     "FreeformCount": 37, "IncrementalVolumeCount": "<<Slice>>" if scn in ('2', '3b', '3c') else 0, "RuleCount": 0}
    for scn in SCENARIOS])
PROFILE_UPSERT = r"""$base = '{{ScenarioMgtBaseUrl}}'.TrimEnd('/') + '/'
$headers = @{ 'x-api-key' = '{{ScenarioMgtApiKey}}'; accept = 'application/json' }
$version = '{{ProfiseeVersionCode}}'
$profiles = @(foreach ($one in $specs) {
    foreach ($p in ($one | ConvertFrom-Json)) {
        [ordered]@{ Code = $p.Code; ProfiseeVersion = $version; Scenario = $p.Scenario; MatchingStrategy = $p.MatchingStrategy
            MatchingScenarioName = $p.MatchingScenarioName; SourceRecordCount = [long]$p.SourceRecordCount; AttributeCount = [int]$p.AttributeCount
            DBACount = [int]$p.DBACount; FreeformCount = [int]$p.FreeformCount; IncrementalVolumeCount = [long]$p.IncrementalVolumeCount
            RuleCount = [int]$p.RuleCount }
    }
})
Invoke-RestMethod -Method Patch -Uri "${base}v1/Records/UnifiedMatchingApiExecutionRunProfile?IsUpsert=true&recordsAreSameShape=true" -Headers $headers -ContentType 'application/json' -Body (ConvertTo-Json -Depth 5 -InputObject $profiles) | Out-Null
"$($profiles.Count) run profile(s) upserted: $(($profiles | ForEach-Object { $_.Code }) -join ' | ')"
"""
PROFILE_MARKER = '# ---- upsert the run profiles'


def profiles_step(family, setup_name, size_loop, sets, prelude_text, derive):
    script = (specs.expand_script(PROFILE_TEMPLATE, size_loop, setup_name, sets, prelude_text, derive) + '\n' + PROFILE_MARKER + '\n'
              + PROFILE_UPSERT)
    return steps.ps("Upsert Run Profiles", script,
                    "What: Create or update the Matching run profiles of Scenarios 1, 2, 3a, 3b and 3c for every size in "
                    f"{family}/sizes (<ProfiseeVersionCode>-RetailClient-Scenario <x>-<record count>-0). Why: the snapshot, lookup "
                    "and timing steps record their results under them. Success: the last line lists the profiles. If it fails: "
                    "a size with a bad record count is named in the error; 401 = the ScenarioMgt key.", timeout=600)


# ---------------------------------------------------------------- shared SQL and scripts
with open(os.path.join(HERE, 'monitor_quiet.sql'), encoding='utf-8') as _f:
    MONITOR_QUIET_SQL = _f.read()
RESTORE_NOTE = "The executor takes the database OFFLINE WITH ROLLBACK IMMEDIATE first and brings it back ONLINE if the restore fails."
STOP_WHY = "a restore must not run under services that hold connections and caches"
START_WHY = "the services must read the restored database"
GOLDEN = """DECLARE @golden bigint = (SELECT COUNT_BIG(*) FROM data.tRetailClient r JOIN data.tMatchStatus s ON s.ID = r.[Match Status] WHERE s.Code = N'10');
DECLARE @loaded bigint = (SELECT COUNT_BIG(*) FROM data.tRetailClient) - @golden;"""
# How a check finds the slice (the records each later scenario works on), and how its description names it.
SLICE_SQL_TENTH = "DECLARE @slice bigint = {{RecordCount}} / 10;  -- every scenario after the first works on a tenth of the record count"
SLICE_TEXT_TENTH = "a tenth of {{RecordCount}}"


def source(scn):
    return "[{{ModelSourceDB}}].dbo." + table(scn)


def created_since(scn):
    # Records a scenario creates get a Profisee-assigned Code, so count non-golden records entered after its start marker (both UTC).
    return f"""DECLARE @start datetime2 = (SELECT MAX(StartedTime) FROM monitor.tActivity WHERE Name = N'Start of Scenario {scn} for Retail Client');
IF @start IS NULL THROW 50012, N'Scenario {scn} start marker not found in monitor.tActivity.', 1;
DECLARE @created bigint, @createdMatched bigint;
SELECT @created = COUNT_BIG(*), @createdMatched = COUNT_BIG(s.Code) FROM data.tRetailClient r LEFT JOIN data.tMatchStatus s ON s.ID = r.[Match Status] WHERE r.[$EnterDTM] >= @start AND (s.Code IS NULL OR s.Code <> N'10');"""


def checks(slice_sql=SLICE_SQL_TENTH, slice_text=SLICE_TEXT_TENTH):
    """(label, SQL, description) of the check after each scenario, keyed by scenario."""
    return {
        '1': ("Check Matching Ran", f"""-- Golden records (match status code 10) are created by survivorship; every other row is a loaded record.
{GOLDEN}
DECLARE @matched bigint = (SELECT COUNT_BIG(*) FROM data.tRetailClient r JOIN data.tMatchStatus s ON s.ID = r.[Match Status] WHERE s.Code <> N'10');
DECLARE @skipped bigint = @loaded - @matched;
IF @loaded <> {{{{RecordCount}}}} OR @golden = 0 OR @matched = 0
BEGIN
    DECLARE @msg nvarchar(400) = CONCAT(N'After Scenario 1: ', @loaded, N' loaded rows (expected {{{{RecordCount}}}}), ', @matched, N' with a match status, ', @golden, N' golden records; matching did not run or did not finish.');
    THROW 50006, @msg, 1;
END
PRINT CONCAT(N'After Scenario 1: ', @loaded, N' loaded rows, ', @matched, N' with a match status, ', @golden, N' golden records, ', @skipped, N' left unmatched by the strategy (too few match fields).');""",
              "What: Confirm matching ran over the load: {{RecordCount}} loaded rows, some with a match status and some golden records. "
              "Records with too few match fields stay without a match status by design; their count is printed. Why: Scenario 2 needs a "
              "matched starting point. Success: the counts line prints. If it fails: matching did not run or did not finish; check the "
              "RetailClient strategy and the matching service."),
        '2': ("Check Scenario 2 Landed", f"""{GOLDEN}
DECLARE @updates bigint = (SELECT COUNT_BIG(*) FROM {source('2')} WHERE RecordAction <> N'New');
DECLARE @present bigint = (SELECT COUNT_BIG(*) FROM {source('2')} t JOIN data.tRetailClient r ON r.Code = t.Code);
DECLARE @new bigint = (SELECT COUNT_BIG(*) FROM {source('2')} WHERE RecordAction = N'New');
-- New rows are created without their source Code (Profisee assigns one), so they are the loaded rows outside Scenario 1.
DECLARE @newMatched bigint = (SELECT COUNT_BIG(*) FROM data.tRetailClient r JOIN data.tMatchStatus s ON s.ID = r.[Match Status] WHERE s.Code <> N'10' AND NOT EXISTS (SELECT 1 FROM {source('1')} t WHERE t.Code = r.Code));
IF @present <> @updates OR @loaded <> {{{{RecordCount}}}} + @new OR @newMatched = 0
BEGIN
    DECLARE @msg nvarchar(400) = CONCAT(N'After Scenario 2: ', @present, N' of ', @updates, N' Changed/NoChange codes present; ', @loaded, N' loaded rows (expected {{{{RecordCount}}}} + ', @new, N' new); ', @newMatched, N' new rows matched (continuous matching must match at least one).');
    THROW 50007, @msg, 1;
END
PRINT CONCAT(N'After Scenario 2: ', @present, N' Changed/NoChange codes present, ', @new, N' new rows created (', @newMatched, N' matched), ', @loaded, N' loaded rows, ', @golden, N' golden records.');""",
              f"What: Confirm the batch landed: every Changed/NoChange row of {table('2')} is in RetailClient, the New rows added records, "
              "and continuous matching matched new rows. Why: Scenario 3a starts from this state, and an unmatched batch means the "
              "strategy was not running. Success: the counts line prints. If it fails: open the TestAuto run log; zero new rows matched = "
              "check the strategy is enabled with continuous matching on."),
        '3a': ("Check Scenario 3a Created Nothing", f"""{GOLDEN}
DECLARE @new bigint = (SELECT COUNT_BIG(*) FROM {source('2')} WHERE RecordAction = N'New');
IF @loaded <> {{{{RecordCount}}}} + @new
BEGIN
    DECLARE @msg nvarchar(400) = CONCAT(N'After Scenario 3a: ', @loaded, N' loaded rows (expected {{{{RecordCount}}}} + ', @new, N' from Scenario 2); lookups must not create records.');
    THROW 50008, @msg, 1;
END
PRINT CONCAT(N'After Scenario 3a: ', @loaded, N' loaded rows, unchanged by the lookups; ', @golden, N' golden records.');""",
               "What: Confirm the lookups created no records. Why: 3a is lookups only. Success: the loaded row count is unchanged from "
               "Scenario 2. If it fails: the lookup scenario created records; check its OperationType in TestAuto."),
        '3b': ("Check Scenario 3b Ran", f"""{slice_sql}
{created_since('3b')}
IF @created = 0 OR @created > @slice
BEGIN
    DECLARE @msg nvarchar(400) = CONCAT(N'After Scenario 3b: ', @created, N' records created since the start marker (expected 1 to ', @slice, N'); the lookup-then-create run must create the rows whose lookup missed.');
    THROW 50009, @msg, 1;
END
PRINT CONCAT(N'After Scenario 3b: ', @created, N' of ', @slice, N' {table('3b')} rows created (', @createdMatched, N' matched); the rest found an existing record at lookup.');""",
               "What: Confirm the run created records for the rows whose lookup found no match. Why: 3b is lookup, then create on a miss. "
               "Created records get a Profisee-assigned Code, so they are counted as non-golden records entered after the Scenario 3b "
               f"start marker. Success: 1 to {slice_text} created; the count is printed. If it fails: open the TestAuto run log."),
        '3c': ("Check Scenario 3c Created Every Row", f"""{slice_sql}
{created_since('3c')}
IF @created <> @slice
BEGIN
    DECLARE @msg nvarchar(400) = CONCAT(N'After Scenario 3c: ', @created, N' of ', @slice, N' {table('3c')} rows created since the start marker.');
    THROW 50010, @msg, 1;
END
PRINT CONCAT(N'After Scenario 3c: all ', @slice, N' {table('3c')} rows created (', @createdMatched, N' matched).');""",
               f"What: Confirm every {table('3c')} row was created. Why: 3c is create only. Created records get a Profisee-assigned Code, "
               f"so they are counted as non-golden records entered after the Scenario 3c start marker. Success: {slice_text} "
               "created. If it fails: open the TestAuto run log."),
    }


CM_SCRIPT = r"""$ErrorActionPreference = 'Stop'
$base = '{{ProfiseeBaseUrl}}'.TrimEnd('/')
$headers = @{ 'x-api-key' = '{{ProfiseeApiKey}}'; accept = 'application/json' }
$uri = "$base/v1/Matching/strategies/$([uri]::EscapeDataString('{{MatchingStrategyName}}'))"
$s = @((Invoke-RestMethod -Uri $uri -Headers $headers -SkipCertificateCheck).data)[0]
if (-not $s) { throw "Matching strategy '{{MatchingStrategyName}}' not found." }
# PUT takes the strategy configuration plus its header; only autoMatch and autoSurvive change (continuous matching).
$body = [ordered]@{ name = $s.name; code = $s.code; entity = [ordered]@{ id = $s.entityUid; name = $s.entityName }
    status = 1; lockStatus = $s.lockStatus; includeMatching = $true; autoMatch = $true; includeSurvivorship = $true; autoSurvive = $true }
foreach ($p in $s.configuration.PSObject.Properties) { if ($p.Name -ne 'artifactVersion') { $body[$p.Name] = $p.Value } }
Invoke-RestMethod -Method Put -Uri "$base/v1/Matching/strategies" -Headers $headers -ContentType 'application/json' -SkipCertificateCheck -Body (ConvertTo-Json -Depth 30 -InputObject @($body)) | Out-Null
$after = @((Invoke-RestMethod -Uri $uri -Headers $headers -SkipCertificateCheck).data)[0]
if ([int]$after.autoMatch -ne 1 -or [int]$after.autoSurvive -ne 1) { throw "Continuous matching is still off for '{{MatchingStrategyName}}' (autoMatch=$($after.autoMatch), autoSurvive=$($after.autoSurvive))." }
# Saving the strategy leaves it disabled (status 0). The TestAuto workflow enables and runs it right after its start marker,
# as the production Matching workflow does, so that activity falls inside the scenario.
"Continuous matching on for '{{MatchingStrategyName}}' (autoMatch and autoSurvive = 1); the workflow enables and runs it."
"""


def continuous_matching_step():
    return steps.ps("Turn Continuous Matching On", CM_SCRIPT,
        "What: Turn continuous matching on for the RetailClient strategy (read it, set autoMatch and autoSurvive, PUT it back). "
        "Why: Scenarios 2, 3a, 3b and 3c measure records matched as they arrive; the checkpoint from Scenario 1 has it off. Saving the "
        "strategy disables it; the TestAuto workflow enables and runs it after its start marker, so that work is measured. "
        "Success: the strategy reads back with autoMatch and autoSurvive on. "
        "If it fails: 401 = the API key; 404 = the strategy name in this workload's MatchingStrategyName.", timeout=300)


def monitor_quiet():
    return steps.sql("Wait For Monitor Quiet", MONITOR_QUIET_SQL,
        "What: Wait until the Activity Monitor has no outstanding task (every monitor.tActivity row in a finished status) and no "
        "new task has started for {{QuietSeconds}} seconds. Why: setup (restore, restart, continuous matching on) can start "
        "monitor tasks; the workflow's start marker must come after them so the scenario window holds only the scenario's own work. "
        "Success: the monitor is quiet. If it fails: after 30 minutes a task is still outstanding; the error names it, check it "
        "in the portal's Activity Monitor.", timeout=1900)


def title(name):
    return name.title().replace('-', ' ')
