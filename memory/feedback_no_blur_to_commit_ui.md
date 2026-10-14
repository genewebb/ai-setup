---
name: feedback_no_blur_to_commit_ui
description: "Never require tabbing out of a field, and never grey out an action button because input is empty — bind on oninput, keep buttons always enabled, and validate on click with a message"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: b93f036c-3f21-475d-9f60-bf15589cddd9
  modified: 2026-07-27T14:51:31.398Z
---

User rule, stated 2026-07-27 and then **corrected the same day after a first attempt got it half right**. Treat as a general standard for all Blazor UI in this repo.

**The rule has two halves — both are required:**

1. **No blur to commit.** Values must register as typed. Never require tab-out/focus-loss to save a value or reveal an option.
2. **Never disable an action button because the input is empty.** The button is always visible AND always clickable. If the field is empty or invalid, **clicking it tells the user what to do** ("Enter the master password") via the page's existing message surface. Enter-key on an empty field gives the same message, not a silent no-op.

**Why:** Radzen `RadzenTextBox @bind-Value` and plain `@bind` commit on **change (blur)**. In Blazor Server that races the next click, so typing then clicking Save can lose the edit. Real bugs from this: CrewChief global parameters seemed to need a junk extra parameter before Save would stick; secrets pages needed a tab-out before Verify worked. Nastier variant: a **disabled** button fires no blur at all, so a field that gates its own button leaves it permanently dead.

**Why half 2 exists:** my first fix used `Disabled="@(string.IsNullOrWhiteSpace(x))"` and called "always visible" satisfied. The user rejected it with a screenshot of a greyed-out VERIFY button: *"It should be visible all the time. If the field is empty then it should just tell them to enter a value."* A greyed button is a dead end — the user cannot tell whether they are missing input, lack permission, or hit a bug. **Do not substitute a disabled state for a validation message.**

**How to apply:** native `<input>` + `@bind` + `@bind:event="oninput"` + `@onkeydown` Enter-submit. No `Disabled` binding tied to empty/blank/not-yet-valid input — move that condition into the click handler and surface a specific message (distinguish "enter a passphrase" from "the passphrases do not match"). Applies to textareas too. `Disabled` is ONLY acceptable for genuine operation state — an in-flight double-submit guard or a hard lockout — and even then the button stays visible. Keep state-driven conditionals (don't offer Unlock when already unlocked). Also flush pending editor rows on Save rather than requiring an explicit Add click.

**Watch the cost:** `oninput` fires per keystroke — verify no consumer does I/O per change. In CrewChief `MarkDirty` clears the verdict cache and a `Ref` step verdict did an uncached file read per row per keystroke. Related: [[feedback_radzenswitch_not_selectbar]], [[project_crewchief_ui_conventions_2026-07]], [[feedback_ui_parity_before_new]], [[project_crewchief_stale_css_cache_bust]].
