---
name: feedback-inrepo-ai-docs-to-workai
description: "User prefers in-repo AI/agent guidance migrated into work-ai skills, not kept in the repo"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 644f2317-0d3b-4825-9aab-24140b0a46ed
---

When the repo contains AI/agent guidance files (e.g. a per-module `AGENTS.md`/`Agents.md`), the user prefers to **migrate the content into a work-ai skill** (with a linker junction) and **remove the repo copy** — i.e. centralize AI guidance in work-ai rather than keep it in the repo.

**Why:** The user wants a single source of truth for agent guidance in the work-ai skill corpus, consistent with how all other skills are managed.

**How to apply:** If an in-repo agent guide is a maintainer/extender guide that overlaps existing skills, create a new skill (maintainer view) that cross-links the consumer-view skills, register it in `link-to-ai.ps1`, run the linker, then `git rm` the repo file (never commit). I advised keeping it in-repo (teammates/CI lose it on a true move) — user overrode; respect the migration preference and don't re-litigate. Concrete instance: `TestAuto.Utilities/Agents.md` → [[testauto-utilities-module]] skill (2026-05-31, scan 8).
