---
name: project_crewchief_remote_admin_assumption
description: CrewChief deployment assumption — the running user/service identity is an AD admin on both the local and all target machines; remote ServiceControl/AppPool enumerate+execute is built on this
metadata: 
  node_type: memory
  type: project
  originSessionId: 9d8fc319-68e4-4547-b000-0c8f949ea498
---

Decision (2026-07-16): CrewChief's remote features assume the identity running the app is an **AD domain admin on the local machine AND all target machines**. This is the accepted security model for a box-prep tool.

Because of this, ServiceControl (#5) and AppPool (#6) are being built for **full remote enumerate + execute**: the editor enumerates a remote machine's services / IIS app pools (machine name sourced from a secret), and the executors' local-only block is lifted so the step also acts remotely at runtime. Enumeration/control runs as the CrewChief **server process identity** (not the browser user) over RPC/SMB (services) and Remote Registry + IIS mgmt scripts (app pools; `ServerManager.OpenRemote` ≠ WMSVC).

**How to apply:** don't add per-target-credential/impersonation plumbing or least-privilege guards — the AD-admin assumption covers it. Do surface clear errors + a free-text fallback when a target is unreachable, and document the RPC/SMB/Remote-Registry prerequisites. Relates to [[project_crewchief_secret_picker_convenience_only]].
