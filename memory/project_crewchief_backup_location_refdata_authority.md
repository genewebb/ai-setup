---
name: project_crewchief_backup_location_refdata_authority
description: "CrewChief backup folder — backup-location ref data is the sole authority, throws when unset; default now C:\\Deploy\\CrewChief\\Backups"
metadata: 
  node_type: memory
  type: project
  originSessionId: 58643c62-5a5a-4b93-bd61-29e95b1c0942
  modified: 2026-08-27T12:52:08.149Z
---

2026-08-27: CrewChief's backup folder moved from `C:\tmp` to `C:\Deploy\CrewChief\Backups`, and the
`backup-location` reference-data entry (key `path`) became the SINGLE authority for it.

- `BackupService.DefaultLocation` renamed to `SeedLocation`. It is used in exactly one place —
  `CrewChief.Web/Program.cs`, which seeds the ref-data entry once when the key is absent.
- `BackupService.ResolveLocation` now throws `InvalidOperationException` (with a `Fix:` clause) when the
  entry is missing, blank, or unreadable. It used to `catch { return DefaultLocation; }`.
- **Why no fallback:** backups silently written to a folder the operator never chose are only discovered
  later, when a restore reads the configured folder and finds nothing.
- Non-obvious: changing `SeedLocation` does NOT migrate an existing install, because the seed is
  guarded on key absence. The operator's on-disk
  `CrewChief.Web/data/reference-kv/backup-location.json` must be edited (or the entry cleared) too.
- `Backup.razor` / `.razor.cs`: `ResolveLocation` moved inside the try; `BackupLocation` starts empty and
  the banner says "a location that is not configured" rather than naming a path backups won't reach.
- `CrewChief.Cli` `backup` case catches `InvalidOperationException` and returns
  `CliExitCodes.NotFoundOrValidation` instead of falling through to the top-level "Unexpected error" net.

Suite 3292 passing after the change (was 3289). Tests in `BackupServiceTests` now drive off ref data and
assert the throw; none hard-code a path except the override values. Uncommitted — see [[feedback_no_commits]].

Still `C:\tmp` elsewhere in CrewChief and NOT changed (separate concerns, flagged not touched): installer
output dir in `installer/BUILDING.md` + `New-CrewChiefInstaller.ps1`, `03_Installation.md`,
`01_DeveloperGuide.md`, and `ConnectImport.razor.cs` `_outputDirectory`.
