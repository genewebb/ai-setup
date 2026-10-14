---
name: feedback-value-picker-always
description: Gene 2026-09-13 16:56 - every editable field uses the value picker (ValueEditor) unless it is genuinely not possible; plan for it on every screen, incl. dial-up URL and API key
metadata:
  type: feedback
---

"We will ALWAYS want to pick values using the value picker when possible we will only NOT use it when not possible plan for that now." Applies to ALL possible fields, explicitly the dial-up/down (load test) TARGET URL and API KEY.

**Why:** the picker is the product's constant feature (Gene 09-12: "The value picker will be a constant feature"); retrofitting per field later is the expensive path.

**How to apply:**
- Every mockup and build ticket lists each field as PICKER (with its allowed tabs via ValueEditor `Kinds`) or NOT-PICKER with the reason (identity/key, structural enum/toggle, multi-line body, passphrase entry).
- Picked values resolve at LAUNCH into the frozen run snapshot (48.RV5 LoadWorkloadExecutionSnapshot); Secret values stay NAMES and resolve only in the executing process.
- Secret tab may wait for its section (§2 after §1 reference data) - sequence unchanged - but the data shape must accept a ValueSpecification NOW.
- Related: [[feedback-dial-up-real-first]]
