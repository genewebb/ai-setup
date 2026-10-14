---
name: crewchief-reference-data
description: >
  CrewChief's files-only key-value reference-data subsystem (tags, step descriptions, drive map,
  configuration-template/values, server names), its seeding doctrines, the $ref token resolver,
  ReferenceTransferService export/import, and the Configuration.exe switch catalog. Use when adding a
  reference-data set, shipping or merging embedded defaults, resolving {{$ref:type:key}} tokens,
  working on the Configure step's switch table, add-missing vs additive-merge idempotency, or the
  drive-map set behind the remote Browse dialog.
---

Repo: speed-merchants (paths below are repo-relative)

# CrewChief Reference Data (KV) + Config-Switch Catalog

CrewChief stores its curated reference lists as files (no DB). Each "type" is one JSON file under `<dataFolder>\reference-kv\<typeName>.json`. Types are used for tag pickers, step-description prefills, the MapShare drive-letter picker, the Configure step's two-tier switch template/values, and server-name pickers, and they back the runtime `{{$ref:type:key}}` token.

## When to Use
- Adding a new reference-data set or shipping a new embedded `*.refkv.json` default.
- Resolving/consuming `{{$ref:type:key}}` tokens (respecting `includeInReplacements`).
- Working on the Configure step editor's switch table or the configuration-template/configuration-values pair.
- Deciding between the **add-missing** vs **additive-merge** idempotency doctrine.
- Exporting/importing reference sets between instances (`ReferenceTransferService`).
- Reading/writing the wrapped `{includeInReplacements, entries}` file format or debugging a legacy-flat auto-upgrade.

## Well-known sets (`ReferenceDataSets`)

| Const | Type name | Role |
| --- | --- | --- |
| `Tags` | `tags` | Shared tag vocabulary for steps/workloads; key == value |
| `StepDescriptions` | `step-descriptions` | Default one-liner per step type, keyed by canonical step-type string |
| `DriveMap` | `drive-map` | Selectable drive letters for MapShare (D:–Z:). **No shipped set any more** — `drive-map.refkv.json` was dropped, so the *type* is live (`ReferenceDataSets.DriveMap`, `CrewChief.Data/Stores/ReferenceDataSets.cs:26`) but it starts empty and is created/populated by the operator. ALSO consumed by the remote file-Browse dialog (`RemoteWindowsOps.BuildFileBrowseScript(path, pattern, driveMap)`): non-identity letter→UNC entries are appended to the roots view and translate typed drive-letter paths (letters are per-interactive-logon, invisible to a WinRM logon); identity entries skipped. Deep behavior in [[crewchief-remote-box-prep]] |
| `ConfigurationTemplate` | `configuration-template` | PLACEHOLDER map a new Configure step is generated from: MOSTLY `{{token}}`s — structural values point at `{{$ref:configuration-values:…}}`, credentials at `{{$config:UserCredentials:…}}`, DB/server at their own sets (`database-names`, `{{$config:ServerNames:…}}`) — but since 2026-07-22 (`_shippedUtc`) it ALSO ships benign literals for the widened default-switch profile: `dropMaestroDatabase`/`UseSeparateDatabases` = `"FALSE"`, `authAdName` = `"Windows"`, `AttachmentRepositoryLogonType` = `"Interactive"`, and `sqlUserName`/`sqlUserPassword`/`purviewURL`/`purviewTenantId`/`purviewClientId`/`purviewClientSecret` = `""`. Shipped with `includeInReplacements: false` |
| `ConfigurationValues` | `configuration-values` | The ACTUAL editable values the template tokens resolve against (e.g. `webSiteName = "Default Web Site"`, `maestroServicePort = "8003"`); flagged replaceable so `{{$ref:configuration-values:…}}` resolves |
| `ServerNames` | `server-names` | Friendly-name → host mapping for Target Machine fields |
| `BackupLocation` | `backup-location` | Single entry (key `path`, via `BackupService.LocationKey`) holding the backup folder; seeded inline in `Program.cs:329-331` with `BackupService.DefaultLocation` (`{ScratchRoot}`) when missing — the ONLY reference-data seed still automatic at startup |

The old `configuration-defaults` set (one literal default per switch) **no longer exists** — it was replaced by the two-tier template/values pair above. The Configure editor's `SwitchPrefillValue` reads `ConfigurationTemplate` (`StepEditorCard.razor.cs:1888`; also consumed for the "is this the default?" tint at `:1511` and on enable at `:1918`). A NEW Configure step's `Switches` map is built from it too: both list pages declare a private `ConfigureDefaults()` that loads the `configuration-template` set and feed it to `ConfigurationSwitchCatalog.BuildDefaultSwitches` (`CrewChief.Web/Helpers/ConfigurationSwitchCatalog.cs:131`) — `Steps.razor.cs:629`/`:642`, and in `WorkloadEditor.razor.cs` the same `ConfigureDefaults()` → `BuildDefaultSwitches` pair inside its new-step factory (currently `:544`/`:556`; anchor on the symbol names, this file moves).

## Store (`KeyValueReferenceStore : IKeyValueReferenceStore`)
- File shape: `{ "includeInReplacements": bool, "entries": { key: value, ... } }`.
- **Legacy-flat auto-upgrade**: a bare `{ key: value }` file (no `entries` wrapper) is still read (as entries with `includeInReplacements = false`) and rewritten in wrapped form on the next write. Only leaf string values are entries — nested objects are skipped on load.
- **Kebab-name guard**: type name must match `^[a-z0-9]+(-[a-z0-9]+)*$` — doubles as a path-traversal guard (`RequireValidTypeName`). Keys are trimmed; empty keys rejected.
- **Atomic write**: serialize to `.tmp` then `File.Move(..., overwrite:true)`, with a bounded 5-attempt backoff (`Thread.Sleep(20*attempt)`) to survive a transient AV/indexer handle on Windows (common when a seeder rewrites the same file repeatedly).
- **Tolerant read**: a malformed file is skipped with a Serilog warning (returns empty), not thrown.
- Entries are stored/written key-sorted (Ordinal); keys compared OrdinalIgnoreCase (existing key casing preserved on `Set`).

## Cache (`CachedKeyValueReferenceStore : IKeyValueReferenceStore, IReferenceDataCache`)
- Memoizing decorator over the real store; caches per-type entries, per-type `includeInReplacements` flag, and both type-name lists (`GetTypeNames`/`GetReplaceableTypeNames`).
- **Write-through invalidation**: every mutating call (`Set`, `RemoveKey`, `CreateType`, `DeleteType`, `SetIncludeInReplacements`) forwards to the inner store then `Invalidate(typeName)` (also nulls the two cached lists) — cache stays coherent with no manual refresh.
- `IReferenceDataCache`: `Refresh()` clears everything (for a "Refresh Cache" button); `Invalidate(type)` drops one type. Registered as the app-wide `IKeyValueReferenceStore` so resolver, pickers, and pages all read through the cache.

## Resolver (`KeyValueReferenceDataResolver : IReferenceDataResolver`)
- Resolves `{{$ref:type:key}}` live. **Fail-safe**: if the type's `includeInReplacements` is false (or type/key missing, or any exception), returns `null` so the token stays unresolved — never throws.
- The set of resolvable types is `GetReplaceableTypeNames()` (types with the flag set). See [[crewchief-token-replacement]] for the token pipeline.

## Tags as KV (`TagStoreExtensions`)
- Tags are just the `tags` type where each entry's **key equals its value**. `GetTagNames()` = entry keys; `AddTag(name)` trims, no-ops on empty, is idempotent, and auto-creates the type. Pickers never hand-code the key=value shape; "filter on key OR value" is trivial (same string).

## Seeding doctrines
The four CONTENT seeders run **on demand, not at startup**. `ITemplateInstaller.InstallAll` (`TemplateInstaller.cs:83`) invokes all four in sequence — `StarterTemplateSeeder.SeedIfEmpty` (`:93`) → `SampleContentSeeder.Seed` (`:103`) → `StepDescriptionSeeder.Seed` (`:113`) → `ReferenceDefaultsSeeder.Seed` (`:123`) — each in its own `try/catch`, surfaced as a per-category non-fatal error string in `TemplateInstallResult` (with per-category counts). `InstallAll` is triggered from the Home first-run banner (`FirstRunBanner`, gated by `FirstRunGate`'s `<dataFolder>\.first-run-complete` marker; **Get Started always installs — there is no checkbox and no opt-out**) and from the Templates page's **"Add Default Templates"** button. A **selective** install (`InstallSelected`, `TemplateInstaller.cs:141`, from the Templates page's checkbox rows) reaches only the two *itemized* seeders — `SampleContentSeeder` and `ReferenceDefaultsSeeder`, each with an "only these" filter — so `StarterTemplateSeeder`/`StepDescriptionSeeder` stay `InstallAll`-only. None of this is wired into `Program.cs` startup any more (the four `builder.Services`/inline seeder calls were removed; `Program.cs:313-315` now registers only `FirstRunGate` + `TemplateInstaller`). The ONLY reference-data seed still automatic at startup is the BackupLocation seed-once (`Program.cs:329-331`). The old per-type seeders (`DriveMapSeeder`, `ConfigurationDefaultsSeeder`, `ServerNamesSeeder`) are **deleted** — replaced by the single data-driven `ReferenceDefaultsSeeder`. The per-seeder MERGE doctrines below (add-missing / additive-merge / smart-seed) are **UNCHANGED** — only the when/how-invoked framing moved from startup to on-demand. The on-demand install subsystem (installer, first-run gate, banner, Templates page) is owned by [[crewchief-default-templates]].

| Seeder | Doctrine | Rule |
| --- | --- | --- |
| `StepDescriptionSeeder` | **add-missing** | Invoked **only** from `TemplateInstaller.InstallAll` (`TemplateInstaller.cs:113`) — **never at startup**, and never from `InstallSelected` (it has no per-row identity to select, so a selective install always reports `StepDescriptionsAdded == 0`). `Seed()` (`StepDescriptionSeeder.cs:36`) calls `CreateType(step-descriptions)`, then for each `UtilityStepTypeInfo.AllTypes` entry writes `GetDescription(type)` **only if the key is absent** (`:44-51`). Never overwrites user edits; a newly-added step type gains its default on **the next template install** (not the next app start). Grows over time. **Gotcha:** the class XML-doc still says "runs on every startup" — that comment is stale, the wiring is authoritative. |
| `ReferenceDefaultsSeeder` | **additive 3-way merge from embedded** | Installs each embedded `SampleContent/reference-data/*.refkv.json` set (currently tags, server-names, database-names, configuration-template, configuration-values — **`drive-map` is no longer shipped**) into `reference-kv`. `ComputeKeysToAdd` (pure, testable) adds only keys **new in this release** — present in the shipped set but NOT in `SeedRecord.ShippedEntryKeys` (the previously shipped keys, `Seeding\SeedRecord.cs` ~13–22) and not already on disk — so an operator-deleted key is **never re-added** and edits/additions survive. Manifest keyed `reference-kv/<type>`; `_shippedUtc` + `includeInReplacements` read from each `.refkv.json` (flag applied only on first-ever creation, so an operator's toggle sticks). Non-kebab set names skipped with a warning; per-set failures non-fatal. |
| `SampleContentSeeder` | **smart-seed (date-gated, edit-preserving)** | Installs each embedded sample into the data folder, routed by filename suffix (`SubfolderFor`, `SampleContentSeeder.cs:236-247`; manifest keyed `<subfolder>/<fileName>`): `SampleContent/*.step.json` → `steps/`, `*.workload.json` → `workloads/`, and **`SampleSecrets/*.secrets.json` → `secret-samples/`** (`SecretSamplesFolder`, `:41`). **The secrets samples are inert placeholders** — `secret-samples/` is deliberately NOT the `secrets/` folder and never the encrypted Local Secrets store, so installing one can never clobber real credentials; the operator copies it, fills it in, and imports it on `/secrets`. They carry no `_shippedUtc`, so a re-install is never "newer" and never overwrites a filled-in copy, and their Templates row gets the `Secrets` Kind badge + `"Installs to secret-samples/ — placeholders only"` Detail (`:181`). `SuffixOf` (`:210-217`) knows all three suffixes, so a keep-both copy is `<base>-<stamp>.secrets.json`. Per file, `SeedGate.Decide(shippedUtc, recorded, onDiskExists, onDiskHash, embeddedHash)` (pure, `Seeding\SeedGate.cs`) returns `Skip`/`WriteInPlace`/`WriteVersioned`: **missing on disk → write**; **tracked**: shipped `_shippedUtc` (read by `SampleMeta.ReadShippedUtc`, fail-safe `""`; `DateOnly` parse, unparsable → MinValue) NOT strictly newer than the recorded date → **Skip** — a content diff alone never triggers a rewrite, so operator edits stick until a newer ship; newer + on-disk SHA-256 (`SeedHash.Of`, lowercase hex) == recorded `SeededHash` (untouched) → refresh **in place**; newer + EDITED → **keeps-both**: the new version is written ALONGSIDE as `<base>-<shippedUtc>` (stamp falls back to `-update` if `_shippedUtc` blank) with its internal `name` rewritten to the versioned base — operator's copy untouched, and the versioned write is skipped if that file already exists. **Untracked-but-present** (first run of the seeder): hash == embedded → baseline in place, else treated as an operator edit → versioned. State lives in `<dataFolder>\.seed-manifest.json` (`SeedManifest`: fail-safe load — missing/corrupt = empty manifest; atomic `.tmp` + `File.Move(overwrite:true)` save). Nothing is ever deleted; operator-created file names are never written. See memory [[project_crewchief_smart_seed]] |

Doctrine choice rule: use **add-missing** when the domain keeps gaining members that should get defaults (step types); ship a `*.refkv.json` under `SampleContent/reference-data/` (covered by the single `SampleContent\**\*.json` EmbeddedResource glob) for any curated default set — the additive merge gives you seed-once semantics per key with the ability to ship NEW keys in later releases. See memory [[project_crewchief_reference_pickers]].

> [!important] `DefaultReferenceData/` no longer exists
> The folder was deleted and its sets moved under `SampleContent/reference-data/`, so all shipped content is now covered by one embed glob. Grepping the old path finds nothing but a historical comment in `ShippedContentRoutingTests.cs` — do not conclude the seeding subsystem is gone.

### `ShippedContentKinds` is the single routing authority
Suffix→kind→destination used to be open-coded per seeder; it now lives in `Services/Seeding/ShippedContentKinds.cs` (`KindOf`, `SuffixOf`, `FileSubfolderFor`, `IsReferenceSet`, `ReferenceTypeNameOf`), and `SampleContentSeeder` / `ReferenceDefaultsSeeder` / `TemplateInstaller` all classify through it.

| Suffix | Kind | Destination |
|---|---|---|
| `.step.json` | `Step` | `steps/` |
| `.workload.json` | `Workload` | `workloads/` |
| `.secrets.json` | `SecretsSample` | `secret-samples/` |
| `.refkv.json` | `ReferenceSet` | **`null`** → the `reference-kv` store, additive key merge — not written as a file |

That `null` from `FileSubfolderFor` (`:113`) is the **explicit mechanism** that stops `SampleContentSeeder` double-installing a reference set. It used to be an accidental fall-through — the suffix simply failing to match — which is exactly the kind of correctness-by-luck the consolidation removed.

Because `LogicalName` is the bare filename, **two shipped files may never share a name across subfolders**; a collision is a hard compile error, which is the build's own no-double-embed guarantee.

## Configuration switch catalog (`CrewChief.Web/Helpers/ConfigurationSwitchCatalog.cs`)
Authoritative in-code catalog of Profisee `Configuration.exe` switches, transcribed from the platform `Server\Configuration\Program.cs`. Drives the Configure step editor's grouped enable/disable switch table, prefilling values from the editable `configuration-template` reference set (shipped as `SampleContent/reference-data/configuration-template.refkv.json`, installed by `ReferenceDefaultsSeeder`), falling back to `GetSeedDefault` for switches not in the set.

- `ConfigurationSwitchInfo` record: `Name` (verbatim `/Name:value`), `DisplayName`, `Type` (`ConfigSwitchType` = `Bool`/`String`/`Path`/`Enum`), `Group`, `Description`, `IsSecret` (renders a secret picker), `IsMode` (runs one op then exits), `EnumValues`, `Default`; init-props `DefaultEnabled` (enabled on a NEW Configure step), `PreferredDefault` (CrewChief's opinionated default, wins over the platform-documented `Default`), `SubGroup` (wizard renders one page per (Group, SubGroup)).
- `All` = every catalogued switch; `ByGroup` = grouped in `GroupOrder` (Mode, Licensing, SQL, IIS, AppPool, Auth, Governance, Cluster, FileRepository, Logging); `Find(name)` case-insensitive.
- **Count: 61 entries as of this writing** (Mode 3, Licensing 1, SQL 8, IIS 9, AppPool 3, Auth 16, Governance 9, Cluster 6, FileRepository 4, Logging 2). **Re-count `Build()` before quoting a number** — this list changes.
- `GetSeedDefault(info)` returns the concrete literal fallback default: `PreferredDefault` when set, else `Default` unless dynamic/blank — anything starting with `(` (e.g. `(none)`, `(empty)`, `(follows…)`) or the strings `"current Windows identity"` / `"machine FQDN"` returns `null`. Used by `SwitchPrefillValue` as the fallback when `configuration-template` has no entry for the switch.
- `BuildDefaultSwitches(configDefaults)` builds the initial `Switches` map for a NEW Configure step: every `DefaultEnabled` switch, value taken from the passed reference set (the pages pass the `configuration-template` entries — so new steps are born with whatever the template ships: mostly `{{token}}` placeholders, plus the benign literals above since 2026-07-22); a switch absent from the set is enabled but blank.
- **Widened `DefaultEnabled` profile (2026-07-22, +10)**: `dropMaestroDatabase`, `UseSeparateDatabases`, `sqlUserName`, `sqlUserPassword`, `authAdName`, `AttachmentRepositoryLogonType` (got `PreferredDefault` `"Interactive"`), `purviewURL`, `purviewTenantId`, `purviewClientId`, `purviewClientSecret` — so a NEW Configure step mirrors the canonical `ConfigureProfisee.ps1` invocation (bools explicitly `FALSE`, unused strings explicitly empty). Presence-triggered/mode/cluster/OIDC switches deliberately stay OFF — `useHttps`-style switches act on key PRESENCE, so enabling them by default would change behavior.
- **Authoring rule (always add BOTH)**: setting `DefaultEnabled` on a catalog switch WITHOUT adding a matching `configuration-template` entry yields an enabled-but-BLANK value on new steps (`BuildDefaultSwitches` takes values ONLY from the template set — `GetSeedDefault` is the editor's prefill fallback, not BuildDefaultSwitches'). `ComposeArgumentString` emits an enabled-blank switch as `/name:` (equivalent to `-name:""`) — and the identical-looking canonical scripts pass exactly this profile, so blank-but-enabled is harmless for the widened set but a silent surprise for anything else.
- **Seeder implication**: the new template KEYS land on EXISTING installs via `ReferenceDefaultsSeeder`'s key-diff additive merge (present in the shipped set, absent from the previously-shipped manifest keys) — no manual re-seed needed.
- Secret switches (`IsSecret:true`): `sqlUserPassword`, `maestroServiceUserPassword`, `maestroAppPoolUserPassword`, `authOidcClientSecret`, `purviewClientSecret`, `alationPassword`, `AttachmentRepositoryUserPassword`.

### Presence-triggered vs value-gated — the distinction that bites
Not every switch reads its value. Some are **presence-triggered**: `Configuration.exe` branches on the key existing at all, so a `FALSE` does not disable them. Others are **value-gated** on `ProperEquals("TRUE")`, where `FALSE` is genuinely inert. The doctrine is therefore *pass every switch explicitly* — and never set the same switch in both the table and Additional Raw Arguments, because `Configuration.exe` does not reject the duplicate: it mis-parses, and the damage surfaces later as `Missing parameter <name>` for some unrelated required switch.

> [!danger] `/addToCluster` is PRESENCE-triggered
> `/addToCluster:"FALSE"` **still joins a cluster**. Worse, its presence *skips every required-parameter check* — licenseFile, sqlServer, maestroDatabase, webSiteName, maestroWebAppName and the app-pool trio all stop being validated. It is the one switch that must never be emitted as a default, which is why it stays OFF in the widened `DefaultEnabled` profile.

Two more catalog facts worth carrying, both of which end in a green exit code over a broken install (`Configuration.exe` exits 0 regardless — see [[crewchief-step-executors]]):

- **`authAdEnabled` defaults to `useWindowsAuthentication`.** A SQL-auth install therefore turns the Windows sign-in provider **off**; with OIDC also off there is then no way to sign in, and the run still reports success.
- **`sqlUserName`/`sqlUserPassword` are the INSTALLER credential only, and must be sysadmin.** The platform security script gates database-owner work on `IS_SRVROLEMEMBER('sysadmin')` and merely `PRINT`s when the check fails — yielding a half-secured database and exit 0. The *running* instance uses a generated `Profisee_<db>_<FQDN>` login, which is a different principal entirely.
- `clientId` is relabelled **"Cluster Client ID"** to disambiguate it from `firstUserClientID`; a saved step's `clientId` is migrated to `firstUserClientID` on load unless a cluster switch or an existing `firstUserClientID` is present (`ConfigureStep.cs:150,174-180`).

See memory [[project_crewchief_configure_switches]] and [[crewchief-step-executors]] (the Configure step consumer).

## Export/import (`ReferenceTransferService : IReferenceTransferService`)
Selective export/import of reference sets to a portable JSON bundle (`CrewChief.Data\Services\ReferenceTransferService.cs`, consumed by the Reference Data page; registered singleton as `IReferenceTransferService` at `CrewChief.Web/Program.cs:302`).

- `ReferenceBundle` (~:20): `schemaVersion` (int, currently 1) + `sets` dict of `ReferenceSetBundle`. Each set's on-wire shape mirrors the on-disk file body — `{includeInReplacements, entries}` — so a bundle round-trips losslessly.
- `BuildBundle(setNames)` snapshots the named sets (blank/duplicate names skipped); `Serialize`/`Parse` = indented Newtonsoft JSON (Parse throws on empty/malformed).
- `Import(bundle, setNames)` is **ADDITIVE**: creates/overwrites the sets in the bundle, never deletes a set not in it; `setNames = null`/empty means every set in the bundle; a set whose name is not a valid kebab-case type is **skipped, not fatal** (catches `ArgumentException`). Returns the number of sets written; also applies each set's `includeInReplacements` flag.

## Sources
- `CrewChief\CrewChief.Data\Stores\ReferenceDataSets.cs`
- `CrewChief\CrewChief.Data\Stores\KeyValueReferenceStore.cs`
- `CrewChief\CrewChief.Data\Stores\CachedKeyValueReferenceStore.cs`
- `CrewChief\CrewChief.Data\Stores\TagStoreExtensions.cs`
- `CrewChief\CrewChief.Data\Services\KeyValueReferenceDataResolver.cs`
- `CrewChief\CrewChief.Data\Services\ReferenceTransferService.cs`
- `CrewChief\CrewChief.Web\Services\StepDescriptionSeeder.cs` (`Seed()` `:36`, add-missing loop `:44-51`; sole call site is `TemplateInstaller.cs:113`, NOT startup)
- `CrewChief\CrewChief.Web\Services\ReferenceDefaultsSeeder.cs`
- `CrewChief\CrewChief.Web\Services\Seeding\SeedRecord.cs`
- `CrewChief\CrewChief.Web\Services\SampleContentSeeder.cs` (`SubfolderFor` three-suffix routing `:236-247`, `SecretSamplesFolder` `:41`, secrets-row Detail `:181`)
- `CrewChief\CrewChief.Web\SampleSecrets\` + `CrewChief.Web.csproj:60-71` — shipped placeholder `*.secrets.json` samples (embedded, bare-filename `LogicalName`)
- `CrewChief\CrewChief.Web\Services\TemplateInstaller.cs` — `InstallAll` (`:83`, all four seeders) and `InstallSelected` (`:141`, the two itemized seeders only)
- `CrewChief\CrewChief.Web\Services\FirstRunGate.cs` (`.first-run-complete` marker gating the Home banner)
- `CrewChief\CrewChief.Web\SampleContent\reference-data\` (shipped `*.refkv.json` sets + README)
- `CrewChief\CrewChief.Web\SampleContent\reference-data\configuration-template.refkv.json`
- `CrewChief\CrewChief.Web\Services\Seeding\ShippedContentKinds.cs`
- `CrewChief\CrewChief.Web\Helpers\ConfigurationSwitchCatalog.cs`
- `CrewChief\CrewChief.Engine\Executors\RemoteWindowsOps.cs` (`BuildFileBrowseScript` — drive-map consumer)
- `CrewChief\CrewChief.Web\Program.cs`

## Related
- [[crewchief-token-replacement]] — the `{{$ref:type:key}}` token consumer.
- [[crewchief-web-ui]] — RefDataPicker / ServerNameEditor / Reference Data page consume this.
- [[crewchief-step-executors]] — the Configure step reads the switch catalog + defaults.
- [[crewchief-default-templates]] — owns the on-demand `ITemplateInstaller.InstallAll` subsystem (first-run banner + Templates page) that now invokes the four content seeders documented here.
- [[crewchief-secrets]] — sibling files-only subsystem.
- Memory: [[project_crewchief_reference_pickers]], [[project_crewchief_configure_switches]].
