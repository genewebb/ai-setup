---
name: crewchief-builtin-pool-protection
description: "IIS built-in app pools are never deletable through CrewChief (IisBuiltInAppPools guard, 2026-08-07); plus the Built-in Protections reference page"
metadata: 
  node_type: memory
  type: project
  originSessionId: 009eacec-06ba-4a48-9aec-b7bd692a2bd4
  modified: 2026-08-07T21:55:24.003Z
---

CrewChief must never delete the IIS pools Windows itself creates (user directive 2026-08-07, SMVM2 screenshot): DefaultAppPool, Classic .NET AppPool, .NET v2.0 (+Classic), .NET v4.5 (+Classic), ASP.NET v4.0 (+Classic).

**Why:** DefaultAppPool loss breaks every future default-created site; .NET pools break feature installs/repairs. Never deployment artifacts, so no legitimate teardown includes them.

**How to apply:** `IisBuiltInAppPools` (CrewChief.Engine\Executors) is the single source — `IsProtected` (trim, case-insensitive) + `PowerShellArrayLiteral()` for generated scripts. Three guard points:
1. `AppPoolExecutor.ExecuteAsync` — Delete refused at choke point BEFORE any runner call, fail-whole on mixed lists, all transports (local ServerManager / WSMan / local Run As). Start/Stop/Recycle still allowed.
2. `DefaultWebSiteRunner.RemoveOrphanedPools` (IWebSiteRunner.cs) — skip via IsProtected.
3. `RemoteWindowsOps.BuildWebSiteControlScript` delete block — `$builtIn -contains $pool` skip (PS -contains is case-insensitive).

Tests: `BuiltInAppPoolProtectionTests.cs` (9). Suite 2913 green. Docs: 22/48 updated + NEW `50_ReferenceBuiltInProtections.md` — catalogue of ALL built-in guards (secrets at rest/screen/logs, password lockouts, account-lockout protection, pool protection, dependency-ordered teardown, run honesty guards, content safety). Add new guards to that page when shipping them. Note: step delete uses the Windows Recycle Bin (useRecycleBin:true both hosts); secrets file writes are NOT atomic (M-3 open).

Related: [[crewchief-docs-full-audit-2026-08-07]].
