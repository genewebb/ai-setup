---
name: reference-radzen-light-text-button-invisible
description: Radzen ButtonStyle.Light + Variant.Text renders #eeeeee icons — invisible on white panels, looks disabled
metadata:
  type: reference
---

Radzen.Blazor 7.1.7, `material.css` theme:

```css
.rz-button.rz-variant-text.rz-light { color: var(--rz-base-200); }   /* #eeeeee */
.rz-button.rz-variant-text.rz-light:not(.rz-state-disabled):hover {
  background-color: rgba(255,255,255,0.12);                          /* white on white */
}
```

So `ButtonStyle="ButtonStyle.Light" Variant="Variant.Text"` on any light/white panel gives ~1.1:1 contrast icons with no hover feedback. Users read this as "the buttons are disabled". `ButtonStyle.Danger` siblings stay red, so one icon per row is visible and the rest vanish — a strong tell for this bug.

Fix: use `ButtonStyle.Base` (its text variant sets no `color` at all) plus a scoped class that pins the colour explicitly. Radzen still applies `--rz-button-disabled-opacity` to `.rz-state-disabled`, so real disabled state stays distinguishable.

Hit 2026-08-24 in TestData.Mutation.Web `Home.razor` field-row actions (duplicate / move top/up/down/bottom / delete) and the "Reset to equal" button; fixed with `.tdm-row-action` in `Home.razor.css`. See [[project_tdg_ui_family_redesign]], [[reference_blazormonaco_integration_gotchas]].
