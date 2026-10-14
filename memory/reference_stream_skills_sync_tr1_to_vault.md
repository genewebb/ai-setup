---
name: stream-skills-sync-tr1-to-vault
description: "How /stream-* skill edits made on SMVMTR1 get to the laptop: machine-sync SMVMTR1->CORPLTR94 -What corpus -Apply -Publish, then Install-AIMachine.ps1"
metadata:
  node_type: memory
  type: reference
  originSessionId: 7a4a12d9-1bfc-4bb2-92dc-efc4e075367a
  modified: 2026-10-04T14:35:24.102Z
---

Gene edits the /stream-* skills on **SMVMTR1** (corpus `\\SMVMTR1\d$\AIWork\work-ai`).

Sync (done 2026-10-04, 31 files, 0 conflicts):
1. `pwsh -NoProfile -Command "& D:\DeployMyAI\steps\Sync-Machine.ps1 -Source SMVMTR1 -Target CORPLTR94 -What corpus"` (dry run; `-What` list must go through `-Command`, `-File` rejects `corpus,streamhost` as one string).
2. Same + `-Apply -Publish` (laptop corpus D:\DeployMyAI\corpus, publish to Q:).
3. `~\.claude\bin\Install-AIMachine.ps1 -WhatIf`, then without -WhatIf: installs into `~\.claude\skills` (copies, not links). Restart Claude to pick up.

Operator guide for the kit: `Q:\Work\Work\99_Frequent\StreamGuide.md`.

Related: [[project_machine_sync_skill_2026-10-01]], [[stream-host-smvmtr1]].
