---
name: feedback_git_ok_testautoisolation_2026-11-18
description: Gene 2026-11-18 on SMVMTR1 - git commands allowed on the TestAutoIsolation project in speed-merchants as needed; pickup prompt still says Gene commits
metadata:
  node_type: memory
  type: feedback
  originSessionId: 48e8ba62-42b2-44d2-b5a8-39d62dc558bf
  modified: 2026-11-18T08:52:53.556Z
---

Gene 2026-11-18 (SMVMTR1 session, isolation pickup): "You now have permission to do git commands on the TestAutoIsolation project as needed."

Scope: `D:\devops\repos\speed-merchants\TestAutoIsolation`, branch `bug/isolation_testing_linux/genewebb`. Never main, never push to main (shared ADO repo, see [[feedback_no_direct_commits_to_main_pr_only]]). The same day's pickup prompt said "Never commit or push; I do" - the later message widens it to git commands for TestAutoIsolation work; repo-level files outside that folder (`.gitignore`, `docs/`) stay Gene's to commit. git-guard may still block speed-merchants (not in the machine git policy table); if it does, say so, do not bypass.

Gene 2026-11-18 04:34: "You have permission to do the git commits and build and install TestAutoIsolation updates on this machine" - build the installer AND install it on SMVMTR1 myself (service TestAutoIsolation), no need to wait for Gene.

**Why:** Gene wants TAI code changes on this machine handled end to end.
**How to apply:** status/diff/log/add/commit on the TAI folder on the work branch when a TAI change is done and verified; ask before push or anything destructive. Related: [[project_testautoisolation_2026-11-13]].
