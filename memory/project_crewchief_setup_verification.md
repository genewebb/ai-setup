---
name: project_crewchief_setup_verification
description: "CrewChief \"Setup Verification\" page (/setup) — verifies remote-access (WinRM/Kerberos/CredSSP) prereqs + RSA API-key-encryption setup, with copy-paste remediation"
metadata: 
  node_type: memory
  type: project
  originSessionId: e25dbfb4-02af-4011-8c05-18e207b68e9c
  modified: 2026-07-23T16:23:45.640Z
---

New CrewChief.Web page **Setup Verification** (`SetupVerification.razor(.cs)`, `@page "/setup"`, nav item
"Setup Verification", icon `fact_check`), added 2026-07-23. Uncommitted; user rebuilds. Two read-only readiness
checks (nothing is mutated — it VERIFIES the setup the help pages document):

1. **Remote access** (per target machine) — `IRemoteAccessChecker`/`DefaultRemoteAccessChecker` (engine,
   `Executors/IRemoteAccessChecker.cs`) over the shared `IRemoteCommandRunner`. Checks: DNS→FQDN, WinRM TCP 5985
   reachable, PSRemoting session+auth, credential-is-local-admin, and (only if CredSSP selected) CredSSP server
   role. **All three auth mechanisms (Kerberos/Negotiate/CredSSP) are attempted sequentially in ONE run**, each
   a red/green light (`RemoteAccessCheckKind.Authentication`); no per-mechanism selecting-then-running.
   `RemoteAccessReport.Ready` = core checks (FQDN/WinRM/admin) all pass **and ≥1 auth green** (CredSSP red is
   fine unless you double-hop). Probe = `RemoteWindowsOps.BuildRemoteAccessProbeScript()` → JSON `{whoami,isAdmin}`;
   attempting the session with each mechanism IS the per-mechanism test (CredSSP green ⇒ both ends configured). Each failed check carries a copy-paste `RemoteAccessFix` (RunOn label + Commands/Note) sourced from —
   and kept in lockstep with — the Remote Box-Prep help page (`43_OpsRemoteBoxPrep.md` §4 WinRM / §5 CredSSP).
   Machine + Run As resolved design-time (`{{$config:...}}`→Configuration, `{{$ref:server-names:...}}`→ref store),
   reusing `ServerNameEditor` + `SecretValueEditor` + auth `SegmentedToggle`. DNS + reachability are
   `protected virtual` on the checker so it's unit-tested vs a fake runner (8 permutations + 2 probe tests).
2. **RSA / API-key encryption** (host-local) — `CheckRsa` probes `IApiKeyEncryptor.Encrypt`(+optional `Decrypt`
   round-trip) of a throwaway token; only the PUBLIC key (`CrewChief:ApiKeyEncryption:PublicKeyXml`, fed by the
   sealed Encryption Secrets) is needed for the SetApiKey step. On fail → points at `/secrets` +
   `/help/operations/sealed-secrets` + `/help/step-guides/set-api-key`. No interface change (reuses Encrypt/Decrypt).

DI: `IRemoteAccessChecker` registered in `EngineServiceCollectionExtensions` (mirrors the inventory/browser
registrations). Copy uses `navigator.clipboard.writeText` + Radzen `NotificationService` (matches StepEditorCard).
Icons from the whitelist (`fact_check`, `play_circle`, `check_circle`, `cancel`, `warning`, `content_copy`,
`refresh`, `key`/`sync_alt`/`lock`). 1527 unit tests green. Spec:
`99 Documentation\speed-merchants\planning\Design_CheckRemoteAccess.md`.
Related: [[project_crewchief_remote_boxprep_transport]], [[project_crewchief_share_credentials]], [[project_crewchief_secrets_shipped]].
