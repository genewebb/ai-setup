---
name: project_crewchief_value_card_2026-08-25
description: "CrewChief tabbed value card (design 2), Parameter source, Runtime pill, subtract filters, preview closure fix — built 2026-08-25, uncommitted"
metadata: 
  node_type: memory
  type: project
  originSessionId: 1bdf8c2b-86c9-4397-b982-386752ae932c
  modified: 2026-08-25T23:13:19.021Z
---

CrewChief value editor rebuilt 2026-08-25 (suite 3247/0, uncommitted). Five things landed together:

1. **subtract\* filters** — `subtractDays/Hours/Minutes/Months/Years` in `TokenFilters.cs` (Arity, Descriptions, ApplyOne, ValidateArgTypes). Negation of the add\* twins; a negative amount adds. Negatives already worked via `addDays:-7` — user wanted explicit names. See [[project_crewchief_token_filters]].

2. **`SegmentSource.Parameter`** in `TokenComposition` — a bare `{{Name}}` is now representable, retiring the "D2 exclusion". This is why composed values reopen in the Builder instead of falling back to Literal. Guard: `IsParameterName` rejects anything starting with `$`, or containing `: | { }`, or with surrounding whitespace — `TryParse`'s byte-exact rebuild still catches non-canonical spellings. See [[project_crewchief_value_builder]].

3. **Tabbed value card (design 2)** — user picked it from 5 mockups. New `ValueSourceTabs.razor` (+ `.razor.css`); `SegmentedToggle` deliberately left alone, it serves 9 other call sites. `SecretValueEditor` is now `.cc-value-card` (tab strip + `.cc-value-pane`); `SecretOnly` hosts keep the old plain stack. `ValueMode` gained `Parameter` (5 tabs).

4. **Runtime pill** replaced the Effective Value column in the WorkloadEditor global-params grid. `RuntimeValueChip.razor` rides the tab strip's `Shoulder` RenderFragment. CSS-only hover popover — NOT Radzen TooltipService, so it survives a circuit reconnect. It is a chip, never a 5th tab, because `SetModeAsync` clears the value on mode change.

5. **`ValuePreviewService` closure fix** — it resolved the WHOLE sibling dictionary, and `ResolveSpecialParameterValues` is all-or-nothing, so ONE unresolvable sibling deferred every composed value in the grid to "Run time". Now resolves only the value's transitive closure (`BuildClosure`). New `ValuePreview.DeferredReason` names the offending token.

**Root cause of the user's "everything says Run time"**: a typo in their own workload — `{{profisee_short_version}}` vs the defined `profisee_version_short`. Fixed in `C:\Deploy\CrewChief\web\data\workloads\26r2-parm-driven-connect.workload.json` (backup at `C:\tmp\...bak`). Still open there: `profisee_installer_fastapp_studio_path` is missing the `\` before the filename that its sibling `profisee_installer_server_path` has.

**Still unexplained**: Workloads, Steps and Reference Data all fail to persist card-vs-list view. `CardViewState` round trip (read AND write) is proven by bUnit tests, deployed DLL is current, `crewchief-io.js` is present and correct. Needs browser evidence — check `crewchief.workloads.viewMode` in devtools localStorage. See [[reference_crewchief_sticky_filters]].
