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
- **Restore by folder** (Backup page "Restore whole folders" or `crewchief restore <zip> --folder workloads/<family>
  --folder reference-kv/<family> --replace`): Replace zips each existing folder to
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
| Gateway 401 (`answers, API key not set yet`) | Clean install before setup | - | Normal; setup sets the key. After setup = wrong secret (`RestClients:Connect:ApiKey`, `RestKeys:*`) |
| `ModelSource backup file(s) missing on the database server: ...` | `ModelSourcePDATA1K.bak` / `1M.bak` not copied | `SERVERPROPERTY('InstanceDefaultBackupPath')` folder | Copy the files there |
| Old behavior after a pack update (a removed workload still runs, a step the new pack dropped still happens, a TestAuto workflow is started by numeric code instead of by tag, old folders like `1k/` `providers/` `shared/` sit beside `internal/`) | Restored with Add, not Replace: old copies stay and win | Folder tree on the Workloads page shows old folders (`1k/`, `providers/` at the top) | Restore the pack zip again with Replace |
| Run stuck Running after a reboot | Interrupted run | TestAuto active runs | Next `-run` waits for it ("Wait For Interrupted Runs"); do not restart TestAuto during a run |
| Lint (`Test-Pack.ps1`) FAIL lines `file | step | problem` | Pack edit broke the standard | The line names it | Fix in the pack; never ship a failing pack (`New-PackBackup.ps1` refuses) |

## Changing a pack

1. Edit under `CrewChief/packs/<family>/` in git (a branch; Gene commits).
2. Every workload and step description keeps its parts (workload: `What: Why: When: Needs: Success: If it fails:`;
   step: `What: Why: Success: If it fails:` plus `Skipped when:` with a runWhen). Name things by reference key,
   never by box, version, code, date or person.
3. `pwsh CrewChief/packs/tools/Test-Pack.ps1 -PackRoot CrewChief/packs/<family>` must PASS.
4. `pwsh CrewChief/packs/tools/New-PackBackup.ps1 -PackRoot ... -Destination <backup location>` builds
   `crewchief-backup-<time>-pack-<family>.zip`; restore it on each box with Replace for `workloads/<family>` ONLY
   (restoring `reference-kv/<family>` with Replace overwrites that box's values; do it only on a new box).

## Hard safety rules

- Never print API keys or secrets: a gateway 401 body echoes the key; redact `[0-9a-f]{32}` in every log read.
- Never delete an entity, strategy or workflow the pack did not create.
- Never restart TestAuto during a run; never start or stop another box's runs.
- Never run two boxes' tests that share remote targets (Connect: Snowflake, Databricks, Synapse) at the same time.
- Never remove an `AUTO:` tag except from a copy.
- Deploys of CrewChief or TestAuto happen only while no run is active.
