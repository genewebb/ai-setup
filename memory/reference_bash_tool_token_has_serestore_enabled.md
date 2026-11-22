---
name: reference-bash-tool-token-has-serestore-enabled
description: "On SMVMTR1 the Bash tool's token has SeBackup/SeRestorePrivilege ENABLED, the PowerShell tool's has them Disabled, so ACL-deny test fixtures pass in one shell and fail in the other"
metadata:
  node_type: memory
  type: reference
  originSessionId: 1913cdde-afda-4717-9d00-4dc3c3f40fcf
  modified: 2026-10-04T03:35:14.305Z
---

Measured 2026-10-01 on SMVMTR1 (elevated session; both shells are High integrity and members of Administrators):
- `whoami /priv` from the PowerShell tool: SeRestorePrivilege and SeBackupPrivilege are **Disabled**.
- From the Bash tool (Git Bash): both are **Enabled**.

Consequence: a test fixture that blocks an ACL change with a Deny (for example, an inherit-only OWNER RIGHTS deny of ChangePermissions to take away WRITE_DAC) works under PowerShell but not under Bash. Restore privilege rewrites the ACL anyway. G3.T021's five refusal tests passed in the builder's PowerShell grader run and failed in a blind verifier that ran them through Bash.

**How to apply:**
- Run ACL- or privilege-sensitive tests and graders through the PowerShell tool.
- Tell verifiers which shell to use.
- Make such fixtures probe once and report `Assert.Inconclusive` when the deny does not take, instead of a false product failure.

- **Integrate drains too:** on 2026-10-04, drain 1004b was launched via Bash and graded G3.T269 with SeRestore enabled. Two ACL tests went Inconclusive, so the result was a false SUSPECT and the row was set to planned. Launch drains with the PowerShell tool and `run_in_background`. Undo a false SUSPECT with `Update-Task -Role integrate -To built` (the planned>built transition exists for this) once no Bash drain is running.

Related: [[reference-verifier-subagent-stalls-while-builder-beats]], [[reference-integrate-drain-needs-long-background-timeout]].
