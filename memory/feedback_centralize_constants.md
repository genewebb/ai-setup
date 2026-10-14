---
name: Centralize magic strings into constants
description: User expects magic strings (step types, etc.) to be centralized into constants classes, not scattered as raw strings
type: feedback
originSessionId: f5d73f81-507f-4c6e-8fba-934deccd17d9
---

When adding or referencing string literals that identify step types, service names, or similar categorical values, always check for an existing constants class first (e.g., `UtilityTypeConstants`). If one exists, use it. If not, create one rather than using raw strings.

**Why:** User explicitly corrected this — after adding `"Http"` as a raw string to the ScriptKey validation exclusion, user said "There should be a centralized place for this already." Resulted in creating `UtilityTypeConstants` with all step type strings.

**How to apply:** Before writing any string literal that identifies a type/category, grep for existing constants. Use `UtilityTypeConstants` for step types. Follow the same pattern for other categorical strings.
