---
name: project_crewchief_backup_restore
description: "CrewChief backup/restore of steps+workloads+reference-data as a portable zip — BackupService (Data), /backup UI page + nav, CLI backup/restore, backup-location reference-data default C:\\tmp"
metadata: 
  node_type: memory
  type: project
  originSessionId: bc525bea-d92c-43f1-b02b-dd4de1184b90
  modified: 2026-07-20T18:01:54.421Z
---

2026-07-20: Added backup/restore of operator content to CrewChief (UI + CLI).

- **Engine:** `CrewChief.Data/Stores/BackupService.cs` (`IBackupService`) — zips the `steps`, `workloads`, and `reference-kv` subfolders of the data folder into `crewchief-backup-<yyyyMMdd-HHmmss>.zip`. `CreateBackup(destDir)`, `RestoreBackup(zipPath)` (additive: add/overwrite the backed-up files, never delete other content; zip-slip guarded; only restores the three known top-level folders), `ListBackups(dir)` (BackupInfo records, newest first). Secrets/runs/logs/manifest are deliberately NOT backed up.
- **Location:** reference-data set `ReferenceDataSets.BackupLocation = "backup-location"`, single entry key `path` (BackupService.LocationKey), default `C:\tmp` (BackupService.DefaultLocation). Resolve via `BackupService.ResolveLocation(refStore)`. Seeded (create-type + default path) in Web Program.cs so it shows/edits on the Reference Data page.
- **UI:** `Components/Pages/Backup.razor(.cs)` at `/backup` + a "Backup" nav item (icon `backup`) in NavMenu.razor. Create button + a grid of existing backups with per-row Restore (confirm dialog).
- **CLI:** `crewchief backup [--out <path>]` and `crewchief restore <zipPath>` (CliArgs verbs + Dispatch in CrewChief.Cli/Program.cs; IBackupService registered in both Web + CLI DI).
- **Tests:** `Data/BackupServiceTests` (round-trip, excludes secrets/includes reference data, list, default-location) + `Cli/CliArgsTests` backup/restore parse tests.
- Pairs with the deploy hygiene ([[project_crewchief_smart_seed]] — redeploy uses `robocopy /XD data logs`, so the runtime data this backs up is never clobbered by a copy).
