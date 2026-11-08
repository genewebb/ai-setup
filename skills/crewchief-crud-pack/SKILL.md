---
name: crewchief-crud-pack
description: The CrewChief CRUD workload pack (CrewChief/packs/crud) and its generator gen_crud.py - REST API Create/Update/Get/Delete at 1K-1M and interactive stewardship (1-60 min or 10-1000 iterations per step) with and without business rules, restored from profisee_CRUD_base.bak before every test, the 18-step 1M release run, business-rule removal through REST. Use when changing, regenerating, deploying or debugging the CRUD pack, its TestAuto workflows (AUTO:...:crud-*), crud-preflight / crud-setup / crud-test-*, or comparing CRUD runs with the release CRUD history.
---

# CrewChief CRUD pack

Repo: speed-merchants, `CrewChief/packs/crud` (Gene commits). Built 11/07/2026 on the Matching pack blueprint
(`crewchief-workload-packs`, `crewchief-matching-pack`). Pack notes: `CrewChief/packs/crud/CLAUDE.md`. People docs:
CrewChief help pages `69`-`72_PackCrud*.md`.

## Regenerate (never hand-edit a workload)

```powershell
Remove-Item -Recurse C:\devops\repos\speed-merchants\CrewChief\packs\crud\workloads, C:\devops\repos\speed-merchants\CrewChief\packs\crud\rounds, C:\devops\repos\speed-merchants\CrewChief\packs\crud\reference-kv
python <skill>\scripts\gen_crud.py C:\devops\repos\speed-merchants\CrewChief\packs\crud
pwsh C:\devops\repos\speed-merchants\CrewChief\packs\tools\New-PackCatalog.ps1 -PackRoot C:\devops\repos\speed-merchants\CrewChief\packs\crud -Family crud
pwsh C:\devops\repos\speed-merchants\CrewChief\packs\tools\Test-Pack.ps1 -PackRoot C:\devops\repos\speed-merchants\CrewChief\packs\crud -Family crud
```

`catalog-meta.json` (estimate per test) is hand-kept at the pack root; `New-PackCatalog.ps1` rewrites `catalog.json` from it, `tests/` and `rounds/`; the lint fails while it is stale.

`scripts/connect_upsert_body.ps1` and `scripts/health.ps1` are copies of the Matching pack's (upsert by AUTO tag,
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

## Run start and key sequence (11/08)

- Profisee Configuration writes NEW service sign-in ids (meta.tUser ClientId of every service user, encrypted) into the
  database it runs on AND into the application server. Only the backup configured LAST works; any other gets GET
  v1/Rules 400 DATA00030 (auth log: `No client with id ... found`). Seen 11/08: CRUD base configured 10:32, Matching
  10:38, CRUD failed. `auth.Clients` is empty in every base (not the cause).
- So every `crud-test-*` (and smoke, proof) starts with `crud-run-start` (Gene: once per pack run): wait, stop Main, IIS
  stop, restore `BaseBackupFileName` (never overwritten), IIS start, start Main, `install-configure-upgrade` (install pack,
  Configure 7200 s), health, IIS stop, SetApiKey, IIS start, health, verify gateway + Data, Check Base State, BackupDatabase
  `RunStartBackupFileName` (`profisee_CRUD_run-start.bak`). `crud-setup` no longer touches the base.
- `crud-base-reset`: stop Main, stop W3SVC + WAS, restore the RUN-START copy, SetApiKey, start WAS + W3SVC, start Main,
  health, verify key through the gateway (v1/Entities) AND the Data service (v1/Rules?PageSize=1). The gateway check alone
  passes while Data rejects. A core/steward workload run alone after another pack configured fails red at the Data check.
- REST PowerShell steps append `Get-Why` to failures (401 body never shown, ids masked, 800 chars).
