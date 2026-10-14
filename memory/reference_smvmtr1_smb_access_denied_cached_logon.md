---
name: reference-smvmtr1-smb-access-denied-cached-logon
description: "Laptop -> \\SMVMTR1\d$ 'Access is denied' / Test-Path False while ping and 445 work = the Claude process's logon session (type 11 cached logon) has no Kerberos TGT; fix = cmdkey /add:SMVMTR1 /user:corp\\agenewe /pass (Gene types it), verified 2026-10-06"
metadata:
  type: reference
---

2026-10-06 15:00: every SMB read of `\\SMVMTR1\d$` / `c$` from Claude Code on CORPLTR94 failed (`Test-Path` False, `net view` System error 5). Network fine (DNS 10.0.0.6, port 445 open, CorpDC01 88/389/445 open, `nltest /sc_query` NERR_Success). Cause: the Claude process ran in logon session 0x209c972, LogonType 11 (CachedInteractive) from 10/5 14:40, with `Cached Tickets: (0)`; `klist tgt` = "No credentials are available in the security package" (1312), `klist get cifs/...` = 0xc000005e STATUS_NO_LOGON_SERVERS.

**Fix that worked:** Gene ran `cmdkey /add:SMVMTR1 /user:corp\agenewe /pass` in any terminal (Credential Manager is per user, not per logon session); the next `Test-Path` from Claude was True. Diagnose with `klist` (0 tickets) + `Get-CimInstance Win32_LogonSession` (LogonType 11) before suggesting it. Related: [[project_machine_sync_skill_2026-10-01]].
