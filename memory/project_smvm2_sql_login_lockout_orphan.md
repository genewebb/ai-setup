---
name: smvm2-sql-login-lockout-orphan
description: SMVM2 SQL-auth configure failures verified 2026-08-07 — generated login Profisee_profisee_SMVM2.corp.profisee.com LOCKED OUT (CHECK_POLICY=ON) AND its profisee DB user ORPHANED (SID mismatch); Configure rerun can never heal either.
metadata: 
  node_type: memory
  type: project
  originSessionId: d7c3bb9f-f56b-459f-8385-d3a178b89509
  modified: 2026-08-07T15:38:49.248Z
---

Verified 2026-08-07 on smvmdb2 (live queries, CORP\AGeneWe integrated auth works from laptop):

**Two independent faults behind 18456 'Login failed for user Profisee_profisee_SMVM2.corp.profisee.com':**

1. **Login locked out.** `LOGINPROPERTY('IsLocked')=1`, `is_policy_checked=1`, lockout_time 2026-08-07 15:16:21 (during the configure run, when services started with stale passwords). Corp lockout policy applies because `Script.UpdateSecurityForSql.sql` CREATE LOGIN omits `CHECK_POLICY=OFF`, and its `ALTER LOGIN ... WITH PASSWORD` (line 37) omits `UNLOCK` — so reruns reset the password but never unlock.
2. **DB users orphaned.** In DB `profisee`, users `Profisee_profisee_SMVM2.corp.profisee.com` AND `ProfiseeRpt_profisee_SMVM2.corp.profisee.com` have SIDs ≠ their server logins (DB restored / login recreated). Scripts only `CREATE USER IF NOT EXISTS` by name; no `ALTER USER ... WITH LOGIN` remap anywhere. Server-side symptom: 18456 State 38 "Failed to open the explicitly specified database" (seen in smvmdb2 errorlog 7/15). Client always sees generic State 1.

**Code facts (platform repo, Server\Configuration):**
- Login name = `Profisee_{maestroDatabase}_{FQDN}` — WebAppConfigurationContext.cs:284.
- Non-container cmdline run: `IsEdit` only set under ConfigForContainer (WebAppConfigurationContext.cs:360-363) → UpdateDatabase 5494-5510 generates a **new GUID password every run** and writes it to all appsettings via SaveConfigSettings→setSqlPasswords.
- `updateWFSubscriberConfigurations` (WebAppConfigurationContext.cs:3398) swallows its exception (catch → LogException → logs "finished") → DB-stored encrypted subscriber conn strings keep OLD password → services hammer old password → feeds the lockout loop.
- "Running update security script ... started/finished" both logged BEFORE processSqlString executes (DatabaseUtilities.cs:950-956) — success lines are not evidence.

**Fix (sysadmin on smvmdb2):** `ALTER LOGIN [...] WITH CHECK_POLICY = OFF` (clears lock, prevents recurrence — GUID rotating password gains nothing from policy), then in `profisee` DB `ALTER USER [...] WITH LOGIN = [...]` for both Profisee_ and ProfiseeRpt_ users, then rerun Configuration.exe.

Related: [[smvm2-profisee-identity-drift-chain]], [[configuration-exe-failure-modes]], [[smvm2-profadmin-lockout]].
