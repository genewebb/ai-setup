---
name: crewchief-default-templates
description: >
  CrewChief's on-demand default-content install subsystem (ITemplateInstaller, the four seeders,
  FirstRunGate, the Templates page) that REPLACED automatic startup seeding. Use when shipping a
  default step, workload, secrets sample, or reference set, debugging why a sample won't install,
  doing a selective install from the Templates page, working on the Home first-run banner or
  GetSampleStatuses, editing TemplateInstaller or FirstRunGate, or reasoning about when default
  content is installed.
---

Repo: speed-merchants (paths below are repo-relative)

# CrewChief Default Templates (on-demand install)

As of 2026-07-25, CrewChief installs its shipped default content **on demand only** — the old
automatic startup seeding is gone. Nothing seeds at app start except the one BackupLocation default
(below). Every other default (starter examples, shipped samples, step descriptions, reference-data
defaults) is installed through `ITemplateInstaller`, triggered from **exactly two** places: the Home
first-run banner and the Templates page button.

## The installer: `ITemplateInstaller` / `TemplateInstaller.InstallAll`

`CrewChief.Web/Services/TemplateInstaller.cs`. `InstallAll()` runs all **four** seeders, each
**fault-isolated in its own `try/catch`** — an error in one is recorded in `Errors` and does not stop
the others. It returns a `TemplateInstallResult` record:

```
record TemplateInstallResult(
    bool StarterExamplesSeeded,
    int  SamplesWritten,
    int  StepDescriptionsAdded,
    int  ReferenceEntriesAdded,
    IReadOnlyList<string> Errors)
    // WroteAnything => StarterExamplesSeeded || SamplesWritten>0 || StepDescriptionsAdded>0 || ReferenceEntriesAdded>0
```

The four seeders, in order, and their doctrines:

| Seeder | What it seeds | Idempotency doctrine |
|---|---|---|
| `StarterTemplateSeeder.SeedIfEmpty()` | one starter example step + workload | **only into a completely empty install** |
| `SampleContentSeeder.Seed()` | shipped samples embedded in CrewChief.Web.dll | **smart-seed: manifest- + date-gated**, edit-preserving |
| `StepDescriptionSeeder.Seed()` | default one-liner per step type | **add-missing** (never overwrites operator edits) |
| `ReferenceDefaultsSeeder.Seed()` | shipped `*.refkv.json` sets (drive map, config template, …) | **additive merge** (edits/deletions/additions preserved) |

`InstallAll` is **non-destructive and safe to repeat** — a repeat run with nothing new returns all
zeros / `WroteAnything == false`.

### `InstallSelected(IReadOnlyCollection<string> fileNames)` — the narrower sibling

`TemplateInstaller.cs:141`. Installs **only** the rows the operator ticked on the Templates page, using
the **exact same** smart-seed / additive-merge policies — a selective install is never a different kind
of write, just a narrower one. Mechanics:
- The selection is split by suffix (`TemplateInstaller.cs:157`): a name ending `.refkv.json` is a
  reference set (the suffix is **stripped**, because `ReferenceDefaultsSeeder` is keyed by TYPE name);
  everything else is a sample file name passed straight through. Both seeders take an optional
  "only these" filter (`SampleContentSeeder.Seed(onlyFileNames)`, `ReferenceDefaultsSeeder.Seed(types)`).
- **Non-itemized categories are deliberately excluded**: `StarterTemplateSeeder` and
  `StepDescriptionSeeder` have no per-row identity to select, so they run **only** from `InstallAll`.
  The returned record therefore always has `StarterExamplesSeeded == false` and
  `StepDescriptionsAdded == 0` (`TemplateInstaller.cs:195`).
- An empty collection writes nothing. Each category stays fault-isolated.

### `GetSampleStatuses()` — a UNION, not just samples

`TemplateInstaller.cs:198`. It concatenates **two** sources, each in its own `try/catch` so one failing
category can never blank the whole list:
1. `SampleContentSeeder.GetStatuses()` — the embedded `*.step.json` / `*.workload.json` / `*.secrets.json`
   samples (`TemplateInstaller.cs:204`);
2. `ReferenceDefaultsSeeder.GetStatuses()` — the shipped `*.refkv.json` reference sets
   (`TemplateInstaller.cs:214`).

So a Templates-page row can be a Step, a Workload, a **Secrets** sample, or a **Reference Data** set —
`SampleTemplateStatus` exposes `ReferenceDataKind`/`SecretsKind` consts plus `IsReferenceData` /
`IsSecretsSample` predicates (`SampleTemplateStatus.cs:49-61`).

The per-seeder merge doctrines live in [[crewchief-reference-data]] — this skill owns only the on-demand
install orchestration.

## What actually ships today

The shipped catalog was **wholesale replaced**: the old toy samples (`echo-hello`, `sql-select`,
`powershell-write-a-line-to-stdout`, `wait-pause-1-second`, `http-get-crewchief-home-page`,
`drop-database-demo`, `configure-profisee`, `delete-profisee-service`) are gone, as are the
`clean-profisee-instance-26r2`, `restore-200m-profisee-instance-26r2` and `unit-test-all-steps`
workloads. What ships now is a **Profisee box-prep library**, not a syntax demo.

> [!note] Re-read the folders; do not quote this list as gospel
> `SampleContent/steps/` and `SampleContent/workloads/` change most releases. As of 2026-08-10 the
> steps are install/uninstall platform + FastApp Studio, start/stop/restart the Profisee service,
> start/stop W3SVC, stop WAS, restart IIS, drop/restore database, configure instance, set-api-key
> (14 files); the workloads are `26r2-parm-driven-{crud,matching,no-database,uninstall}`,
> `26r3-parm-driven-{crud,uninstall}`, and `all-step-types` (7 files).

The workloads demonstrate the canonical composition pattern — a workload-level `globalParameters` block
of `profisee_*` variables that self-compose (`profisee_service_name` =
`"Profisee {{profisee_version_number}} (Profisee)"`) and are consumed by every inline step, plus a
workload-level Run As trio inherited by the box-prep steps. See [[crewchief-workload-and-runs]].

## Secrets samples (`*.secrets.json`) — inert, and never the real store

Routing is no longer open-coded in the seeder. **`Services/Seeding/ShippedContentKinds.cs` is the single
routing authority** — `KindOf` / `SuffixOf` / `FileSubfolderFor` / `IsReferenceSet` / `ReferenceTypeNameOf` —
and `SampleContentSeeder`, `ReferenceDefaultsSeeder` and `TemplateInstaller` all classify through it, so the
suffix table exists in exactly one place:

| Suffix | Kind | Destination |
|---|---|---|
| `.step.json` | `Step` | `steps/` |
| `.workload.json` | `Workload` | `workloads/` |
| `.secrets.json` | `SecretsSample` | **`secret-samples/`** (`SampleContentSeeder.SecretSamplesFolder`) |
| `.refkv.json` | `ReferenceSet` | **`null`** → `reference-kv` store (additive key merge), never written as a file |

`FileSubfolderFor` returning `null` for `.refkv.json` (`ShippedContentKinds.cs:113`) is the **explicit
mechanism** that stops `SampleContentSeeder` double-installing a reference set — previously it was ignored
only by accidental fall-through, which is a very different guarantee.

- The destination is **deliberately NOT `secrets/`** and never the encrypted Local Secrets store. A
  secrets sample is a placeholder-only starting point the operator copies, fills in, and imports on the
  `/secrets` console — installing it **can never overwrite real credentials**.
- Shipped source folder is `CrewChief.Web/SampleSecrets/` (currently `sample-secrets.secrets.json`),
  embedded via its own csproj `ItemGroup` (`CrewChief.Web.csproj:65-71`, `LogicalName` = bare filename).
- A secrets sample carries **no `_shippedUtc`**, so `SeedGate` never treats a re-install as "newer" — the
  operator's filled-in copy is never clobbered. Its Templates row gets a `Secrets` Kind badge and the
  Detail string `"Installs to secret-samples/ — placeholders only"` (`SampleContentSeeder.cs:181`).
- The versioned keep-both name uses the real suffix (`SuffixOf`, `SampleContentSeeder.cs:210-217`), so a
  kept-edit copy is `<base>-<stamp>.secrets.json`, not `.step.json`.

## The two — and only two — triggers

Default content is **never installed automatically at startup**. It installs only from:

### 1. Home first-run banner — `FirstRunBanner.razor`

`CrewChief.Web/Components/Controls/FirstRunBanner.razor`. Shown on Home only. **There is NO checkbox
and no opt-out** — the banner is a blurb plus a single **Get Started** button. `GetStartedAsync`
(`FirstRunBanner.razor:50`):
- **always** runs `TemplateInstaller.InstallAll()`, off the render thread via `Task.Run`
  (`FirstRunBanner.razor:57`) — the rationale in the file's own header comment is that the banner only
  shows on a genuinely empty install, so there is nothing there to overwrite,
- then calls `FirstRunGate.Complete()` **either way** — including a best-effort second attempt inside
  the `catch` (`FirstRunBanner.razor:66`) so the banner never nags forever.

Do **not** describe an `_installDefaults` flag or an "install defaults?" checkbox — neither exists.
The `Program.cs` DI comment above the `ITemplateInstaller` registration (`:390-394`) now agrees:
*"which always calls InstallAll: there is no opt-out checkbox, because the banner only shows on a
genuinely empty install."* (An earlier revision of this skill warned that comment was stale — it has
since been rewritten and the warning no longer applies.)

### 2. Templates page — `/templates`

`CrewChief.Web/Components/Pages/Templates.razor(.cs)`. Route `/templates`; in `NavMenu.razor` it sits
**right after Reference Data**. Two install buttons, both via `Task.Run`, both followed by
`ReferenceDataCache.Refresh()` (so newly merged sets appear everywhere immediately) and a status-list
reload. This page is the **only** install path once first-run is complete.

| Button | `data-testid` | Handler | Calls |
|---|---|---|---|
| **Add Default Templates** | `install-all` | `InstallAsync` (`Templates.razor.cs:108`) | `InstallAll()` |
| **Install Selected (N)** | `install-selected` | `InstallSelectedAsync` (`Templates.razor.cs:132`) | `InstallSelected(_selected)` |

Selection state is a `HashSet<string>` of **file names** keyed `OrdinalIgnoreCase`
(`Templates.razor.cs:35`) — file name, not row index, so a reload can't mis-target. Supporting UI:
a header **select-all** checkbox (`data-testid="select-all"` → `ToggleSelectAll`), **Select needed**
(`data-testid="select-needed"` — ticks every row an install would actually change), and **Clear**
(`data-testid="clear-selection"`). On refresh, `_selected` drops names no longer present
(`Templates.razor.cs:52`).

## `FirstRunGate` — the one-shot banner marker

`CrewChief.Web/Services/FirstRunGate.cs`. Writes a `.first-run-complete` marker file in the data folder
(content = UTC timestamp). `IsPending()` is `!File.Exists(marker)`; `Complete()` creates the data
folder and writes the marker.

**Silent completion for upgrades.** Home decides whether to show the banner in `Home.razor.cs`
`DecideFirstRunBanner()`:
- if `!FirstRunGate.IsPending()` → nothing,
- else if `StepCount > 0 || WorkloadCount > 0` → an existing install that already has content
  **completes the gate silently** (`FirstRunGate.Complete()`) and **never shows the banner**,
- else → shows the banner.

So an operator upgrading into a build that has the banner is never nagged; the Templates page is their
on-demand path.

## Templates-page status list predicts the button's action

`ITemplateInstaller.GetSampleStatuses()` returns `IReadOnlyList<SampleTemplateStatus>`
(`SampleTemplateStatus.cs`), one row per shipped **sample step/workload/secrets file AND per shipped
reference-data set** (see the union above), with `SampleTemplateState`:

| State | Meaning |
|---|---|
| `NotInstalled` | not on disk — Add installs it |
| `UpToDate` | on disk, identical to shipped |
| `ModifiedKept` | operator edited; shipped isn't newer, edit kept as-is |
| `UpdateAvailable` | newer shipped version, local untouched — Add refreshes in place |
| `UpdateKeepsEdit` | newer shipped version but local edited — Add keeps the edit, writes update as a versioned copy |

Critically, `GetStatuses()` computes each state through the **same `SeedGate.Decide(...)`** the
installer's `Seed()` uses, so **the list always predicts exactly what "Add Default Templates" will do**.
`SeedGate.WriteVersioned → UpdateKeepsEdit`, `WriteInPlace + !exists → NotInstalled`, `WriteInPlace +
exists → UpdateAvailable`, `Skip → UpToDate` or `ModifiedKept` by hash comparison.

## Program.cs wiring

`CrewChief.Web/Program.cs`:
- The four content seeders were **REMOVED from startup**. The comment block spells out that
  default-content installation is on-demand only.
- `FirstRunGate` and `ITemplateInstaller` are both registered as **singletons over the resolved data
  folder** (`ContentRootPath` + `CrewChief:DataFolder` config, default `"data"`).
- The **only** automatic startup seed that remains is the **BackupLocation seed-once**:
  `refStore.CreateType(ReferenceDataSets.BackupLocation)` and, if absent,
  `refStore.Set(..., BackupService.LocationKey, BackupService.DefaultLocation)`.

## Installer: no re-baseline task

`installer/CrewChief.iss` ships **four** tasks — `service`, `firewall` (unchecked), `clipath`,
`desktopicon` (`CrewChief.iss:75-79`). There is **no `resetsamples` task**; the identifier has zero
hits anywhere in the repo. Re-baselining shipped samples is done by deleting
`<dataFolder>\.seed-manifest.json` by hand, then running an install from the Templates page.

## Cross-links

- [[crewchief-reference-data]] — the per-seeder merge doctrines (StepDescription add-missing,
  ReferenceDefaultsSeeder additive-merge of `*.refkv.json`).
- [[crewchief-web-ui]] — the Templates page + banner components, Blazor conventions.
- Memory: [[project_crewchief_smart_seed]] — the SampleContentSeeder smart-seed/manifest/date-gate.

## Sources

Verified against live code under `CrewChief\`:
- `CrewChief.Web/Services/TemplateInstaller.cs` — `ITemplateInstaller`, `InstallAll` (`:83`), `InstallSelected` (`:141`), `GetSampleStatuses` (`:198`, unions samples + reference sets), `TemplateInstallResult`, four fault-isolated seeder calls.
- `CrewChief.Web/Services/FirstRunGate.cs` — `.first-run-complete` marker, `IsPending()`, `Complete()`.
- `CrewChief.Web/Services/SampleTemplateStatus.cs` — `SampleTemplateStatus` record, `SampleTemplateState` enum, `ReferenceDataKind`/`SecretsKind` (`:49`, `:55`).
- `CrewChief.Web/Services/SampleContentSeeder.cs` — `Seed(onlyFileNames)` (`:62`), `GetStatuses()` (`:142`), `SubfolderFor` suffix routing incl. `*.secrets.json` (`:236-247`), `SecretSamplesFolder` (`:41`).
- `CrewChief.Web/SampleSecrets/` + `CrewChief.Web.csproj:60-71` — shipped `*.secrets.json` placeholder samples, embedded with a bare-filename `LogicalName`.
- `CrewChief.Web/Components/Controls/FirstRunBanner.razor` — no checkbox; `GetStartedAsync` (`:50`) always calls `InstallAll` (`:57`).
- `CrewChief.Web/Components/Pages/Templates.razor` and `Templates.razor.cs` — `/templates`, "Add Default Templates" (`install-all`) + "Install Selected" (`install-selected`), `_selected` file-name set (`.razor.cs:35`).
- `CrewChief.Web/Components/Pages/Home.razor(.cs)` — `DecideFirstRunBanner` silent-complete logic.
- `CrewChief.Web/Components/Layout/NavMenu.razor` — Templates nav after Reference Data.
- `CrewChief.Web/Program.cs` — seeders removed from startup; DI singletons; BackupLocation seed-once retained.
- `installer/CrewChief.iss:75-79` — the four `[Tasks]` (`service`, `firewall`, `clipath`, `desktopicon`); no `resetsamples`.
