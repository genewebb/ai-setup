---
name: project_crewchief_remote_boxprep_transport
description: CrewChief remote box-prep transport (DefaultRemoteCommandRunner) shipped & proven vs SMVM2; the auth/transport gotchas
metadata: 
  node_type: memory
  type: project
  originSessionId: 08e95719-a0d7-4939-83f7-2163348e1d0b
  modified: 2026-07-21T02:32:32.438Z
---

Remote Install/Configure/Uninstall on a non-local `TargetComputer` runs over PowerShell Remoting via `DefaultRemoteCommandRunner` (CrewChief.Engine\Executors) — a **shell-out to `powershell.exe`, NOT the PowerShell SDK**. Proven end-to-end vs SMVM2 (gated `RemoteLab` integration test passed 2026-07-19).

**UPDATE (committed 2026-07-20, commits 94f08cda/0931603b):** the credentialed transport now extends to **ServiceControl / AppPool / IisReset** too — the old "only the installer family is credentialed; the service family always runs as the ambient process identity" model is superseded. Every remote step now has three routing modes: **local** (local runner, credential ignored) / **credentialed-remote** (WSMan as the resolved credential — works under the LocalSystem service; service/app-pool/IIS ops build their inner op-script via the new pure `RemoteWindowsOps` helper) / **legacy-remote-no-credential** (installer family FAILS; service family falls back to `ServiceController(name,machine)`/`ServerManager.OpenRemote`/`iisreset computername` as process identity + logs a warning — typically fails under LocalSystem). Resolver now also unwraps the `{{$config:...}}` picker form and normalizes a `:User`/`:Password` leaf to its parent. New gated test `CredentialedRemoteOpsIntegrationTests` (Spooler Stop→Start roundtrip). Canonical detail lives in skill [[crewchief-remote-box-prep]].

Hard-won gotchas (each surfaced only when testing against a real box):
- **Auth = explicit stored credential over Kerberos.** The runner resolves the target to its **FQDN** (short-name Kerberos fails with 0x80090311). `credentialSecretName` resolves `{name}:User`/`{name}:Password` from the flattened secret store (`DefaultRemoteCredentialResolver`). A local target (blank/`.`/`localhost`/own hostname/FQDN) runs under the process identity, no credential.
- **Script delivery = `-EncodedCommand`** (base64 UTF-16LE), NOT `-Command -`/stdin — feeding a multi-line/scriptblock/`$using:` script over stdin silently drops its output ("Remote transport returned no parseable result").
- **PSModulePath restore** is the first driver-script line (`$PSHOME\Modules;` + machine PSModulePath) — a `powershell.exe` spawned from a .NET host inherits a stripped PSModulePath, so `ConvertTo-SecureString`/core cmdlet modules fail to auto-load.
- **MSI staging over the session:** a local/mapped/UNC file is read on the CrewChief host and streamed to a remote temp dir via `Copy-Item -ToSession` (no double-hop), installed, cleaned up. `RemoteRunRequest.StageFiles` drives it; runner rewrites the arg to the staged path.
- Bounded pre-flight TCP check on 5985; failures map to `RemoteRunResult.ErrorMessage` (never throws); `NotWiredRemoteCommandRunner` is the inert fallback.
- Gated test: `[TestCategory("RemoteLab")]` reads `CREWCHIEF_REMOTE_TEST_HOST`/`_USER`/`_PW` (or `integrationsettings.local.json`); `Assert.Inconclusive` when unset so CI stays green.

Lab host = **SMVM2** (10.0.0.7, corp.profisee.com domain); admin cred `corp\qaautomation`; the CrewChief host must reach a KDC + the target. See [[project_crewchief_secrets_shipped]], [[project_crewchief_reference_pickers]].
