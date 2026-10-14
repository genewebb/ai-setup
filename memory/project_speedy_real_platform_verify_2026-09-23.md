---
name: project_speedy_real_platform_verify_2026-09-23
description: "Real-platform verification plan for the CrewChief port — targets, the one account, Gene's permissions (SMVM2 objects, IIS reset, SetApiKey on a restored copy)"
metadata:
  node_type: memory
  type: project
  originSessionId: 0359fc02-cccc-4830-81fb-20a4bcd43ea3
  modified: 2026-09-23T20:00:05.266Z
---

Gene 2026-09-23: real-platform runs for the CrewChief port use the test machines from CORPLTR94. There are no new service accounts; **CORP\speedmerchants** is the only test identity. It is already local Administrator on SMVM2 and sysadmin on SMVMDB2. Gene enters its password into Speedy Secrets on a verify host (127.0.0.1:5290, state C:\tmp\speedy-verify, NOT the review host on 5280). Claude never sees or types it.

Reach from CORPLTR94:
- SMVM2: WinRM Kerberos works as corp\agenewe (admin).
- SMVMTR2 and SMVMDB2: WinRM fails with Kerberos 0x80090311, probably a missing WSMAN SPN; a domain admin must run setspn. The SMB c$ share works.
- SMVMDB2: SQL works as sysadmin. Its databases are profisee, ModelSource and ConnectExport.

Permissions granted:
- **SMVM2 objects:** create and then delete throwaway objects prefixed speedy-verify-: an app pool, a website, a service, and C:\SpeedyVerify shared as \\SMVM2\speedy-verify. Never touch Profisee objects.
- **IIS reset:** allowed "as needed for your tests".
- **SetApiKey:** runs only against a restored copy, profisee_speedyverify on SMVMDB2, which is dropped afterwards. Never against the live `profisee` database.

The "limited account refused" paths cannot be tested, because there is no non-admin account. Record them as a gap.

**Why:** these close the "never run on a real system" gaps in the coverage rows. See [[project_crewchief_remaining_port_2026-09-23]].
**How to apply:** start only after the pending test/census work is committed. Build from the committed code. Record the evidence as a new attempt under test-evidence/<commit>/ in the vault.

**Update 2026-09-23 17:15:** Self-registration UI shipped in c9ec693 (/register, 3 steps, QR code rendered on the server, sign-in page links to it). Verify host rebuilt from c9ec693 at C:\tmp\speedy-verify-src and running on 127.0.0.1:5290 with state C:\tmp\speedy-verify (identity store empty). Gene registers there, then sets up Secrets (default profile, CORP\speedmerchants Run As credential, RSA key). Gotcha: static-SSR multi-step forms must restore the step from the posted `_handler` in OnInitialized, or Blazor refuses with "no form on the page currently has that name".

**Update 2026-09-23 17:40 (Gene):** Windows/IIS/service targets moved to SMVMTR2; DB ops stay SMVMDB2; SetApiKey + Model Import on the empty Profisee instance on SMVM2. Gene registered through /register (works) and imported an SMVMTR2 secrets file into profile "smvmtr2" (22 CrewChief-style sections) — but defaultProfileId was null and no RSA key imported. SMVMTR2 WinRM: this shell's logon session has NO Kerberos TGT (klist 1312; LDAP bind fails), so remoting falls back to NTLM, which needs TrustedHosts; Gene chose to add SMVMTR2 to TrustedHosts (elevated, Gene runs it). The Speedy host started from this shell inherits the same session.
