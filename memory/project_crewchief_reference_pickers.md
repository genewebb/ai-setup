---
name: project_crewchief_reference_pickers
description: "CrewChief reference-data picker pattern — DriveMap/ServerNames/ConfigurationDefaults sets + seeders + ServerNameEditor 3-mode control + {{$ref}} tokens"
metadata: 
  node_type: memory
  type: reference
  originSessionId: 08e95719-a0d7-4939-83f7-2163348e1d0b
  modified: 2026-07-22T18:47:25.659Z
---

Pattern for editor pickers fed from reference data (`IKeyValueReferenceStore`, `ReferenceDataSets` constants in CrewChief.Data\Stores):

- **Seeders** (CrewChief.Web\Services, wired in `Program.cs` as consecutive try/catch blocks): `StepDescriptionSeeder` is **add-missing** (new step types gain a default). `DriveMapSeeder`, `ServerNamesSeeder`, `ConfigurationDefaultsSeeder` are **seed-once** — no-op if the set already has entries — so an operator's curation (including removals) sticks across restarts. Mirror `DriveMapSeederTests` for coverage.
- **Reference sets:** `drive-map` (D:–Z:, MapShare picker), `server-names` (empty; `IncludeInReplacements=true` so `{{$ref:server-names:KEY}}` resolves), `configuration-defaults`, `step-descriptions`, `tags`.
- **`{{$ref:type:key}}`** tokens resolve at runtime via `TextTemplater` + `KeyValueReferenceDataResolver`/`IReferenceDataResolver` **only when the type's `IncludeInReplacements` flag is set**. `{{$config:Section:Item}}` resolves secrets from configuration.
- **`ServerNameEditor`** (CrewChief.Web\Components\Controls) = reusable **3-mode** control — Secret (embeds `SecretValueEditor` → `{{$config:…}}`) / Reference Data (dropdown of `server-names` → `{{$ref:server-names:KEY}}`) / Text — used on **every** `TargetComputer`/server field (ServiceControl, AppPool, IisReset, Install, Uninstall, Configure, MapShare, HealthGate, the Configure `sqlServer` switch). Infers mode from the value prefix; always emits a plain string (no model change). `StepEditorCard.ResolveConfigRef` resolves both `{{$config:}}` and `{{$ref:server-names:}}` for the design-time "Load services/app-pools" enumeration.

Bug fix: `KeyValueReferenceStore.WriteType` now **retries** on IOException/UnauthorizedAccessException (AV/indexer file-lock flake — a seeder rewriting the same file many times raced the overwrite-move). See [[project_list_page_nplus1_parallelization]].

**Drive Map feeds the remote Browse dialog (2026-07-22):** `RemoteWindowsOps.BuildFileBrowseScript(path, pattern, driveMap)` takes the `drive-map` set (FileBrowserDialog injects the store and passes it through `IRemoteFileBrowser.ListAsync`). Non-identity letter→UNC entries are (a) appended to the roots view and (b) used to translate a typed `S:\x` path (drive letters are per-interactive-logon — a WinRM network logon NEVER sees them; Get-SmbMapping is session-scoped and HKU\*\Network only covers loaded hives + persistent mappings, so an Azure File share mapped by logon script is invisible to discovery). A still-unresolved path now throws a FRIENDLY "Path not found from this remote session…" — the old symptom was the baffling PS error "A parameter cannot be found that matches parameter name 'Directory'" (`-Directory` is a FileSystem-provider DYNAMIC parameter that never binds when the drive is unknown). Shipped drive-map entries are identity placeholders ("S:"→"S:") — the operator must set the real UNC for translation to work. Open caveat: reaching an Azure Files UNC from the WinRM session may still need auth (storage-key `net use` in-session, or AD-auth + CredSSP for the second hop).
