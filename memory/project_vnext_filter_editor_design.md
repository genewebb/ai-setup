---
name: project_vnext_filter_editor_design
description: "LOCKED 2026-09-01: vNext value-builder filter editing = C+D — stacked numbered rows, date-math composer for date arithmetic, labelled fields for string work. Do not re-open."
metadata: 
  node_type: memory
  type: project
  originSessionId: 04eb84aa-4767-416c-8095-a17f6844fa07
  modified: 2026-09-01T12:43:24.134Z
---

**LOCKED 2026-09-01 — build it, do not re-litigate.** Five treatments were mocked live against the
real catalogue ([[project_crewchief_value_builder]]) and Gene chose the C+D combination, then
confirmed it the next morning: *"Good, lock in the combination."*

**The design — stacked numbered rows, row renderer chosen per filter kind:**

- **Frame:** one filter per row, stacked, **numbered because order changes the result** (`replace`
  before `date` is not `date` before `replace`; the chip strip implied order by position without
  saying so). Explicit reorder controls.
- **Date-arithmetic rows:** Direction (add/subtract) × Amount × Unit. **Ten catalogue entries collapse
  into one control** — `add`/`subtract` × Days/Hours/Minutes/Months/Years are all arity (1,1) with a
  single "Amount". **Emitted filter name is unchanged** (`subtractMonths:3`), so nothing downstream
  knows the difference.
- **String rows:** labelled fields, labels **outside** the input. Carries `replace`, `substring`,
  `padLeft`, `left`, `right`, `upper`, `lower`, `trim` — the 15 filters the composer does not answer
  for, and the reason C alone was not enough.
- **Per-row readout:** each row shows the value **as it leaves that step**, so a broken pipeline names
  the step that broke it. Impossible in a chip strip.

**The root defect it fixes, and it is NOT "missing labels":** `TokenFilters.Describe` already
publishes `ArgumentLabels` for every filter; the Builder wires them in as **`placeholder`**, which
vanishes on first keystroke. Fill `replace` and both hints go, leaving two identical boxes. **The
catalogue is already correct — the fix is presentational.**

**Cost accepted, check still owed:** this is the tallest treatment and it lives inside a value editor
inside a step card inside a page. **Measure height against a real workload page before committing** —
that could still send it to a popover variant. Not yet done.

**Invariant that must survive the port:** every treatment emits byte-identical tokens. The editor
stores a plain string and infers the pill from it — no schema, no migration, no engine change.

Spec: §5d of `Q:\Work\Work\99 Documentation\speed-merchants\vNext\Archive\vNextImplementation_v2.md`.
Mockups: `Q:\Work\Work\99 Documentation\claude\webpages\2026-09-01-token-filter-bench.{html,md}`,
hosted at https://claude.ai/code/artifact/65bb6aae-0276-49b4-8a92-71b79942b82a
See also [[project_crewchief_secret_picker_convenience_only]] (pickers go on most single-line fields,
not just sensitive ones), [[project_crewchief_token_filters]].
