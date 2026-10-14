---
name: reference_skill_override_two_speeds
description: "skillOverrides enforcement is live mid-session, but reclaiming listing tokens needs /clear — two different refresh cycles"
metadata: 
  node_type: memory
  type: reference
  originSessionId: 48036b6c-03b5-4821-aa20-ae5dbe200171
  modified: 2026-08-01T19:30:56.298Z
---

Verified 2026-08-01 by direct test, not inferred.

| Effect | Lands | Evidence |
|---|---|---|
| Disabled skill **refused on invocation** | **Immediately** | Wrote `"skillOverrides": {"grill-me": "off"}` to `~\.claude\settings.json`, invoked it seconds later in the same session → `Skill grill-me is disabled for model invocation in skillOverrides settings`. No restart, no `/clear`. |
| **Newly added** skill appears in the listing | **Immediately** | `skill-profile` was announced by a system-reminder in-session right after `link-to-ai.ps1` created its junction. |
| Listing **shrinks**, tokens reclaimed | **Assume next session** | No observable signal on removal. NOT proven either way — keep the guidance conservative: run `/clear`. |

`settings.json` is re-read on the hot path (per invocation), while the listing is
assembled into the system prompt at session start. Enforcement and presentation
are on different refresh cycles.

**Never claim a profile change "saved tokens" in the current session.** It changed
what can be *invoked*. The token saving lands after `/clear`.

The upside is a graceful failure mode: applying a profile without clearing still
improves routing and never silently does nothing.

Used by [[project_skill_profile_system]].
