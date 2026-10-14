---
name: feedback_requirements_system_review_gate_per_task
description: "Speedy requirements system (Q:\\...\\speedy\\requirements) — Gene reviews and refines after EACH numbered task of the restart prompt; stop and report, do not roll into the next task"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: c940690e-2c4b-49c8-a91c-5b1a0bd14b6d
  modified: 2026-09-17T21:53:26.219Z
---

On 2026-09-17 17:48, mid task 1 of the requirements restart prompt, Gene said: "Tell me when you get
done with this first task as it will be fully reviewed and refined before we continue."

**Why:** the requirements corpus is the authoritative source the whole programme will be regenerated
from; a defect in the templates or the validator rules propagates into every later tranche. He wants a
gate after each numbered task (1 verify+fix · 2 backlog · 3 tooling · 4 tranches), not one review at
the end.

**How to apply:** finish the numbered task completely (including the fixes it forces), rerun the check,
report verified / changed / undetermined in that order, then STOP. Do not start task N+1 in the same
turn. Corpus writes go through `Write-VaultFile.ps1` (Q: is the Obsidian vault). Related:
[[project_speedy_requirements_system]], [[reference_obsidian_smb_vault_watcher_blind]].
