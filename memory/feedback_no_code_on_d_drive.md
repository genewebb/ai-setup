---
name: feedback_no_code_on_d_drive
description: "NO code on the D: drive on any machine; repos/worktrees live at C:\\devops\\repos\\<name> and C:\\devops\\worktrees, real folders, laid out like the laptop"
metadata:
  node_type: memory
  type: feedback
  originSessionId: c3aa3b64-526e-4596-8884-263473ad4aff
  modified: 2026-09-29T02:05:11.367Z
---

No code ever goes on D:, on any machine (laptop, SMVMTR1, SMVMTR2). Repos go at `C:\devops\repos\<name>` and worktrees at
`C:\devops\worktrees`. They are real folders with no junctions to D:, laid out exactly like the laptop.

**Why:** Gene, 9/28 21:59: "NO CODE GOES ON THE D DRIVE set this up for c:\devops\repos\speedmerchants just like my
laptop". Claude had put the stream-host repos on D: behind junctions to save C: space, without asking.

**How to apply:** never default a data drive or junction code to another volume. If C: is short on space, say so and
let Gene grow C:; don't relocate. Related: [[project_stream_host_smvmtr1_2026-09-28]].
