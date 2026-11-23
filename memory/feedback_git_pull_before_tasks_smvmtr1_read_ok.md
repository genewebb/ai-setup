---
name: feedback-git-pull-before-tasks-smvmtr1-read-ok
description: Gene 11/22 - git pull (ff-only) before tasks to get current commits; may read whatever is needed on SMVMTR1 for better answers
metadata:
  node_type: memory
  type: feedback
  originSessionId: 4dd5f09a-5ddb-4cb7-8a77-b1ee5237e704
  modified: 2026-11-23T00:56:23.319Z
---

Gene (2026-11-22): "You can do git pulls before your tasks to make sure you have the most current commits" and "You can access whatever you need on SMVMTR1 to give me a better answers".

**Why:** the laptop speedmerchants clone was a month stale (afa8799, 10/17 `.streams`). That gave wrong throughput (55 tasks/day vs the live 39) and stale suite facts.

**How to apply:**
- Before Speedy analysis, run `git -C C:\devops\repos\speedmerchants pull --ff-only`. Pull only: no commit or push from the laptop.
- Read live stream state on SMVMTR1 by UNC: `\\SMVMTR1\d$\devops\repos\speedmerchants\.streams\` (tasks.json, suites/<group>.run.json).
- Git on that UNC path needs `git -c safe.directory=* -C <unc>` (dubious ownership).
- If UNC gives access denied, see [[reference_smvmtr1_smb_access_denied_cached_logon]].
