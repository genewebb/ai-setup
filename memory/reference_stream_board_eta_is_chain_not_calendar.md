---
name: reference_stream_board_eta_is_chain_not_calendar
description: "Get-StreamStatus etaMinutes is critical-chain depth, not wall-clock; the Speedy board is throughput-bound, so compare remaining est hours per group"
metadata: 
  node_type: memory
  type: reference
  originSessionId: 791f1040-13cb-474c-8883-7a1bc9dc8c14
  modified: 2026-09-30T01:26:33.460Z
---

`Get-StreamStatus.ps1` reports `etaMinutes` per group. It is the **longest dependency chain** in that group,
not a calendar estimate. Reading it as a finish date leads to the wrong conclusion:

On 2026-09-30 the chain was 62–72 h for **every** group, within 15% of each other, while the calendar
projections spanned 2 Oct to 14 Oct. G6's chain (65 h) was SHORTER than G3's (72 h) yet G6 was projected six
days later. The schedule is set by **work volume against builder concurrency**, not by chain depth.

To see what actually drives the date, sum `estMinutes` over tasks not `integrated`/`done`, per group:

| | open tasks | remaining est |
|---|---|---|
| G3 | 133 | 310 h |
| G6 | 83 | 202 h |
| G5 | 62 | 150 h |
| G4 | 53 | 126 h |
| G2 | 21 | 28 h |
| G1 | 10 | 18 h |

834 h total against 4 concurrent builders (the SMVMTR1 ceiling, see
[[project_stream_capacity_two_authors_two_builders]]) is ~9 days of continuous building, which is what the
projections were really showing. **G3 is the schedule, not G6.** The only levers are more hosts or less scope;
re-ordering the chain moves nothing.

See [[project_stream_kit_replaces_myloop]], [[project_stream_host_smvmtr1_2026-09-28]].
