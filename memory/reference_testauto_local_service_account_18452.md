---
name: reference_testauto_local_service_account_18452
description: "SQL 18452 \"login is from an untrusted domain\" in TestAuto means the Windows service runs as a LOCAL account reaching remote SQL; the installer's keep-current upgrade path allowed it until 2026-08-10"
metadata: 
  node_type: memory
  type: reference
  originSessionId: 53e568ca-6ecd-4060-8b4d-c375fd5aadc8
  modified: 2026-08-11T03:19:15.458Z
---

`Login failed. The login is from an untrusted domain and cannot be used with Integrated authentication.` (error 18452, state 1) from a TestAuto step = the **service identity is a local account** and the target SQL Server is on another machine. A local SID exists only in that box's own SAM, so a remote SQL Server cannot resolve it and rejects pre-authorization. Contrast: 18456 = principal resolved but not authorized; 4060 = login fine, database missing.

Diagnosis on 2026-08-10, SMVMTR2 (verified, not inferred):
- `sc.exe \\SMVMTR2 qc TestAuto` reported `SERVICE_START_NAME : .\ProfAdmin` — a local account.
- `web\LogFiles\SystemLog.log` stamps the identity on every line (`SMVMTR2\ProfAdmin`), which is the fastest way to confirm what a deployed TestAuto is actually running as.
- SMVMTR2 *does* have a local `MSSQLSERVER` instance, so a local account against local SQL would have worked — 18452 by itself proves the target was off-box.

Root cause in the installer: `TestAuto.iss`'s `CanKeepCurrentAccount()` screened the existing service account with `AccountIsBuiltIn` only, never `AccountIsLocal`. So on an upgrade, "Keep the current account" was offered *and preselected* for a service already running as a local account — bypassing the domain-account refusal that only fired on typed input (`NextButtonClick`) and on a supplied account (`PrepareToInstall`). Fixed by adding the `AccountIsLocal` term; the wizard now names the unkeepable account and demands a domain one, and an unattended upgrade of such a service fails instead of preserving it.

Safe to swap the service account on an installed box: TestAuto's secrets are DPAPI **LocalMachine** (`MasterPasswordManager`, and `ProtectKeysWithDpapi(protectToLocalMachine: true)` in `Program.cs`), so `master.json` and the data-protection key ring survive an identity change — no re-bootstrap. What does *not* carry over: read access to the HTTPS certificate's private key.

Related: [[project_testauto_service_install_plan]] · [[reference_testauto_entra_p2p_cert_lockout]] · [[reference_smvm2_profadmin_lockout]] · [[reference_corp_dual_accounts]]
