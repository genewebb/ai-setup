---
name: project-machine-config-tr1-live-2026-10-01
description: "SMVMTR1 on machine-config 10/1 (ALL GREEN); skills/agents/commands are symlinks to the AIWork share by UNC (SkillsLinkRoot, R38); next T15 = TR2/TR3"
metadata:
  node_type: memory
  type: project
  originSessionId: e071532a-95ca-4f16-ae81-7a5cb0301769
  modified: 2026-10-01T15:21:23.461Z
---

SMVMTR1 went live on machine-config 10/1/2026 11:09 (revision 1F86ACFD3CA2). The rollout report `D:\tmp\machine-config-rollout\report-20261001-110450.txt` came back ALL GREEN. Follows [[project-machine-config-laptop-live-2026-10-01]].

- Profile key `SkillsLinkRoot` (R38) = `\\smshareddrive.file.core.windows.net\sharedfiles\AIWork`. It is the same tree as S:\AIWork, given by UNC because an elevated console does not see the S: mapping. 184 skills, 12 agents and 2 commands are symlinks into it. `synced` and `.trash` are real folders. CLAUDE.md is a copy.
- The corpus wins on the share: the apply wrote about 201 newer, tokenized files over TR1's older literal-D:-path snapshot. A line diff found 0 real S:-only edits. Old content is in `D:\DataArchive\ai-config-2026-10-01\pre-rollout\claude` and the rollback snapshot.
- The corpus copy on TR1 is `D:\AIWork\work-ai`, pushed from the laptop by `D:\DeployMyAI\steps\Stage-TR1.ps1`. Change the corpus on the laptop, sync it to Q:, re-stage, then re-apply on TR1.
- Open: 1 prunable worktree record `C:/Tmp/g1t17-salv`. Prune it only after Gene confirms.

**Why:** Gene wanted TR1 to keep its symlinks, with the profile choosing the target. TR2 and TR3 share the same tree.
**How to apply:** Laptop build area is `D:\DeployMyAI` (moved there from C:\tmp 10/1). T15 = roll TR2/TR3 by `Q:\Work\Work\99_Frequent\HowToInstall.md` (Stage-Machine.ps1 + {AIWorkRoot}\setup\Start-MachineRollout.ps1); Gene said wait. Until then their sessions see unresolved `{Key}` placeholders in shared skills. Never write to the share without the line-diff check: mtime comparisons are meaningless after a corpus rewrite.
