---
name: feedback_radzenswitch_not_selectbar
description: "For on/off toggles use RadzenSwitch, never RadzenSelectBar; independent options each get their own switch"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 3855e7c4-2315-43fa-a872-7386e1dd2b3b
---

For on/off toggles in TestAuto.Web Blazor UI, use a **`RadzenSwitch`** (slider) with a label, NOT a `RadzenSelectBar` (segmented toggle-button group). The user explicitly dislikes the `RadzenSelectBar` style. For multiple independent on/off options (e.g. "Files" and "Scenarios" — each can be on, off, or both), render **one `RadzenSwitch` per option**, each independently bindable — do not use a single multi-select segmented control.

**Why:** User rejected the segmented `RadzenSelectBar` look twice during the workflow-export dialog work and asked for the slider-switch style; independent switches also model "either/both/neither" more clearly than a segmented bar.

**How to apply:** When adding a toggle, reach for `<RadzenSwitch @bind-Value="..." @bind-Value:after="StateHasChanged" />` + label. Never `RadzenSelectBar`/segmented buttons for on/off. Codified in the [[testauto-ui-patterns]] skill ("Toggle Controls" section + Rejected Patterns row).
