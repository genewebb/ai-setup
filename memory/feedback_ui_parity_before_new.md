---
name: feedback-ui-parity-before-new
description: "Preserve existing UI patterns when refactoring; reach parity in existing editors before adding new ones; implement the user's described alternative exactly"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 644f2317-0d3b-4825-9aab-24140b0a46ed
---

When refactoring UI through a new framework, **preserve existing patterns** (layout, format, filters, memory) — don't replace them with generic alternatives unless explicitly asked. Fix all current issues and achieve **parity in existing editors before introducing new ones**; the user explicitly defers new custom editors until existing ones work correctly. When a UI suggestion is rejected as "not any better," the user will describe a specific alternative layout — **implement that description exactly**, don't re-propose.

**Why:** Migrated from the repo-root `AGENTS.md` "Learned User Preferences" (2026-05-31).

**How to apply:** Default to matching the current UI's structure and behavior when reworking it. Don't pitch new editors/components while existing ones have open issues. After a rejected suggestion, build precisely what the user describes. Relates to [[project_repos]] (speed-merchants / TestAuto.Web) UI work and the testauto-ui-patterns skill.