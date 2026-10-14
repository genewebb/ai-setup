---
name: docker-aspire-class-setup
description: "Docker Desktop 4.86 + Aspire CLI 13.4.6 setup state on Precision 7680 for Docker/Aspire class, plus the settings-store.json Hyper-V gotcha and NuGet dead-feed retry-storm gotcha"
metadata: 
  node_type: memory
  type: reference
  originSessionId: 1f30b31d-1f7c-4947-80d0-94a49898ae67
  modified: 2026-08-13T22:24:54.024Z
---

Docker + Aspire class toolchain set up 2026-08-13 on Dell Precision 7680 (2× Thunderbolt 4):

- **Docker Desktop 4.86** (engine 29.7.2, WSL2 Linux containers). CLI at `C:\Program Files\Docker\Docker\resources\bin` (machine PATH).
- **Gotcha:** uninstall keeps `%APPDATA%\Docker\settings-store.json`. Old 4.38 config had `UseWindowsContainers: true` + `WslEngineEnabled: false`, made fresh 4.86 demand Hyper-V feature. Fix = flip both booleans in that file with app quit, relaunch. No Hyper-V feature needed for WSL2 engine.
- **SQL Server 2025 test container:** `sql2025`, host port **14333** (1433 left for local SQL), sa / CavemanSql!2026x, ephemeral (no volume).
- **Aspire CLI 13.4.6** via `dotnet tool install -g Aspire.Cli --add-source https://api.nuget.org/v3/index.json --ignore-failed-sources` (winget broken on box). Templates `Aspire.ProjectTemplates` 13.4.6 installed. Starter builds clean on .NET 10 SDK 10.0.400.
- **NuGet gotcha:** global NuGet.Config has two authed feeds with dead creds — Profisee ADO (`pkgs.dev.azure.com/profisee`) and **nuget.hangfire.io** (401). Non-repo restores crawl through per-package retry storms against both. Fix per project: local `nuget.config` with `<clear/>` + nuget.org. Durable fix: `dotnet restore --interactive` in a corp repo to refresh ADO creds.
- **Wave Terminal PATH staleness:** machine-PATH changes invisible to shells until whole Wave app restarted (tray quit) or logoff/logon.
- Ordered: Corsair EX400U 2TB USB4 external SSD. Plan: reformat NTFS, fixed drive letter, Docker Desktop > Resources > Advanced > Disk image location → move VHDX there. See [[corp-dual-accounts]].
