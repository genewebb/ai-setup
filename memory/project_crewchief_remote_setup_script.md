---
name: crewchief-remote-setup-script
description: Enable-CrewChiefRemoteManagement.ps1 in CrewChief/installer/ — role-based (Target/Host/Both) WinRM+CredSSP machine prep; remediation text in lockstep with IRemoteAccessChecker.cs + 43_OpsRemoteBoxPrep.md §4/§5
metadata: 
  node_type: memory
  type: project
  originSessionId: f55edf44-80e4-4cc6-aeb0-d3c5a7423aa7
  modified: 2026-07-24T13:52:53.477Z
---

`CrewChief\installer\Enable-CrewChiefRemoteManagement.ps1` (created 2026-07-24, uncommitted) preps machines for CrewChief remote box-prep. Role-based: `-Role Target` (Enable-PSRemoting w/ -SkipNetworkProfileCheck, WinRM firewall group by locale-independent id `@FirewallAPI.dll,-30267`, optional `-CredSsp` server role, optional `-AllowLocalAccountAdmin` = LocalAccountTokenFilterPolicy=1, GPO AllowAutoConfig warn, Kerberos-ready advisory), `-Role Host` (`-DelegateComputer` = CredSSP client w/ AllowFreshCredentials wildcard-aware registry check, `-TrustedHosts` additive merge, `-VerifyTarget` DNS→FQDN + TCP 5985 probes mirroring the C# pre-flight), `-DatabaseServer` (TCP probe + LocalSystem-machine-account warning reading the service ObjectName). Every step is test→fix→re-test (idempotent); `-VerifyOnly` audits; exit 0/1. PS 5.1-compatible.

Topology mapping: "CrewChief on the box, remote DB" = `-Role Host -DatabaseServer x` (no WinRM needed — local steps never hop; only the service identity matters). "All targets remote" = `-Role Target` on each target + `-Role Host -VerifyTarget ...` on the CrewChief box; CredSSP pair only for double-hop.

In-app usage doc: `44_OpsRemoteManagementSetup.md` (/help/operations/remote-management-setup, Operations order 9 — alphabetical tie-break slots it right after 43_OpsRemoteBoxPrep, which cross-links it in §4 + See also). Covers both topologies, parameter/status tables, undo.

MUST stay in lockstep with [[project_crewchief_setup_verification]] (`IRemoteAccessChecker.cs` RemoteAccessRemediation blocks), `43_OpsRemoteBoxPrep.md` §4/§5, AND `44_OpsRemoteManagementSetup.md` — same commands, four places. Deliberately NOT wired into CrewChief.iss (user decision 2026-07-24: run separately; doc says "copy from CrewChief\installer\").
