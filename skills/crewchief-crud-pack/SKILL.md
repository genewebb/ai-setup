---
name: crewchief-crud-pack
description: The CrewChief CRUD workload pack (CrewChief/packs/crud) and its generator gen_crud.py - REST API Create/Update/Get/Delete at 1K-1M and interactive stewardship (1-60 min or 10-1000 iterations per step) with and without business rules, restored from profisee_CRUD_base.bak before every test, the 18-step 1M release run, business-rule removal through REST. Use when changing, regenerating, deploying or debugging the CRUD pack, its TestAuto workflows (AUTO:...:crud-*), crud-preflight / crud-setup / crud-test-*, or comparing CRUD runs with the release CRUD history.
---

# CrewChief CRUD pack

Repo: speed-merchants, `CrewChief/packs/crud` (Gene commits). Built 11/07/2026 on the Matching pack blueprint
(`crewchief-workload-packs`, `crewchief-matching-pack`). Pack notes: `CrewChief/packs/crud/CLAUDE.md`. People docs:
CrewChief help pages `69`-`72_PackCrud*.md`.

Every input carries a `"default"` (Gene 11/10, hand runs; `INPUT_DEFAULTS` in `gen_crud.py`): version keys `{{$ref:crud/environment:<key>}}`, backup names composed as the roots compose them (`{{$ref:crud/databases:BaseBackupStem}}_{{ProfiseeVersionCode}}.bak`). A default is used only when no caller supplies the value, and a workload whose default uses `{{ProfiseeVersionCode}}` must declare it as an input too. A new input needs an `INPUT_DEFAULTS` entry (the generator fails without one); Test-Pack rule R-handrun checks it.

## Regenerate (never hand-edit a workload)

```powershell
Remove-Item -Recurse C:\devops\repos\speed-merchants\CrewChief\packs\crud\workloads, C:\devops\repos\speed-merchants\CrewChief\packs\crud\rounds, C:\devops\repos\speed-merchants\CrewChief\packs\crud\reference-kv
python <skill>\scripts\gen_crud.py C:\devops\repos\speed-merchants\CrewChief\packs\crud
pwsh C:\devops\repos\speed-merchants\CrewChief\packs\tools\New-PackCatalog.ps1 -PackRoot C:\devops\repos\speed-merchants\CrewChief\packs\crud -Family crud
pwsh C:\devops\repos\speed-merchants\CrewChief\packs\tools\Test-Pack.ps1 -PackRoot C:\devops\repos\speed-merchants\CrewChief\packs\crud -Family crud
```

`catalog-meta.json` (estimate per test) is hand-kept at the pack root; `New-PackCatalog.ps1` rewrites `catalog.json` from it, `tests/` and `rounds/`; the lint fails while it is stale.

Service and pools (Gene 11/10): the generator imports `CrewChief\packs\tools\instance_steps.py` (path from the pack
root: `<packRoot>\..\tools`), so regenerate from a speed-merchants checkout that has it. No step names the Profisee
service or a pool, and no reference key holds one (`MainServiceName`, `AnalyticsPoolName` are retired; Test-Pack rule
R-instance refuses them, an `AppPoolStep`, a typed Profisee `serviceName`, and a discovery step whose text is not the
current `packs\tools\instance-discovery.ps1.txt`). `instance_steps.add_service_discovery(workload, family)` puts the
remote PowerShell step `Find The Instance Service` (outputParameterName `InstanceServiceName`, global `""`) right before
the first step reading `{{InstanceServiceName}}`; service steps use `serviceName` and `runWhen` `{{InstanceServiceName}}`
(none found = Skipped, two = red). Pools: `instance_steps.pools_step(label, 'Recycle'|'Start', target, family, what, why)`
finds the pools of the IIS applications `/<instance>` and below on the server and recycles or starts exactly those
(AppPoolStep cannot take a run-time list); no pool = red. A change to the fragment means: regenerate every pack and
run `connect_instance_discovery.py` for Connect.

`scripts/connect_upsert_body.ps1.txt` and `scripts/health.ps1` are copies of the Matching pack's (upsert by AUTO tag,
adds missing TestAutoTags, deterministic step codes; health wait). The reference sets are regenerated too: on a box
restore only `workloads/crud` unless the box is new.

## What it generates

| Workflows (26) | Steps |
|---|---|
| `crud-<1k|10k|100k|1m>-core-<br|nobr>` | Create (TDATA to ZDATA, 1000/batch), Update (10% `_Changed`, 5% `_New`), Get 1/10/100 users, Delete (filter, 500/batch) |
| `crud-steward-<1|5|15|30|60>min-<br|nobr>` | 12 x StewardshipFilterScenario on TDATA: widths (ff,da) 10/5, 20/10, 40/20, 70/50 x users 1/10/100; TimeLimit `00:MM:00` (60 = `00:59:59`), IterationLimit 0 |
| `crud-steward-<10|100|1000>it-<br|nobr>` | Same 12 steps by count (Gene 11/07): TimeLimit `00:00:00`, IterationLimit N (`ForEachIterationAsync` stops at whichever limit is non-zero) |
| `crud-1m-release-<br|nobr>` | Release CRUD order: Create, Update, Get x3, stewardship x12 (60 min), Delete |

Configs copied from PROD 10000195/10000197 (read 11/07); changes: size, TimeLimit, all stewardship on TDATA (PROD
steps 10-13 read PDATA), blank `WorkloadExecution`, version/machines tokens. DqRuleCount 10 (br) / 0 (nobr).
Environment block: env name and app server = `crud/machines:ApplicationServerName`, DB server = `DatabaseServerName`.

Tests: each size pairs core with stewardship 1K-5, 10K-15, 100K-30 min; 1M = release run; smoke = 1K core br + 1 min
stewardship nobr; proof (`crud-test-proof`, `rounds/proof-round.txt`) = every form at 1K: core, 10it and 1min, br+nobr
(Gene 11/07: prove forms without the 1M run). Generator keys: `STEWARD_FORMS`, `TEST_FORM`, `stew_key(form, m)`.

## Traps

- **Rule delete**: `DELETE v1/Rules?RuleIds=a,b` (comma list); repeating `RuleIds=` deletes only the first.
- **4000-character config limit**: the generator asserts it (stewardship configs about 2800).
- **Setup file size**: one setup workload with every spec was 836 KB; split into `internal/testauto/crud-testauto-*`
  children (60-224 KB each), like Matching.
- **Preflight state step is information only**: the Profisee database is shared with Connect and Matching, so it
  may hold another model; every run restores the base.
- Literal-pattern lint: never write the base TDATA count (10002325 looks like a workflow code) or a release name
  like 26R3 in a workload.

## Deployed

SMVMTR1 (11/07/2026, 26R3T): workflows 10000470-10000489, count forms 10000490-10000495. Smoke 11/07 PASS 50 min
(core 1K br 15.6 min incl. restore, ZDATA 900; steward 1min nobr 34 min). A 1-min TestAuto step takes ~2 min wall.

## Version-aware lanes (multi-version, 11/09)

- Version keys ProfiseeVersionCode, ProfiseeVersionNumber, ConfigurationManagerKind are ROOT
  GLOBALS defaulting to `{{$ref:crud/environment:<key>}}` (a root = a workload no workload runs: crud-preflight, crud-setup,
  crud-base-create, crud-test-*); a TestAutoManager lane overrides them with `--param`. Every workload below declares the keys
  it or its callees use as `inputs` (`inputs_for`, `run_inputs`); a key read by `$ref` below a root fails Test-Pack (R-root).
- Base names are composed in the roots: `BaseBackupFileName = {{$ref:crud/databases:BaseBackupStem}}_{{ProfiseeVersionCode}}.bak`
  (likewise `RunStartBackupFileName`); children take them as inputs. `BaseSeedBackupFileName` (`profisee_CRUD_base.bak`, today's
  file) is the only unversioned backup key; Test-Pack R-bak exempts keys ending `SeedBackupFileName`.
- Pool steps are `instance_steps.pools_step` (found on the server); there is no pool list.
- Tags: `AUTO:{{$env:COMPUTERNAME}}:{{ProfiseeVersionCode}}:<key>`.
- `start/crud-base-create` (D18): wait, check whether the versioned base exists (PowerShell step, `outputParameterName` BaseMissing; when it exists every later step is Skipped through `runWhen {{BaseMissing}}` / `{{ServiceStepsOn}}`, a message says nothing was done and the run ends green; never overwrites), stop Main + IIS, restore the seed,
  IIS + Main start, `install-configure-upgrade`, health, `crud-api-key-set` (R-key: restore + configure are followed by the key set), Check Base State, back up as `BaseBackupFileName`. The seed must be the
  same or an older version (Configuration only upgrades). `crud-preflight` 'CRUD Base Backup Exists' names it when the base is missing.

## Run start and key sequence (11/08)

- Profisee Configuration writes NEW service sign-in ids (meta.tUser ClientId of every service user, encrypted) into the
  database it runs on AND into the application server. Only the backup configured LAST works; any other gets GET
  v1/Rules 400 DATA00030 (auth log: `No client with id ... found`). Seen 11/08: CRUD base configured 10:32, Matching
  10:38, CRUD failed. `auth.Clients` is empty in every base (not the cause).
- So every `crud-test-*` (and smoke, proof) starts with `crud-run-start` (Gene: once per pack run): wait, stop Main, IIS
  stop, restore `BaseBackupFileName` (never overwritten), IIS start, start Main, `install-configure-upgrade` (install pack; its two version inputs ProfiseeVersionNumber, ConfigurationManagerKind are inputs of `crud-run-start`, passed through from the root, no step parameters; timeout 7500 s,
  Configure 7200 s), health, `crud-api-key-set`, Check Base State, BackupDatabase
  `RunStartBackupFileName`. `crud-setup` no longer touches the base.
- `crud-base-reset`: wait, stop Main, stop W3SVC + WAS, restore the RUN-START copy, `crud-api-key-set`, Check Base State.
  The gateway check alone passes while Data rejects. A core/steward workload run alone after another pack configured
  fails red at the Data check.
- **Key standard (Gene 11/08, help rule 10):** the API key is set before ANY gateway call; a clean Configuration issues a
  new key (401). `internal/shared/crud-api-key-set` = stop Main, IIS stop, SetApiKey, IIS start, start Main, health,
  verify gateway (v1/Entities) AND Data (v1/Rules), 200 only. Run by `crud-preflight` (after Wait For Interrupted Runs;
  the preflight no longer "changes nothing": it restarts IIS), `crud-run-start` and `crud-base-reset`. No 401 allowance
  anywhere. First proven 11/09 on SMVM2 fresh 26R3 (TR2 crud-preflight green).
- REST PowerShell steps append `Get-Why` to failures (401 body never shown, ids masked, 800 chars).
