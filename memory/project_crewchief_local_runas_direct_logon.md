---
name: project-crewchief-local-runas-direct-logon
description: "CrewChief local Run-As uses a direct local logon, NOT a WinRM loopback — Windows blocks credentialed auth to itself by default"
metadata: 
  node_type: memory
  type: project
  originSessionId: 7dc6c870-9aa7-4891-a85e-d99e95480385
  modified: 2026-07-30T01:51:05.278Z
---

CrewChief's local Run-As box-prep (a step targeting **this** machine but carrying a Run-As credential) executes
via a **direct local logon** — `LogonUser(BATCH→INTERACTIVE)` → `DuplicateTokenEx` → `CreateProcessWithTokenW`
(falling back to `CreateProcessAsUser`) — in `LocalRunAsCommandRunner`. Route: `BoxPrepRoute.LocalRunAs`,
dispatched by `BoxPrepCommandRunner` on `RemoteRunRequest.LocalRunAs`.

**Why (the load-bearing platform fact, verified on CORPLTR94 2026-07-29):** it was originally built as a **WinRM
loopback** against the host's own FQDN. That cannot work on a stock Windows box — Windows blocks credentialed
authentication to *itself* unless `DisableLoopbackCheck`, `BackConnectionHostNames`, or
`LocalAccountTokenFilterPolicy` is set, and **all three are unset by default**. Negotiate/CredSSP returned
"Access is denied"; Kerberos returned "user name or password is incorrect". Combined with the hard-block
preflight, this refused every local Run-As step on a healthy host.

**Consequences worth remembering:**
- A local step derives `LocalAdmin + RemoteRunAs + LocalLogon` and **never `RemoteWinRm`**. Requiring WinRM for
  work that never leaves the box is what broke it.
- Three installer executors (Install/Uninstall/Configure) must gate their local path on `route.Route ==
  LocalDirect`, **not** `UsesCredentialedRunner` — `LegacyRpc` (remote, no credential) must still be rejected,
  not run locally. The three control executors correctly use `UsesCredentialedRunner`.
- Output capture uses **temp files, not pipes**: `CreateProcessWithTokenW`/`WithLogonW` take no
  `bInheritHandles`, so pipe redirection is unreliable by design.
- The Run-As password reaches `LogonUser` only — never the child's command line, environment, or driver script.
- New Win32 taxonomy in `LocalLogonErrors`: 1385 = missing *Log on as a batch job* right, 1058 = seclogon
  disabled, 1314 = caller lacks SeImpersonatePrivilege (about CrewChief's identity, not the Run-As account),
  1326 = bad credential. None of these is fixed by `Enable-PSRemoting`.
- **Retired a documented caveat:** the old network-logon probe was UAC-token-filtered for local/workgroup
  accounts, so a real local admin probed as not-admin. BATCH/INTERACTIVE logons are not filtered.
- `/setup` is now self-target-aware (`RemoteAccessReport.IsSelfTarget`) and no longer prints the impossible
  two-box CredSSP block for one machine.

## Account lockout policy — hard constraint (2026-07-29)

**The domain locks an account after 3 CONSECUTIVE bad password attempts, with NO time-based reset.** Nothing
decays; only a successful sign-in as that account clears the count. Getting it unlocked requires a support
request to a domain admin — it has happened, so this is a real operational cost, not a theoretical one.

Because of that, rate limiting is useless (1 attempt / 5 min still reaches 3 in 15 min). `LogonAttemptGuard`
enforces a **hard ceiling**:
- `MaxAutomaticFailedAttempts = 1` — all automatic paths (preflight, badges, step execution, re-running the
  same workload) get ONE attempt per distinct credential, for the process lifetime. Failures **never expire**.
- `AbsoluteMaxFailedAttempts = 2` — a ceiling **no path can cross**, including repeated deliberate re-checks.
  CrewChief stops one short and reports it, leaving the 3rd attempt for the operator's manual sign-in.
- Only `1326/1327/1330/1331/1793/1907/1909` count against the budget. `1385` (user right), `1058` (seclogon),
  `1314` (caller privilege) happen AFTER authentication, cost nothing, and are never cached.
- Key = user + logon-kind + salted SHA-256(password), so a corrected password gets a fresh attempt at once.
- `Reset(user,password,kind)` exists for after a manual sign-in.
- **`/setup` confirmation gate:** a 2nd check of an already-failed credential STOPS and shows
  "N of 3 attempts already used" with a *Use attempt N+1 of 3* button (`RemoteAccessReport.PendingConfirmation`,
  `IRemoteAccessChecker.CheckAsync(..., confirmedRetry)`). At the ceiling no button is offered — only the
  manual-sign-in remedy. `IWindowsLogonProbe.IsLocalAdministrator` gained `operatorForced` to carry consent;
  only the /setup confirm path passes true.
- **`/setup` remote path was a ONE-CLICK lockout** (pre-existing, fixed 2026-07-29): it authenticated all
  THREE mechanisms (Kerberos/Negotiate/CredSSP) unconditionally, so one press of Run Check with a bad password
  = 3 consecutive failures = instant lockout. Now stops at the first credential rejection
  (`DefaultRemoteAccessChecker.LooksLikeCredentialRejection`, biased towards stopping) and reports the rest as
  "Not attempted" with the reason.
- **Test gotcha:** `LogonAttemptGuard.Shared` is process-wide static, so tests MUST inject
  `new LogonAttemptGuard()` — a leaked failure makes a later test stop-and-ask instead of running
  (order-dependent). Fakes must also route through the injected guard or the budget gate has nothing to read.

Also fixed: badge rendering used to perform real logons for Run-As steps (`LocalAdmin` was classified
"deterministic local" — true for a token read, false for a `LogonUser`). N steps x 2 requirements = 2N logons
**per page render**, so navigating could lock an account. `CapabilityAdvisor.UsesRealCredential` now defers
those off the render path. Guarded by `LogonLockoutSafetyTests` (20 tests).

Design record: `Design_CrewChiefCapabilityAdvisor.md` §6a/§6b, decision **D5b** (supersedes D5).

Related: [[project_crewchief_remote_boxprep_transport]], [[project_crewchief_credentialed_remote_ops]],
[[reference_configuration_exe_failure_modes]]
