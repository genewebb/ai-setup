---
name: feedback-free-oss-only-no-revenue-gated-libs
description: "Profisee is over $2M revenue - third-party libraries must be free OSI open source (MIT/Apache); revenue-gated \"community\" licences (ApexCharts, Blazorise, Syncfusion community) are out"
metadata:
  node_type: memory
  type: feedback
  originSessionId: afae390a-5c8d-4b78-91ac-028a93fcf051
  modified: 2026-10-21T20:27:02.245Z
---

Third-party libraries for Profisee work must be free, genuinely open source (MIT, Apache-2.0, etc.). Gene 2026-10-21: "We are over 2M so it needs to be free opensource."

**Why:** Profisee's annual revenue is over $2M, so "free for small companies" licences need a paid commercial licence. Examples: ApexCharts.js Community licence (cap $2M, counts parent and affiliates), Blazorise (source-available SLA, not OSS), Syncfusion community licence. A wrapper with an MIT licence does not help if the JS library it wraps is gated (Blazor-ApexCharts is MIT, ApexCharts.js is not).

**How to apply:** When recommending any library, check the licence of the package AND of every engine it wraps before offering it. Drop revenue-gated, source-available and paid options up front, or list them only as excluded with the reason. Blazor charts as of 2026-10-21: Radzen.Blazor (MIT, native SVG) was the pick; MudBlazor MudChart, Plotly.Blazor, BlazorExpress.ChartJS were the free alternatives.
