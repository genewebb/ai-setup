---
name: reference_acl_deny_tests_need_backup_privilege_off
description: Windows deny-ACL tests pass on one token and fail on another; an enabled SeBackupPrivilege lets a listing through whatever the DACL says
metadata:
  node_type: memory
  type: reference
  originSessionId: 8082bbc9-52fb-4e53-9a34-f0b6977ebe46
  modified: 2026-10-02T00:11:07.845Z
---

A test that denies `FileSystemRights.ListDirectory` (or ReadData) to the current SID cannot deny anything when the process token has **SeBackupPrivilege enabled**. That happens in an elevated admin session or under a service account. Windows then grants the listing whatever the DACL says: `Directory.EnumerateFileSystemEntries` and even `cmd dir` succeed. On SMVMTR1 the builder's token had the privilege present but disabled, so the tests passed there. The verifier's token had it enabled, so the same tests were red (G3.T080, 2026-10-01).

**Why:** the test result depends on which seat runs it.

**How to apply:**
- Run the code under test through `WindowsIdentity.RunImpersonatedAsync`, on a `DuplicateTokenEx` copy of the process token.
- On that copy, disable SeBackupPrivilege and SeRestorePrivilege with `AdjustTokenPrivileges`. It is the same user, so identity strings do not change. Pattern: `tests/Tests.Unit/FoundationSetupChecksTests.cs` (`WithoutBackupPrivilegeAsync`).
- To reproduce the elevated case, enable both privileges in a child pwsh, then run `dotnet test` from it. The child process inherits the enabled state.
- `whoami /priv` shows the current state.
- Older tests with the same weakness: ProtectionKeyStartCheckTests, ProtectionKeyProvisioningTests and BackupSelectionAndListingTests. They have not been checked yet.
