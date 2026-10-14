---
name: project_crewchief_dropdb_connstring_guard
description: "CrewChief DB-ops now takes a plain serverName (trusted conn to master built for you); connectionSecretName demoted to optional advanced override. Plus the earlier cryptic-\"Format of the initialization string...index 0\" crash guards."
metadata: 
  node_type: memory
  type: project
  originSessionId: bc525bea-d92c-43f1-b02b-dd4de1184b90
  modified: 2026-07-22T20:11:54.409Z
---

## 2026-07-20 (follow-up) — serverName is now the primary target

The user pushed back: create/drop/backup/restore conceptually need only a **server + database name**,
not a full connection string — and the runner forces `InitialCatalog=master` anyway, so the connection
string's db is thrown away. Root design smell: the step was born as snapshot-restore ("inherently
remote, connection string decides the server"); create/drop/backup/restore were bolted on and inherited
the connection-string requirement.

Fix (chosen: Windows/trusted + optional secret override):
- `DatabaseOperationsStep.ServerName` (`serverName`) added; `HasTarget` = ServerName OR
  ConnectionSecretName. Validate/GetValidationError/CanExecute now require HasTarget.
- `DatabaseOperationsExecutor.ResolveTargetConnectionString`: secret override wins; else
  `BuildTrustedConnectionString(server)` → `Data Source=<server>;Initial Catalog=master;Integrated
  Security=True;TrustServerCertificate=True` (public static, connects as CrewChief identity — same
  running-identity model as IIS-reset/remote steps). Instance names NOT supported.
- `connectionSecretName` demoted to OPTIONAL advanced override (SQL logins/custom opts).
- Editor (StepEditorCard.razor DB-ops block): ServerNameEditor for ServerName (required); Connection
  moved under a `<details>` "Advanced: connection override".
- Tests: MissingConnectionSecret→renamed MissingTarget; +ServerNameOnly CanExecute,
  +BuildsTrustedConnectionToMaster, +ConnectionSecretOverridesServerName, +BuildTrustedConnectionString_BlankServer.
  Full unit suite 1323 green; clean solution build.
- Docs: 21_StepGuideDatabaseOperations.md reworked (serverName primary, override advanced, +troubleshooting).
- NOTE: the CrewChief identity needs dbcreator/ALTER ANY DATABASE on the remote box for trusted mode.

## 2026-07-22 — SetApiKeyStep adopted the same connection model

User: "treat it like we do the sql connection in other places." `SetApiKeyStep` gained
`serverName` + `databaseName` + `authMode` (Windows default / Sql) + `credentialUserId`/`credentialPassword`
(+ UsesSqlAuth/HasCredential/HasTarget mirroring DatabaseOperationsStep); the old
`sqlDestinationConnectionSecretName` is demoted to the Advanced connection override (wins when set —
back-compat with saved steps). The DB-ops builders gained an optional `initialCatalog` param
(default "master"; SetApiKey passes the Profisee database). Windows auth + explicit credential →
`WindowsImpersonation.RunAsAsync` around the UPDATE, same as DB-ops. Orchestrator SetApiKey case now
delegates to `step.GetValidationError()`. Editor: ServerNameEditor + database input + the
RadzenSwitch Windows/SQL auth block + credentials pair + `<details>` override — mirrors the DB-ops
block; Username/Key/override all use the UNRESTRICTED three-mode SecretValueEditor (SecretOnly dropped).
NOTE: a plain-text value in the override is a legacy secret NAME (ConnectionStrings/alias lookup),
NEVER a raw connection string (`SetApiKeyExecutor.ResolveConnectionString` — only `{{...}}` tokens
resolve to the string itself).

**SetApiKey operational truths (verified live SMVM3 2026-07-22):** (1) the new key takes effect ONLY
after restarting the Profisee (Maestro) service and/or IIS — the auth cache lives in BOTH; compose
ServiceControl/IisReset/AppPool steps after SetApiKey. (2) The raw UPDATE touches only `ClientId` —
`LastChgDTM`/`LastChgUserID` NEVER change, so they cannot be used to check whether the step ran; the
reliable check is that the stored blob CHANGES on every successful write (randomized PKCS#1 padding),
even re-setting the same key. (3) The step output/logs now include the resolved destination as
"on <server>/<database>" (`SetApiKeyExecutor.DescribeDestination` — never the raw connection string).

## Original (guards) — still in place

2026-07-20: CrewChief DatabaseOperations DROP/CREATE DATABASE for a remote DB crashed with
`Format of the initialization string does not conform to specification starting at index 0`.
Root cause: the user pointed `ConnectionSecretName` at a secret that resolved to a **bare database
name** (non-empty, malformed) instead of a full ADO.NET connection string. `ResolveConnectionString`
succeeded (secret found), then `new SqlConnectionStringBuilder(value)` in the runner threw the cryptic
parse error. (An *unknown* secret already threw a clear "Connection string not found for secret name..."
message — that path was fine; the crash was the *malformed-but-present* case.)

Fix (both in CrewChief.Engine.Executors):
- `IDatabaseCommandRunner.cs` `DefaultDatabaseCommandRunner.RunMasterCommandAsync`: wrapped the
  `SqlConnectionStringBuilder` construction in try/catch → `Succeeded=false`,
  ErrorMessage = "The connection string is not a valid ADO.NET connection string: {ex.Message}".
  This is the guard that fixes the user's exact error.
- `DatabaseOperationsExecutor.cs`: after `ResolveConnectionString`, an empty-string guard fails with a
  message naming the `ConnectionSecretName` and explaining a bare db name is not a connection string
  (secondary safety for the resolve-to-empty case).

Regression test: `DatabaseOperationsExecutorTests.RunMasterCommand_MalformedConnectionString_FailsClearly_NoCrypticThrow`
drives `DefaultDatabaseCommandRunner` with connectionString "SomeRemoteDatabaseName" and asserts the
actionable message (no SQL connection needed — the parse fails first). Full unit suite: 1319 green.
Related: [[project_crewchief_standalone]].
