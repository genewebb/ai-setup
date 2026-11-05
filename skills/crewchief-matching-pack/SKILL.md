---
name: crewchief-matching-pack
description: The CrewChief Matching workload pack (CrewChief/packs/matching) that measures Profisee Matching Scenarios 1, 2, 3a, 3b and 3c through small tagged TestAuto workflows, with setup, restores and backups in CrewChief. Covers the per-scenario workloads and backup chain, the generator scripts that write the workloads and the TestAuto workflow specs, the continuous-matching setup, the post-run checks, and the traps already hit. Use when running, rerunning, tweaking or extending a Matching scenario workload, changing a TestAuto Matching step config, adding a size, or debugging a Matching run that measured nothing.
---

# CrewChief Matching pack

Repo: speed-merchants, `CrewChief/packs/matching` (Gene commits). Built 11/05/2026 on the Connect pack pattern
(`crewchief-workload-packs`). Results log: `Q:\Work\Work\99 Documentation\Connect\Matching Rewrite Results.md`.

## What runs, in order (1K)

| Workload | Restores | Does | Backs up |
|---|---|---|---|
| `matching-1k-scenario1-load` | (empty model) | SetApiKey, recycle -auth/-rest/-connex, health, Connect strategy `RetailClientImport` loads `ModelSource.dbo.RetailClient1KScenario1` | `loaded` |
| `matching-1k-testauto-create` | - | 5 run profiles + 5 tagged TestAuto workflows in the TestAuto repository | - |
| `matching-1k-scenario1` | `loaded` | recycle all pools, health, run workflow, check | `after-1` |
| `matching-1k-scenario2` | `after-1` | + Turn Continuous Matching On | `after-2` |
| `matching-1k-scenario3a` | `after-2` | same | `after-3a` |
| `matching-1k-scenario3b` | `after-3a` | same | `after-3b` |
| `matching-1k-scenario3c` | `after-3b` | same | `after-3c` |

Backups: `profisee_Matching_<SizeLabel>_<suffix>.bak` in the SQL Server default backup folder.

**Rule (Gene): a rerun always restores the scenario's start backup.** Rerun the whole workload; never rerun only the
TestAuto workflow or continue on a dirty DB, or the monitor markers and timings are useless.

Scenario workload steps: Wait For Interrupted Runs, Stop Profisee Service (Skipped when
`matching/environment:MainServiceName` is blank, 26R3+), Restore (DatabaseOperationsStep, takes the DB OFFLINE, back
ONLINE on failure), Recycle all 20 instance pools, Start service, health wait, [2+: Turn Continuous Matching On],
run the workflow by tag `AUTO:<box>:<ProfiseeVersionCode>:matching-1k-scenario<x>`, check, backup.

TestAuto workflows (steps copied from PROD 10000215; setup that must not be measured comes before the start marker):

| Workflow | Steps |
|---|---|
| Scenario 1 | start marker, counts Pre, enable + run strategy (IncludeSurvivorship), wait idle, end marker, counts Post, timing (`{{STEP:3}}`) |
| Scenario 2 | wait idle, start, counts, BatchLoad from `RetailClient1KScenario2` (step 4), wait, end, counts, timing |
| Scenario 3a | wait idle, start, LookupOnly / ExistingMatchedOnly (100 lookups), end (no counts, no timing) |
| Scenario 3b | wait idle, start, counts, LookupThenCreate from `RetailClient1KScenario3b`, wait, end, counts, timing |
| Scenario 3c | wait idle, start, counts, CreateOnly from `RetailClient1KScenario3c`, wait, end, post-run collection, counts, timing |

Run profiles: `<ProfiseeVersionCode>-RetailClient-Scenario <x>-1000-0` (IncrementalVolumeCount 100 for 2/3b/3c).

## Changing anything: use the generators

The TestAuto step configs live as JSON strings inside PowerShell here-strings in
`matching-1k-testauto-create.workload.json`; do not hand-edit them. Edit and rerun the generator:

```powershell
python <skill>\scripts\gen_all.py C:\devops\repos\speed-merchants\CrewChief\packs\matching <skill>\scripts\connect_upsert_body.ps1
```

- `scripts/gen_s1.py`: reference sets, Scenario 1 workflow, `matching-1k-testauto-create`, `matching-1k-scenario1`.
  `gen_all.py` runs it first, then adds 2/3a/3b/3c (workflows, run profiles, workloads, reference keys).
- `scripts/wf10000215/NN.json`: PROD workflow 10000215 step configs (read 11/05, CHUNKREF reassembled by `seq`).
  2/3a/3b/3c steps are these, patched only for: box/version tokens, size, run profile, `{{STEP:n}}`, blank
  `WorkloadExecution`, and ScenarioTable mode.
- `scripts/connect_upsert_body.ps1`: the Connect pack's workflow upsert code (after its spec), reused verbatim.

Then: `pwsh packs\tools\Test-Pack.ps1 -PackRoot packs\matching -Family matching` must PASS;
`New-PackBackup.ps1 -PackRoot matching -Family matching -Destination <dir>`; `crewchief restore <zip> --folder
workloads/matching --folder reference-kv/matching --replace`; `crewchief validate workload <name> --strict`;
rerun `matching-1k-testauto-create` if a TestAuto spec changed (upsert updates in place by tag).

## Traps already hit (each cost a run)

1. **TestAuto runtime tokens inside a spec**: CrewChief resolves `{{...}}`, so `{{$config:RestClients:Profisee:ApiKey}}`
   would write CrewChief's real key into the TestAuto repository. Generators write `{%...%}`; the upsert step swaps
   back to `{{ }}`. Never put a TestAuto token in a spec with `{{`.
2. **4000-character limit**: `TestAutoWorkflowDetail.ScenarioConfiguration` over 4000 characters is stored NULL with
   a success response. Generators compact long configs and assert <= 4000; wizard-only keys (`ModelSourceDefaults`,
   `SelectedLookupAttributeCodes`, `SelectedScenarioTemplate`) are dropped in ScenarioTable configs.
3. **Saving the strategy disables it**: the continuous-matching PUT (`v1/Matching/strategies`, read-modify-write,
   autoMatch/autoSurvive true) leaves `status = 0`. The setup step must then PATCH `v1/Matching/RetailClient`
   `{"status":1}` and POST `processActions` `IncludeSurvivorship`, and verify status 1. Without it Scenario 2 ran,
   matched nothing, and the Activity Monitor showed no Matching rows between the markers.
4. **Restore with SINGLE_USER deadlocks** against reconnecting Profisee services and left the DB SINGLE_USER. Use
   DatabaseOperationsStep RestoreDatabase (OFFLINE) as Connect does.
5. **Row counts**: survivorship adds golden records (match status code 10, source system 7); sparse records (too
   few match fields) never get a match status. Count loaded rows as non-golden. New rows of a BatchLoad are created
   without their source Code (Profisee assigns one), so find them as loaded rows outside the Scenario 1 table.
6. **Pool recycle time**: recycling all 20 pools takes about 2 minutes per run; the health wait follows.
7. `MatchingStrategyName` must be in the UnifiedMatchingScenario CustomParms for ScenarioTable mode (the mutator
   reads the strategy's fields); PROD's Scenario 2 config lacks it.

## Proof a run measured something

Activity Monitor (`monitor.tActivity`) must show Matching "Clustering & Survivorship" rows between the scenario's
Start and End markers. No Matching rows there = the strategy was disabled or continuous matching off; the run's
numbers are useless, rerun the whole workload (it restores its start backup).
A rematch that leaves a record in its cluster does not change its `Match DateTime`.

## Run history (1K, CORPLTR94, 26R3T)

| Scenario | Good execution | Notes |
|---|---|---|
| 1 | 10000401 (10000400 also valid) | 976 matched, 200 golden, 24 sparse unmatched |
| 2 | 10000404 | 10000403 invalid (strategy disabled); 5 new matched |

## Where things are

- ScenarioMgt REST `https://profiseecloud.dev/speedmerchantstest/rest/` writes the PROD TestAuto DB
  (`speedmerchants-prod-mssql` MCP reads it). Workflows 10000371-10000375 (1K, 26R3T, CORPLTR94).
- Scenario tables: local `ModelSource.dbo.RetailClient<size>Scenario{1,2,3b,3c}` (`RecordAction` New/Changed/NoChange),
  built by `C:\Deploy\SQLScripts\ModelSource\Build-MatchingScenarioTables.ps1`.
- Mutation plan (ScenarioTable mode, TransformSeed 350, D5 rules with NoChange 3):
  `Q:\Work\Work\99 Documentation\speed-merchants\planning\2026-11-04-matching-scenario2-mutation-plan.md`.
- Related skills: `crewchief-workload-packs`, `testauto-matching-scenarios`, `testauto-matching-source-data`.
