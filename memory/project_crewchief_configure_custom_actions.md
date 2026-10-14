---
name: crewchief-configure-custom-actions
description: "Configure step Custom Actions shipped 2026-08-07 — 4 default-ON toggles (SQL repair pre/postflight, IIS-site preflight, identity enforcement) + Login-failed detection + switch pairing warnings, coding around the 14 Configuration.exe defects."
metadata: 
  node_type: memory
  type: project
  originSessionId: d7c3bb9f-f56b-459f-8385-d3a178b89509
  modified: 2026-08-07T18:41:21.609Z
---

Shipped 2026-08-07 (2904/2904 unit tests green, clean solution build). The Configure step now codes
around the verified Configuration.exe defects ([[smvm2-sql-login-lockout-orphan]], defect list at
C:\tmp\configuration-manager-defects.md).

**Four bool properties on ConfigureStep, ALL DEFAULT TRUE** (absent JSON = on; wizard "Custom Actions"
page between Advanced and Review, badge = enabled count):
- `preflightSqlRepair` — clears policy lockout (`CHECK_POLICY = OFF`) + remaps orphaned DB users for
  `Profisee_{db}_{fqdn}` AND `ProfiseeRpt_{db}_{fqdn}`; warns when installer login not sysadmin.
  Applicable ONLY when useWindowsAuthentication=FALSE + sqlServer/maestroDatabase/sqlUserName/sqlUserPassword
  all resolve non-blank (ConfigureExecutor.BuildSqlRepairContext — public static, pure).
- `preflightVerifyIisSite` — Test-Path IIS:\Sites when useHttps + webSiteName set; missing site FAILS
  the step BEFORE Configure runs (pre-empts the arg-parse NRE). Probe failure = warn-and-continue.
- `postflightDisableCheckPolicy` — CHECK_POLICY=OFF on both generated logins + final orphan remap after
  a successful run. Postflight failure FAILS the step.
- `postflightEnforceIdentities` — applies maestroAppPoolUserName/Password to every {maestroAppPoolName}
  / {prefix}-* pool (Set-ItemProperty processModel.* + recycle started pools) and
  maestroServiceUserName/Password to the Profisee service (Win32_Service.Change + restart if running);
  reports stale previous identities. Always applies (same-name re-apply refreshes a stale password —
  deliberate).

**Key files**: CrewChief.Engine\Executors\IConfigureSqlRepair.cs (seam + DefaultConfigureSqlRepair,
direct SqlClient like SqlScriptExecutor; 6th optional ctor param on ConfigureExecutor);
RemoteWindowsOps.BuildWebSiteExistsScript / BuildIdentityEnforcementScript (JSON-emitting, passwords
escaped-embedded never output); ConfigureStep.TryGetSwitchValue / GetSwitchPairingWarnings.
Script actions run over the SAME route as the configure (LocalDirect → IProcessRunner powershell.exe
-EncodedCommand; credentialed → IRemoteCommandRunner), so existing test fakes intercept them.
Notes appended to StandardOutput under "── CrewChief custom actions ──".

**Also**: DetectConfigurationFailure gained `Login failed for user '(x)'` pattern (fires between
Missing-parameter and StackTrace patterns); GetSwitchPairingWarnings (sqlUserName w/o winAuth FALSE =
split-brain; winAuth FALSE w/o authAdEnabled/OIDC = zero providers; `{{`-tokenized values skipped)
surfaces in StepReadinessIssues AND run log. Fixed false doc claim "rejects duplicates" in the
Advanced-page help. Docs: 25_StepGuideConfigure.md § Custom Actions, 41_ReferenceConfigurationSwitches.md
§ "Two ways the generated login breaks".

**Gotchas**: preflight SQL failure never blocks the run (Configure is authoritative); FQDN for login
names = BoxPrepRouting.LocalMachineFqdn locally, DNS GetHostEntry for dotless remote names
(ConfigureExecutor.ResolveFqdn — dotted names trusted as-is). Tests: ConfigureCustomActionsTests.cs
(24 tests, ScriptedProcessRunner per-exe queue pattern). ProfiseeRpt login exists too — always repair both.
