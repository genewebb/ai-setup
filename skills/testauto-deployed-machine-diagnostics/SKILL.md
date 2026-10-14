---
name: testauto-deployed-machine-diagnostics
description: >
  Startup hang diagnostics for deployed TestAuto.Web machines. Use when TestAuto.Web
  hangs or fails to start on a production or staging server, troubleshooting missing
  secrets, SQL connectivity issues, certificate problems, or port conflicts on a
  deployed machine.
---

Repo: speed-merchants (paths below are repo-relative)

# TestAuto.Web — Deployed Machine Diagnostics

> **Scope**: speed-merchants deployed environments (not local dev)
> **Script**: `TestAuto.Web/RunTimeSetup/Diagnose-DeployedMachine.ps1`

`Diagnose-DeployedMachine.ps1` checks every known cause of a TestAuto.Web startup hang or failure on a deployed machine. It outputs `[PASS]`, `[WARN]`, and `[FAIL]` results with inline fix suggestions.

---

## How to Run

Must be run **as Administrator** — some checks (certificate store key access, port state) require elevation.

<!-- example-paths -->
```powershell
# From the deployed directory
cd C:\Deploy\TestAuto.Web
.\RunTimeSetup\Diagnose-DeployedMachine.ps1

# From anywhere, pointing at the deploy folder
.\Diagnose-DeployedMachine.ps1 -DeployPath "C:\Deploy\TestAuto.Web"

# Adjust TCP probe timeout (default 5 s)
.\Diagnose-DeployedMachine.ps1 -TcpTimeoutSeconds 10

# Test a specific cert thumbprint
.\Diagnose-DeployedMachine.ps1 -SelectedCertThumbprint "ABC123..."
```

---

## What It Checks (10 sections + summary)

### 1 — Deploy Directory & Executable

| Check | Failure means |
|---|---|
| `TestAuto.Web.exe` present | Deploy is incomplete |
| `appsettings.json` present | App cannot start |
| `appsettings.Production.json` present | Warn only — defaults still load |
| `appsettings.Development.json` NOT present | Warn if present on a deployed machine — overrides production settings |

### 2 — ASPNETCORE_ENVIRONMENT

| Value | Behavior |
|---|---|
| Not set | Defaults to `Production` (warn — set it explicitly) |
| `Development` | Forces dev-cert path, localhost-only Kestrel listeners — **wrong on a deployed machine** |
| `Production` | Correct for deployed machines |
| Custom | Loads `appsettings.{env}.json` if present |

`DOTNET_ENVIRONMENT` overrides `ASPNETCORE_ENVIRONMENT` — checked for consistency.

### 3 — .NET Runtime (major matched to the deployed app)

Checks `dotnet --version` and scans `%ProgramFiles%\dotnet\shared\Microsoft.AspNetCore.App` and `Microsoft.NETCore.App` for the required major version. The required major is derived from the deployed app's target framework — read from the app's `deps.json`, falling back to the script's `$targetFramework` default (`net10.0` since the 2026-07 .NET 10 upgrade). Missing runtime causes an immediate crash before any app startup code runs.

### 4 — DPAPI Secrets (`%APPDATA%\TestAuto\master.json`)

`master.json` lives in the profile of the user who runs the exe. DPAPI scope is `LocalMachine` — any user on this machine can decrypt, but the file **must exist in their `%APPDATA%`**. A `master.json` copied from another machine will not decrypt.

Checks:
- File exists
- `EncryptedPassword` decrypts successfully
- `EncryptedScenarioMgtRestUrl` decrypts (needed to call LoadEntitySecrets)
- `EncryptedScenarioMgtApiKey` decrypts

**If master.json is missing or fails to decrypt:** HangfireDB connection string never arrives → Hangfire registration is skipped → no background jobs run.

Re-run first-time setup to regenerate:
```
.\TestAuto.Web.exe
```

### 5 — ScenarioMgt Profisee REST API (secrets source)

Three sub-checks against the ScenarioMgt URL/key extracted from `master.json`:

- **5a — TCP reachability**: if unreachable, `LoadEntitySecrets` times out after ~30 s, the HangfireDB connection string never loads, and the app starts in degraded mode (no background jobs).
- **5b — TestAutoSecrets active record**: REST query for a `TestAutoSecrets` record where `MachineName = $env:COMPUTERNAME` and `IsActive = 'Y'`. Missing record means the app has no secrets and will start in degraded mode.
- **5c — SecretData populated**: verifies the active record's `SecretData` attribute is not empty.

### 6 — SQL Server (required for Hangfire)

**#1 cause of silent startup hangs.** The SQL host is read from the base ProfiseeDB connection in appsettings (HangfireDB comes from secrets, not appsettings). Sub-checks: **6a** Windows service check (local only), **6b** TCP connectivity, **6c** Integrated Security auth test. If SQL is unreachable, `EnsureDatabaseExists` blocks until the TCP timeout, causing the app to appear hung before `builder.Build()` completes.

### 7 — HTTPS Certificate

The thumbprint comes from the secrets payload (which the script cannot fully decrypt), so the script identifies **candidate** certs in the `LocalMachine` store — those whose Subject/DNS name matches this machine or the configured hostname — and tests:
- Private key is accessible to the current user
- Cert is not expired (plus store-wide expired/expiring-soon warnings)

> [!warning] There is NO dev-cert fallback — the app serves HTTP only
> If the cert is missing, expired, lacks the Server Authentication EKU, or its private key is unreadable,
> the **HTTPS listener is skipped entirely** and the app serves HTTP on `WebUI:HttpPort`
> (`KestrelExtensions.cs:50-54`, `:144-151`). This is deliberate: an operator box installed from `Setup.exe`
> has no dotnet SDK and no dev cert, so `UseHttps()` without a certificate would throw during bind and kill
> the whole app — under the SCM that means a dead service and nothing in the browser at all. HTTP always
> survives.
>
> To see *which* candidates were rejected and why, read the ordered `IHttpsRuntimeStatus.Notices` — in the
> startup log or on the `/secrets` page. A configured thumbprint is an **override, not a prerequisite**; see
> [[testauto-https-hosting]].

### 8 — Port Availability (HTTP / HTTPS)

Checks the ports from `WebUI:HttpPort` / `WebUI:HttpsPort` in appsettings (defaults 8080 / 8443; secrets may override at runtime) for an existing listener. If a previous hung instance is still running, the new instance fails to bind and exits immediately; a non-TestAuto process on the port is flagged as a blocker.

### 9 — Windows Firewall

Checks for an enabled inbound TCP rule for each HTTP/HTTPS port. Missing rule is a warn, not a fail — the app still binds, but remote clients are blocked by Windows Firewall (fix suggestion: `New-NetFirewallRule`).

### 10 — Seq Logging (optional)

If `Seq:ServerUrl` is configured in appsettings, TCP-probes the Seq host/port (default 5341). Unreachable Seq is a warn — the app still starts, but structured log events are lost.

### Summary

Prints total `[PASS]` / `[WARN]` / `[FAIL]` counts plus a startup-hang cheat-sheet, and exits with the failure count as the exit code.

---

## Common Hang Scenarios

| Symptom | Most likely cause | Check section |
|---|---|---|
| App appears to hang silently for 30–120 s | SQL Server unreachable | 6 |
| App starts, no jobs run | Secrets not loaded → HangfireDB conn string missing | 4 / 5 |
| App exits immediately after deploy | .NET 10 runtime missing | 3 |
| Works for one user, hangs for another | `master.json` not in that user's `%APPDATA%` | 4 |
| Kestrel only binds to localhost, not all IPs | `ASPNETCORE_ENVIRONMENT=Development` on server | 2 |
| Secrets decrypt on dev, fail on server | `master.json` copied from different machine (DPAPI machine-bound) | 4 |

---

## Sources

- `TestAuto.Web\RunTimeSetup\Diagnose-DeployedMachine.ps1`
