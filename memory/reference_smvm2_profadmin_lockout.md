---
name: smvm2-profadmin-lockout
description: "SMVM2 local ProfAdmin lockout policy — 5 bad passwords locks FOREVER (manual unlock only); WinRM then returns plain \"Access is denied\""
metadata: 
  node_type: memory
  type: reference
  originSessionId: 1d4ab271-ff72-45c2-adef-439a2c473190
  modified: 2026-08-07T02:10:15.268Z
---

SMVM2 local account lockout policy: threshold 5, duration **Never** (stays locked until admin unlock), observation window 30 min. A locked local account makes every WinRM/NTLM logon fail with bare "Access is denied" — indistinguishable from wrong password or missing LocalAccountTokenFilterPolicy.

Verified 2026-08-06: SMVM2 already has LocalAccountTokenFilterPolicy=1, ProfAdmin enabled + in local Administrators, no SeDenyNetworkLogonRight hardening. So when the CrewChief /setup check as SMVM2\ProfAdmin says Access denied, check lockout FIRST:

```powershell
Invoke-Command -ComputerName SMVM2 { net user ProfAdmin | Select-String 'Account active' }
# Unlock:
Invoke-Command -ComputerName SMVM2 { $u=[ADSI]'WinNT://./ProfAdmin,user'; $u.IsAccountLocked=$false; $u.SetInfo() }
```

Related: [[project_crewchief_localrunas_account_mismatch]] (SMVM2 vs SMVMTR2 user id confusion may feed bad attempts), [[corp-domain-lockout-policy]].
