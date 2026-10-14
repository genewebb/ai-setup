---
name: smvm2-profisee-identity-drift-chain
description: "SMVM2 26.2.0 config \"success\" hid a 3-layer identity failure — stale SMVM2\\ProfAdmin on all 19 pools (WAS 5021), service still .\\ProfAdmin, generated SQL login locked on smvmdb2"
metadata: 
  node_type: memory
  type: project
  originSessionId: 1d4ab271-ff72-45c2-adef-439a2c473190
  modified: 2026-08-07T13:00:25.350Z
---

2026-08-07: Configuration.exe on SMVM2 printed "The operation completed successfully" while every
health check timed out — the known exit-0 lie ([[configuration-exe-failure-modes]]). Real chain:

1. **All 19 Profisee* app pools carried the identity of a PREVIOUS configure** — `SMVM2\ProfAdmin`
   with a stale password — even though the command passed `/maestroAppPoolUserName:corp\speedmerchants`.
   Configuration.exe logs "creating/updating of AppPool ... Finished" but does NOT rewrite an existing
   pool's identity. WAS 5021/5057/5059 "identity is invalid" disabled every pool on first request →
   all health probes time out, Service.svc 503. **19 pools retrying a bad ProfAdmin password is also
   what locked SMVM2\ProfAdmin out** ([[smvm2-profadmin-lockout]]).
   FIX APPLIED: set processModel identityType/userName/password on all 19 pools to corp\speedmerchants
   (password verified via a real Kerberos logon first) — pools then started and STAYED started.
2. **Windows service "Profisee 26.2.0 (Profisee)" still runs as `.\ProfAdmin`** (config wanted
   corp\speedmerchants). Same drift, service side. Runs, but one ProfAdmin lockout away from dying.
   Fix (operator): `sc.exe config "Profisee 26.2.0 (Profisee)" obj= corp\speedmerchants password= ...`.
3. **Generated SQL login `Profisee_Profisee_SMVM2.corp.profisee.com` LOCKED on smvmdb2**
   (LOGINPROPERTY IsLocked=1, CHECK_POLICY lockout) → every microservice dies at
   "Pre start-up check failed ... Login failed" → health endpoints 500/503.
   Fix (operator): `ALTER LOGIN [x] WITH CHECK_POLICY = OFF;` then `= ON;` (unlocks without password),
   recycle Profisee* pools. If it RELOCKS, the stored generated password mismatches — re-run
   Configure (its "update security script Sql Auth" resets that login).

Diagnostic order that worked: pool states → WAS events (5021) → pool processModel.userName →
verify intended password with ONE real logon → SQL LOGINPROPERTY IsLocked. This case is the
validation for CrewChief's Configure identity-drift prerun check ([[crewchief-website-step]] session).

Gotcha: `Invoke-Command SMVM2 { param(...) ... IIS:\AppPools ... }` intermittently returned ZERO
pools/services in param-bound scriptblocks; same query with `$using:` worked. Retry with `$using:`
before trusting an empty IIS enumeration.
