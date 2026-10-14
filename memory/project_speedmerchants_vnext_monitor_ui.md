---
name: project-speedmerchants-vnext-monitor-ui
description: "vNext UoW-8 Monitor UI - three views of one data model; iteration 1 CLOSED (U0 dial proof green, dpv2 -Dial), iteration 2 building the containerised Blazor host"
metadata: 
  node_type: memory
  type: project
  originSessionId: e187904d-af49-4c2a-a448-6071056cf6a8
  modified: 2026-08-31T00:45:14.770Z
---

**Decided 2026-08-30 20:44.** The vNext Monitor UI (UoW-8) ships **three switchable views of the same
run, not one screen**, with **A as the default**. Gene: *"I like the first one and I like these since
they are all different views of the same data lets keep them all as tabs or view for now and then
revisit after we have real data to see how they work... That way we can see all the views with real
data and decide."*

| | View | Hero | For |
| --- | --- | --- | --- |
| **A** | **Cluster** | the tach, with commanded and achieved needles | operating a test — dense, open for an hour |
| **B** | **Trace** | the recording — commanded staircase vs achieved curve, the band between them being **load specified but never applied** | reading the result |
| **C** | **Launch** | the number — commanded outlined behind achieved solid, type closing the gap | the room, a projector, CP-3 |

Mockups (interactive, shared simulation): `Dial Directions`
https://claude.ai/code/artifact/f331afe7-0df9-4eec-97c6-042b706e6118 · the fuller single screen
`Pit Wall` https://claude.ai/code/artifact/344b0211-5fc9-4935-9c9f-b8b3f4289c6c

**The one non-negotiable: ONE state model and ONE query layer behind all three views.** Three views
that query independently will disagree about the same run — which is how a dashboard starts lying, and
what criterion U5 exists to catch (every rendered number must equal an independent SQL query the proof
runs itself). Switching view must never restart or re-fetch the run. If an Executor finds itself
writing a second query for the same number, the shared layer is missing and it should say so rather
than duplicate.

**The design thesis, worth keeping even if the visuals change:** the dial is *commanded* workers, the
fleet takes ~1.3 s to get there (measured 1.327 s), and **showing the gap is the selling argument** —
it is R15 (workload validity) made visible instead of buried. Every live number also carries its
staleness, because the S1 spike's live pane trailed the fleet by 1187 completions and queue depth is
not an "is it done?" signal.

**Tokens settled**: ground `#0A0D12`, panel `#141922`, hairline `#222A36`, text `#E9EEF6`, label
`#78859A`; semantic `#F5A623` commanded, `#22C77E` achieved, `#A97BFF` at-target, `#E63946` limit.
Type: Saira Condensed display, Barlow body, JetBrains Mono for every updating digit, `tabular-nums`
throughout.

**Revisit trigger:** after the first live run drives all three. Do not re-litigate the choice on a
simulation. See [[project_vnext_due_diligence_2026-08-28]] and
[[feedback_ui_mockups_before_implementing]].

---

## UoW-8 loop, iteration 1 CLOSED 2026-08-30 22:22 — U0 green, criteria 1/7

**The dial works against a real installation, and you can run it yourself: `dpv2 -Dial`.**

```
targets  4 -> 24 -> 4      observed  4 -> 24 -> 4      rates 13.6 -> 58.1 -> 12.9 rps
2469 successful GETs   control GET saw 737,549 records
```

`observed` is the maximum `HeartbeatSample.ActiveWorkers` the RUN journaled in each window, read back
through the agent's `heartbeats` verb — **never restated from the dial.** That distinction is the
claim the legacy system could not make, and it is why the criterion parses the journal rather than
trusting the script that turned the dial.

Suite 1033 → **1065 unit + 8 architecture**, 0 failures, build 0 warnings.

**Configuration, and the reason it is not `SM_SUT_*`:**
`SM_WORKLOAD_URL` / `SM_WORKLOAD_APIKEY` (User scope) carry the load target — the remote
`profiseecloud.dev/speedmerchantstest` instance, 737,549 records in `RecordInteractiveApiExecution`.
`SM_SUT_URL` / `SM_SUT_APIKEY` stay pointed at the corp box for `ProbeTarget` and K5. **Two different
facts.** Details in [[reference_speedmerchants_vnext_sut_testbed]].

### Three findings worth carrying, none of which was in the plan

1. **The Agent host does not compose through `AddSpeedy`/`AddSpeedyWork` at all.**
   `AgentRunner.PoolAsync` builds `using HttpClient client = new();` itself. Any wiring done in
   `WorkModule` therefore does not reach the `pool` verb — a change made there reaches the container
   and silently does nothing. Iteration 1 worked *around* this (`WorkModule.ApplyApiKey(client, ...)`
   called directly from `AgentRunner`); it did not fix it. **Folding Agent and Cli onto `AddSpeedy`
   was already a carried item from UoW-6, and this is the second time it has cost something.**

2. **A criterion that fails unconditionally looks exactly like a broken product.** `u0` and `u4` both
   contained `[array]::IndexOf(@($ints), ($ints | Measure-Object -Maximum).Maximum)`, which is always
   `-1` because the aggregate is a `Double`. Second consecutive unit of work in which **the
   operator's criterion, not the product, was the defect** (after `i10-migrator.ps1` read the first of
   two `Passed:` summaries). Both were caught because the Executor is forbidden from editing the file
   that grades it and reports a deterministic repro instead — that prohibition is doing real work.
   Mechanics in [[reference_powershell_script_contract_gotchas]].

3. **Design decisions that turned out to matter more than expected.** `ApplyApiKey` does
   remove-then-add (adding an existing header appends a *second* value, and a gateway handed two keys
   picks one by rules nobody here knows) and trims (an env var with a trailing newline is the ordinary
   way this arrives malformed, and a header value containing one is refused outright). The binder's
   new `Optional` reader treats **absent and present-but-blank as different facts**: absent means the
   target needs no credential, blank means a secret was meant to be injected and did not arrive.

### Iteration 2 in flight — the containerised host

`src/Web` (Blazor Server, Radzen, assembly `speedy-web`), `docker/Dockerfile.web`, compose service on
**port 5310**, the Cluster/tachometer view over ONE shared query layer, `tests/Tests.Web` (bUnit).
Flips U2. The dial slider and the Trace/Launch views are iteration 3 — a sizing split, not a scope cut.

**The census finding that made part of it indivisible:** `ArchitectureTests.cs:15` holds a
hand-transcribed `HostProjectNames = ["Agent", "Coordinator", "Cli"]` that three rules iterate. Adding
a Web host does **not** turn it red — it makes the list quietly less true, exempting the new host from
the sample, credential-mask and host-isolation rules with nothing reporting it. Reverse-staleness: the
failure mode is silence. The array and the new project must land together.
