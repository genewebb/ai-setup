---
name: mymemory
description: >
  Slash shortcut that shows the top 10 memory consumers on this Windows machine, rolled up to
  where the memory is coming from (a Claude Code session with its MCP servers, an IIS install's
  app pools, the WSL/Docker VM, a service, a browser) instead of raw process names. Use when the
  user types `/mymemory`, or asks what is using their RAM, their top memory consumers, or why
  free memory is low.
---

# /mymemory

Read-only snapshot: top 10 memory sources on this box, with total/used/free RAM.

## When invoked

1. Run (pass through any arguments the user typed, e.g. `-Top 15` or `-ShowMembers`):

```powershell
pwsh -NoProfile -File "~\.claude\skills\mymemory\Get-TopMemory.ps1"
```

2. Show the output table as-is. Only add advice if the user asks for it.

## Options

| Argument | Effect |
|---|---|
| `-Top <n>` | Show n sources instead of 10 |
| `-ShowMembers` | List each member process (PID, name, IIS pool, MB) under every source |

## How sources are formed

| Source | Rolls up |
|---|---|
| `Claude Code session (PID, started)` | `claude.exe` and every descendant: MCP servers (node, uv, python), tool shells, builds, test hosts, conhost |
| `IIS: <prefix> app pools` | `w3wp.exe` grouped by pool-name prefix before the first `-`, plus out-of-process `dotnet` children |
| `WSL2 / Docker VMs` | `vmcompute` service with `vmmemWSL` / `vmwp` |
| `Service: <display name>` | a non-svchost service process and its descendants |
| `Windows services (svchost)` | every shared `svchost.exe` |
| `<process name>` | everything else, all instances of that name |

A process counts toward the **outermost** source in its parent chain, so a hook-spawned `claude.exe`
inside a session stays with that session. A parent created after its child is a recycled PID and
ends the walk.

## Reading the numbers

- **In RAM MB** = working set. Shared pages (DLLs, mapped files) count in every process, so the
  top-10 sum can exceed "used".
- **Private MB** = committed private bytes, including any part paged out. For `sqlservr` it can be
  larger than In RAM when the buffer pool has been trimmed.
- Loose `dotnet` rows are processes whose parent already exited (MSBuild reuse nodes, orphaned test
  hosts), so they cannot be attributed.
