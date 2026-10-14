---
name: reference-corpltr94-local-admin-cleanup-gpo
description: "CORPLTR94 has a Local Admin Cleanup GPO that wipes local Administrators every ~90 min; only 3 domain principals survive, so manual admin grants for service accounts are erased"
metadata: 
  node_type: memory
  type: reference
  originSessionId: 12c5e146-c909-4a33-a49f-6cce5ea7b60f
  modified: 2026-07-31T01:09:58.550Z
---

`CORPLTR94` (OS Configuration: **Member Workstation**) has the GPO **`Local Admin Cleanup`** applied
(alongside `Local Admin for SCCM Client Push`). On every Group Policy refresh it **deletes every member
of local Administrators, then re-adds a fixed configured set** — the whole rewrite lands inside ~334 ms,
performed by `S-1-5-18` / `CORPLTR94$` (Logon ID `0x3E7`), i.e. SYSTEM, not a human.

Principals that survive (re-added every cycle):
- `CORP\Domain Admins`
- `CORP\SCCM Local Admins`
- `CORP\CORPLTR94_admin` — a **domain global group**, comment "AGene Webb", whose only member is `agenewe`
- `CORPLTR94\Administrator`

Anything else — e.g. a manually added `corp\speedmerchants` or `corp\qaautomation` — is **erased and not
re-added**. Observed: added 7:06:29 PM, evicted 7:59:05 PM (53 minutes later), ~40 s after the 7:58:25 PM
policy refresh. Earlier wipes the same day at 3:44 PM and 4:48 PM.

**Why:** this makes any box-prep run on this laptop time-bomb on a ~90-minute clock — a run can start
with admin rights and lose them mid-workload, surfacing as an opaque
`Cannot open W3SVC service on computer '.'` rather than anything credential-shaped.

**How to apply:** do NOT grant a service account local admin here and expect it to persist. `corp\agenewe`
is the only durably-admin identity available (via `CORPLTR94_admin`). Test/lab machines do **not** have
this GPO — which is why `corp\qaautomation` stays admin there. Treat this laptop as a poor box-prep target;
the narrow ask to IT is "exclude CORPLTR94 from `Local Admin Cleanup`" or "add the account to that policy's
set". Audit trail: Security log events **4732** (added) / **4733** (removed), group `S-1-5-32-544`.
`wevtutil` renders these timestamps in **local** time, not UTC.

Note `net user <acct> /domain` "Local Group Memberships" lists groups on the **DC**, not on the
workstation — it cannot tell you local-admin status. Use `Get-LocalGroupMember -Group Administrators`.

Related: [[reference_corp_domain_lockout_policy]] · [[project_crewchief_localrunas_account_mismatch]]
