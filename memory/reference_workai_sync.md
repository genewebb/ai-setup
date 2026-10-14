---
name: reference-workai-sync
description: "The work-ai skill repo (Obsidian vault) is managed by Obsidian sync, not git — never suggest commits/branches for it"
metadata: 
  node_type: memory
  type: reference
  originSessionId: a04b6158-5be1-4e53-afea-49c2d2e5eb2e
---

`C:\devopslocal\ObsidianVaults\Work\MyWorkVault\03 Shared\work-ai\` (the AI skills/rules/agents source-of-truth) is versioned and propagated by **Obsidian sync**, NOT git. A stray `.git` folder exists there but is not used.

**How to apply:** After editing skills/rules/README/backlog in work-ai, the change is done once written to disk — Obsidian sync distributes it. Do NOT suggest `git commit`/branch/push for this folder, and do not report "uncommitted changes" as an action item. (Distinct from [[feedback_no_commits]], which is about the speed-merchants code repos.) Renaming a skill still requires re-running `link-to-ai.ps1` and deleting the old junction. See [[ConnEx Import Tokenization]] for the connex rename precedent.
