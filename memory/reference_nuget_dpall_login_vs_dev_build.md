---
name: reference_nuget_dpall_login_vs_dev_build
description: "Why dpall (dotnet CLI) prompted for Azure Artifacts NuGet login while `dev build` (VS msbuild) did not; fixes applied 2026-10-27"
metadata:
  node_type: memory
  type: reference
  originSessionId: e11175e5-5462-45e6-a7bb-e8c5544f95e0
  modified: 2026-10-27T20:23:14.512Z
---

Same feed (`Profisee DevOps`, profisee.pkgs.visualstudio.com) in every repo NuGet.config, but two different credential providers:
- `dev build` = VS 18 `msbuild.exe /restore` -> VS-bundled provider `Common7\IDE\CommonExtensions\Microsoft\NuGet\Plugins\CredentialProvider.Microsoft\CredentialProvider.Microsoft.exe` (2.0.4)
- `dpall` = `dotnet build` / `dotnet restore --interactive` -> user provider `~\.nuget\plugins\netcore\CredentialProvider.Microsoft` (was 1.2.1 from 2024)

Fixes 2026-10-27 (CORPLTR94, CORP\agenewe):
1. Removed stale saved `Profisee DevOps` Username/Password from `%APPDATA%\NuGet\NuGet.Config` (NuGet tries config creds BEFORE providers). Backup `NuGet.Config.20261027-bak`.
2. Upgraded user provider to 2.0.5 via installcredprovider.ps1 `-Force` (direct GitHub release URL; aka.ms wrapper skips without -Force).

Gotcha: installer fails `Access denied ... msalruntime.dll` when a `dllhost.exe /Processid:{9D48A7B6-...}` COM surrogate (WAM broker) has it loaded: stop that PID, rerun. Claude's auto mode blocks both the remote install script and stopping that process; user runs them.

Unverified: whether dpall stops prompting (1.2.1 already shipped msalruntime, so the stale saved credential may have been the real cause). Related: [[project_profile_machine_config]].
