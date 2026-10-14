---
name: project-speedmerchants-run-profile-design
description: "vNext run-profile model agreed 2026-08-31 - declared vs captured vs observed, every run climbs from 1 user, break rules, manual pause/resume, and 1..N test drivers"
metadata: 
  node_type: memory
  type: project
  originSessionId: e187904d-af49-4c2a-a448-6071056cf6a8
  modified: 2026-08-31T14:37:26.056Z
---

Design agreed with Gene 2026-08-31 10:27–10:36, during the UoW-8 break. **Specced, not built.** Full
text in `Q:\Work\Work\99 Documentation\speed-merchants\vNext\Archive\vNextImplementation_v2.md` §5b and §5c.
He confirmed the requirements at 10:36.

## THREE kinds of field, and merging them is how a dashboard starts lying

| Column | Examples | Editable |
| --- | --- | --- |
| **Declared** | users profile, duration, data volume, target, claim size | yes |
| **Captured** | Profisee version, **which installation answered**, entity / attribute / DQ-rule counts, image digest, container runtime, machines | **NO — probed at run start** |
| **Observed** | observed users avg & peak, achieved throughput, failures, saturation, break reason | **NO — written by the run** |

**Version, data shape and DQ counts are CAPTURED, never typed.** Someone entering `26.1.0` against a
box running 26.2.0 mislabels every number that run produces, forever, with nothing to contradict it.
Not hypothetical: the local `/profisee` install answers **200 with an empty model** and is outwardly
identical to the populated one — see [[reference_speedmerchants_vnext_sut_testbed]].
`Domain/RunProfile` already captures all of it with zero operator input (K5, UoW-6).

**Most of this already exists, split across two types that do not talk to each other:**
`Domain/RunProfile` (captured, immutable, content-hashed) and `Domain/LoadWorkload` (declared, UoW-8
iteration 3). The work is joining them **without collapsing the columns**.

## Every run climbs from 1 user. Two exits, both first-class.

Gene's simplification of a worse draft that had flat/ramp/breakpoint as three peers:

> *"the sane default is 1 user, we then ramp up until we break it in some way or decide that we don't
> need to go higher"*

- **Start at 1**, always. The first step is a free smoke test — if one user cannot complete a request,
  nothing above it is worth measuring and the run says so in seconds.
- **Exit A — it broke.** Report the **last good level** and **which signal tripped**.
- **Exit B — the operator decides it is far enough.** A recorded ending, not an abandoned run.
- **The stored result MUST distinguish "stopped by operator at 40, nothing was breaking" from "broke at
  40".** Opposite findings; a schema rendering them alike is worthless for capacity planning.
- **Flat N** survives only as an explicit soak override. Optional ceiling for unattended runs.

**Break rule — all three signals, first to trip wins, and it records WHICH:** error rate (available
now) · latency p95/p99 (**needs UoW-7**) · saturation, throughput flattening while users climb
(**needs UoW-7 / R15**). Build the stop-rule seam so the latter two **plug in**; a breakpoint engine
that hard-codes error rate is a rewrite when they arrive.

**Manual override PAUSES the ramp until explicitly resumed.** Rejected: *abandon the schedule* (loses a
planned run to one curious drag) and *hold until next step* (the dial **silently snaps back** — a
screen changing a number the operator set without saying so). The screen must say *"ramp PAUSED by
operator at step 3 of 6 — commanded 20, resume continues to 40"*, never merely show a number.

This settles what the dial IS: **an override on an automatic climb**, not a free-form slider.

## 1..N test drivers — the hard part is already done

*"could be other containers on the same machine or remote machines"* — not scheduled, recorded.

**Multi-claimant distribution is already chaos-proven.** K3/K4 prove several agents claiming one run:
leases, orphan sweep, **zero stranded `Claimed` rows**, carry-forward resume, a verdict that
structurally cannot read Complete over a gapped set. A second driver is `--agent fleet-2` plus a
compose scale. The UoW-8 standing `fleet` service is already one driver; `IFleetPulse` already renders
the roster.

**Missing:** a driver registry that distinguishes **dead** from **not deployed** (different facts) ·
remote transport, credentials, DNS/TLS — note the corp-CA-inside-a-container trap in
[[reference_speedmerchants_vnext_sut_testbed]] · provisioning, which **must not come from the web
app** (`src/Web` starts no process — that is why the standing fleet exists). **Reuse CrewChief's
remote work rather than rebuilding**: [[project_crewchief_remote_boxprep_transport]],
[[project_crewchief_remote_setup_script]], [[project_crewchief_credentialed_remote_ops]],
[[project_crewchief_credssp_diagnosis]].

### Dial scope is CONFIGURABLE — `TargetUsersScope: Total | PerDriver`

Gene, 10:34: *"it might be 100 per box it might be 100 total, lets keep that open."* Per run, not
global — *Total* asks "what does this system do under 100 users", *PerDriver* asks "what does each box
contribute". A capacity test and a scale-out test are not the same test.

**A user count is NEVER rendered without its scope.** `100` on a tachometer describes two completely
different loads, so the bare number is a lie by omission. Show `100 total across 4 drivers` or
`100 per driver — 400 total`. Same family as `measured` provenance and visible staleness: **the number
alone is not the fact.**

Each mode's way of going quietly wrong:
- **Total** — shares derive from the LIVE driver count and must **re-balance on death**, or 4 drivers
  losing one silently delivers 75% while the screen still reads 100.
- **PerDriver** — commanded is stable per box, but the fleet total moves as drivers join or leave, so
  the total must be shown as **observed**, never computed from an expected count that may not be true.

Both are R15 requested-vs-achieved in different clothes; they belong in that panel.

## Where it lands

Registry + dial-share semantics → **UoW-7** (it owns requested-vs-achieved and R15). Remote
provisioning + driver management surface → **UoW-10**. **R20 still holds:** one driver on a laptop
stays a complete configuration; N drivers is scale-out, never a prerequisite.

Related: [[project_speedmerchants_vnext_monitor_ui]] · [[project_connect_runprofile_direction_authority]]

## R27 — run publication: central repo or local only (ADDED 2026-09-04 08:54, AWAITING GENE)

Gene: some jobs send metrics to the central repo, others are testing and stay local; "should be part of the run profile".
Proposed in v3 §5e: DECLARED `DeclaredPublication = LocalOnly | Central` (default LocalOnly) + OBSERVED `ObservedPublication`
(NotPublished / Published when+where / PublishFailed why). Every run drains to its OWN warehouse first, as today; `Central` adds an
idempotent publish of the self-contained run set (run row, profile, lineage, ramp schedule, workload-run link, samples). Rejected:
routing the drain to a second sink (facts without dimension rows break `bi.*`; laptop loses local visibility). Central conn string
`Speedy:Publication:CentralConnectionString` Optional + refused BY NAME at launch when absent, never silently downgraded.
Three decisions requested: auto-publish on ResultsComplete vs explicit (recommend auto for Central, explicit promote for LocalOnly);
intent immutable after launch (recommend yes); one central repo per deployment (recommend yes). Lands UoW-7 (fields+refusal) + UoW-7b (publisher).
**DECIDED 09:06 (Gene):** LocalOnly default confirmed; BOTH publish paths — declared Central publishes from the start, LocalOnly can be published later as a separate explicit step. Still open: intent immutable after launch (implied yes by "separate step"); one central repo per deployment.
