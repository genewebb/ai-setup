---
name: project-machine-config-laptop-live-2026-10-01
description: "Machine-portable AI config is LIVE on the laptop 10/1 (spec rev 4); runtime is a copy installed from Q: work-ai via Install-AIMachine / ai launcher; next = SMVMTR1 rollout (T14)"
metadata:
  node_type: memory
  type: project
  originSessionId: e071532a-95ca-4f16-ae81-7a5cb0301769
  modified: 2026-10-01T12:54:25.967Z
---

Laptop (CORPLTR94) switched 10/1/2026 to the machine-config system (spec `C:\working\machine-config-design.md` rev 4; build root `D:\DeployMyAI`, plan.md there).

- `~\.claude` skills/agents/commands/CLAUDE.md are now real COPIES (old `~\AI` junctions replaced). Edit the corpus `{AIWorkRoot}` (Q: work-ai), never `~\.claude`; `ai` launcher (`~\.local\bin\ai.cmd`) or `/machine-config apply` installs. Hand edits = drift, apply exits 3.
- settings.json is GENERATED from `{AIWorkRoot}\claude\settings.template.json` + `permissions.yaml` + profile `## Claude access` / `## Git policy` (`C:\Deploy\Setup\ProfileMachineConfig.md`).
- Laptop git policy: speedmerchants Commit yes, Push NO (Gene 10/1), Worktrees yes; every other repo nothing. git-guard enforces.
- MyLoop fully retired: Q: copies + myloop/myfable commands archived in `C:\DataArchive\myloop-retired-2026-10-01`, then deleted (Gene 10/1).
- Pre-apply backup: `C:\DataArchive\claude-pre-machine-config-20261001` (links.tsv records old link layout).
- Settings env now sets TEMP=`C:\tmp\temp`, CLAUDE_CODE_TMPDIR=`C:\tmp` (scratchpad `C:\tmp\claude`).

**Why:** one corpus, per-machine profile, no hard paths in shared files ([[feedback-machine-portable-ai-config]]).
**How to apply:** next = T14 SMVMTR1 (repo `D:\devops\repos\speedmerchants`, worktrees `D:\devops\worktrees` need `git worktree repair`, scratch `D:\tmp`); re-run `D:\DeployMyAI\steps\Merge-StreamSkills.ps1` before the push. Vault writes: [[reference-write-aifile-replaces-write-vaultfile]].
