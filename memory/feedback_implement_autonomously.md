---
name: feedback-implement-autonomously
description: "When told to implement, finish all steps without stopping; build the full solution and fix ALL compile errors before reporting"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 644f2317-0d3b-4825-9aab-24140b0a46ed
---

When the user says "implement," complete **all** steps without stopping unless a genuinely blocking error occurs or explicit guidance is needed — don't pause for confirmation between steps. When compile errors appear, **build the full solution and fix every error** before stopping or reporting; don't report back with the build still broken.

**Why:** Migrated from the repo-root `AGENTS.md` "Learned User Preferences" (2026-05-31). The user works in long autonomous stretches and drives session pacing themselves.

**How to apply:** Treat an "implement X" instruction as authorization to run the whole task to completion. Before declaring done, run a full-solution build and clear all errors. Pairs with [[feedback-ui-parity-before-new]] and the no-mid-session-break rule in global instructions.