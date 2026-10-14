# ShareMount and the CC_SHARE_* Environment Variables

Reference for the `crewchief-remote-box-prep` skill. Loaded on demand — see `SKILL.md` for the decision rules and gotchas that decide whether you need this file.

---

### `ShareMount` + the `CC_SHARE_*` env vars — the second-hop share wall

The problem: the remote target must read an installer/license off a **network share**, but the WSMan
session is a network logon that carries no onward credential — a second hop. `net use`-ing the share
*from CrewChief's host* does nothing for the target. The fix is to establish an SMB session **inside**
the remote PSSession before the run, and tear it down after.

**`ShareMount`** (`Executors\ShareCredential.cs:29`) is the fully-resolved description of that mount, set on `RemoteRunRequest.ShareMount`:

| Member | Meaning |
|---|---|
| `Type` (`ShareCredentialType`) | `None` = 0 (no injection — the Run As identity's own rights), `AzureFile` = 1, `WindowsShare` = 2. Never `None` on a live mount. |
| `RemotePath` | The UNC **share root** (`<share>`) — server + share only, because that is the scope `net use` establishes; not a path within it. |
| `UserName` | `AzureFile`: auto-derived `localhost\<account>` when the operator left it blank. `WindowsShare`: the supplied `DOMAIN\user`. |
| `Password` | The resolved secret — an Azure storage-account key or the share password. Never written to output or a command line. |

**Who builds it**: `IShareCredentialResolver` / `ShareCredentialResolver` (`Executors\ShareCredentialResolver.cs`, DI `EngineServiceCollectionExtensions.cs:81`, registered **`AddTransient`** unlike the singleton transport). `Resolve(shareCredentialType, shareRemotePath, shareUserId, sharePassword, fallbackRemotePath, parameters)`:
- Token-resolves every field via `ITextTemplater` — the password normally arrives as a `{{$config:...}}` secret.
- **Fail-safe to null**: a blank/unknown/`None` type returns `null` (no mount), so an old or hand-edited step never breaks on the field.
- Explicit `shareRemotePath` wins; otherwise the share root is derived from `fallbackRemotePath` — for the Install step that is the already-resolved `msiPath`. Either way it is reduced by the public static `ShareCredentialResolver.ShareRoot(path)` (`\\server\share\a\b` → `<share>`; a bare host or non-UNC value passes through trimmed). `ShareRoot` is public/static precisely so the design-time Browse editor derives the identical root. <!-- example-path -->
- Azure user auto-derive: blank user + `AzureFile` → `RemoteWindowsOps.DeriveAzureShareUser(remotePath)` → `localhost\<account>`.
- Pure — no network access, fully unit-testable.

**Who consumes it**: `InstallExecutor` is the live consumer (`InstallExecutor.cs:296` sets `ShareMount = shareMount`), sourced from `InstallStep`'s `shareCredentialType` / `shareRemotePath` / `shareUserId` / `sharePassword` fields (`InstallStep.cs:83,90,98,106`). `IRemoteFileBrowser` also carries one so the design-time Browse dialog can see the same share (`IRemoteFileBrowser.ResolveEffectiveMount`). `InstallStep.GetValidationError()` guards the pair: a non-`None` type with no `sharePassword` → "…requires a share password/key ('sharePassword')"; `WindowsShare` with no `shareUserId` → "…requires a share user id ('shareUserId', DOMAIN\user)" — only `AzureFile` can auto-derive its user.

**How it travels — three `CC_SHARE_*` env vars** (`DefaultRemoteCommandRunner.cs:167-183`), exactly like `CC_REMOTE_PW` and for the same reason (never a command line):

| Env var | Value |
|---|---|
| `CC_SHARE_PATH` | `mount.RemotePath` |
| `CC_SHARE_USER` | `mount.UserName`, with a safety-net Azure auto-derive if a caller populated `ShareMount` without one |
| `CC_SHARE_PW` | `mount.Password` |

All three are **initialized to empty first** and only overwritten when `request.ShareMount` is non-null — so the default is "no share mounted", and a stale value can't leak in from the parent environment. Inside the driver they are read into `$sharePath` / `$shareUser` / `$sharePw` and **`$env:CC_SHARE_PW` is blanked the moment it is read** (`DefaultRemoteCommandRunner.cs:369-372`).

**One canonical `net use`, two call sites.** The driver script contains the placeholders `__CC_SHARE_MOUNT__` / `__CC_SHARE_UNMOUNT__`, substituted at build time from `RemoteWindowsOps.BuildNetUseMountStatement("$sp","$su","$spw")` and `BuildNetUseUnmountStatement("$using:sharePath")` (`DefaultRemoteCommandRunner.cs:152-154`). Those same two builders back the standalone `BuildShareMountScript` / `BuildShareUnmountScript`, so the transport and the standalone script **cannot drift**. The builders take PowerShell *expressions*, not raw values — single-quoted escaped literals for the standalone form, bare `$sp`/`$su`/`$spw` variables for the driver (delivered into the session over `$using:`).

Emitted mount statement: `net use <path> /user:<user> <pw> 2>&1 | Out-Null` followed by an explicit `if($LASTEXITCODE -ne 0){ throw … }`. Two deliberate details: output goes to `Out-Null` so the key is never echoed, and the exit code is checked by hand because **a native exe's nonzero exit does not trip `$ErrorActionPreference='Stop'`** — the throw message carries no password. Unmount is `net use <path> /delete /y 2>&1 | Out-Null`, run best-effort under `SilentlyContinue` in the driver's `finally` (`:453`) so teardown can never mask the run's own result.
