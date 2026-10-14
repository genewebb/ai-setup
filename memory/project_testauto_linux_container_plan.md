---
name: testauto-linux-container-plan
description: Plan for TestAuto dual-target hosting (Windows service unchanged + linux container); doc in vault 52 Technical\Containers\TestAuto
metadata: 
  node_type: memory
  type: project
  originSessionId: fb9f612b-5378-47c3-b918-d5a7f50bec43
  modified: 2026-08-14T22:24:32.427Z
---

Plan doc: `C:\devopslocal\ObsidianVaults\Work\MyWorkVault\52 Technical\Containers\TestAuto\TestAuto Dual-Target Hosting Plan.md` (created 2026-08-14, draft, not started).

Audit findings (verified 2026-08-14): entire Windows-only surface = 6 spots — DPAPI in MasterPasswordManager.cs (:98,241,308,342) + ProtectKeysWithDpapi in Program.cs (:126-143), WindowsIdentity + hardcoded `corp\{user}` in UserHelper.cs (:32,:73), HttpsCertificateResolver cert-store walk, AppRestartService/UpdateCheckService service plumbing, MasterConfigPathResolver paths. Step executors ALREADY cross-platform (pwsh/sh/curl fallbacks). System.Management.Automation + ServiceController package refs = dead weight in TestAuto projects, zero code usage.

**Phase 0 EXECUTED 2026-08-14 evening:** BOTH DBs containerized and validated. sql2022-modelsource (port 14322, ModelSource 203 GB, counts match local incl. 150M RetailClientCloned) + sql2022-speedmerchants (port 14344, 2637 tables match). Logins: testauto/db_owner (speedmerchants), profisee/db_owner (ModelSource, pre-staged for repoint). Credentials: `C:\devopslocal\Secrets\sql-container-credentials.local.txt`. Docker disk image MOVED to `C:\devopslocal\Containers\DockerDesktopWSL\` (user plans whole-devopslocal move to future drive; repeat GUI setting if path changes). Restart-persistence verified; backups deleted; local DBs untouched = rollback. REMAINING Phase 0: repoint TestAuto secrets to 14344 (SQL auth only — container not domain-joined), decide separate 0.1 GB Hangfire DB, repoint local Profisee to 14322 (careful: Configuration.exe exit-0 lies, identity drift), e2e scenario. Tooling users mcp_ro/mcp_user/CursorReadyOnly orphaned in container — recreate with new passwords when tools repoint. Windows-only workload steps recategorized: transitional (Profisee app itself going linux), not cons.

Decisions from user:
- Targets stay Windows Profisee servers; container drives via REST+SQL (cross-platform clean).
- `corp\{user}` hardcode gets fixed either way — config-driven, both platforms.
- Container HTTPS = nice-to-have but preferred: mounted PFX via standard Kestrel env vars; HTTP-only must also boot clean.
- Plan: IMachinePayloadProtector seam (DPAPI vs AES-GCM key file), scheme prefix `dpapi:`/`aeskf:` for back-compat, TESTAUTO_CONFIG_ROOT env override, /var/lib/testauto default, ~4.5-6 d estimate.

**Why:** avoids re-auditing the Windows-only surface when implementation starts.
**How to apply:** on "containerize TestAuto" / "linux TestAuto" work, read the vault doc first; audit file:line refs valid as of 2026-08-14. Related: [[testauto-secrets-persistence-diagnosis]].
