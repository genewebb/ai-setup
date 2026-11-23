---
name: reference-smvmtr1-staging-d-laptop
description: "SMVMTR1 cannot read Q:; stage files for SMVMTR1 sessions in D:\\Laptop (\\\\SMVMTR1\\d$\\Laptop from the laptop), then Gene runs the prompt there"
metadata:
  node_type: memory
  type: reference
  originSessionId: 4dd5f09a-5ddb-4cb7-8a77-b1ee5237e704
  modified: 2026-11-23T03:49:16.906Z
---

Gene (2026-11-22): SMVMTR1 has no access to Q:.

To hand files to SMVMTR1 sessions (the planner, stream sessions):
- Stage them in `D:\Laptop` on SMVMTR1. From the laptop that is `\\SMVMTR1\d$\Laptop`.
- In any prompt or inbox item meant for SMVMTR1, use `D:\Laptop\...` paths, never Q: or W:.
- Gene runs the prompt on SMVMTR1 so the files get picked up there.

Related: [[feedback_git_pull_before_tasks_smvmtr1_read_ok]], [[reference_smvmtr1_smb_access_denied_cached_logon]].
