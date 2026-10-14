---
name: crewchief-filter-rows-composer
description: "2026-09-01 — ValueBuilder filter chips replaced by Token Filter Bench C+D (stacked labeled rows + date-math composer); DateMathFilters mapping + parity test; per-row \"after this step\" readout deferred"
metadata: 
  node_type: memory
  type: project
  originSessionId: 5b8d0023-3598-41d3-83c1-d2a9ffb31fde
  modified: 2026-09-01T14:08:46.518Z
---

2026-09-01: CrewChief ValueBuilder adopted Token Filter Bench C+D (artifact 65bb6aae, direction locked 8/31 for vNext; ported to CrewChief on user go-ahead).

- **Phase 1 (D, stacked rows):** `vb-filter-chip` strip replaced by `vb-filter-stack` / `vb-filter-card` — one filter per numbered row, argument labels rendered ABOVE fields (`vb-filter-label`, placeholder gone — the whole defect was labels-as-placeholders vanishing on type), per-row ▲▼ reorder (`MoveFilterUpAsync/DownAsync` — filter order is pipeline order), date presets kept inside the labeled Format field.
- **Phase 2 (C, date-math composer):** rows whose filter name parses as add/subtract×(Days|Hours|Minutes|Months|Years) render Direction/Amount/Unit selects instead of name+arg (`vb-filter-card-datemath`, amber border). Picker's Date group collapses those 10 entries into one sentinel option `$dateMath` ("date math (add/subtract)…"); picking it seeds `addDays`. Direction/Unit changes recompose the name and KEEP the amount. Emitted names stay the engine's own — token byte-identical, zero engine change.
- **`DateMathFilters`** (CrewChief.Web\Components\Controls\DateMathFilters.cs) is the ONLY place the direction×unit naming lives; `DateMathFiltersTests.Parity_*` walks TokenFilters.DescribeAll so a future `addWeeks` fails tests instead of silently missing from the composer.
- **Phase 3 deferred:** per-row "after this step" resolved readout (needs partial-chain resolution through IValuePreviewService).
- Suite 3675/3675 green (was 3657). Uncommitted (user commits). Bench artifact: claude.ai/code/artifact/65bb6aae-0276-49b4-8a92-71b79942b82a.
