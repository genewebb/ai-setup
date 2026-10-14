---
name: crewchief-remote-box-prep
description: >
  CrewChief's remote machine-setup transport and box-prep step family
  (Install/Uninstall/Configure/IisReset/ServiceControl/AppPool/WebSite). Use when authoring or debugging a
  box-prep step, targeting a remote machine, wiring DefaultRemoteCommandRunner PowerShell Remoting,
  resolving remote Run As credentials, choosing remoteAuthentication (Auto/Kerberos/Negotiate/CredSSP,
  double-hop), mounting a share inside the remote session, or diagnosing a remote step that failed
  silently.
---

Repo: speed-merchants (paths below are repo-relative)

# CrewChief Remote Box-Prep

CrewChief (standalone .NET 10, files-only, in `CrewChief\`) can prepare remote Windows machines: install/uninstall MSIs, run `Configuration.exe`, reset IIS, control Windows services, and bounce IIS app pools — locally or on a remote target. This skill covers the remote transport and the box-prep step family. For the general executor contract see [[crewchief-executor-pattern]]; for the other step executors see [[crewchief-step-executors]]; for how the RemoteLab test is gated see [[crewchief-testing]]. Cross-link memory [[project_crewchief_remote_boxprep_transport]].

## Reference files (load on demand)

This file carries the routing modes, transport rules, credential resolution, and the exact
failure messages. The catalogs live in `references/` and cost nothing until you read one.

| File | Read it when |
|---|---|
| `references/box-prep-steps.md` | Authoring or debugging one of the seven box-prep steps |
| `references/share-mount.md` | A remote step cannot reach a UNC path, or wiring share credentials |
| `references/op-scripts.md` | Changing what a remote op does, or a result parses wrong |
| `references/inventory-elevation-testing.md` | Product inventory, elevation readiness, or the RemoteLab tests |
| `references/sources.md` | You want the underlying source-file list |

## When to Use
- "How does CrewChief run an install on SMVM2 without the PowerShell SDK?"
- "My remote Configure step says it 'requires Run As credentials' — which fields do I set?"
- "Why does a remote install return an error message instead of throwing?"
- "Does ServiceControl/AppPool/IisReset need a credential like Install does?"
- "What counts as a local target vs. a remote one?" (short name vs. FQDN vs. an IP)
- "The remote install can't read the MSI off `<share>` — how do I get the share credential onto the target?" (ShareMount / `CC_SHARE_*`)
- "Where's the reboot-pending (3010) handled as success?"
- "Remote Configuration.exe fails with 'Login failed for user NT AUTHORITY\ANONYMOUS LOGON' against SQL — why?" (double-hop → CredSSP)
- "Remote Configuration.exe NREs in LoadConfig/writeServiceConfig — why does the working directory matter?"
- "A token resolving to 'Default Web Site' got split into three arguments — where's the resolve-before-quote rule?"
- "Remote Browse on a typed drive-letter path fails with 'A parameter cannot be found that matches parameter name Directory' or 'Path not found from this remote session' — how does the Drive Map letter→UNC translation work?"

## Three routing modes — every box-prep step follows the same axes

## Operator prep — `Enable-CrewChiefRemoteManagement.ps1` and the `/setup-verification` page

`CrewChief/installer/Enable-CrewChiefRemoteManagement.ps1` is a shipped, first-class operator tool with a
**Host / Target role split** and an `Invoke-Step -Test / -Fix / -FixHint / -WarnOnly` + `New-Probe` verdict
framework.

> [!tip] The CredSSP diagnostic no other doc covers
> **Both CredSSP roles can be configured correctly and delegation still refuses**, because the target has no
> `WSMAN/<fqdn>` **service principal name**. The first hop's Kerberos accepts a `HOST/` ticket; CredSSP does
> not. WinRM misreports this as *"a computer policy does not allow the delegation"*, which sends operators
> to Group Policy for a problem that lives in AD.
> The script probes it with `klist.exe get WSMAN/<target>` (`:483-488`) and deliberately offers **no `-Fix`**
> — the remedy is an AD write, which CrewChief has no business performing. See memory
> [[reference_corpsql03_missing_wsman_spn]].

### The logon-attempt budget on `/setup-verification`

Site policy locks an account after **3 consecutive bad attempts with no time-based reset**, so the
verification page rations logon attempts rather than retrying freely
(`CrewChief.Web/Components/Pages/SetupVerification.razor.cs`):

- `RunCheckAsync()` defaults to `confirmedRetry: false` (`:115`) and **refuses to spend another attempt**.
- `ConfirmRetryAsync()` (`:127`) is the **only** path passing `confirmedRetry: true`, shown to the operator
  with the used-attempt count in front of them. There is no third path.
- The reset is deliberately **two-step**: `ArmReset()` (`:134`) then `ResetLogonBudget()` (`:161`). A single
  flag would collapse it into the one-click reset the feature exists to prevent.

> [!warning] The reset clears the tally for `_reportCredential`, NOT the credential in the form
> `ResetLogonBudget` uses the credential **the on-screen report was produced for** (`:55`, `:168`), never a
> re-resolution of the current `_user`/`_password` fields. Re-resolving at press time asserted a green
> result about a credential CrewChief held no tally for, while the real tally survived untouched.

## Routing — `BoxPrepRouting.Decide` returns one of FIVE routes

Transport selection is an explicit decision, not an if/else scattered across executors.
`BoxPrepRouting.Decide` (`CrewChief.Engine/Executors/BoxPrepRouting.cs:13`) returns a
`BoxPrepRouteDecision` (route + machine name + credential), and `BoxPrepCommandRunner` dispatches it over
the two transports.

| Route | When | Mechanism |
|---|---|---|
| `LocalDirect` | Local target, no Run-As credential | The step's own local seam (`IServiceControlRunner`, `IAppPoolRunner`, `IProcessRunner`, `IProductInstallRunner`, `IProductUninstallRunner`) as the CrewChief process identity |
| `CredentialedRemote` | **Remote** target **with** a resolvable credential — and only that | `IRemoteCommandRunner` PowerShell Remoting / WSMan |
| `LocalRunAs` | **Local** target **with** a resolvable Run-As credential | `ILocalRunAsCommandRunner` — a direct **in-process local logon**, no network hop |
| `LegacyRpc` | Remote target, **no** credential | ServiceControl / AppPool / IisReset fall back to ambient-identity RPC; **Install / Uninstall / Configure reject instead** |
| `RunAsUnresolved` | Local target whose Run-As fields **are** configured but do **not** resolve | **The step is REJECTED** (`BoxPrepRouteDecision.RejectionReason`) |

> [!important] `LocalRunAs` replaced a WinRM loopback, and the reason is worth knowing
> An earlier phase routed a credentialed *local* step through `CredentialedRemote` against the machine's own
> FQDN, reusing the shipped transport for free. **It does not work on a default Windows box**: Windows
> blocks credentialed authentication to itself unless `DisableLoopbackCheck`, `BackConnectionHostNames` or
> `LocalAccountTokenFilterPolicy` is set — none of which is set out of the box. Every mechanism returned
> *"Access is denied"* against a target that was the host itself, and because a **Failed `RemoteWinRm`
> verdict hard-blocks the run** ([[crewchief-capability-preflight]]), local Run-As became *unreachable*
> rather than merely slow.
>
> A local logon has no network leg for the restriction to apply to, needs no per-host registry relaxation,
> and keeps the Run-As password inside this process instead of handing it to a child `powershell.exe`.

> [!danger] A half-filled local Run-As is REJECTED, never silently downgraded
> `RunAsUnresolved` covers a half-filled User ID/Password pair, or a credential secret that is missing,
> misspelled, or locked. Continuing on the direct local path would run the operator's administrative action
> as the **CrewChief service identity** instead of the account they named — a silent identity substitution
> that is either an escalation (service is admin, Run-As is not) or a confusing access-denied further down
> (on a deliberately non-admin service box). Remote Install/Uninstall/Configure has always rejected exactly
> this misconfiguration, and an unresolvable `{{token}}` in the same field already fails the step out of
> `TextTemplater` — local Run-As is now consistent with both. `continueOnError` remains the explicit,
> per-step escape hatch: the point is that ignoring it is a **decision the author records**, not a default
> the operator never sees.

> Historical note: an earlier design split the box-prep steps into "installer family = credentialed WSMan" vs "service family = ambient-identity RPC." That is **no longer true** — as of the credentialed-remote-ops change, **all seven steps accept an optional Run As credential** (the `credentialUserId`/`credentialPassword` pair, or the legacy `credentialSecretName`) and can run over the credentialed WSMan transport. Routing is now decided by two axes on every step, not by step family.

Each executor computes:
- `machine = IsLocalTarget(resolvedTarget) ? null : resolvedTarget`
- `credential = (machine != null) ? resolver.Resolve(ApplyTokens(credentialUserId), ApplyTokens(credentialPassword)) ?? resolver.Resolve(ApplyTokens(credentialSecretName)) : null` — the explicit two-field Run As pair is PREFERRED; the flattened secret name is the fallback for older saved steps (verified identical in all six executors: `ConfigureExecutor.cs:233-234`, `InstallExecutor.cs:236-237`, `UninstallExecutor.cs:253-254`, `ServiceControlExecutor.cs:152-153`, `AppPoolExecutor.cs:161-162`, `IisResetExecutor.cs:128-129`)

…which yields three modes:

1. **Local** — target is blank/`.`/`localhost`/`127.0.0.1`/machine-name → the existing local runner (`ServiceController(name)`, local `ServerManager`, local `iisreset`, `IProduct*`/`IProcessRunner`). **A credential is ignored even when set** (verified: `ServiceControlExecutorTests.ExecuteAsync_LocalWithCredential_UsesLocalRunner_IgnoresCredential`).
2. **Credentialed remote** (recommended) — remote target **and** a resolvable credential → runs over `IRemoteCommandRunner` (PowerShell Remoting / WSMan) **as that credential**. Identity-independent, so it works even when CrewChief runs as the LocalSystem service. The service/app-pool/IIS ops build their inner op-script via [`RemoteWindowsOps`](#the-op-script-layer--remotewindowsops); installer ops build an `msiexec`/`Configuration.exe` command.
3. **Legacy path** — remote target, **no** credential:
   - **Install / Uninstall / Configure**: FAIL immediately, never falling back to process identity. Both the validation and the runtime message now name BOTH credential forms — exact strings under **Remote credential resolution → "The two failure messages"** below.
   - **ServiceControl / AppPool / IisReset**: fall back to the ambient-identity path (`ServiceController(name, machine)` RPC / `ServerManager.OpenRemote(machine)` / `iisreset computername /flag`) as **whatever identity the CrewChief process runs as**, and log a warning (`ServiceControlExecutor.cs:~182`). This RPC/`ServerManager` path **typically fails under the LocalSystem service** — which is the whole reason the credentialed path was added.

| Step | Local runner | Credentialed remote (WSMan) | Legacy remote (no credential) | Run As credential |
|---|---|---|---|---|
| **Install / Uninstall / Configure** | `IProductInstallRunner` / `IProductUninstallRunner` / `IProcessRunner` | `msiexec` / `Configuration.exe` over WSMan as the credential | **fails** (required) | **required for remote** |
| **ServiceControl** | `ServiceController(name)` | `RemoteWindowsOps.BuildServiceControlScript` over WSMan | `ServiceController(name, machine)` RPC as process identity ⚠ | optional |
| **AppPool** | local `ServerManager` | `RemoteWindowsOps.BuildAppPoolControlScript` over WSMan | `ServerManager.OpenRemote(machine)` as process identity ⚠ | optional |
| **IisReset** | local `iisreset` | `iisreset /flag` run **ON** the target over WSMan (no computer arg) | `iisreset computername /flag` as process identity | optional |

## Local-vs-remote routing

Every box-prep step has a `TargetComputer`. The shared rule is **`MapShareExecutor.IsLocalTarget(target)`** (`MapShareExecutor.cs:296`) — every other executor is a one-line `public static bool IsLocalTarget(...) => MapShareExecutor.IsLocalTarget(...)` delegate, so there is exactly one implementation. Executors token-resolve `TargetComputer` first, then `var machine = IsLocalTarget(resolved) ? null : resolved;` — `null` runs the existing local path unchanged; non-null routes remote (then the credential axis picks WSMan vs. the legacy fallback).

**Callers must pass the RESOLVED value** (tokens already replaced). That is the point of the check: a portable step whose target is `{{$config:ServerNames:ApplicationServerName}}` can resolve to the very box CrewChief is running on, and must then be treated as local — no transport, no credentials.

The live matching logic (`MapShareExecutor.cs:262-307`) is richer than a fixed literal list:

- **Normalize**: trim, then `TrimStart('\\')` — so `\\SMVM2` and `SMVM2` are the same. Blank/whitespace (or a value that is nothing but backslashes) → **local**.
- **Exact set** (`OrdinalIgnoreCase`), built once and cached in a `Lazy<>`: the constants `"."`, `"localhost"`, `"127.0.0.1"`, `"::1"`, plus every discovered host identity — `Environment.MachineName`, `Dns.GetHostName()`, and `Dns.GetHostEntry(Dns.GetHostName()).HostName` (the FQDN). Both DNS lookups are best-effort in `try/catch`, so a machine with no DNS still matches on `MachineName`.
- **Short-label set**: the leading DNS label of each of those hosts (text before the first `.`). A target matches if EITHER its full value is in the exact set OR its own leading label is in the short-label set — so **short name matches FQDN and FQDN matches short name, in both directions** (`SMVM2` ↔ `smvm2.corp.example.com`).
- The `Lazy<>` cache exists because `IsLocalTarget` sits on hot paths — design-time enumeration in the editor as well as every run — and would otherwise do DNS per call.

Practical consequences: a target given as a **non-loopback IP address of the local box** is NOT recognized as local (only `127.0.0.1`/`::1` are), and any alias/CNAME that DNS doesn't return as the host entry's `HostName` also routes remote. Covered by `CrewChief.Tests.Unit\Engine\IsLocalTargetTests.cs`.

> `MapShareStep` itself is the one step that is **local-only**: a non-local `targetComputer` fails it outright with "MapShareStep does not support remote mapping (TargetComputer='…'). Run the engine on the target machine, or use a remote PowerShell step." (`MapShareExecutor.cs:101-106`). To get a share onto a *remote* target, use the `ShareMount` path below, not MapShareStep.

## The WSMan transport — `DefaultRemoteCommandRunner`

`Executors/DefaultRemoteCommandRunner.cs` implements `IRemoteCommandRunner` (`Executors/IRemoteCommandRunner.cs`). It runs a command on a remote Windows host over PowerShell Remoting by **shelling out to `powershell.exe`** — deliberately NOT taking an in-process `Microsoft.PowerShell.SDK` dependency. Reusing the shipped `powershell.exe` is what lets it pass the password as a child-process env var, control the module path, and stage files over the session.

Verified behaviors:
- **Password never on the command line.** All inputs go to the child via **environment variables** — `CC_REMOTE_HOST/USER/PW/EXE/ARGLINE/AUTH/WORKDIR/STAGEDIR/STAGE_JSON` (`DefaultRemoteCommandRunner.cs:157-165`) plus the three `CC_SHARE_*` vars below. Inside the driver the password builds a `PSCredential`, then `$env:CC_REMOTE_PW = ''` clears it.
- **Driver script passed as `-EncodedCommand`** (base64 of UTF-16LE), NOT over stdin. Stdin (`-Command -`) mishandles multi-line here-strings/`$using:` and silently drops output; `-EncodedCommand` runs the whole script as one opaque blob. Launched `-NoProfile -NonInteractive -ExecutionPolicy Bypass`.
- **Short-name → FQDN** (`ResolveHost`) via `Dns.GetHostEntry` so Kerberos can find the host SPN (short names fail Kerberos). A name already containing `.` is used as-is.
- **Bounded WinRM pre-flight**: a 5-second TCP check on port **5985** (`WinRmHttpPort`) fails fast ("not reachable on WinRM port 5985") instead of a long WSMan hang when the VPN is down / host offline.
- **`RemoteAuth` enum** (`Default`, `Negotiate`, `CredSSP`, **`Auto`**); `MapAuth` maps `Default → "Kerberos"` (the validated domain path), `Negotiate → "Negotiate"`, `CredSSP → "Credssp"` (opt-in double-hop, credential-exposing). `Auto` is appended **last** so the existing members keep their ordinal values, and is resolved per target by `RemoteAuthSelector` (below) — never sent to the transport as-is. See [remoteAuthentication](#remoteauthentication--credssp-the-double-hop-answer) for how a step picks the mechanism.
- **PSModulePath restore** inside the driver (`$PSHOME\Modules;` + machine `PSModulePath`) so remoting modules resolve.
- **File staging**: `RemoteRunRequest.StageFiles` (local path / mapped drive / UNC, read on the CrewChief host) are copied to a per-run temp dir `%SystemRoot%\Temp\crewchief_<guid>` via `Copy-Item -ToSession` over the SAME authenticated session (no double-hop); any staged path in `Executable`/`Arguments` is rewritten to the target-side location, and the temp dir is removed in `finally`.
- Remote process launched with a **splatted** `Start-Process -Wait -PassThru -NoNewWindow` (so a GUI-subsystem installer like `msiexec` is actually awaited and its exit code captured), stdout/stderr redirected to temp files and read back. The splat adds `-WorkingDirectory` only when `RemoteRunRequest.WorkingDirectory` is set (carried into the driver as `CC_REMOTE_WORKDIR`, `DefaultRemoteCommandRunner.cs:157` / driver ~374–377); unset means the session default.
- **Marker-wrapped JSON result**: the driver emits `===CCBEGIN===` / `===CCEND===` around a compact JSON object `{ ok, exit, out, err }`; `ExtractPayload`/`MapOutput` parse between the markers.
- **Success = exit `0` OR `3010`** (3010 = reboot pending, common for Windows installers).
- **Never throws**: null/blank request, missing credential, unreachable host, timeout, and transport exceptions are all mapped to a failed `RemoteRunResult` with `ErrorMessage` (timeout also sets `TimedOut`). The local timeout is `TimeoutSeconds + 60s` session overhead (or a 3600s fallback when unset).

`RemoteRunRequest` (init-only): `MachineName`, `Credential` (`RemoteCredential { User, Password }`), `Executable`, `Arguments` (`IReadOnlyList<string>`), `StageFiles`, `TimeoutSeconds`, `Auth` (default `RemoteAuth.Default`), `WorkingDirectory` (a path ON the target, or null for the session default), `ShareMount` (`IRemoteCommandRunner.cs:107`, null = no share injection). `RemoteRunResult`: `Succeeded`, `ExitCode`, `TimedOut`, `StandardOutput`, `StandardError`, `ErrorMessage`.

### `ShareMount` + the `CC_SHARE_*` env vars — the second-hop share wall

Full mechanics of mounting a share inside the remote session: the `CC_SHARE_*` variables,
the emitted `net use` statement and its exit-code check, and the failure modes:
**`references/share-mount.md`**.

Read it when a remote step cannot reach a UNC path, or when wiring share credentials.
The short version: a remote session gets no second hop to a share unless you mount it
explicitly or use CredSSP (below).

### `remoteAuthentication` + CredSSP (the double-hop answer)

All **seven** box-prep steps carry an optional **`remoteAuthentication`** string (token-replaced). Each executor threads it as `Auth = RemoteAuthParser.Parse(ApplyTokens(step.RemoteAuthentication, parameters))` (e.g. `ConfigureExecutor.cs:243`, `InstallExecutor.cs:252`, `UninstallExecutor.cs:273`, `ServiceControlExecutor.cs:176`, `AppPoolExecutor.cs:209`, `IisResetExecutor.cs:171`, plus `WebSiteExecutor`).

**`RemoteAuthParser`** (static, `IRemoteCommandRunner.cs:52`): `Parse` (`:63`) is case-insensitive and fail-safe — `"negotiate" → Negotiate`, `"credssp" → CredSSP`, `"auto" → Auto`, and **everything else** (null/blank/`"Default"`/`"kerberos"`/unknown) → `Default` (the proven Kerberos path), so an old or hand-edited step never breaks on this field. Its `Names` list (`:59`) is **`Auto`, `Default`, `Negotiate`, `CredSSP`** — `Auto` first because that is what a new step is created with, and `Default` keeps its own entry because choosing Kerberos-only deliberately is a legitimate, stricter answer rather than merely the absence of a choice.

> [!important] `Auto` is opt-in by VALUE, never by omission
> A blank `remoteAuthentication` still parses to `RemoteAuth.Default` (Kerberos-only), exactly as before `Auto` existed — so **no saved or shipped step changed behaviour** when this option landed. New steps get the literal string `"Auto"` from `StepTypeRegistry.CreateStepForAuthoring`; making blank *mean* Auto would have silently re-authenticated every existing remote step.
> All seven box-prep editors now render `RemoteAuthParser.Names` / `PickerValue` / `PickerLabel` directly (`StepEditorCard.razor.cs:101`) instead of hard-coding `<option>` lists. The old hard-coded lists rendered Kerberos-only as `value=""` and offered no option for the literal `"Default"`/`"Kerberos"` the parser accepts — so once `Auto` took index 0, a step that actually runs Kerberos-only displayed as "Auto".

**`RemoteAuthSelector`** resolves `Auto` per target from a `RemoteTargetShape` (Blank / Local / Unresolved-token / IpAddress / ShortName / Fqdn) crossed with the host's domain membership — read via the `NetGetJoinInformation` P/Invoke, **not** `Environment.UserDomainName` (which reports a value on a workgroup box too). Kerberos for an FQDN from a domain-joined host, Negotiate for an IP address / short NetBIOS name / non-domain host, and **never CredSSP** — Auto will not silently opt you into credential exposure.

**CredSSP is the double-hop answer for the WinRM path.** The classic case: a remote `Configuration.exe` opens a Windows-auth SQL connection to a THIRD machine — Kerberos won't delegate the Run As identity onward, so SQL sees the symptom `Login failed for user 'NT AUTHORITY\ANONYMOUS LOGON'`. Machine setup (one-time, per machine pair — each role goes on a **DIFFERENT** machine; running both commands on one box is the classic mistake, it delegates to itself and changes nothing):
- **CrewChief host**: `Enable-WSManCredSSP -Role Client -DelegateComputer '<target-FQDN>' -Force`
- **Target**: `Enable-WSManCredSSP -Role Server -Force`

CredSSP places the Run As credential on the target in recoverable form while the session runs — keep Default (Kerberos) unless the step genuinely hops twice. `Negotiate` does NOT solve the double-hop (it's for workgroup/IP-addressed targets). Alternatives: SQL login switches (`sqlUserName`/`sqlUserPassword`) or AD constrained delegation. Full what/why/how (verify steps, undo, trade-offs): in-app doc `CrewChief.Web/Documentation/43_OpsRemoteBoxPrep.md` §5.

### Working directory on the target

`RemoteRunRequest.WorkingDirectory` is a target-side path; the driver splats it onto `Start-Process` only when non-blank. **`ConfigureExecutor` defaults the working directory (local AND remote) to the exe's own folder** when the step doesn't name one (`ConfigureExecutor.cs:~141-146`), because Profisee `Configuration.exe` derives `PhysicalPath` from `Environment.CurrentDirectory` (`GetParent(CWD)`), NOT from its own exe location — started anywhere else it NREs in `LoadConfig`/`writeServiceConfig`.

### Placeholder swap
- `NotWiredRemoteCommandRunner` (same file) is a documented inert placeholder — it always returns a failed result ("Remote execution is disabled (NotWiredRemoteCommandRunner is registered)…"). To force every remote step to fail cleanly, swap the DI line to it. **Production wires the REAL runner**: `EngineServiceCollectionExtensions.cs` registers `IRemoteCredentialResolver → DefaultRemoteCredentialResolver` (line 78, singleton), `IShareCredentialResolver → ShareCredentialResolver` (line 81, **transient**), and `IRemoteCommandRunner → DefaultRemoteCommandRunner` (line 82, singleton).
- The `IRemoteCommandRunner.cs` XML summary (~L117) now correctly states the shell-out `DefaultRemoteCommandRunner` — "NOT the PowerShell SDK) ships and is the DI default." (An earlier revision's "transport pending (PowerShell SDK)" wording is gone; trust the shipped code either way.)

## The op-script layer — `RemoteWindowsOps`

The generated PowerShell op-scripts, their compact-JSON return contract, and the
`ParseServiceControlResult` / `ParseAppPoolControlResult` parsers:
**`references/op-scripts.md`**.

Read it when changing what a remote op does on the target, or when a remote result
parses wrong despite the command succeeding.

## Remote credential resolution

**Two-field Run As pair (preferred).** All six remote steps carry `credentialUserId` + `credentialPassword` (JSON `credentialUserId`/`credentialPassword`; e.g. `Steps/ConfigureStep.cs:~69-84`). Each field supports a literal, a `{{$config:...}}` secret, or a `{{$ref:...}}` reference — the executor token-resolves each field FIRST, then calls the new overload `IRemoteCredentialResolver.Resolve(userId, password)` (`Services/IRemoteCredentialResolver.cs:36,93`): no configuration lookup at all, it just **requires BOTH halves non-blank** (else `null`, so a half-filled pair fails cleanly rather than authenticating partially). `userId` is trimmed; the password is left verbatim (trailing/leading characters can be significant).

**Legacy flattened secret name (fallback).** Every executor composes the two forms as `Resolve(userId, password) ?? Resolve(credentialSecretName)` — the secret-name path exists for older saved steps. `DefaultRemoteCredentialResolver.Resolve(credentialSecretName)` reads `<name>:User` and `<name>:Password` from `IConfiguration` (the flattened Local Secrets store — see [[crewchief-secrets]]) and returns a `RemoteCredential` **only when BOTH are present and non-blank**; otherwise `null`. A section can hold many machines via nested per-machine entries, e.g. `credentialSecretName = "RemoteRuntime:SMVM2"` reads `RemoteRuntime:SMVM2:User` / `:Password`.

**Input normalization (secret-name path only)** — the resolver accepts more than a bare path, because the UI's secret picker and reference tokens emit wrapped forms (verified in `RemoteCredentialResolverTests.cs`):
- a plain path (`RemoteRuntime:SMVM3`);
- the picker's `{{$config:...}}` wrapper (`ConfigRefPattern` strips it), **including one with inner whitespace**;
- a `:User` **or** `:Password` **leaf** selection → normalizes up to the parent section and retries against the pair;
- blank/whitespace/null name → `null`.

The executor also **token-resolves the name first**: it passes `ApplyTokens(step.CredentialSecretName, parameters)` into `Resolve(...)`, so `{{$ref:...}}` / parameter indirection composes before the lookup.

**Validation** — the Install/Uninstall/Configure `GetValidationError()` accepts EITHER form: it errors only when `credentialSecretName` is blank AND the pair is incomplete, with the message "…requires Run As credentials (a User ID and Password)" (`ConfigureStep.cs:~171-176`, `InstallStep.cs:107`, `UninstallStep.cs:125`).

**Where the null result goes differs by family** (this is the credential axis of the [three routing modes](#three-routing-modes--every-box-prep-step-follows-the-same-axes)):
- **Install/Uninstall/Configure** resolve the credential BEFORE touching the transport; a null result **fails the step immediately**. Remote install never falls back to process identity.
- **ServiceControl/AppPool/IisReset** treat the credential as optional: a null result **falls back to the legacy ambient-identity path** (RPC / `ServerManager` / `iisreset computername`) with a warning — it does not fail the step.

### The two failure messages — quote them exactly

There are TWO distinct strings for the same condition, and they are **not** interchangeable. An older
revision of this skill claimed the runtime one "still names the old `credentialSecretName` field only" —
that is **no longer true**: it now names both forms. Live text:

| Where | Exact message |
|---|---|
| **Step validation** — `GetValidationError()`, fires when `targetComputer` is remote AND the two-field pair is incomplete (`ConfigureStep.cs:175-176`, `InstallStep.cs:141-142`, `UninstallStep.cs:125-126`) | `"<Step> with a remote 'targetComputer' requires Run As credentials (a User ID and Password)."` |
| **Executor runtime guard** — fires when BOTH forms failed to resolve (`ConfigureExecutor.cs:239-240`, `InstallExecutor.cs:242-243`, `UninstallExecutor.cs:259-260`) | `"<Step> with a remote 'targetComputer' requires Run As credentials — a User ID and Password, or a 'credentialSecretName' secret holding User/Password."` |

`<Step>` is the literal step class name (`ConfigureStep` / `InstallStep` / `UninstallStep`). The runtime
guard is the one with the em-dash and the `credentialSecretName` clause — a validation message that
mentions `credentialSecretName` would be a bug, since validation deliberately checks only the pair.

The installed-product inventory has its own, THIRD wording and **throws** rather than returning a
failed result: `"Enumerating installed products on '<label>' requires a Run As credential (User ID / Password)."`
(`IInstalledProductInventory.cs:90`) and `"Locating Configuration.exe on '<machine>' requires a Run As credential (User ID / Password)."` (`:138`).

## The box-prep steps

Per-step property catalog for the seven box-prep steps — `WebSiteStep`, `InstallStep`, `UninstallStep`,
`ConfigureStep`, `IisResetStep`, `ServiceControlStep`, `AppPoolStep`:
**`references/box-prep-steps.md`**.

Read it when authoring or debugging one of those steps. The routing modes, credential
resolution, and failure messages above apply to all seven and stay here.

> [!tip] What *makes* a step a box-prep step
> There is no marker interface and no base class. The structural guard test enumerates the family by reflecting over `StepTypeRegistry.Registrations` and keeping every type that **declares a `CredentialSecretName` property** (`WorkloadRunAsInheritanceTests.cs:347-355`), then asserts the count is **7**. Add a credentialed step type and that test goes red until you also add an arm to `WorkloadRunAsInheritance.InheritIfBoxPrep` — see [[crewchief-adding-a-step-type]].

## Inventory, elevation readiness, and testing

Remote installed-product inventory, the elevation-readiness check, and the RemoteLab-gated
integration tests: **`references/inventory-elevation-testing.md`**.

## Sources

Full source-file list: **`references/sources.md`**.
