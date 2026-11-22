---
name: reference_gates_md_is_hand_maintained_and_drifts
description: ".streams\\owner\\gates.md is hand-written, nothing regenerates it, so a gate task added between refreshes is invisible"
metadata: 
  node_type: memory
  type: reference
  originSessionId: 791f1040-13cb-474c-8883-7a1bc9dc8c14
  modified: 2026-09-29T18:51:01.980Z
---

A gate is a **task** in `tasks.json` with `kind: gate`. `.streams\owner\gates.md` is only its human listing,
and **no script writes it** — `Init-Streams.ps1:19` just creates the header, and the `Refreshed ... by <session>`
line at the top is typed by whoever last edited it. `/stream-integrate gate <task> pass|fail` resolves the id
against `tasks.json`, not against the listing.

Two consequences, both seen on 2026-09-29:

- A gate task added between refreshes is never listed, so the owner cannot act on a gate he cannot see.
  `G6.G91` was added at 16:13Z to a file last refreshed at 15:19Z and sat invisible.
- A line hand-written into `gates.md` for an id that is not a gate task is decorative: it holds nothing and
  its `pass` command finds no task. Writing `G2.G04` into the file created exactly this.

Also: a gate holds **only its own group's** close. Debt that must outlive a group's close belongs to a gate in
a later group, not in the group that is closing.

Fixed by a drift flag in `Get-StreamStatus.ps1` (just before the `$model` assembly) that reports both
directions on every status run and status-page build. Match the id **anchored at line start**
(`^\s*(?:RESOLVED\s+)?-\s+(\S+?)\s+\|`), never as a substring — every gate id also appears inside other gates'
prose, and a substring sweep deleted a live gate's line.

See [[reference_stream_owner_queue_bullets_are_the_escalations]], [[project_stream_kit_replaces_myloop]].
