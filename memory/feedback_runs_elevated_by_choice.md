---
name: feedback-runs-elevated-by-choice
description: "Gene runs Claude ELEVATED (admin account agenewe) all the time by choice; do not push least-privilege / gsudo-split setups (Martin's gsudo-elevation skill declined 10/14)"
metadata:
  node_type: memory
  type: feedback
  originSessionId: f0454aab-598a-49d1-b5bc-df925330f846
  modified: 2026-10-15T00:41:36.686Z
---

Gene 2026-10-14, declining Martin Perry's `gsudo-elevation` skill: "martin runs his not elevated I run my elevated
all the time, not sure I want to change this".

**Why:** his workflow is built around Claude running as the admin account (corp\agenewe) on the laptop and CORPVM17;
splitting into normal-user + per-command elevation would change every machine and script.
**How to apply:** do not recommend least-privilege/gsudo elevation patterns or two-account splits as improvements.
Still handle the real consequences (user-scope env vars, GitHub/ADO credentials and git safe.directory are per
account) when they come up. Related: [[reference-ai-profisee-review-2026-10-14]].
