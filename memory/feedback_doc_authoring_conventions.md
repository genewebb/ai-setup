---
name: doc-authoring-conventions
description: Shared skills/docs use MCP-client-agnostic wording; tutorial expansions go in the standalone tutorial only, not mirrored into overview/index docs
metadata:
  type: feedback
---

Two documentation-authoring preferences:

1. In shared skills and documentation that may run under different MCP hosts, prefer **MCP-client-agnostic wording** over product-specific UI or configuration names.
2. When maintaining both a standalone tutorial document and a broader learning/index document, put substantive tutorial expansions and plain-English rewrites in the **standalone tutorial only**; do not mirror them into the learning overview unless asked.

**Why:** Skills run under multiple hosts (Claude Code, Copilot, etc.); duplicated tutorial content drifts.

**How to apply:** Check the doc's audience before naming host-specific UI; on tutorial edits, touch one file. (Migrated from myworkspace AGENTS.md, 2026-07-30.)
