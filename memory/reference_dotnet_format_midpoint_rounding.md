---
name: reference-dotnet-format-midpoint-rounding
description: "On .NET 10 the custom format \"0\" ({0:0}) rounds midpoints half away from zero, but \"N0\"/\"F0\" round half to even — donor code using N0 is NOT {0:0}"
metadata:
  node_type: memory
  type: reference
  originSessionId: 0ea61e79-068c-4a42-9300-94ed42155416
  modified: 2026-09-24T16:29:59.856Z
---

Measured 2026-09-24 in PowerShell 7 on .NET 10.0.12, InvariantCulture:
- `ToString("0")` (= `{0:0}`): 0.5 gives 1, 2.5 gives 3, 210450.5 gives 210451 (half away from zero).
- `ToString("N0")` and `ToString("F0")`: 0.5 gives 0, 2.5 gives 2, 210450.5 gives 210,450 (half to even).

The speed-merchants donor report writers format throughput with `N0` (half to even). The tab-title percent uses `{0:0}` (half away from zero). An owner answer that says "round like {0:0}" for throughput therefore contradicts the donor code; ask the owner which rule applies instead of assuming one.

**How to apply:** when a requirement pins rounding "like the donor", grep the actual format string and probe it on the donor's runtime (`pwsh` is enough) before accepting either rule. Related: [[feedback-verify-no-guessing]].
