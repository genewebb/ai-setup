---
name: testauto-secrets-management
description: >
  Database-backed secret management system for TestAuto (TestAutoSecrets Profisee entity).
  Use when bootstrapping a new machine, importing or editing secrets via the /secrets UI,
  switching Profisee environments, troubleshooting startup failures related to missing
  secrets, rotating the master password, or adding a new REST client to the secrets store.
---

Repo: speed-merchants (paths below are repo-relative)

# TestAuto Secret Management

> **Scope**: speed-merchants (TestAuto.Web)
> **Source**: SecretManagement_UserGuide.md, 11_DeveloperGuide.md
> **Note**: the old PowerShell SecretManagement provider approach (`SecretManagementConfigurationProvider`) was retired — its classes were deleted from the repo. This DB-backed system is the only secrets mechanism.

---

## Architecture

Secrets are stored in the `TestAutoSecrets` Profisee entity (in the **ScenarioMgt** Profisee instance) and loaded at startup into `IConfiguration`. This is distinct from the Profisee instance being tested.

```
Local machine
  master.json (DPAPI encrypted)
    ├── Master encryption password
    ├── ScenarioMgt REST URL
    └── ScenarioMgt API key
          │
          ▼
  ScenarioMgt Profisee Instance
    TestAutoSecrets entity
      SecretData (AES-256 + Brotli, `ENC:BROTLI:` prefix)
      SecretDataDisplay (masked preview)
          │
          ▼ loaded at startup
  IConfiguration
    RestClients:Profisee:BaseUrl
    ConnectionStrings:HangfireDB
    Profisee:CLU:Path
    ...
```

**Only the active profile** (`IsActive = Y`) is loaded. Each machine can have multiple profiles (Development/Production).

---

## First-Time Bootstrap (One-Time Per Machine)

### The primary path is the **browser wizard** (redirect is LIVE as of 2026-08-08)

`SecretsBootstrapMiddleware` IS wired: `PipelineExtensions.ConfigurePipeline` calls
`app.UseSecretsBootstrapRedirect()` right after `UseAntiforgery()`. While
`!IsPasswordConfigured() || !IsScenarioMgtConfigured()`, every HTML request redirects to
`/secrets/bootstrap`; the bypass list covers `/api`, `/swagger`, `/_blazor`, `/_framework`,
`/_content`, static assets. This is the whole setup path for a **Windows Service** install (no
console exists there — the service starts in degraded mode and waits for the browser).

### The console prompt still exists — interactive launches only

`TestAuto.Web\Program.cs` constructs a `MasterPasswordManager` **before**
`WebApplication.CreateBuilder`; on an unconfigured box it runs
`SecretSetupCommands.RunInteractiveSetupAsync(args)` — but ONLY when the session is interactive
(`!WindowsServiceHelpers.IsWindowsService() && !Console.IsInputRedirected`). Non-interactive
launches log a line and continue to the host in degraded mode. `--setup` is unchanged.

> [!note] master.json location is resolver-driven (2026-08-08)
> `MasterConfigPathResolver` (TestAuto.Shared.Security) decides where `master.json` lives:
> `TESTAUTO_SECRETS_FOLDER` machine env var (service installs set it to `%ProgramData%\TestAuto`)
> → `%ProgramData%\TestAuto` when running as a service → `%APPDATA%\TestAuto` interactive/dev.
> The default `MasterPasswordManager()` ctor routes through it — never hardcode `%APPDATA%` again.
> A legacy `%APPDATA%` store is auto-migrated (copy + read-back verify) when a machine-shared
> location is adopted. CrewChief's separate middleware/resolver pair predates this and stays as-is.

### The web wizard, step by step

`/secrets/bootstrap` (`TestAuto.Web\Components\Pages\SecretsBootstrap.razor`) — 3 steps revealed
progressively:

1. **Generate master password** — strong password (min 16 chars, no common patterns), store in 1Password.
2. **Step 1 — Master Password**: enter the master password → **Verify Password**. A fresh machine (no
   existing secrets) accepts any compliant password; if secrets already exist it must match the one that
   encrypted them. Repeated failures trigger a lockout.
3. **Step 2 — ScenarioMgt Connection** (appears after password verified): enter **Machine Name**,
   **Profile Type** (Development/Production), **ScenarioMgt REST URL** (e.g. `https://profiseecloud.dev/speedmerchants/rest/`),
   and **ScenarioMgt API Key** → **Test Connection**. Verifying + testing writes `master.json` (DPAPI).
4. **Step 3 — Import Method** (appears after the connection test succeeds): choose
   **Import from JSON file** (recommended — upload the v2 secrets JSON, preview, **Import Secrets**) or
   **Enter secrets manually** (routes to `/secrets/edit/{machine}`).
5. On success → **Restart TestAuto** button (`RestartAppButton`, service mode: detached
   Stop-Service/Start-Service helper + auto page reload; console mode: close-and-relaunch note) and
   **Go to Secrets Management** (`/secrets`). If the imported profile is not active, click
   **Set as Active**, then restart to load it — `/secrets` carries the same restart button.

---

## Daily Use — the `/secrets` page

The Secrets Management page is **read-only by default** and **schema-driven**: it renders one collapsible
panel per section in the loaded profile, each showing the section's **Category** badge, an **"Included in
replacements" / "Not in replacements"** badge, its **description**, and a Key/Value table (values masked
where appropriate). New sections appear automatically — there are no hardcoded "REST Clients"/"Connection
Strings" sections anymore.

### Select / load a profile
- **Machine** dropdown + **Profile Type** dropdown → **Load**.
- The Active Status row shows **✓ ACTIVE** or a **Set as Active** button (+ **Delete** profile).
- An alert reminds you only the **active** profile is loaded at runtime; changes need an app **restart**.

### View Only ↔ Edit Mode (master-password gate)
- The page opens in **View Only**. To change anything, enter the **master password** in the
  "Password Verification Required" card → **Verify & Enable Edit** → the badge flips to **🔓 Edit Mode**.
- Click the **lock** button to drop back to View Only.

### Header actions
- **Verify All** — tests every connection/REST client in the profile (green/red per result).
- **Refresh** — reload the current profile from the database.
- **Export** — download the active profile as JSON (`ISecretImportExportService.ExportToJsonAsync`).
- **Backup All** — export every machine's profiles.
- **Bootstrap** — (shown when the machine has no profiles) routes to the `/secrets/bootstrap` wizard.

### Editing values / adding entries or sections (`EditSectionDialog`)
In **Edit Mode**, sections are edited **inline on `/secrets`** via a per-section modal
(`EditSectionDialog`) — the old "manual entry only" flow is gone:

- **Edit / Add Entry** on a section panel → `EditSectionAsync` opens the dialog with every leaf entry
  built from the **real (decrypted) values** (so saving doesn't clobber secrets with masks). Add Entry
  seeds one blank row (`StartWithNewEntry`).
- **Add Section** in the header → `AddSectionAsync` opens the dialog in **`CreateMode`**: the section
  **name** and the v2 descriptors (**category / description / includeInReplacements**) become editable.
  Category is picked from the known list (`KnownCategories`: Credentials, RestClient, RestKeys,
  ConnectionString, Url, Servers, Path, General, Other) or typed via a Custom toggle;
  `includeInReplacements` defaults to true.
- Rows are `SecretFieldEdit` objects: `Key` (colon-delimited leaf relative to the section's `values`,
  e.g. `Profisee:BaseUrl`), `Value`, `IsSecret` (password field + reveal toggle — set when the section's
  category is Credentials/RestKeys or the key looks secret), `IsNew` (key editable; written as a new
  leaf on save), `ShowValue`.
- The dialog returns a structured **`EditSectionResult`** (`Saved`, `Fields`, plus `IsCreate`,
  `SectionName`, `Category`, `Description`, `IncludeInReplacements` for create mode).
- **Validation (create mode)**: section name required + **unique** (case-insensitive vs existing
  top-level names), category + description required (the schema rejects sections without one), and
  **duplicate entry keys rejected** (case-insensitive). In both modes, entirely-empty new rows are
  silently dropped on save.
- On save the page writes edits back into the section's `values` block (`SetLeafValue` preserves
  nesting and the original scalar type), persists the profile, and reloads the masked panels. Create
  mode assembles a full v2 section (descriptors + `values`) via the `SecretSchema` field constants.

Bulk alternative: re-import an updated JSON through the bootstrap wizard's Step 3 (importing over an
existing machine+profile overwrites it — the UI warns first). Either way, **restart** to load changes
into `IConfiguration`; a new `RestClients:NewService:*` entry becomes available as
`IConfiguration["RestClients:NewService:BaseUrl"]`.

---

## Literal-or-Secret values in feature UIs (`SecretValueEditor`)

Step Parameters, HTTP headers/body, and similar single-value fields can be either a **Literal** or a
**Secret**, chosen with a small Literal/Secret toggle (`SecretValueEditor`). A "Secret" is stored as a
runtime token **`{{$config:Section:Item}}`** (resolved by `TextTemplater` at execution — *not* at import,
and *not* the same as the import-time `{{Section:Key}}` references in the secrets file).

- The mode is inferred from the value alone (`SecretValueRef.TryParse`/`Build`) — **no schema change**.
- The **Section** dropdown lists only `IncludeInReplacements == true` sections (`SecretCatalog.GetReplaceableSections()`);
  the **Entry** dropdown lists that section's leaf paths (`GetItems`, e.g. `Profisee:ApiKey`); a masked
  preview is shown via `GetMaskedValue`.
- Source: `TestAuto.Web/Components/Controls/SecretValueEditor.razor`, `Services/Secrets/SecretValueRef.cs`.

---

## Machine Profiles

| Profile Type | Code | When to Use |
|---|---|---|
| Development | D | Local development |
| Production | P | Production deployments |

Only one profile is active (`IsActive = Y`) per machine at a time. Switch via the Secrets UI.

---

## Switching Active Profile (Dev ↔ Prod)

Only one profile is active per machine at a time. To switch between Development and Production:

1. Navigate to `/secrets` (e.g., `https://localhost:7019/secrets`)
2. Select your machine from the **"Available Machines"** dropdown
3. Select the target profile from the **"Profile Type"** dropdown
4. Click **"Load"** to preview that profile's secrets
5. If it is not the active profile, click **"Set as Active"** → confirm the dialog
6. **Restart the application** — secrets reload from the newly active profile at startup
7. Verify: check the startup banner or click **Verify All** in the page header

> The previously active profile remains in `TestAutoSecrets` — it is not deleted, just deactivated.

---

## Switching ScenarioMgt Instance

When the ScenarioMgt Profisee instance changes:

1. Delete `master.json` from the application directory
2. Restart the application — the `/secrets/bootstrap` wizard appears
3. Re-run the wizard: master password → new ScenarioMgt REST URL + API key (+ Test Connection)
4. Import secrets for the new environment (wizard Step 3)

---

## Key Rotation

There is no "Change Master Password" UI yet. To rotate:

1. Export all secrets from the Secrets Management UI
2. Delete and re-bootstrap the machine with the new password
3. Re-import all secrets
4. Update `master.json` on each machine that uses this environment

---

## Troubleshooting

| Error | Cause | Solution |
|---|---|---|
| "Current machine has not been bootstrapped" | `master.json` not found | Run app → complete the `/secrets/bootstrap` wizard |
| "No active secrets profile found for machine" | No `IsActive = Y` record in TestAutoSecrets | Import a secrets JSON file for this machine |
| "Failed to decrypt secrets" | Master password mismatch | Verify password → re-import with correct password |
| Secrets not loading after import | Profile not marked active | Verify `IsActive = Y`; restart application |
| Startup banner shows secrets error | DB unavailable at startup | App continues in degraded state via `IAppStartupStatus` — check DB connection |
| `SECRETS FILE IS NOT VALID` (startup) / import rejected | A section is missing `category`/`description`/`includeInReplacements`, or a `{{Section:Key}}` token references a real section with an unknown key (typo) | Read the message — it names the section + field/token. Fix the JSON and re-import. |
| A `{{Section:Key}}` shows up literally in a stored value | The token was not resolved at import — its prefix is not a real section (so it was left alone) | Use a real `Section:Key` path; only known secret keys are resolved at import |

---

## Secret JSON Format (v2 — per-section metadata)

The file is an array with a single object; each top-level key is a **section**. Every section carries
**mandatory descriptors** inline plus a `values` block holding the actual key/value content. The loader
flattens only `values` under the section name (so `IConfiguration` keys are unchanged from the legacy
format) and exposes the descriptors under the reserved `SecretSectionMeta:` prefix.

```json
[
  {
    "ServerNames": {
      "category": "Servers",
      "description": "Server name values",
      "includeInReplacements": true,
      "values": {
        "ApplicationServerName": "CORPLTR94",
        "DatabaseServerName": "CORPLTR94",
        "InstrumentServerName": "CORPVM17"
      }
    },
    "RestKeys": {
      "category": "RestKeys",
      "description": "Profisee REST API keys",
      "includeInReplacements": true,
      "values": { "ProfiseeRestKey": "b9a3...", "ScenarioMgtRestKey": "06f7..." }
    },
    "RestClients": {
      "category": "RestClient",
      "description": "Profisee REST endpoints + API keys",
      "includeInReplacements": true,
      "values": {
        "Profisee": {
          "BaseUrl": "https://{{ServerNames:ApplicationServerName}}.corp.profisee.com/profisee/rest/",
          "ApiKey": "{{RestKeys:ProfiseeRestKey}}",
          "TimeoutSeconds": 600
        }
      }
    },
    "SQL Server Service Provider": {
      "category": "Credentials",
      "description": "Credentials for the SQL Server service provider",
      "includeInReplacements": true,
      "values": { "ConnectReadOnly": "..." }
    },
    "WebUI": {
      "category": "Other",
      "description": "Web host + certificate config",
      "includeInReplacements": false,
      "values": {
        "HostName": "{{ServerNames:ApplicationServerName}}.corp.profisee.com",
        "Certificate:Thumbprint": "ABC123...",
        "ExecutionMachine": "CORPLTR94"
      }
    }
  }
]
```

### Mandatory descriptors (every section)

| Field | Meaning |
|---|---|
| `category` | e.g. Credentials / RestClient / RestKeys / ConnectionString / Url / Servers / Path / General / Other. Drives page-by-category replacement binding and masking. |
| `description` | Human-readable; shown in the secrets UI and dropdown tooltips. |
| `includeInReplacements` | Hard global kill-switch. `false` = never offered for replacement anywhere, regardless of page config. |

A section missing any of these is **rejected at import** with a specific message; the startup loader logs a
clear `SECRETS FILE IS NOT VALID` error and starts in degraded state rather than crashing.

### Internal references — `{{Section:Key}}`

Values may reference other secret values with `{{Section:Key}}` (the `Section:subpath` to a leaf). These are
resolved **at import, before the file is stored**, so a shared value (server name, REST key) is edited in
exactly one place — see `{{ServerNames:ApplicationServerName}}` and `{{RestKeys:ProfiseeRestKey}}` above.

- Runtime tokens (`{{$config:...}}`, `{{$env:...}}`) and step tokens are **left untouched** — only known
  secret keys are replaced.
- A `{{Section:Key}}` whose `Section` is a real section but whose key does not exist is treated as a **typo
  and rejected at import** (e.g. `{{ServerNames:InstrumentServerNameServerName}}`).

### IConfiguration keys after loading

Values flatten under the section name — identical to the legacy format:
- `RestClients:Profisee:BaseUrl` / `:ApiKey`
- `ConnectionStrings:HangfireDB`
- `Profisee:CLU:Path` / `:ClientId`
- `WebUI:HostName` / `WebUI:Certificate:Thumbprint`
- `WebUI:ExecutionMachine` (auto-set to local machine name at startup)

Descriptors are exposed separately under `SecretSectionMeta:<Section>:Category|Description|IncludeInReplacements`
and read at runtime via `ISecretSectionRegistry` (feature code rarely touches these directly).

---

## Page-Scoped Replacement Dropdowns

Which sections feed a page's secret/replacement dropdowns is configured in **appsettings** under
`SecretReplacements:Pages`. A section appears on a page when `includeInReplacements == true` **and**
(its `category` is in the page's `Categories` OR its name is in the page's `Sections`):

```json
"SecretReplacements": {
  "Pages": {
    "ConnExServiceConfigImport":       { "Categories": [ "Credentials" ],               "Sections": [] },
    "ConnExIntegrationStrategyImport": { "Categories": [ "Credentials", "RestClient" ], "Sections": [] }
  }
}
```

New sections of an included category appear automatically (discovery stays dynamic). Page keys are defined in
`SecretReplacementPages`; `SecretCatalog.GetSectionsForPage(pageKey)` applies the rule, backed by
`ISecretSectionRegistry`.

---

## Storage Layer — `SecretStorageHelper`

The static, stateless `SecretStorageHelper` (`TestAuto.Shared.Security\Services\SecretStorageHelper.cs`)
is the encode/decode layer beneath the `TestAutoSecrets` entity — `MachineSecretService` calls it for
every load, save, export, and master-password rotation. Encryption itself is `ISecretEncryptionService`
(AES-256-CBC, PBKDF2/SHA256 key derivation from the master password).

### `EncryptCompressAndStore(Dictionary<string, object>, ISecretEncryptionService)` → `SecretData`
1. Serialize to JSON (`Formatting.None`); **pre-compression guard**: plaintext > 16000 chars throws
   (`MaxPlaintextLength = 16000`; Brotli typically compresses JSON 75–85%).
2. Brotli compress (`CompressionLevel.SmallestSize`) → Base64.
3. AES encrypt, prefix with **`ENC:BROTLI:`**.
4. **Post-encryption guard**: result > 4000 chars (the Profisee attribute limit) throws with a
   diagnostic message that includes plaintext/compressed/encrypted lengths and the compression ratio.
   Remedies: remove unused secrets, shorten values, split across machines.

### `LoadDecryptAndDecompress(string, ISecretEncryptionService)` → `Dictionary<string, object>`
- Accepts both **`ENC:BROTLI:`** and **legacy `ENC:GZIP:`** prefixes (GZIP is read-only legacy —
  every save re-writes as Brotli); any other prefix throws.
- Decrypt (a `CryptographicException` is wrapped as "Password may be incorrect or data may be
  corrupted") → decompress per the prefix → deserialize. Every failure surfaces as a specific
  `InvalidOperationException` — these are the messages behind the Troubleshooting table above.

### `GetDisplayText` → `SecretDataDisplay`
Decrypts, masks via the private recursive `MaskSensitiveValues` (walks nested dictionaries and
`JObject`s), serializes indented, and truncates to 4000 chars. Any failure returns
`"(Unable to decrypt/decompress)"` rather than throwing — the display column is best-effort.

**Masking rule**: a key is sensitive if it contains (case-insensitive) `apikey`, `password`, `pwd`,
`clientid`, `secret`, `token`, or `thumbprint`. Masked as first 3 + `*` + last 3 (values ≤ 6 chars
become all `*`; empty → `(empty)`). URLs, timeouts, paths, and other values pass through unmasked.

> Same prefix idea as the `configuration-compression-codec` skill's TemplateStorage, but with the
> added AES layer (`ENC:` prefix) — do not mix the two helpers.

---

## What's Encrypted vs Masked

| Data | Storage |
|---|---|
| `SecretData` attribute | AES-256 encrypted + Brotli compressed (`ENC:BROTLI:`; legacy `ENC:GZIP:` still readable) |
| `SecretDataDisplay` | Masked preview (API keys: `31d***08a`; passwords: `***`) |
| Machine names, profile types | Not sensitive — stored in plain text |
| `master.json` | DPAPI encrypted at **`DataProtectionScope.LocalMachine`** — bound to the *machine*, **not** the Windows user. Any account on that box can decrypt it; copying the file to another machine cannot (`MasterPasswordManager.cs:106,249,313,317,347,351`; class remarks at `:35`). |

## Sources

- `TestAuto.Web\Documentation\SecretManagement_UserGuide.md`
- `TestAuto.Web\Documentation\SecretManagement_SwitchProfiseeInstance.md`
- `TestAuto.Web\Documentation\11_DeveloperGuide.md`
- v2 schema: `TestAuto.Shared.Security\Services\SecretSchema.cs` (validate, flatten, `ResolveInternalReferences`, `ValidateInternalReferences`)
- Loader: `TestAuto.DependencyInjection\ServiceExtensions\RegisterAllServices.cs` (`LoadEntitySecrets`)
- Import/export + validation: `TestAuto.Shared.Security\Services\MachineSecretService.cs`
- Runtime metadata: `TestAuto.Web\Services\Secrets\SecretSectionRegistry.cs`, `SecretReplacementOptions.cs`
- Page-scoped replacements + masking: `TestAuto.Web\Services\ConnExTokenization\SecretCatalog.cs` (`GetSectionsForPage`, `GetReplaceableSections`, `GetItems`, `GetMaskedValue`); appsettings `SecretReplacements:Pages`
- **Primary bootstrap (browser redirect)**: `TestAuto.Web\Middleware\SecretsBootstrapMiddleware.cs` wired via `UseSecretsBootstrapRedirect()` in `TestAuto.Web\ServiceExtensions\PipelineExtensions.cs` (after `UseAntiforgery`)
- Console prompt (interactive launches only): `TestAuto.Web\Program.cs` (interactivity-gated) → `TestAuto.Web\Services\SecretSetupCommands.cs:17` (`RunInteractiveSetupAsync`)
- Bootstrap wizard: `TestAuto.Web\Components\Pages\SecretsBootstrap.razor`
- Restart affordance: `TestAuto.Web\Services\AppRestartService.cs` + `Components\Common\RestartAppButton.razor(.cs)`
- Store location: `TestAuto.Shared.Security\Services\MasterConfigPathResolver.cs` (env var → ProgramData(service) → APPDATA; legacy migration)
- DPAPI master password: `TestAuto.Shared.Security\Services\MasterPasswordManager.cs` (`DataProtectionScope.LocalMachine`)
- Secrets page: `TestAuto.Web\Components\Pages\SecretsManagement.razor(.cs)` (schema-driven panels, edit-mode gate, Verify All/Export/Backup All; `EditSectionAsync`/`AddSectionAsync`, `SetLeafValue`)
- Section edit/create dialog: `TestAuto.Web\Components\Controls\EditSectionDialog.razor(.cs)` (`SecretFieldEdit`, `EditSectionResult`, `KnownCategories`, create-mode validation)
- Storage layer: `TestAuto.Shared.Security\Services\SecretStorageHelper.cs` (`EncryptCompressAndStore`, `LoadDecryptAndDecompress`, `GetDisplayText`, masking, legacy GZIP read); encryption: `TestAuto.Shared.Security\Services\SecretEncryptionService.cs`
- Literal-or-secret editor: `TestAuto.Web\Components\Controls\SecretValueEditor.razor`, `Services\Secrets\SecretValueRef.cs`
- Plan: `99 Documentation\speed-merchants\planning\Plan_SecretsRestructure.md`
