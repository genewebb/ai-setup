---
name: project_local_two_profisee_installs_required
description: "CORPLTR94 runs two Profisee installs (26.1.0 speedmerchants, 26.2.0 Profisee) side by side; both are required, never suggest stopping either"
metadata: 
  node_type: memory
  type: project
  originSessionId: 2df56e31-55f7-426a-928f-23de05d43c74
  modified: 2026-09-28T02:51:41.494Z
---

Local box CORPLTR94 hosts two full Profisee installs at once, each ~5 GB RAM:
- `Profisee 26.1.0 (speedmerchants)` service + 19 `speedmerchants-*` IIS app pools
- `Profisee 26.2.0 (Profisee)` service + 19 `Profisee-*` IIS app pools

All pools `startMode=AlwaysRunning`, `idleTimeout=00:00:00`; out-of-process ones (proflow, connex, auth, taskman, scriptrunner, attachments) spawn a `dotnet` child that holds the real memory.

**Why:** Gene stated 2026-09-13 during a memory-reduction review: "I need both of the profisee installs so those have to stay."

**Exception, 2026-09-27 22:46 EDT (Gene):** "We can stop the profisee service if they are not needed for coding or planning". During stream-kit coding/planning runs that nothing hits Profisee for (check the `.streams` graders and tickets first), stopping them is allowed. All 38 pools were stopped that night; the restart command is in `speedmerchants\.streams\overnight-log.md`. Restart them before any real-platform or matching work.

**How to apply:** When reducing memory/CPU on this box, treat both installs as fixed load (except under the exception above). Do not propose stopping either install or toggling between them. Look elsewhere (Claude sessions/MCP servers, browsers, build servers, SQL cap — set to 16384 MB same day).
