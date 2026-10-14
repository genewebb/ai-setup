---
name: corp-domain-lockout-policy
description: "corp.profisee.com AD lockout policy — 5 bad attempts / 30-min window, duration Never (manual admin unlock only); checked 2026-07-29"
metadata: 
  node_type: memory
  type: reference
  originSessionId: c29244b8-ec7a-4e10-b9fe-312174cc028e
  modified: 2026-07-30T01:21:55.842Z
---

corp.profisee.com domain lockout policy (verified via `net accounts /domain` on 2026-07-29):

- **Lockout threshold**: 5 bad password attempts
- **Observation window**: 30 minutes
- **Lockout duration**: Never — NO auto-unlock; requires manual unlock by an account with AD unlock rights
- corp\agenewe does NOT have unlock rights (ADSI SetInfo → Access denied)
- Check status without RSAT: `net user <name> /domain` → "Account active: Locked"
- Lockout is domain-wide (AD object flag, urgent replication), never per-machine

This is why [[crewchief-local-runas-direct-logon]] LogonAttemptGuard matters: a stale password retried 5x within 30 min bricks corp\speedmerchants until an admin unlocks it.
