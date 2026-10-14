---
name: corpltr94-svc-web-lockout
description: "CORPLTR94 speedmerchants IIS pools run as corp\\svc_web (locked out 2026-08-09, domain lockout duration Never = manual IT unlock); Profisee pools run corp\\agenewe"
metadata: 
  node_type: memory
  type: reference
  originSessionId: 42705a5a-fb23-47d4-a4e4-c0913d6a696a
  modified: 2026-08-09T22:49:46.177Z
---

On CORPLTR94, the `speedmerchants-*` IIS app pools (ScenarioMgt Profisee instance, hosts TestAutoSecrets) run as **SpecificUser `corp\svc_web`** (password last set 2015-08-20, never expires). The `Profisee-*` pools run as `corp\agenewe` and stay healthy.

2026-08-09: `corp\svc_web` was locked out → every speedmerchants pool start fails with WAS event 5021 (identity invalid) then 5057/5059 (pool disabled) → whole instance returns HTTP.sys 503 → TestAuto startup cannot fetch TestAutoSecrets → degraded mode.

Domain policy: lockout threshold 5, observation 30 min, **duration Never** — auto-unlock never happens; needs IT/domain-admin unlock ([[corp-domain-no-ad-write]]: user cannot unlock). If the stored pool password is STALE, pool restarts will re-lock the account in 5 attempts — verify/re-enter current password in ALL speedmerchants-* pools after unlock, or switch pools to a working identity.

Check first when speedmerchants REST 503s: `appcmd list apppool | findstr speedmerchants` + System event log WAS 5021. Same failure family as [[smvm2-profisee-identity-drift]].

Full svc_web usage census on CORPLTR94 (2026-08-09): 19 speedmerchants-* pools, 19 MyDevProfisee-* pools, Windows service "Profisee 26.1.0 (speedmerchants)" (kept running through lockout on its pre-lockout token — easy to miss when re-identitying), 3 scheduled tasks (2 OneDrive + VS UpdateConfiguration; per-user tasks from a past interactive svc_web logon). Local Security log had ONLY "account locked out" 4625s, zero bad-password → lockout source is ANOTHER machine (SMVM VMs suspected); DC event 4740 names the caller computer. 2026-08-09 18:49: user removing all svc_web usage from CORPLTR94, retest pending.
