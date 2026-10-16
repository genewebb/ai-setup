---
name: project-crewchief-secrets-to-reference-data-2026-10-15
description: "CrewChief secrets slimmed 10/15 - only user ids/passwords/keys/thumbprints stay secret; hosts, DBs, Windows-auth conn strings, URLs, paths, share names go to reference-kv parent folders; CrewChief code change for folder types + configuration bindings"
metadata:
  node_type: memory
  type: project
  originSessionId: 62facdb4-e40f-4ba8-8baa-0e03f6026148
  modified: 2026-10-15T14:51:18.047Z
---

Gene's rule (2026-10-15): secrets hold ONLY sensitive values: user ids and passwords, API/REST keys, client ids and secrets, PATs, private keys, certificate thumbprints, and file-share KEYS. Everything else goes to reference data:
- host and server names
- database names
- Windows-auth connection strings
- REST URLs and timeouts
- paths
- file-share NAMES

**Why:** too much non-sensitive data was hidden in secrets. Define-once must survive the move.

**How to apply:** use the skill `crewchief-secrets-to-reference-data`.
- Layout: `reference-kv\{target-machines,database,rest-urls,crewchief}\<group>.json`. The type always wins: there is no `connect\` folder.
- Tokens: `{{$ref:parent/sub:Key}}`.
- Each secret section carries a `referenceData` pointer attribute.
- Scripts (in `D:\PowershellScripts\CrewChiefConnect`):
  - `Build-ConnectReferenceData.ps1` (build-time define-once expansion, the token map, the slim secrets file)
  - `Convert-WorkloadSecretsToReference.ps1`
  - `New-ConnectWorkloads.ps1` has `ReferenceData=$true` for SMVMTR1 only. The laptop is still on `$config`.

**CrewChief change** (speed-merchants, uncommitted, 4,243 unit tests green):
- folder type names (`KebabName.IsValidPath`)
- `ReferenceDataConfigurationSource` driven by `crewchief/configuration-bindings`. It sits between appsettings and secrets, so secrets win.

**Folder pane (10/15, 09:40–10:30, uncommitted, 4,258 unit tests green).** Gene asked for "directories just like Steps and Workloads, same UI". The Reference Data page now has:
- the shared `FolderTree`;
- `IReferenceDataFolderService` (a `LibraryFolderService` subclass with catalog `folders\reference-kv.json`);
- `ReferenceTypeMover`, used for every move. A type's folder is part of its name, so each move also rewrites the `$ref` tokens and the configuration-bindings values.

~~Built-in types are pinned~~ (pin removed 10/15 PM: Gene wanted built-ins movable).

**Built-in names + descriptions + editor screen (10/15 PM, uncommitted, 4,291 unit tests green).** Gene's asks: identify built-ins IN the ref-data json and organize them in any folder; description per store; Built-in badge + tag own types as built-in for secrets; edit like Steps/Workloads (list + edit screen) because width was a problem.
- File gains `"builtIn"` + `"description"`. Store resolves any name to the type whose marker equals it (implicit for unmarked root file at a `BuiltInUses` name; stamped before move). CrewChief ids fixed; operator ids unique, CrewChief ids reserved unless unclaimed (import). Cached store clears ALL on any write (aliasing).
- Page: `/reference-data` list (folder pane + full-width types, description on card/row) and `/reference-data/edit/{*EditType}` editor (Back, Rename/Export/Delete, Details card: description + built-in name with explicit Save/Cancel, then Entries/Used by). Same component, both routes. Edit URL accepts a built-in name.
- Usage counts tokens written with path OR built-in name (`RefUsageIndex.ForType(type, builtInId)`).
- Export/import bundle carries `builtIn` + `description`; import leaves a held name off (logged).
- Gene must rebuild + view it (UI not seen live by Gene yet). SMVMTR1 duplicates (root vs foldered server-names/database-names) still open: root ones are the built-ins.

**Status at 08:50, 10/15:**
- Reference data is built on SMVMTR1 (14 files).
- The 57 non-connect workloads on SMVMTR1 were deleted. Backups: `\\SMVMTR1\c$\Deploy\CrewChief\backup-workloads-20261015-noncconnect` and `scratchpad\tr1-workloads-backup-20261015-noncconnect`.
- The slim file `\\SMVMTR1\c$\Deploy\Secrets\SMVMTR1_connect_crewchief.slim.json` is built.
- PENDING:
  1. Gene rebuilds and deploys CrewChief.
  2. Then deploy the 30 regenerated connect workloads and rewrite the 7 step-library files.
  3. Gene imports the slim file.

**Open:**
- `RestClients:Seq:ApiKey` was a literal that differs from `RestKeys:SeqApiKey`. It now points at `RestKeys`, so verify the Seq key.
- The generator needs the QA `cz-perf-tests` folder; pass `-QaFolder <backup>`.

Related: [[project-crewchief-connect-restructure-2026-10-13]]
