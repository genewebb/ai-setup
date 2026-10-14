---
name: testauto-windows-service-hosting
description: >
  Running TestAuto.Web under the Windows SCM — the five things Program.cs must do before anything else, the
  startup-crash breadcrumb, the persisted DataProtection ring, the runtime-availability marker convention,
  and the restart/self-update contract. Use when the service dies at startup with nothing in the log, when
  antiforgery fails after every restart, when adding a startup decision that consumers must read, when
  wiring the restart button or update feed, or when diagnosing an SCM 1053 / 7009.
---

Repo: speed-merchants (paths below are repo-relative)

# TestAuto Windows-Service Hosting

TestAuto.Web runs interactively **and** under the Windows SCM from the same binary. Service mode is not a
flag you can add late — it changes process identity, working directory, config paths, and what "logging"
even means before Serilog exists.

## When to Use

- The service starts and dies with nothing in the log.
- `AntiforgeryValidationException` on every form post after a restart.
- Adding a startup decision that other code must consult.
- Working on the restart button, update feed, or `AppVersionInfo`.
- Diagnosing SCM error **1053** (did not respond in time) or event **7009**.

## The five things that must happen first

`TestAuto.Web/Program.cs`, in order:

1. **`Directory.SetCurrentDirectory(AppContext.BaseDirectory)`** (`:27-44`). The SCM starts the process in
   `%SystemRoot%\System32`. Content-root pinning alone is not enough — Serilog resolves a relative sink path
   against the **CWD**.
2. **`MasterConfigPathResolver.RunningAsWindowsService = true` BEFORE any `MasterPasswordManager` is
   constructed.** Order is load-bearing: the resolver decides where the master config store lives, and a
   manager built first would resolve the interactive per-user path.
3. **An `AppDomain.UnhandledException` breadcrumb** writing `startup-crash.log` next to the master-config
   store (`:51-65`). Serilog's file sink does not exist yet, so this is **the only surviving channel** for a
   1053 death. If a service dies silently, this file is the first place to look.
4. **`WebApplicationOptions.ContentRootPath` pinned** to the exe folder.
5. **A persisted DataProtection ring** (`:126-143`) at `<masterConfigFolder>\dataprotection-keys`, with
   `ProtectKeysWithDpapi(protectToLocalMachine: true)` and `SetApplicationName("TestAuto")`. Without it every
   restart mints a fresh ring and antiforgery fails on the next post; `protectToLocalMachine` means the ring
   survives a service-account change, and the constant application name means a content-root move does not
   orphan it.

Interactive first-run console prompting is gated on `!runningAsService && !Console.IsInputRedirected`
(`:88-122`) — a service must never block on a prompt nobody can answer.

## Runtime-availability markers — one decider, one immutable singleton

A convention now used three times: `HangfireAvailability`, `RuntimeSecretsStatus`, `IHttpsRuntimeStatus`.

**Whoever decides registers the marker; no consumer may re-derive the answer** from the underlying input
(the connection string, `master.json`'s presence, the certificate store). Each marker carries a
human-readable reason string, because the decision is made before Serilog's file sink exists and the reason
would otherwise be unrecoverable.

> [!danger] Two deciders is one too many
> A dashboard that re-derived Hangfire availability from the connection string crashed the pipeline at
> **build time** and killed the service — a token-garbage connection string looks "configured" to a
> string check. See [[testauto-hangfire-architecture]].

Evidence: `TestAuto.DependencyInjection/ServiceExtensions/HangfireAvailability.cs:8-16`,
`RuntimeSecretsStatus.cs:34-46`, `TestAuto.Web/Services/HttpsRuntimeStatus.cs:6-14`; consumers at
`PipelineExtensions.cs:106`, `:184`.

## Restart and self-update

**A service cannot restart itself.** `AppRestartService` (`:39-68`) spawns a **detached `powershell.exe`**
helper that stops and starts the service. `Stop-Service` waits, so `Start-Service` cannot race it; a 2 s
delay lets the in-flight request finish, and `RestartAppButton.razor.cs:17-42` reloads the browser after
15 s.

`UpdateCheckService`:

- `Updates:FeedFolder` blank **or** `Development` environment ⇒ the feature is off entirely.
- Newest-wins parse of `TestAuto-Setup-<ver>.exe` by regex, **no manifest** — the publish step prunes older
  packages (`:105-151`).
- The listing is cached for 6 hours; an unreachable share logs **once** and hides the feature rather than
  degrading the app.
- `CanSelfUpdate` is gated on `IAppRestartService.IsWindowsService`, and the installer is copied **local**
  before `/VERYSILENT /SUPPRESSMSGBOXES` because it stops the running service mid-flight.

Because the package version is `Major.Minor` only (see [[inno-setup-installer]]), the update banner fires
only on a Major/Minor bump — same-version rebuilds are invisible to the feed.

## Service recovery is installer-side

`sc failure … reset= 86400 actions= restart/60000/restart/120000/restart/300000` plus
**`sc failureflag <svc> 1`**. The flag is the load-bearing part: recovery actions otherwise fire only for a
crash, not for the SCM's 30-second start-timeout (event **7009**) that TestAuto can hit while waiting on
REST secrets and Hangfire SQL. `start= delayed-auto` alone does not cover it. Details in
[[inno-setup-installer]].

## Sources

- `TestAuto.Web\Program.cs`
- `TestAuto.Shared.Security\Services\MasterConfigPathResolver.cs`
- `TestAuto.Web\Services\AppRestartService.cs`, `UpdateCheckService.cs`, `AppVersionInfo.cs`
- `TestAuto.DependencyInjection\ServiceExtensions\HangfireAvailability.cs`, `RuntimeSecretsStatus.cs`
- `TestAuto.Web\Components\Common\RestartAppButton.razor(.cs)`
- `installer\TestAuto.iss`, `Grant-ServiceLogonRight.ps1`

## Related

[[testauto-https-hosting]] · [[inno-setup-installer]] · [[testauto-secrets-management]] · [[secrets-bootstrap-middleware]] · [[testauto-hangfire-architecture]] · [[testauto-deployed-machine-diagnostics]]
