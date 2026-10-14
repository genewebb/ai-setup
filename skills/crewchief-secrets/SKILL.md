---
name: crewchief-secrets
description: >
  CrewChief's files-only two-tier secret architecture (Encryption Secrets travel blob + Local Secrets
  store) — crypto constants, lockout, on-disk layout, config-source wiring, and CLI. Use when
  sealing/unsealing the portable RSA key, wiring a secrets page or test through SecretsHostContext
  (the named bundle holding the two type-indistinguishable ProtectedTextFile instances that ARE the
  objects configuration reads), importing/exporting a Local Secrets v2 store, diagnosing
  wrong-passphrase vs lockout, bootstrapping a fresh box, SecretsRootResolver precedence and the
  machine-shared store, DPAPI LocalMachine vs CurrentUser scope, or HTTPS certificate thumbprint
  resolution.
---

Repo: speed-merchants (paths below are repo-relative)

# CrewChief Secrets (Two-Tier, Files-Only)

CrewChief has NO database. Its secrets live in encrypted files in a **resolver-driven folder** (per-user `%APPDATA%\CrewChief` interactively, `%ProgramData%\CrewChief\secrets` as a Windows Service — see "Where the store lives" below), split into two independent tiers with **hard passphrase separation**:

| Tier (current name) | Purpose | Cipher | Portable? | Class |
| --- | --- | --- | --- | --- |
| **Encryption Secrets** (was "Tier-1") | Ship one shared secret (the Profisee RSA key) with every deployment; inert without a travel passphrase | AES-256-GCM + PBKDF2-SHA256 | YES (`sealed.json` is committed/shipped) | `SealedSecretService` |
| **Local Secrets** (was "Tier-2") | Files-only replacement for TestAuto's DB `TestAutoSecrets` entity; per-box install secrets | AES-256-CBC + Brotli | NO (gitignored, per box) | `LocalSecretStore` + `SecretEncryptionService` |

The "Tier-1/Tier-2" naming was renamed to "Encryption Secrets / Local Secrets" everywhere (code + docs + env vars); on-disk file format is unchanged. See memory [[project_crewchief_tier_rename]] and [[project_crewchief_secrets_shipped]].

## When to Use
- Sealing/unsealing the portable RSA key, or reasoning about the versioned sealed blob envelope.
- Importing, exporting, or reading a Local Secrets v2 store (esp. TestAuto interop).
- Diagnosing "wrong passphrase" vs tamper vs lockout, or a persisted lockout that survives restart.
- Bootstrapping a fresh box (`/secrets/bootstrap` redirect) or wiring the secrets `IConfigurationSource`s.
- Choosing/reading env vars `CREWCHIEF_MASTER_KEY` and `CREWCHIEF_LOCAL_SECRETS_MASTER`.

## Tier 1 — Encryption Secrets (portable seal)

`SealedSecretService` (`ISealedSecretService.Seal/Unseal`). All constants verified from source:

| Parameter | Value | Const |
| --- | --- | --- |
| Cipher | AES-256-GCM (`System.Security.Cryptography.AesGcm`) | — |
| KDF | PBKDF2-SHA256 (`Rfc2898DeriveBytes.Pbkdf2`) | — |
| Default iterations | **300,000** | `DefaultIterations` |
| Minimum iterations | **100,000** (rejected below, on seal AND unseal) | `MinIterations` |
| Salt | 16 bytes (128-bit), random per seal | `SaltSizeBytes` |
| GCM nonce | 12 bytes (96-bit), random per seal | `NonceSizeBytes` |
| GCM tag | 16 bytes (128-bit) | `TagSizeBytes` |
| AES key | 32 bytes (256-bit) | `KeySizeBytes` |
| Schema version | `"v1"` | `SchemaVersion` |
| KDF name | `"pbkdf2-sha256"` | `KdfName` |

**Envelope** (Newtonsoft JSON, `Formatting.Indented`, all binary fields Base64):
```json
{ "Version": "v1", "Kdf": "pbkdf2-sha256", "Iterations": 300000,
  "Salt": "...", "Nonce": "...", "Tag": "...", "Ciphertext": "..." }
```
Self-describing so KDF/params can evolve without breaking old blobs. A fresh random salt+nonce every `Seal`, so the same input never produces the same blob twice.

**Unseal validation** (in order): version must equal `"v1"` (Ordinal), KDF must equal `"pbkdf2-sha256"` (OrdinalIgnoreCase), declared `Iterations >= MinIterations`, Base64 fields decode, nonce/tag lengths + non-empty salt. Failures here throw `SealedSecretFormatException`.

**Exception taxonomy** (drives lockout policy):

| Exception | Meaning | Lockout event? |
| --- | --- | --- |
| `SealedSecretFormatException` | Structural: bad JSON, unknown version/KDF, bad Base64, low iteration count | **NO** |
| `SealedSecretAuthenticationException` | GCM `AuthenticationTagMismatchException` mapped up — wrong passphrase OR tampered blob (**indistinguishable by design**) | **YES** |
| `SealedSecretException` | Base type of both | — |

### Unlock / passphrase resolution (`SealedKeyManager`)
- Raw RSA key is handled only by `Seal` (central box). On deployed boxes only the sealed blob + resolved passphrase exist; the unsealed key lives solely in process memory.
- `Unlock(passphrase)`: `EnsureNotLockedOut` → separation check (does NOT count as a failed attempt) → unseal to validate → on `SealedSecretAuthenticationException` calls `RegisterFailure` and rethrows; on success `RegisterSuccess` then DPAPI-wraps the passphrase to `travel.json`.
- **Runtime resolution order** (`ResolvePassphrase`): DPAPI-wrapped local file → `CREWCHIEF_MASTER_KEY` env var → null.
- `TryResolveKey()` never throws (swallows `SealedSecretException`/`IOException`) — used by the startup config source.
- `IsSealed` = blob file exists; `IsUnlocked` = DPAPI file exists OR env var set.

### At-rest passphrase wrapping (`PassphraseProtector.cs`)
- `IPassphraseProtector` → `DpapiPassphraseProtector`: DPAPI (`ProtectedData`). **The scope is a ctor arg, NOT hard-wired to `CurrentUser`** — `DpapiPassphraseProtector(DataProtectionScope scope = DataProtectionScope.CurrentUser)`. Both composition roots pick the scope off the resolved store's `IsMachineShared` flag: `new DpapiPassphraseProtector(secretsRoot.IsMachineShared ? DataProtectionScope.LocalMachine : DataProtectionScope.CurrentUser)` (Web `Program.cs:41-43`, CLI `Program.cs:44-46`).
  - **`CurrentUser`** (per-user interactive default) — bound to the current Windows machine+user, so a copied deployment folder can't unwrap it.
  - **`LocalMachine`** (machine-shared store: any explicit `CrewChief:SecretsFolder`/`CREWCHIEF_SECRETS_FOLDER` override, or the `%ProgramData%` service default — i.e. `SecretsRootResolution.IsMachineShared == true`) — so the Windows-service host (SYSTEM) and an interactive admin CLI can unwrap the **same** `travel.json`/`master.json`. The weaker machine scope is compensated by the restrictive ACL the installer places on that folder.
- **Windows-only.** Off-Windows `DpapiPassphraseProtector` throws `PlatformNotSupportedException`; there is **no env fallback inside the protector**. The env-var fallback is applied at the *resolver* level (see wiring below and `SealedKeyManager`), not by the protector.
- `ProtectedTextFile` = one at-rest secret file (`Save`/`TryLoad`/`Delete`); `TryLoad` returns null on any `CryptographicException`/`IOException`/`PlatformNotSupportedException`.

## Tier 2 — Local Secrets (files-only, TestAuto byte-compatible)

`SecretEncryptionService` — **byte-identical to TestAuto v2** so an existing TestAuto v2 export imports directly (the load-bearing interop fact). Constants verified from source:

| Parameter | Value |
| --- | --- |
| Cipher | AES-256-CBC, `PaddingMode.PKCS7` |
| KDF | PBKDF2 `Rfc2898DeriveBytes`, **SHA256, 10,000 iterations** |
| Fixed salt | UTF-8 bytes of `"TestAutoSecrets.v1"` — *"reproduced verbatim from TestAuto … DO NOT change it"* |
| Key / IV | 32 bytes key + 16 bytes IV, both from the same derive |
| Min master password | **16 chars** (`MinPasswordLength`); rejected if whitespace-padded |

`SecretStorageHelper` — compression + storage codec:
- Format: `"ENC:BROTLI:"` prefix + Base64(AES(Base64(Brotli(JSON)))). Brotli `CompressionLevel.SmallestSize`.
- Legacy read: `"ENC:GZIP:"` (older TestAuto exports) still decoded.
- **4000-char guard**: post-encryption size check is authoritative for the DB path; a loose pre-compression fast-fail (`MaxPlaintextLength = 16000`). The files-only `LocalSecretStore` calls `EncryptCompressAndStore(..., enforceSizeLimit: false)` to **bypass the 4000 DB-attribute cap while keeping the byte format identical** — so the same blob still round-trips to/from TestAuto. (This mirrors why the DB path ever needed the cap — see memory [[reference_scenariodatadisplay_4000_ceiling]] and [[configuration-compression-codec]].)
- Masking (`GetDisplayText`, max 4000): keys whose lowercased name contains `apikey`/`password`/`pwd`/`clientid`/`secret`/`token`/`thumbprint` are masked (first 3 + stars + last 3; fully starred if ≤6 chars); non-sensitive values (URLs) shown.

### v2 schema (`SecretSchema`)
Each top-level section: `category` (required), `description` (required), `includeInReplacements` (required bool), `values` (required object). Reproduced byte-for-byte from TestAuto.
- `FlattenForConfiguration` → `Section:Key` value entries + `SecretSectionMeta:<Section>:Category|Description|IncludeInReplacements`. Leaf values are `.Trim()`-ed (paste artifacts like a trailing newline in an API key can't corrupt headers/URLs).
- **Internal references**: `ResolveInternalReferences` multi-pass (cap 10) resolves `{{Section:Key}}` against the file's own values, in place, before storage. Regex `\{\{\s*(?!\$)([^}]+?)\s*\}\}` deliberately leaves runtime tokens `{{$config:...}}` / `{{$env:...}}` untouched. `ValidateInternalReferences` flags a `{{Section:Key}}` whose section prefix is real but whose full key has no value.
- `SecretSchemaException` carries the specific `Errors` list.

### `LocalSecretStore`
- `Import(v2Json, master, profile?)`: accepts a bare v2 object OR a single-element array (PowerShell SecretStore export shape) → validate schema → validate internal refs → resolve refs → encrypt (`enforceSizeLimit:false`) → write `secrets.json` (profile default `"Local"`, `CurrentVersion = 1`).
- `Export(master)` returns a **single-element JSON array** (matches TestAuto's `ExportToJsonAsync` so an export re-imports elsewhere).
- `GetSections`/`GetStatus` (status needs no password).

### Console editing is a WHOLE-STORE rewrite (`SecretsManagement`)
There is no per-secret write API. Edit / Add Section / Add Entry / **Delete** all mutate the decrypted
`Dictionary<string, object>` held in memory during Edit Mode, then call `LocalSecretStore.Import` to
re-encrypt **everything** (`PersistDecryptedAsync`). Consequences worth knowing before touching this page:

- **Deleting the last section is refused** by the page: `SecretSchema.Validate` rejects a store with no
  sections (*"Secrets file contains no sections."*), so the re-import could never succeed. An **empty
  `values` block IS legal**, so a section may be emptied of every entry.
- **Entry deletes** come back from `EditSectionDialog` as `EditSectionResult.RemovedKeys` — queued and
  undoable inside the dialog, applied by the page **before** the writes. `EditSectionDialog.ProjectRemovedKeys`
  (pure static, directly testable) excludes any key that is simultaneously being re-written, and never
  reports a row added in the dialog. `SecretsManagement.RemoveLeafValue` prunes parent objects the removal
  emptied, so exports don't accumulate `"Group": {}`.
- **`Import` overwrites `secrets.json` with `File.WriteAllText`** — no backup, no temp-and-move (unlike
  `StepFileStore`). A deleted secret value is unrecoverable; the console tells the operator to Export first.
  Both delete paths **roll back the in-memory copy** when a persist fails, so the view keeps matching disk.
- **Testability seams**: `ConfirmAsync` and `OpenSectionDialogAsync` are `protected virtual` — bUnit can
  drive neither Radzen's confirm nor a Radzen modal (Radzen raises `OnClose` only for a dialog it opened).
  Subclass the page, as `SecretsSectionDeleteTests.TestableSecretsManagement` does.

## Cross-tier rules
- **Hard passphrase separation** (`PassphraseSeparationException`): the Encryption Secrets travel passphrase and the Local Secrets master password MUST differ. Enforced **both directions**: `SealedKeyManager.EnforceSeparation` (via the `localSecretsMasterResolver`) and `SecretsCommand.IsSameAsEncryptionSecretsPassphrase`.
- **Lockout** (`FileLockoutGuard : ILockoutGuard`), verified constants:
  - `MaxAttempts = 3` failures before the first lockout.
  - Base window **15 minutes** (`DefaultBaseLockout`); each successive lockout **doubles** the window (15m → 30m → 60m …) via `_baseLockout.Ticks * (1L << factor)`, `factor = Math.Min(LockoutCount, 20)` (overflow cap).
  - State persisted to `lockout.json` (per-scope failure count + `LockedUntilUtc` + `LockoutCount`); survives process/app restart.
  - **Fails CLOSED**: a corrupt/unreadable state file is treated as "no history" (never silently unlocks, never crashes the caller).
  - Scopes: `LockoutScopes.EncryptionSecrets = "encryptionsecrets"`, `LockoutScopes.LocalSecrets = "localsecrets"`.
- `IClock` (injectable; `SystemClock` = `DateTimeOffset.UtcNow`) makes escalation testable without real waiting.

## On-disk layout (`SecretsRootResolver` + `SecretsPaths`)
The store folder is **not** a fixed path — `SecretsRootResolver` (`CrewChief.Data\Secrets\SecretsRootResolver.cs`) resolves it with a 4-level precedence, so the location DOES depend on launch context:
1. `CrewChief:SecretsFolder` config value (if set), else
2. `CREWCHIEF_SECRETS_FOLDER` env var (if set), else
3. service default `%ProgramData%\CrewChief\secrets` (Windows Service context), else
4. interactive default `%APPDATA%\CrewChief` (per-user — note: NO `secrets` subfolder here).

`SecretsPaths` then composes the individual file names (below) **under the resolved folder**. The Web UI and CLI agree on the same files only because the installer unifies the location machine-wide (via the env var / config), not because the path is hard-coded.

`Resolve(...)` returns a `SecretsRootResolution { Folder, IsMachineShared }`. **Any explicit override (levels 1/2) AND the service default (level 3) set `IsMachineShared = true`; only the interactive per-user default (level 4) is `false`.** That flag is the single input that drives the DPAPI scope choice above (`LocalMachine` when shared, `CurrentUser` when per-user) — a machine-shared store MUST use `LocalMachine` so SYSTEM (service) and the admin CLI can unwrap the same `travel.json`/`master.json`.

| File | Purpose | Shippable? |
| --- | --- | --- |
| `sealed.json` | Portable Encryption Secrets sealed blob | **YES** |
| `travel.json` | DPAPI-wrapped travel passphrase | no (per box, gitignored) |
| `secrets.json` | Local Secrets store | no (gitignored) |
| `master.json` | DPAPI-wrapped Local Secrets master | no (gitignored) |
| `lockout.json` | Persisted lockout state | no |

## Wiring (`CrewChief.Web/Program.cs`)
Two custom `IConfigurationSource`s are added to `builder.Configuration`, both **fail-open** at startup (contribute nothing rather than crash):
- `EncryptionSecretsUnsealConfigurationSource(() => sealedKeyManager.TryResolveKey())` — unseals the RSA key in memory and feeds it to BOTH `ApiKeyEncryptor.PublicKeyConfigKey` and `PrivateKeyConfigKey` (the RSA private key XML carries public params, sufficient for encrypt+decrypt). Raw key never written to disk.
- `LocalSecretsConfigurationSource(localSecretStore, localSecretsMasterResolver)` — decrypts the store and flattens v2 sections into `IConfiguration` so `{{$config:Section:Item}}` resolves at runtime.
- `localSecretsMasterResolver = () => master.json (DPAPI) ?? CREWCHIEF_LOCAL_SECRETS_MASTER`.
- **Reload rebuilds `Data` (drops removed keys).** `LocalSecretsConfigurationProvider.Load()` **replaces** the whole `Data` map with a fresh `OrdinalIgnoreCase` dictionary on each successful load rather than additively writing keys — so a secret **removed** from the store since the last load actually disappears on reload (before this fix, deleting 2 of 5 `ServerNames` left all 5 resolving). The rebuild happens **only on the success path**; every early-return/`catch` leaves the existing `Data` intact, so a transient decrypt failure on reload never wipes live secrets (`SecretConfigurationSources.cs:~146-159`).
- **Direct reload seam — `LocalSecretsConfigurationSource.ReloadNow()`** (`SecretConfigurationSources.cs:~88`, delegates to the provider's `ReloadAndSignal()` at `~102`): re-runs `Load()` then fires the provider's change token (`OnReload()`) DIRECTLY, independent of `IConfigurationRoot.Reload()`. Exists because a source added to the minimal-hosting `ConfigurationManager` **after** `Build()` is not reliably re-run by `root.Reload()` — so the /secrets console Reload/Replace actions (`SecretsManagement.razor.cs:~808`, also `SecretsBootstrap.razor.cs:~351`) call `LocalSecretsSource?.ReloadNow()` to guarantee the step editor sees fresh secrets without an app restart. The source keeps a reference to the provider it builds (`_provider` set in `Build`) to make this possible; `ReloadNow` is a no-op if `Build` never ran.
- **Every keep-stale path in `Load()` logs a Serilog WARNING** (`SecretConfigurationSources.cs:~114-166`): store file missing, master resolver threw, master passphrase unresolved (empty file/env), store decrypted to 0 sections, and decrypt failure (wrong master / corrupt) each emit `Serilog.Log.Warning` saying secrets are being KEPT — previously these paths silently kept stale `Data` (the step editor read frozen startup secrets while /secrets showed fresh). At STARTUP these run before Serilog is configured so they're no-ops then; at reload Serilog is live and the outcome is visible. The success path logs an Information with section/key counts.
- `sealedKeyManager` env fallback var = `CREWCHIEF_MASTER_KEY`.

**Bootstrap middleware IS wired** — `CrewChief.Web\Program.cs:359 app.UseSecretsBootstrapRedirect()` (after `UseStaticFiles`/`UseAntiforgery`, before `MapRazorComponents` — exactly the placement the extension's doc-comment requires). `SecretsBootstrapMiddleware` redirects a never-bootstrapped box to `/secrets/bootstrap`; gate is `needsBootstrap = !store.Exists && !sealedKeyManager.IsUnlocked` (a completely fresh box only — partial setup is left to the pages, so no redirect loop). Bypasses `/secrets/bootstrap`, `/_framework`, `/_blazor`, `/_content`, `/css`, `/js`, `/lib` and static-asset extensions; only issues the redirect for HTML/`Accept`-less requests. **Contrast with TestAuto**, where the equivalent middleware is dormant/not wired — see [[secrets-bootstrap-middleware]] and memory [[project_secrets_bootstrap_middleware_not_wired]].

## "I could not look" ≠ "it is not there" — `SecretsAccessProbe`

Secrets-folder presence is a **three-state probe**, never a `File.Exists` boolean
(`CrewChief.Data/Secrets/SecretsAccessProbe.cs`):

| `SecretsAccessState` | Meaning | What the UI may offer |
|---|---|---|
| `Accessible` | Folder readable | Normal flow |
| `Missing` | Genuinely a fresh box | Bootstrap |
| `AccessDenied` | An ACL blocked the read | **Never bootstrap** — show remediation |

This distinction is the whole point. An ACL denial previously surfaced as `File.Exists == false`, which read
as "fresh box" — so the app cheerfully offered to **re-bootstrap over a perfectly healthy secret store**.
`SecretsAccessResult` therefore carries the probing process's **Windows identity** alongside the underlying
exception message (`IsAccessDenied`, `:47`), because the remediation is always "grant *this* account access
to *that* folder" and the operator cannot act without knowing which account asked.

Consumers: `SecretsBootstrap.razor.cs` (`:43`, `:84`, `:448`) converts an `UnauthorizedAccessException` into
an inline message instead of killing the Blazor circuit, and `SecretsBootstrapMiddleware` (`:75`) logs the
denial **once** rather than on every request. The same doctrine is repeated in
`ServiceAccountStatus.ErrorMessage` on the CLI side.

## Secret reveal is a circuit-scoped GRANT, not a per-component flag

`ISecretRevealSession` / `SecretRevealSession` (`CrewChief.Web/Services/Secrets/`) holds **one** grant state
per browser circuit — an opaque token in `sessionStorage`, a sliding expiry, and a `GrantChanged` event —
registered **Scoped** so one instance serves one circuit. It replaced per-component snapshots in
`SecretRevealToggle`, which desynchronised whenever several toggles shared a host flag.

Two rules worth stating outright:

1. **GRANT ≠ TOGGLE.** The grant is server-side *permission* to reveal; the toggle is per-visit
   *visibility*. A live grant still renders secrets **hidden** by default — re-entering a page never
   silently exposes values.
2. **One reveal flag per host page** (`Steps._dialogRevealSecrets`, `WorkloadEditor._revealSecrets`), owned
   by the host and read/written by the card, the page header, and every JSON pane — so a re-lock from any
   of them lands on the host's single confirm-then-defer handler.

## HTTPS certificate resolution (`CrewChief.Web/Program.cs`)
Kestrel binds HTTPS **only** when a real installed certificate resolves from a **dual-source thumbprint**, checked in this order (**secrets win**):
1. `Certificates:LocalHttpCertificateThumbprint` — from the loaded /secrets store (per-box, authoritative). This is why the cert thumbprint can be a Local Secret.
2. `WebUI:Certificate:Thumbprint` — from `appsettings.json` (shipped, often a placeholder).

Both are whitespace-normalized (`Replace(" ", "")`) into a candidate array `{ secrets, appsettings }`; each candidate is looked up in the **`LocalMachine\My`** store (`FindByThumbprint`, `validOnly:false`). A placeholder / stale / unknown value simply fails to match and falls through to the next candidate (`Program.cs:~98-145`).

**No dev-cert fallback.** If NEITHER thumbprint resolves to an installed cert, HTTPS is left unbound → CrewChief runs **HTTP-only**, logs a warning, and prints an **`ACTION REQUIRED`** console banner telling the operator to set the thumbprint in appsettings OR /secrets and point it at a cert in `LocalMachine\My` (`Program.cs:~150-167`, no-dev-cert comment `~177-178`). This is deliberate — a box never silently serves HTTPS with an untrusted ASP.NET dev cert.

## CLI (`CrewChief.Cli`)
Secrets are entered no-echo and are **never a command-line argument**. `IConsoleIo.ReadHidden` reads key-by-key with echo suppressed (falls back to a plain read when stdin is redirected); `ReadAllStdin` pipes a raw key in without echo.

| Command | Class | Notes |
| --- | --- | --- |
| `crewchief seal-secret` | `SealSecretCommand` | Reads raw key (stdin `--stdin` or no-echo prompt) + travel passphrase (entered twice). `MinPassphraseLength = 12`. Rejects passphrase == Local master (`PassphraseSeparationException`). |
| `crewchief unlock` | `UnlockCommand` | No-echo passphrase → validate by unseal → DPAPI-wrap. Maps `LockoutException`→`LockedOut`, auth failure→counted attempt, no blob→`NotUnlocked`. |
| `crewchief secrets import\|export\|status` | `SecretsCommand` | Import: master entered twice, must differ from travel passphrase, must match existing store, then DPAPI-wraps master (falls back to advising `CREWCHIEF_LOCAL_SECRETS_MASTER` if DPAPI unavailable). Honors `LockoutScopes.LocalSecrets`. |

## The Web composition root - SecretsHostContext

Secrets are **not** wired per-type in the Web host. `SecretsHostContext` is a **named bundle** carrying the
process-wide singletons: `SealedKeyManager`, `ILocalSecretStore`, `ILockoutGuard`, the deleter - **plus TWO
`ProtectedTextFile` instances that DI cannot tell apart by type.** That type-ambiguity is the reason the
bundle exists rather than a set of registrations.

The load-bearing detail: **those are the SAME objects wired into the startup `IConfiguration` sources.**
Which is why a change made in the UI becomes visible after `IConfigurationRoot.Reload()` - the store the
page wrote to and the store configuration reads from are one object, not two views.

**Any new secrets page or test goes through `SecretsHostContext`**, never by resolving the pieces
individually - resolving `ILocalSecretStore` alone gets you a store that is not the one configuration is
reading.

## Sources
- `CrewChief\CrewChief.Data\Secrets\SealedSecretService.cs`
- `CrewChief\CrewChief.Data\Secrets\SealedKeyManager.cs`
- `CrewChief\CrewChief.Data\Secrets\PassphraseProtector.cs`
- `CrewChief\CrewChief.Data\Secrets\LocalSecretStore.cs`
- `CrewChief\CrewChief.Data\Secrets\SecretEncryptionService.cs`
- `CrewChief\CrewChief.Data\Secrets\SecretStorageHelper.cs`
- `CrewChief\CrewChief.Data\Secrets\SecretSchema.cs`
- `CrewChief\CrewChief.Data\Secrets\LockoutGuard.cs`
- `CrewChief\CrewChief.Data\Secrets\IClock.cs`
- `CrewChief\CrewChief.Data\Secrets\SecretsPaths.cs`
- `CrewChief\CrewChief.Data\Secrets\SecretConfigurationSources.cs`
- `CrewChief\CrewChief.Web\Middleware\SecretsBootstrapMiddleware.cs`
- `CrewChief\CrewChief.Web\Components\Pages\SecretsManagement.razor.cs`
- `CrewChief\CrewChief.Web\Components\Pages\SecretsBootstrap.razor.cs`
- `CrewChief\CrewChief.Web\Program.cs`
- `CrewChief\CrewChief.Cli\IConsoleIo.cs`
- `CrewChief\CrewChief.Cli\Commands\SealSecretCommand.cs`
- `CrewChief\CrewChief.Cli\Commands\UnlockCommand.cs`
- `CrewChief\CrewChief.Cli\Commands\SecretsCommand.cs`

## Related
- [[testauto-secrets-management]] — the DB-backed predecessor CrewChief replaces.
- [[secrets-bootstrap-middleware]] — TestAuto's (dormant) equivalent middleware.
- [[configuration-compression-codec]] — the shared BROTLI/GZIP codec lineage.
- [[crewchief-reference-data]] — sibling files-only KV subsystem.
- Memory: [[project_crewchief_secrets_shipped]], [[project_crewchief_tier_rename]], [[project_secrets_bootstrap_middleware_not_wired]].
