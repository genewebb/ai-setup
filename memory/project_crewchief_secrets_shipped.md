---
name: project_crewchief_secrets_shipped
description: "CrewChief SetApiKey step + two-tier sealed-secrets subsystem shipped 2026-07-16 (design, mechanics, how to run)"
metadata: 
  node_type: memory
  type: project
  originSessionId: 7f76139b-3f09-411a-ba87-88ab6d9b2e03
---

Shipped in CrewChief (C:\devops\repos\speed-merchants\CrewChief) on 2026-07-16. Final: build 0/0, unit 1162/1162, integration 24/24 (SQL-gated now run against CORPLTR94/tempdb via gitignored integrationsettings.local.json). Design docs in Obsidian planning\CrewChief\ (2026-07-16-setapikey-step-design.md, 2026-07-16-sealed-secrets-design.md).

**SetApiKey step**: sets a user's encrypted Profisee ClientId. Params Username/Key/SqlDestinationConnectionSecretName/StripHyphens(default true). Reproduces the platform RSA (utilities\Utilities.Security\Security\Encryption.cs: 1024-bit RSA, PKCS#1 v1.5, UTF-16, 100-byte batches, base64) from CONFIG keys (CrewChief:ApiKeyEncryption:PublicKeyXml/PrivateKeyXml), does parameterized `UPDATE meta.tUser SET ClientId=@enc WHERE Name=@user`, 0 rows→"user not found". ApiKeyEncryptor in CrewChief.Engine\Services.

**Sealed secrets (two tiers, TWO different passphrases — enforced distinct)**:
- Tier-1 travel (the shared RSA key): AES-256-GCM + high PBKDF2, portable blob (secrets.sealed.json), dedicated passphrase from 1Password. First run per box: `crewchief unlock` (no-echo prompt) validates + DPAPI-wraps the passphrase locally (secrets.passphrase.dpapi) → unattended after. `crewchief seal-secret` = central seal (raw key via stdin, never a CLI arg). SealedKeyManager/SealedSecretService.
- Tier-2 local install secrets (connection strings etc.): TestAuto-compatible — reproduced SecretEncryptionService (AES-256-CBC+PBKDF2), SecretStorageHelper (ENC:BROTLI:), v2 section JSON (category/description/includeInReplacements+values, {{Section:Key}} import-refs), DB→local file (secrets.tier2.json), same master password as TestAuto. LocalSecretStore + SecretConfigurationSources feed IConfiguration; {{$config:Section:Item}} resolves via TextTemplater.
- Lockout: 3 fails→persisted timed lockout (secrets.lockout.json), both tiers. FileLockoutGuard.
- Web: /secrets/bootstrap wizard + SecretsBootstrapMiddleware, /secrets management console (view/edit/verify/export, master-password edit gate), SecretValueEditor literal/secret toggle in StepEditorCard (ConnEx ApiKey/MapShare Password/SetApiKey Key). CLI Program + Web Program both wire the two config sources.
- Never-commit rule enforced: only placeholders in committed files; real key/secrets only in gitignored local files (secrets.local.json, secrets.*.dpapi/json/sealed). Verified: zero real-key fragments in tree.

All in CrewChief.Data\Secrets (backend, shared by Web+CLI) + CrewChief.Web (UI). Self-contained (zero TestAuto refs, reproduced). Only added package: System.Security.Cryptography.ProtectedData (DPAPI). Relates to [[project_crewchief_review_2026-07-16]], [[feedback_workflow_parallelizes_agents]], [[project_crewchief_standalone]].

**UPDATE (later 2026-07-16) — secrets storage reworked to match TestAuto + UI-first:**
- **All encrypted files now live per-user under `%APPDATA%\CrewChief\`** (NOT under the data folder — that was the original design miss causing Web/CLI divergence). SecretsPaths is constructed in both Program.cs as `new SecretsPaths(Environment.GetFolderPath(ApplicationData), "CrewChief")`, so location is fixed regardless of content root / --data-folder → Web and CLI inherently share the same files.
- **TestAuto-style names**: `master.json` (Tier-2 master, DPAPI), `secrets.json` (Tier-2 store), `sealed.json` (Tier-1 RSA blob), `travel.json` (Tier-1 passphrase, DPAPI), `lockout.json`. (Renamed from the old secrets.*.dpapi/secrets.tier2.json scheme.)
- **Web UI can now SEAL the RSA key** (not just unlock): SecretsBootstrap Step 3 branches on IsSealed → "Set up the RSA key" form (paste key XML + travel passphrase → Seal+Unlock) OR unlock. So import (Tier-2) + seal + unlock (Tier-1) are all in the UI.
- **RSA key is NOT in secrets.local.json** — sample files had the ApiKeyEncryption placeholders removed. Key is sealed in %APPDATA%\CrewChief\sealed.json (config fallback still honored if set).
- **No secrets needed to run the app or manage secrets** (sources fail open; bootstrap redirect). Only running a secret-using step needs them.
- **Clear**: `dpcrewchief -ClearSecrets` wipes %APPDATA%\CrewChief\* (+ secrets.local.json); raw = `Remove-Item "$env:APPDATA\CrewChief\*" -Force`.
- **Profile**: `dpcrewchief --sealsecret` / `--unlock` (and -SealSecret/-Unlock) run the interactive CLI verbs; no --data-folder needed for secrets.
- **RunHistoryFile hardened**: added WithFileRetry (retry File.WriteAllText/Move/ReadAllText on transient IOException/UnauthorizedAccessException) — fixed the flaky TwoInstances_OverSameFile_InterleaveAppend test AND made concurrent Web+CLI runs.json writes robust; read path now only treats JsonException as corruption (transient IO no longer nukes history).
- Final: build 0/0, unit 1166/1166 (5x green). Detailed testing doc: in-app /help/operations/secrets-setup-and-testing (02_/35_/40_ docs refreshed to %APPDATA%). Runbook also in Obsidian 00 Credentials\CrewChief.md; profile cmds in 52 Technical\Powershell\MyProfileCommand.md.
