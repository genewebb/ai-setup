---
name: reference-add-tasks-overlap-counts-integrated-and-globs
description: "Stream kit Add-Tasks.ps1 overlap check treats INTEGRATED rows and glob write-set entries as open owners, so a new row needs a dependsOn edge on landed rows and on glob owners"
metadata: 
  node_type: memory
  type: reference
  originSessionId: 1a14b1e5-45cb-4509-8b19-dd9a75142145
  modified: 2026-09-30T15:50:08.385Z
---

`Add-Tasks.ps1` builds its overlap set as every task whose state is not `done` and whose kind is not `gate`/`integration` (script lines ~25). So a new row's write set collides with **integrated** rows too, not just unlanded ones, and the file is refused whole (`REFUSED <id>: write set overlaps <other>`) unless an edge exists in either direction.

Two consequences measured on 2026-09-30:

- A follow-up row over files whose only owners are integrated must still list those rows in `dependsOn` (for example `G2.T106 dependsOn G2.T10, G2.T99, G2.T18`). Under `-Role integrate` the script chains it automatically; under `-Role plan` it refuses.
- A write set can hold a **glob** (`G5.T010` owns `src/Web/Documentation/*.md`), and the overlap test matches it, so any row over one such file collides with the glob's owner. When the order you want is *glob owner after the new row*, the edge cannot exist at creation: add the row naming the glob owner, then in the same tick reverse it with `Revise-Task.ps1 -File` (`removeDependsOn` on the new row, `addDependsOn` on the glob owner). The batch validates the FINAL board state, so one batch is enough — the same shape as [[reference-stream-inbox-item-reopened-while-held]]'s sibling case with `G6.T109`.

**Why:** two REFUSED batches in one tick, both diagnosed as bad ownership measurement when the rule was actually working as written.

**How to apply:** before writing an `Add-Tasks` file, list owners with state `!= done` (not `state == planned`), and check whether any owner's entry is a glob rather than a path.
