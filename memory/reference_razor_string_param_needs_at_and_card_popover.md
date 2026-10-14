---
name: reference_razor_string_param_needs_at_and_card_popover
description: "Two silent Blazor/Bootstrap UI bugs found on Speedy reference data 9/23 - string component params without @ pass literal text; .card on a [popover] draws it inline"
metadata:
  node_type: memory
  type: reference
  originSessionId: 0359fc02-cccc-4830-81fb-20a4bcd43ea3
  modified: 2026-09-24T01:43:52.507Z
---

1. **Razor string parameter without `@` is a LITERAL.** `<ReferenceTransferPanel Set="headerSet.Name" />` passed the text "headerSet.Name" (button read "Export headerSet.Name"); `Exported="exported"` passed the word "exported". Non-string params (int, objects) are evaluated as C#, so the bug only bites string-typed ones. Scan: component tags with `Param="lowercaseIdent"` values, then check the param type.
2. **Bootstrap `.card` (display:flex) on an element with the HTML `popover` attribute beats the UA's hidden-until-open rule**, so the popover renders inline and stretches its flex row. Put the card INSIDE the popover element. Browser test must assert `IsVisibleAsync()==false` before opening, not only that controls exist.

Related: [[reference_playwright_enhanced_nav_waitforloadstate]].
