---
name: corp-dual-accounts
description: Corp domain account convention — every employee has regular + admin account; admin accounts (corp\a*) never expire; user is corp\genewe / corp\agenewe
metadata: 
  node_type: memory
  type: reference
  originSessionId: dc468bb7-982d-43ea-81a5-1ec2f20c7ca2
  modified: 2026-08-09T00:06:47.208Z
---

Every employee on the corp domain has two accounts: a regular account and an admin account. Admin accounts are prefixed `a` — pattern `corp\a*` — provisioned at hire for everyone, and **their passwords do not expire** (rotated only if exposed; user has held theirs for years).

There are also **special accounts** for infrastructure, e.g. `corp\speedmerchants`, used on the actual dedicated test machines — **used only by Gene today, nobody else**. Individuals (e.g. a QA tester on their own box) always use their own `a*` admin account instead.

**Operator prerequisite**: anyone given TestAuto or CrewChief must already know how to provision SQL accounts/logins, REST API keys, and similar grants themselves — baseline entry skill, docs assume it (checklist style, not "ask a developer").

User's own accounts: regular `corp\genewe`, admin `corp\agenewe`.

**Why it matters**: `corp\a*` accounts are safe as Windows Service identities (no password-rotation breakage) — this is the basis for the TestAuto service-install decision to run the service as the operator's own admin account ([[testauto-service-install-plan]]). Grants (SQL, shares, Profisee) for operator-run services should target the `a*` accounts. Corp lockout policy still applies to them ([[corp-domain-lockout-policy]] if present).

**Session split on CORPLTR94 (verified 2026-08-30):** Gene's INTERACTIVE console session is the regular account `corp\genewe`; Claude's shell runs as `corp\agenewe`, NON-interactive. Consequences that repeatedly cause false alarms:
- **Mapped drives `Q:` (obsidian vault) and `D:` (devopslocal) are per-logon-token and invisible to agenewe.** `Get-PSDrive` in Claude's shell shows only `C:` and a Temp drive; `Test-Path Q:\` = False even while `dir Q:\` works fine for Gene. NOT a broken mapping. Reach the vault by UNC: `\\SynologyDS918\obsidian\Work\Work\...` (works from both Bash and PowerShell tools).
- **WSL distro registration is per-user too** (`HKCU\...\Lxss`). agenewe sees only `Ubuntu` + leftover `docker-desktop`; the `rancher-desktop` distro and all Rancher state live under genewe. Absence there is expected, not a missing install.
- **Named pipes are machine-global.** Rancher Desktop launched by genewe publishes `\\.\pipe\docker_engine`, and agenewe's `docker` CLI drives it with no bridging — verified client `29.6.2-rd` / server `29.5.3`. This is the CORRECT arrangement: launching Rancher as agenewe would register a second empty WSL distro and orphan the existing images. Never run it under both accounts at once.
- Claude cannot launch a GUI app into genewe's session — ask Gene to start Rancher Desktop himself after a reboot. See [[reference_rancher_desktop_switch]].
