---
name: reference-testauto-metrics-catalog-doc
description: "Executive \"TestAuto Performance Metrics Catalog\" Claude Doc (Matching/CRUD/Connect scenarios + metrics + scorecard mockup), created 2026-10-10"
metadata:
  node_type: memory
  type: reference
  originSessionId: b4b21157-850d-422d-92e4-127a4af7d3a2
  modified: 2026-10-10T21:12:35.139Z
---

CURRENT (Gene preferred, 10/10): polished HTML page https://claude.ai/artifact/TSXnnA9PXXaBodXZbMcPps, source C:\scratch\claude\C--devops-repos-speed-merchants\b4b21157-850d-422d-92e4-127a4af7d3a2\scratchpad\testauto-metrics\index.html. Landing + tabs Overview/Matching/CRUD/Connect/Metadata, Stewardship Filter deep dive (#stewardship). Gene: no report mockup (scorecards exist), releases vary per test family, Metadata = scenario run with NO metrics, one summary per area.

PDF (Gene chose PDF for execs 10/10): Q:\Work\Work\99 Documentation\speed-merchants\TestAuto-Metrics-Catalog.pdf, 14 pages Letter landscape. Built from print.html (same scratch folder) = index.html + print CSS (zoom .74 + body width 1320px, forced desktop grid columns with !important because zoom still trips the <860px media queries, break-inside avoid on tables/:has(>.tbl) sections) rendered by headless Edge `--print-to-pdf --no-pdf-header-footer`. Start-Process -Wait HANGS on Edge: start without -Wait, poll PDF LastWriteTime, then kill the print-to-pdf process.

Superseded Claude Doc: https://claude.ai/code/artifact/080e4e81-3b9d-4faa-b5e0-5832b4bf4e6c (project 080e4e81-3b9d-4faa-b5e0-5832b4bf4e6c, prose node 7b95c69c-0668, scorecard widget 04d702c3-74fc).

Built from code 2026-10-10: [ScenarioTypes] + [MetricColumn] in TestAuto.Matching/Records/Connect Metrics folders. All example values and the scorecard numbers are ILLUSTRATIVE (labelled so in the doc). Matching 3B/3C described per the wizard mapping (3B = LookupThenCreate, 3C = CreateOnly), not the shipped sample JSONs.

Open items in doc: release pair to compare, green/amber/red targets, Metadata as 4th area, one page vs per-area.
