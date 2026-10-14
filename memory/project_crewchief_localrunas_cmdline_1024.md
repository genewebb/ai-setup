---
name: crewchief-localrunas-cmdline-1024
description: CrewChief local Run-As failed after a SUCCESSFUL logon — CreateProcessWithTokenW caps lpCommandLine at 1024 chars and the driver was a ~4.7KB -EncodedCommand blob; FIXED 2026-07-30
metadata: 
  node_type: memory
  type: project
  originSessionId: e5c24a2f-da92-4542-98a8-0a9bfdd08f22
  modified: 2026-07-30T20:20:37.633Z
---

Every local Run-As box-prep step failed on first live use (2026-07-30, installed build at `C:\deploy\crewchief`)
with: *"Service 'Profisee 26.2.0' Stop failed: Windows rejected the local logon for 'corp\speedmerchants' with
Win32 error -2147024809. (CreateProcessWithTokenW failed with Win32 -2147024809; the CreateProcessAsUser
fallback failed with Win32 1314.)"*

**The credential was never the problem — `LogonUser` SUCCEEDED.** Both failures are in the process launch:

- `-2147024809` = `0x80070057` = `HRESULT_FROM_WIN32(ERROR_INVALID_PARAMETER)`. seclogon reports through
  `HRESULT_FROM_WIN32`, so `GetLastError` returns the HRESULT shape where the docs say `87`.
- **Root cause: `CreateProcessWithTokenW` caps `lpCommandLine` at 1,024 characters** (documented, far below
  ordinary `CreateProcess`'s 32,767). `LocalRunAsCommandRunner.BuildDriverCommandLine` carried the ~1.75 K-char
  driver script as a base64 `-EncodedCommand` blob → **~4.7 KB command line**. The pattern was copied from
  [[project_crewchief_remote_boxprep_transport]]'s `DefaultRemoteCommandRunner`, where it is CORRECT because
  that driver goes through `ProcessStartInfo` (ordinary `CreateProcess`).
- `1314` on the fallback is the separate, expected `ERROR_PRIVILEGE_NOT_HELD`: `CreateProcessAsUser` needs
  `SeAssignPrimaryTokenPrivilege`, which only LocalSystem holds. **So the bug is INVISIBLE when CrewChief runs
  as the installed LocalSystem service** — the fallback succeeds there (32,767 limit) and masks it. It only
  bites when CrewChief runs interactively.

**Fix (2026-07-30):** the driver is written to `driver.ps1` in the existing per-run work folder and launched with
`-File "<path>"` (~130 chars). `LocalRunAsCommandRunner.MaxCommandLineChars = 1024` is public and
`BuildDriverCommandLine` throws if the composed line exceeds it. Also added `LocalLogonErrors.NormalizeWin32`
(`0x8007xxxx` → low word, so `87` reaches its own case), a `Describe` entry for `87` that names the launch
arguments rather than the credential, and reworded the `_ =>` fallback from "Windows rejected the local logon"
to "Windows could not run the command as …" — that wording is reached by LAUNCH failures too and actively
misdirected the diagnosis.

**No ACL grant was added:** the child already had to WRITE three files this process created in that folder, and
one DACL governs read and write, so reading `driver.ps1` adds no new access requirement. (Managed
`DirectorySecurity` would also need a NuGet package the `net10.0` engine doesn't reference — see
`CrewChief.Cli\ServiceAccountOps.cs:175`, which uses `icacls` for the same reason.)

**Why it shipped broken:** the real launch is only covered by `LocalRunAsIntegrationTests`'s
`[TestCategory("LocalRunAsLab")]` test, gated on `CREWCHIEF_TEST_RUNAS_USER`/`_PASSWORD`, so it had never run.
The unit suite stubs `LaunchAsync`, so nothing exercised the P/Invoke. Now pinned by
`DriverCommandLine_StaysUnderTheWin32Limit_AndIsNotEncodedInline`, which asserts against `-EncodedCommand`
explicitly so a future "simplification" back to the inline form fails loudly.

Related: [[project_crewchief_local_runas_direct_logon]], [[project_crewchief_remote_boxprep_transport]],
[[reference_corp_domain_lockout_policy]]
