---
name: project_crewchief_secrets_store_delete_cli
description: "CrewChief CLI `secrets delete` (2026-08-20) — lost-master recovery hatch: backup-then-delete Local Secrets tier, optional Encryption Secrets tier, no password prompt, typed DELETE confirm"
metadata: 
  node_type: memory
  type: project
  originSessionId: 0574db30-900a-43b0-8394-14213cb9d03c
  modified: 2026-08-20T17:10:11.939Z
---

Shipped 2026-08-20 (rebooted mid-task, resumed from untracked test file): `crewchief secrets delete [--include-encryption-secrets]` — the recovery hatch for a store whose master password is lost (the SMVMTR2 lockout scenario). 3044 unit tests green.

Design decisions:
- **No password prompt, ever** — the operator lost it; box+console possession is the authority. `SecretsDelete_NeverAsksForAPassword` pins this via `FakeConsoleIo.HiddenReads == 0`.
- **Works while locked out** — an active `FileLockoutGuard` lockout must not block recovery; `lockout.json` is deleted with the store (delete IS the lockout clear).
- **Backup always taken first** (unlike the UI section-delete which took none): timestamped `backup-yyyyMMdd-HHmmss[-N]` folder INSIDE the secrets folder (inherits ACL; DPAPI files useless off-box anyway). Copy-all-then-delete-all ordering so a failed copy aborts before anything dies.
- Typed `DELETE` confirm (Ordinal); declined → `NotFoundOrValidation` (non-zero, scripts can detect); nothing-to-delete → `Success`, no prompt.
- Default scope: `secrets.json` + `master.json` + `lockout.json`. `--include-encryption-secrets` adds `sealed.json` + `travel.json`; flag rejected anywhere but `secrets delete` (same policy as `--local-system`).

Pieces: `CrewChief.Data\Secrets\LocalSecretStoreDeleter.cs` (core + `GetExistingFiles` pre-confirm query + `SecretStoreDeleteResult`), `SecretsCommand.ExecuteDelete` (ctor gained deleter param — 10 test ctor sites updated via replace_all), `CliArgs` (`IncludeEncryptionSecrets`, `ParseSecrets` delete case), `Program.cs` wiring with `SystemClock`.

Related: [[project_crewchief_secrets_delete]] (UI section/entry delete — different scope, no backup) · [[project_crewchief_secrets_shipped]] · [[reference_corpltr94_local_admin_cleanup_gpo]]
