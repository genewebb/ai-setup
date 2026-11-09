---
name: crewchief-workload-packs
description: >
  Diagnose and change CrewChief workload packs: the box-neutral layout (start / tests / schedule / internal) whose
  workloads hold no environment values, the reference-kv/<family>/ sets a person edits instead, the
  AUTO:<box>:<version>:<key> automation tag that finds TestAuto workflows, runWhen and the Skipped outcome,
  blank application pool names dropped, the pre-run reference check, restore by folder with Replace, and the pack
  lint. Use when a pack workload (Connect today) fails or is skipped unexpectedly, when an error says "No TestAuto
  workflow carries tag", "TestAuto workflows carry tag", "Reference data check failed before step 1", "runWhen ...
  could not be resolved", when setting up a new box or upgrading Profisee for a pack, or when adding or editing a
  pack workload.
---

# CrewChief workload packs

Repo: speed-merchants. Pack source: `CrewChief/packs/<family>/` (`workloads/<family>/**`, `reference-kv/<family>/*.json`),
tools in `CrewChief/packs/tools/`. Family notes: `CrewChief/packs/<family>/CLAUDE.md` (Connect: `packs/connect/CLAUDE.md`).
Design: `Q:\Work\Work\99 Documentation\speed-merchants\planning\2026-11-04-crewchief-workload-packs-design.md`.

**People docs = CrewChief in-app help, category `Packs` (Gene 11/06: the one source; the vault Connect docs are pointers).**
Sources in `CrewChief/CrewChief.Web/Documentation/`: `60_PacksOverview.md` (model, tools, changing a pack, and the
**BLUEPRINT checklist** a new pack (Matching, CRUD) must meet) and per pack four pages in a fixed shape: overview,
move to a new machine, check before a run, run manually (Connect: `61`-`64_PackConnect*.md`, orders 10-13; Matching
takes 20-23, CRUD 30-33). The move / check / run pages are for a tester new to CrewChief: numbered steps with
**Do / Check / If it fails**. A new category value must be added to `ApprovedCategories` in
`CrewChief.Tests.Unit/Web/DocsCatalogTests.cs` (`Packs` is there). Every pack also ships `start/<family>-preflight`
(changes nothing), `start/<family>-setup`, `rounds/*.txt` for `tools/runner/run-queue.sh`, and a `README.md`.
When a pack changes in a way a person would notice, update its help pages in the same change.

**Declared inputs (rule 9 of 60_PacksOverview; Gene 11/06).** A building block that uses a value only its parent passes
(`SourceTableName`, `RecordCount`, `ModelSourceSize`, `WorkerThreadCount`) lists it in the workload's `inputs`
(`{name, description}`), never as a child global (child globals beat parent globals). A workload that only hands it on
to its own child declares it too (Connect `connect-objects-reset` -> `connect-strategies-create`, found by the new parent
check). Connect: 16 workloads declare inputs. `Test-Pack.ps1` refuses a plain `{{Token}}` that is neither defined
(globals, step parameters) nor declared, an input without description or shadowed by a global, and a Run Workload step
that does not supply a child's input. Needs a CrewChief build with inputs (11/06); an older build keeps `inputs` in
the open ExtraParms bag and still shows those 16 red. Engine detail: `crewchief-nested-workloads`.

**Database names (rule 8 of 60_PacksOverview; Gene 11/06, after Connect and Matching both used `ModelSource`).**
Packs share a box and its SQL Server (one pack runs at a time), so each pack has its OWN source database,
`ModelSource<Pack>` (`ModelSourceConnect`, `ModelSourceMatching`, `ModelSourceCRUD`), in
`<family>/databases:ModelSourceDB`. A database name hides in three places; all three must come from that key:

| Place | Do | Found 11/06 |
|---|---|---|
| Step SQL / PowerShell | `[{{$ref:<family>/databases:ModelSourceDB}}].dbo.<t>`, `RESTORE DATABASE [{{$ref:...}}]`, `DB_ID(N'{{$ref:...}}')` | Connect `connect-source-data-load` had `ModelSource` 9 times while the key existed |
| Profisee Connect service configuration | setup/load deletes and imports it with `DbServer`/`DatabaseName` parameters from reference data (Connect: `connect-service-configurations-create`; Matching: load steps "Remove/Import ModelSource Service Configuration") | Matching's lived only inside `profisee_Matching_empty.bak` |
| TestAuto scenario code + workflow CustomParms | a CustomParm with the name, written by `<family>-setup` from the key; the code defaults to the old name | `MatchingRecordLoader` had `DatabaseName = "ModelSource"`; fixed with CustomParm `SourceDatabaseName` |

`Test-Pack.ps1` refuses a literal database name in `sqlScript`/`scriptContent` (`x.dbo.`, `[x].dbo.`, `ALTER|RESTORE|
BACKUP|CREATE|DROP|USE DATABASE x`, `USE x;`, `DB_ID('x')`; `master`, `msdb`, `tempdb`, `model` allowed). It cannot
see service configurations or TestAuto code: for a new pack also run
`grep -rnw ModelSource CrewChief/packs/<family> TestAuto.<Area>` and fix every hit that names a database.

## The model (read before diagnosing)

- **Workload files hold no environment values.** Machine names, databases, URLs, the Profisee version, the
  Windows service name and the analytics pool live in reference data `reference-kv/<family>/<set>.json`, used as
  `{{$ref:<family>/<set>:<Key>}}`. A person edits ONLY reference data (Reference Data page). A fix that needs a
  workload edit is a pack bug: fix it in git under `CrewChief/packs/<family>`, lint, rebuild the zip.
- **Layout**: `start/` (`<family>-preflight`, `<family>-setup`: a person runs them once per box and after an
  upgrade), `tests/` (one master per test, runs its thread counts in order, stops at the first failure),
  `schedule/` (Task Scheduler parents), `internal/` (everything else; only parents run them).
  Workload names are unique across folders; the shallowest copy wins name resolution, so stale copies matter.
- **Reference keys carry a description and a "may be blank" flag** (`keyDescriptions`, `keyBlankAllowed` in the
  set file; shown under each key on the Reference Data page). A blank value resolves to empty ONLY when flagged;
  any other blank, or a missing key, is unresolved and fails fast.
- **Pre-run reference check**: before step 1 of ANY workload, every `{{$ref}}` it uses (any step field, script
  body, parameter, global; not descriptions or notes) must resolve. Child workloads are checked when they run.
- **runWhen** (any step): token-resolved after parameters; blank or `false` = step **Skipped** (counts as
  success, logged with the reason); an unresolvable token = step **Failed**. Packs use it for the Profisee Windows
  service steps: `runWhen = {{$ref:connect/environment:MainServiceName}}`.
- **AppPool**: pool names that resolve blank are dropped (the analytics pool before it exists); all blank = Skipped.
- **Automation tag**: every measured TestAuto workflow carries `AUTO:<CrewChief box>:<ProfiseeVersionCode>:<key>`
  in its Tags (box from `{{$env:COMPUTERNAME}}`, version from reference data, key = a `<family>/workflows` key).
  Run steps carry `workflowTag`, never `workflowCode`. TestAuto `GET api/workflows/by-tag?tag=` returns the ACTIVE
  workflows whose comma-split Tags contain that whole entry (trimmed, case-insensitive; `...:x` never matches
  `...:x-8t`). Exactly one must match. Setup creates or updates by the same lookup; an upgrade (new version in
  reference data) makes setup create a NEW set and leaves the old version's workflows and history alone.
- **Tags (decided by Gene 11/05)**: CrewChief workload tags = family (`connect`), folder words, size `1K`/`1M`
  (upper case, matching TestAuto) and threads `4T`/`8T`/`12T`. A workload that runs every thread count (tests
  masters, provider `-all` parents, schedules) carries all three. A workload that serves every size (shared,
  provider-level, start) carries none. TestAuto workflow Tags = `AUTO:...`, family, version, Main machine, size,
  threads. **Every TestAuto tag must exist in the PROD `TestAutoTags` entity** (TestAuto's tag picker and filters list
  only those). Each upsert step adds the missing ones (Code = Name = tag text; existing tags are never changed).
  Check: `SELECT Code FROM data.vTestAutoTags` on PROD (speedmerchants-prod-mssql).
- **Finding them in TestAuto**: the Workloads page switch **Automation Only** shows only workflows with an `AUTO:`
  tag (`WorkflowTagMatcher.HasAutomationTag`, choice remembered in localStorage `workflows-filter-automation-only`).
  It needs the TestAuto build from 11/05.
- **Restore by folder** (Backup page "Restore whole folders" or on the box `crewchief restore <zip> --folder
  workloads/<family> [--folder reference-kv/<family>] --replace --data-folder C:\Deploy\CrewChief\web\data`;
  always pass `--data-folder` = the folder the Web app and the CLI runner use): Replace zips each existing folder to
  `crewchief-backup-<time>-before-restore-<folder>.zip` in the backup location first, then removes it, then
  restores. Add mode leaves files the pack no longer has. Undo = restore the safety zip with Replace.

## Diagnostic order

1. Run `<family>-preflight` (Connect: `connect-preflight`). Each failing step names the key or machine.
2. Read the failed run: Web run page, or CLI runner `status.json` + `out\<stamp>-<workload>.log`, then
   `crewchief-cli-YYYYMMDD.log`; then the TestAuto execution; then Seq (`seq-query` skill).
3. Match the exact error text in the table below. Fix reference data, secrets, or the box; re-run preflight.
4. Never edit a workload file on a box to get past an environment problem.

## Symptom -> cause -> check -> fix

| Exact text (or symptom) | Cause | Check | Fix |
|---|---|---|---|
| `Reference data check failed before step 1 (N value(s)): Reference value '{{$ref:connect/<set>:<Key>}}' is missing. <description>` | Key absent from the set (old or partial reference restore) | Reference Data page, set `connect/<set>` | Restore `reference-kv/<family>` from the pack zip with Replace, then re-enter this box's values; or add the key |
| `... is blank (and not marked 'may be blank'). <description>` | Required value left blank | The key description says what goes there | Fill it in. Only the service and analytics pool keys may be blank |
| `... cannot be resolved: its reference-data set is missing or not marked usable in replacements` | Set file missing, or "usable in replacements" off | Reference Data page: the set exists, switch on | Restore the set; turn the switch on |
| `runWhen '{{...}}' could not be resolved: ...` (step FAILED, not skipped) | runWhen names a missing key | as above | Add the key (blank is fine when it is flagged may-be-blank) |
| Service stop/start step **Skipped**: `runWhen '{{$ref:connect/environment:MainServiceName}}' resolved blank` | Service name blank | Normal on releases with no Profisee Windows service | Nothing; if this release HAS the service, fill `MainServiceName` (services.msc on Main) |
| Service step **Failed** on a release with no Profisee Windows service (service not found) | `MainServiceName` / `TargetServiceName` still set after an upgrade | `Get-Service Profisee*` on the server shows none | Blank the key (it is flagged may-be-blank) |
| AppPool step fails, a pool not found | Wrong instance name, or analytics pool set on a release without it | IIS Manager on the server | Fix `connect/instances:ProfiseeInstanceName` or blank `AnalyticsPoolName` / `TargetAnalyticsPoolName` |
| `No TestAuto workflow carries tag 'AUTO:<box>:<ver>:<key>'. Run connect-setup (or the family's setup) on this box.` | Setup not run for this box and version (new box, upgrade, version key changed, box renamed) | Preflight tag step | Run `<family>-setup` |
| `<n> TestAuto workflows carry tag 'AUTO:...': <code> '<name>'; .... Remove the tag from the copies.` (also from setup and preflight) | Someone copied a workflow and kept the tag | TestAuto workflow list, filter by the tag | Remove the AUTO tag from the copy's Tags field in TestAuto (the original is the one the person did not just create, usually the lower code; ask when unsure), never delete the original; then preflight |
| `TestAuto at <url> cannot look up workflows by tag (HTTP 404): it needs the build with GET api/workflows/by-tag.` | TestAuto on the box is older than the pack | TestAuto version | Deploy current TestAuto (only when no run is active) |
| Preflight: `Workflows for <ver> not created yet on this box (0 of 54 automation tags found)` | Before the first setup, or after an upgrade | - | Normal; run setup |
| Preflight: `<n> of 54 automation tags have no TestAuto workflow` | Setup stopped part way, or a workflow was deactivated | TestAuto list | Run setup again |
| Gateway 401 right after the pack's key-set step (`<family>-api-key-set`, `connect-api-key-set-main`) | Key did not take: API user (`ConnectRuntime:ApiKeyUserName`) missing from meta.tUser, IIS not restarted, or wrong secret (`RestKeys:ProfiseeRestKey`) | The key-set run's failed step | Fix the user or secret, rerun the preflight. Key standard (help rule 10, Gene 11/08): every clean Configuration issues a new key, so each pack sets the key (IIS stop/start) before any gateway call; only the Connect P2P target gateway (another lane's instance) may still say "not set yet" |
| `ModelSource backup file(s) missing on the database server: ...` | `ModelSourcePDATA1K.bak` / `1M.bak` not copied | `SERVERPROPERTY('InstanceDefaultBackupPath')` folder | Copy the files there |
| Old behavior after a pack update (a removed workload still runs, a step the new pack dropped still happens, a TestAuto workflow is started by numeric code instead of by tag, old folders like `1k/` `providers/` `shared/` sit beside `internal/`) | Restored with Add, not Replace: old copies stay and win | Folder tree on the Workloads page shows old folders (`1k/`, `providers/` at the top) | Restore the pack zip again with Replace |
| Run stuck Running after a reboot | Interrupted run | TestAuto active runs | Next `-run` waits for it ("Wait For Interrupted Runs"); do not restart TestAuto during a run |
| Lint (`Test-Pack.ps1`) FAIL lines `file | step | problem` | Pack edit broke the standard | The line names it | Fix in the pack; never ship a failing pack (`New-PackBackup.ps1` refuses) |

## Changing a pack

1. Edit under `CrewChief/packs/<family>/` in git (a branch; Gene commits).
2. Every workload and step description keeps its parts (workload: `What: Why: When: Needs: Success: If it fails:`;
   step: `What: Why: Success: If it fails:` plus `Skipped when:` with a runWhen). Name things by reference key,
   never by box, version, code, date or person.
3. `pwsh CrewChief/packs/tools/Test-Pack.ps1 -PackRoot CrewChief/packs/<family> -Family <family>` must PASS
   (`-Family` defaults to `connect`: pass it for any other pack).
4. `pwsh CrewChief/packs/tools/New-PackBackup.ps1 -PackRoot ... -Destination <backup location>` builds
   `crewchief-backup-<time>-pack-<family>.zip`; restore it on each box with Replace for `workloads/<family>` ONLY
   (restoring `reference-kv/<family>` with Replace overwrites that box's values; do it only on a new box).

## Tweak recipes (where each kind of change goes)

Running and recording a round (runner, queue, board, run times): [[crewchief-connect-test-rounds]].

| Change | Edit | Then |
|---|---|---|
| A box value (server, database, URL, version, service, pool) | Reference Data page on that box only, never the pack | `<family>-preflight` |
| Profisee upgrade on a box | `<family>/environment`: `ProfiseeVersionCode`, service names (blank on 26R3+), analytics pools | preflight, `<family>-setup` (creates a NEW tagged workflow set, keeps the old one) |
| A database the pack reads or writes | A key in `<family>/databases` (own name per pack, e.g. `ModelSource<Pack>`); every SQL, service configuration and TestAuto CustomParm uses it | lint (refuses literal names), the grep above |
| New reference key | `reference-kv/<family>/<set>.json`: value, `keyDescriptions` entry, `keyBlankAllowed` only if a release lacks it | lint; on boxes add the key by hand (restoring reference-kv with Replace wipes box values) |
| A step every run shares (reset, source load, row check) | The one child under `internal/shared/**` or `internal/<size>/` that owns it; `-run` files only call children | lint, zip, restore `workloads/<family>` with Replace, one 1K `-run` to prove it |
| One provider's prepare | `internal/providers/<p>/` (`connect-<p>-<dir>-prepare`, strategies-create, service-configuration-refresh, credentials-refresh) | as above, run that provider's 1K pair |
| TestAuto workflow shape (steps, run profile) | Upsert steps in `internal/<size>/testauto/*-workflows-create` and `*-run-profiles-create` (matched by AUTO tag, re-run updates in place) | lint, restore, `<family>-setup` (or just the testauto-setup child) |
| New thread count or size | New `-run`/prepare workloads under `internal/providers/<p>/<size>/t<n>/`, upsert steps, `<family>/workflows` keys `<family>-<size>-<p>-<dir>-<n>t`, the `tests/` masters, the `<size>-all` parents | lint enforces run-step tags = upsert keys = workflow keys; setup creates the workflows |
| New provider | Copy a provider folder whose shape matches (remote table: databricks/snowflake/synapse; database: sql-server), its keys, secrets entries | same, plus a credentials refresh on each box |
| Description wording | The workload or step `description` (parts listed in step 2 of "Changing a pack") | lint |

Never hand-edit pack workloads on a box: the next Replace restore wipes the edit, and the boxes drift apart.
A copied workflow in TestAuto that keeps its AUTO tag makes the run step stop (two matches): remove the tag from the copy.

## Hard safety rules

- Never print API keys or secrets: a gateway 401 body echoes the key; redact `[0-9a-f]{32}` in every log read.
- Never delete an entity, strategy or workflow the pack did not create.
- Never restart TestAuto during a run; never start or stop another box's runs.
- Never run two boxes' tests that share remote targets (Connect: Snowflake, Databricks, Synapse) at the same time.
- Never remove an `AUTO:` tag except from a copy.
- Deploys of CrewChief or TestAuto happen only while no run is active.
