---
name: project-ado-166723-26r3-perf-datas-gc
description: "ADO 166723 (26R3 vs 26R2 CRUD perf regression) - Josh Machol asks re-run Batch Record Read with DOTNET_GCDynamicAdaptationMode=0 (disable .NET DATAS GC); 26.3 = net10 + Server GC, 26.2 = net8"
metadata:
  node_type: memory
  type: project
  originSessionId: fa8bee62-76ab-4d3f-b6aa-fb9277563b36
  modified: 2026-10-21T16:09:46.918Z
---

ADO 166723 (Bug, Gene owner, 26R4 Smooth Sloperator 1): 26R3 build 26.3.0.1167 slower than 26R2 26.2.0.1196 on many-record ops (batch read +29..50%, batch create no-rules +45%, batch update +18..31%, page read +10..14%). Suspect .NET 8 -> .NET 10 upgrade.

2026-10-21 Josh Machol asked: re-run Batch Record Read with machine env var `DOTNET_GCDynamicAdaptationMode=0` (disables DATAS), and said all Profisee apps must restart after setting it.

Verified on CORPLTR94 install folders 2026-10-21: every 26.3.0 server runtimeconfig.json = net10.0 + `"System.GC.Server": true`, no DynamicAdaptationMode set (so DATAS on by default); 26.2.0 = net8.0 + Server GC (DATAS off by default). So env var is a no-op for 26.2 apps on a shared box.

**Why:** DATAS is the main GC behaviour change 26R2 -> 26R3 picked up by skipping .NET 9.
**How to apply:** A/B on same 26R3 server, DATAS on vs off; reboot app server (safest way to get a machine env var into IIS + Windows services); capture GC counters, not just timings.
