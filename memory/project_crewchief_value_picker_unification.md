---
name: crewchief-value-picker-unification
description: 2026-09-01 — ServerNameEditor + ServiceNameEditor unified onto the 5-source tab card (Literal/Parameter/Secret/Reference Data/Builder + Runtime shoulder pill); all StepEditorCard hosts pass Siblings/Reveal/KeyName
metadata: 
  node_type: memory
  type: project
  originSessionId: 5b8d0023-3598-41d3-83c1-d2a9ffb31fde
  modified: 2026-09-01T13:52:33.582Z
---

2026-09-01: CrewChief value pickers unified. User rule: **every value picker always offers Literal, Parameter, Secret, Reference Data, Builder + the Runtime pill.**

- `ServerNameEditor` — was 4-mode SegmentedToggle (Secret/Reference/**Text**/Builder). Now 5-source `ValueSourceTabs` card, enum `NameMode { Literal, Parameter, Secret, Reference, Builder }` (Text renamed Literal), Parameter datalist pane, ParseValue mirrors [[ValueSourceClassifier]] ordering (scoped-$ref → $config → bare-param → composition → literal), literal input switched `onchange`→`oninput` (blur-to-commit fix). Scoped-ReferenceType behavior kept (foreign $ref stays Literal).
- `ServiceNameEditor` — same treatment plus its extra **Pick** tab stays first (6 tabs). Gained Runtime chip + `Siblings`/`KeyName`/`Reveal` params it never had; nested SecretValueEditor gets `ShowRuntime="false"` (no double chip).
- Card CSS (`cc-value-card`/`cc-value-pane`) is copied per component on purpose — Blazor CSS isolation; only ValueSourceTabs' own strip styles are shared.
- All ~20 `StepEditorCard.razor` host sites now pass `Siblings="@BuildResolutionParameters()" Reveal="@Revealed" KeyName="..."` (Parameter suggestions + chip resolution). ConnExTokenSelectionDialog/SetupVerification hosts left without Siblings (no step params there).
- Tests: ServerNameEditorTests/ServiceNameEditorTests rewritten (ValueSourceTabs find, `.cc-vtabs .cc-rt` selectors, `.Input()` not `.Change()`, tab-label + Parameter tests). Suite 3657/3657 green. Uncommitted (user commits).
- SecretOnly remains the deliberate single-source exception (nested delegation + must-be-secret fields).

**Why:** two variations on one page (DB-ops Server Name vs Windows User ID) read as different controls.
**How to apply:** any new value-ish field editor must render the full 5-source tab card; extra modes (Pick) prepend, never replace.
