---
name: crewchief-backup-restore
description: >
  CrewChief's portable-zip backup/restore of operator-authored content (steps, workloads, reference-kv) with selective-by-part backup and a two-tier per-item restore. Use when working on BackupService/IBackupService, the BackupParts catalog, the /backup Web page or its restore dialog, the CLI backup/restore verbs and --parts, the backup-location reference-data entry, InspectBackup/InspectBackupItems/RestoreBackupEntries, or reasoning about what a backup zip contains, additive-restore semantics, or the zip-slip guard.
---

Repo: speed-merchants (paths below are repo-relative)

# CrewChief Backup & Restore

CrewChief backs up the operator's authored content — the `steps`, `workloads`, and `reference-kv` subfolders of the data folder (see [[crewchief-file-persistence]] for what lives there) — into a single portable zip, and restores from it **additively** (add/overwrite selected files, never delete anything else). One `BackupService` in `CrewChief.Data` is shared by the `/backup` Web page and the CLI `backup`/`restore` verbs. Both directions are **selective and independent**: a zip may hold every part while a restore brings back one part — or, via the Web UI, one individual file. Memory: [[project_crewchief_backup_restore]].

## When to Use
- "Add a new part to the backup zip" / "why isn't X included in the backup?"
- "The restore dialog on /backup — how does the group/item selection work?"
- "What does `crewchief backup --parts refdata` actually back up?"
- "Where does the backup land and how do I change the folder?"
- "Can a restore delete or corrupt content that isn't in the zip?"

## What a backup contains (and excludes by construction)
- `CreateBackup(destinationDir, parts?)` zips only the selected `BackupParts` subfolders of the data folder: `steps/`, `workloads/`, `reference-kv/`. Entry paths are stored **relative to the data folder** with `/` separators, so restore lands files back in the right subfolders.
- Everything else is excluded *by construction*, because only those subfolders are enumerated: `runs.json` (data-folder root), secrets files, logs, and `.seed-manifest.json` are never captured.
- Zip name: `crewchief-backup-<yyyyMMdd-HHmmss>.zip` (timestamp is **local** `DateTime.Now`); destination dir is created if missing; returns the zip path.
- A missing source subfolder is silently skipped. Explicitly selecting only unknown parts throws `ArgumentException("No known backup parts were selected.")` — but see the CLI footgun below.
- `ListBackups(dir)` matches `crewchief-backup-*.zip`, newest first; `BackupInfo.CreatedUtc` is actually the file's `LastWriteTimeUtc` (not a parsed timestamp).

## The BackupParts catalog (selective-by-part)
`BackupParts` (static class, `CrewChief.Data.Stores.BackupService.cs`) identifies parts by their **data-subfolder name**:

| Const | Id | Label |
|---|---|---|
| `Steps` | `steps` | Steps |
| `Workloads` | `workloads` | Workloads |
| `ReferenceData` | `reference-kv` | Reference Data |

- `All` — display-order list; also the *only* top-level folders restore will ever write.
- `Label(part)` — friendly label, falls back to the id.
- `Normalize(token)` — maps loose tokens to canonical ids or `null`: `step|steps`, `workload|workloads`, `reference-data|reference-kv|referencedata|refdata|reference`. Exists so the CLI's `--parts` accepts human-friendly values.
- `CreateBackup`/`RestoreBackup` take `IReadOnlyCollection<string>? parts`; **null/empty = all parts**. Internally `SelectParts` intersects the request with `BackupParts.All` (case-insensitive, canonical order preserved).

## Restore semantics — additive, part-guarded, zip-slip guarded
`RestoreBackup(zipPath, parts?)`:
- Throws `FileNotFoundException` if the zip is missing.
- For each entry: skips directory markers (`entry.Name` empty); takes the entry's **top-level folder** and skips it unless it's in the allowed set (requested subset ∩ `BackupParts.All`) — this filter is both the part selection *and* the guard against stray/foreign entries in a tampered zip.
- **Zip-slip guard**: resolves `Path.GetFullPath(dataFolder + entry.FullName)` and silently skips any entry that would land outside the data root (prefix check with the directory separator, case-insensitive).
- Extracts with `overwrite: true` — restore **adds/overwrites, never deletes**, so it cannot wipe content that isn't in the backup.

## Two-tier inspect + per-item restore (2026-07 addition)
- `InspectBackup(zipPath)` → which parts are present (canonical display order); empty list if the zip is missing/unreadable (never throws). Lets a restore UI offer only what the backup contains.
- `InspectBackupItems(zipPath)` → `IReadOnlyList<BackupGroup>` for a **two-tier group → item picker**. Records: `BackupGroup(Part, Label, Items)` and `BackupEntry(EntryPath, DisplayName)`. `DisplayName` = filename up to its **first dot** (`load-customers.step.json` → `load-customers` — safe because kebab names carry no dots); items sorted case-insensitively; empty groups omitted.
- `RestoreBackupEntries(zipPath, entryPaths)` restores **exactly** the given zip entry paths (as returned by `InspectBackupItems`, `/`-normalized, case-insensitive match): same top-level-part guard + zip-slip guard as `RestoreBackup`; entries outside known parts are ignored; **null/empty selection restores nothing** (no throw).

## Backup location — the backup-location reference-data set
- `ReferenceDataSets.BackupLocation = "backup-location"` (see [[crewchief-reference-data]]): a single-entry set, key `path` (= `BackupService.LocationKey`), holding the folder where backups are written and listed. Seeded with default `{ScratchRoot}` (= `BackupService.DefaultLocation`) and editable on the Reference Data page.
- `BackupService.ResolveLocation(IKeyValueReferenceStore)` (static): reads the set, prefers the `path` key, **falls back to the first non-empty value** if `path` is absent, and returns `DefaultLocation` on unset/empty/any exception. Trims the result.

## Surfaces
- **Web** — `/backup` page (`Backup.razor` + `.razor.cs`), NavMenu link (icon `backup`, text "Backup"). Page shows the resolved location in the info banner, a **per-part checkbox row** for creating a backup (all pre-checked; Create disabled with none selected), a `RadzenDataGrid` of existing backups (name/created-local/size/Restore), and the **two-tier restore dialog**: groups with a header checkbox + `selected/total` badge, per-item checkboxes, Select all / Clear buttons; opening pre-selects **everything** the backup contains and the operator narrows down; confirm calls `RestoreBackupEntries` and toasts "Reopen the affected pages to see the changes" (stores re-read from disk; no in-memory invalidation needed).
- **CLI** — `crewchief backup [--out <path>] [--parts steps,workloads,reference-data] [--data-folder <path>]` and `crewchief restore <zipPath> [--parts ...] [--data-folder <path>]` (see the crewchief-cli skill). `--parts` is comma-split with trim/remove-empty in `CliArgs`; `Program.cs` maps tokens through `BackupParts.Normalize` and drops unrecognized ones. `backup` writes to `--out` if given, else `ResolveLocation`; `restore` prints `Restored from: <zip>` or `Restore failed: <msg>` (error exit code).
- **DI** — registered as a **singleton** `IBackupService` → `new BackupService(dataFolder)` in both `CrewChief.Web/Program.cs` and `CrewChief.Cli/Program.cs`; the service holds no state beyond the data folder path.

## Footguns
- **CLI unknown `--parts` silently means ALL.** `Normalize` drops unrecognized tokens; if *every* token is dropped the list is empty, and empty = "all parts" — so `crewchief backup --parts bogus` backs up everything instead of erroring. (Calling `CreateBackup` directly with only-unknown *non-normalized* parts does throw.)
- **Backup ≠ full disaster recovery.** Runs history, secrets, and logs are deliberately outside the zip — restoring onto a fresh box still needs the secrets bootstrap (crewchief-secrets skill).
- **Restore never deletes** — a restore cannot be used to *remove* a step/workload; delete via the normal stores/UI.
- **`BackupInfo.CreatedUtc` is `LastWriteTimeUtc`** of the zip file, not the filename timestamp (which is local time anyway).

## Sources
- CrewChief\CrewChief.Data\Stores\BackupService.cs
- CrewChief\CrewChief.Data\Stores\ReferenceDataSets.cs
- CrewChief\CrewChief.Web\Components\Pages\Backup.razor
- CrewChief\CrewChief.Web\Components\Pages\Backup.razor.cs
- CrewChief\CrewChief.Web\Components\Layout\NavMenu.razor
- CrewChief\CrewChief.Web\Program.cs
- CrewChief\CrewChief.Cli\CliArgs.cs
- CrewChief\CrewChief.Cli\Program.cs
