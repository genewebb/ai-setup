---
name: reference-speedmerchants-vnext-sut-testbed
description: "Which local Profisee install is the vNext SUT, why the other one is a trap, and that the REST gateway serves no version endpoint"
metadata: 
  node_type: memory
  type: reference
  originSessionId: e187904d-af49-4c2a-a448-6071056cf6a8
  modified: 2026-08-30T23:30:23.819Z
---

CORPLTR94 hosts **three** Profisee installs behind one IIS site, and two of them look alike from the
outside. Established 2026-08-30 while unblocking vNext criterion K5.

| Path | Version | Gateway | Model | Role |
| --- | --- | --- | --- | --- |
| `/speedmerchants` | 26.1.0.1795 | alive | **92 entities, 755 attributes, 50 DQ rules** | **THE SUT** — the version the speed-merchants repo targets, and the install holding its data |
| `/profisee` | 26.2.0 | alive | **empty — 0 / 0 / 0** | the newer platform instance, freshly built. Not broken — just has nothing in it yet |
| `/MyDevProfisee` | dev build from `C:\devops\repos\platform` | — | — | not a testbed |

**Consequence for any probe:** a RunProfile captured from the SUT is stamped **26.1.0**, not the
current 26.2.0. Record WHICH install answered alongside the version, so the gap is visible in the data
rather than implied by a URL nobody re-reads.

`SM_SUT_URL` / `SM_SUT_APIKEY` are set at **User scope** and now point at `/speedmerchants`. An API key
is **scoped to one install** — the 26.2.0 key returns `Auth Error: invalid_client` against 26.1.0, and
that error means wrong-install far more often than wrong-key.

**Three traps, all of which cost time on 2026-08-30:**

1. **`/rest/v1/Health` is a 404 on every install — it was never a route.** A 404 there says nothing
   about health. Probe `/rest/v1/Entities` instead. Reading that 404 as "the app is down" sent a whole
   session's diagnosis in the wrong direction.
2. **A 200 with `totalRecords: 0` is not a healthy testbed.** Liveness and usefulness are separate
   questions; a probe suite pointed at 26.2.0 would go green measuring nothing.
3. **The REST gateway serves NO platform-version endpoint.** All 159 paths in
   `/rest/swagger/v1/swagger.json` were enumerated: no `Version`, `System`, `Info`, `Health` or
   `Status` route. `swagger.info.version` is the literal string `"v1"` and the only version header is
   `api-supported-versions: 1.0`. The real product version (`26.1.0.1795`) comes from the **`/mcp`
   app**, not from `/rest`.

   **How to actually read it** (worked 2026-08-30): `{base}/mcp` speaks **JSON-RPC**, not REST, so the
   call is a sequence of POSTs with an SSE-accepting client —
   `initialize` → `notifications/initialized` → `tools/call get_system_version`. It takes no arguments,
   reads only, and mutates nothing; the POSTs are the protocol, not a write. A probe that insists on
   `GET` will conclude the version is unavailable when it plainly is not.

Auth header is **`X-Api-Key`** (the gateway names it in its own 401 body). Never log the key value.

Pairs with [[reference_profisee_health_endpoint_503]], [[reference_profisee_platform_log]] and
[[project_vnext_due_diligence_2026-08-28]].

## The LOAD target is a different installation from the PROBE target (2026-08-30 21:40)

Gene supplied a cloud test instance for the vNext dial workload, and it is deliberately **not** the
box above. Two targets, two variable pairs, and conflating them breaks K5:

| Purpose | Variables | Target |
| --- | --- | --- |
| RunProfile capture (`ProbeTarget`, K5) | `SM_SUT_URL` / `SM_SUT_APIKEY` | `corpltr94…/speedmerchants` |
| Fleet workload (U0 dial proof) | **`SM_WORKLOAD_URL` / `SM_WORKLOAD_APIKEY`** | `profiseecloud.dev/speedmerchantstest/rest/` |

The cloud instance carries the same TestAuto model (91 entities). Measured record volumes and the
per-request cost they imply — the largest table is the one worth loading, because the server pays a
`COUNT` over it on every page request:

| Entity | Records | Page GET |
| --- | --- | --- |
| **`RecordInteractiveApiExecution`** | **737,549** | **~1,158 ms** |
| `RecordApiExecution` | 87,467 | 564 ms |
| `ConnectApiExecution` | 4,000 | 541 ms |

**Two things about that host, both measured rather than assumed:**

- Its certificate is issued by **GlobalSign** — a public CA — so a Linux container trusts it with no
  plumbing. That matters because the *corp* box's cert is issued by the internal `corp-CORPIT01-CA`:
  the domain-joined host trusts it and **`mcr.microsoft.com/dotnet/runtime:10.0` does not**, carrying
  public roots only. A containerised HTTPS workload aimed at the corp box needs that CA **appended**
  to `/etc/ssl/certs/ca-certificates.crt` — appended, never replaced, or every public root is
  stripped. Plain `http://` serves the same payload and avoids it entirely.
- It sits behind **Imperva** (`CN=imperva.com`). A WAF could rate-limit a burst and have it read as a
  product defect, so it was tested: **48 concurrent GETs → 48× 200**, no 429, no challenge, 411–2,933
  ms, mean 792. It does not throttle at dial-proof levels.

**The trap this sharpens, and it is the recurring one:** trap 2 above says a 200 with
`totalRecords: 0` is not a healthy testbed. Counting *successful responses* therefore cannot tell a
real workload from one aimed at an empty install — the same shape as the three `IF OBJECT_ID` /
`IF DB_ID` defects in [[project_speedmerchants_dual_runprofile_migrator]]: **a guard that asks whether
a NAME answers and concludes the CONTENT is there.** Assert records, not status codes.
