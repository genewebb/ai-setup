---
name: reference_stream_claim_order_is_group_first_by_design
description: "Claim-Task.ps1 sorts group rank BEFORE chain depth on purpose (added 2026-09-30); four kit tests lock it - do not 'fix' it to chain-first"
metadata: 
  node_type: memory
  type: reference
  originSessionId: 791f1040-13cb-474c-8883-7a1bc9dc8c14
  modified: 2026-09-30T14:28:20.378Z
---

`Claim-Task.ps1:46` sorts candidates `Fix desc, Rank asc, Chain desc, Order asc`. `Rank` is the group's index
in `doc.groups`, and it sorts **before** chain depth. This looks like a scheduling bug and is not one.

The comment at `Test-StreamKit.ps1:345-349` states the reason: before 2026-09-30 the keys were
integration-fix, longest chain and board order only, so with all six groups released at once **every session
spread across all six groups and no group ever finished first**. Rank was promoted above Chain to restore
group-at-a-time draining, which is the owner's standing campaign rule
(see [[project_speedy_build_campaign_2026-09-26]]: RefData > Backup > Steps > Workflows > TestAuto > Dial,
one group at a time).

Four tests lock the behaviour and fail immediately if the keys are swapped back:

- `build claims the earliest category, not the longest chain`
- `the earliest category is drained before the next one`
- `a later category is taken once the earlier one has none claimable`
- `the author tickets in category order too`

`an integration fix still outranks the category order` stays green either way, because `Fix` is still first.

**The known cost, which is accepted, not overlooked.** Group-first means a deep chain in a later group waits
behind a shallow one in an earlier group. Measured on 2026-09-30: a ready G5 task with a 618-minute chain sat
behind a G3 task with a 245-minute chain, and G6 - the group that sets the board finish date - waits on those
G5 chains. Group coherence was chosen over the earlier board date. Do not trade it back without asking.

Lesson beyond this file: **run `Test-StreamKit.ps1` before editing any kit script**, not after. The suite is
where the kit records intent that the script itself does not comment.

**The lever the sort left the planner, added 2026-09-30 21:47Z.** Group-first means a row's GROUP is the only
thing that moves it in the queue, and until that evening nothing could change a row's group: `Revise-Task.ps1`
edited write sets, dependsOn, title, tests, estimates and the release. Measured cost: G3.T149, 8 estimated
minutes, was the last thing between G1 and its close (G1.T17 dependsOn it) and sat 103rd of 108 planned G3 rows,
so an author had to ask for out-of-order ticketing by inbox item. `Revise-Task.ps1 -Group <id>` (or a `group`
field in a batch) now moves it, and the row KEEPS its id - G3.T149 in G1 is still G3.T149. The sort itself was
NOT touched, on the owner's instruction. The move refuses: an unknown group; a gate or integration task; a row
under a live claim; a target group that is not released or integrating (`Claim-Task.ps1:35` would hide it);
either group whose integration task has landed; and `GROUP-WIRING` unless the batch also moves the integration
edge - old group's integration task drops the row from dependsOn, new group's adds it. Case 23 of
`Test-StreamKitRecovery.ps1`, twelve clauses, guards it.

See [[project_stream_kit_replaces_myloop]], [[reference_stream_board_eta_is_chain_not_calendar]].
