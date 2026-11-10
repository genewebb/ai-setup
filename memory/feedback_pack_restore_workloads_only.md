---
name: feedback-pack-restore-workloads-only
description: "Pack zip restore on a box that already has the pack = workloads/<family> only, never reference-kv (holds box machine names + TestAuto workflow codes)"
metadata:
  node_type: memory
  type: feedback
  originSessionId: 95f5b98f-d94c-408a-8901-e309c3b37709
  modified: 2026-11-10T19:02:47.970Z
---

When telling Gene how to restore a CrewChief pack zip on an existing box: tick ONLY `workloads/<family>` (mode Replace).
Never `reference-kv/<family>`: the repo copy holds repo machine values (SMVM1, CORPLTR94) and repo workflow codes
(`<family>/workflows`), and Replace overwrites the box's own. reference-kv only for a box that never had the pack,
then edit machines/instances. New reference keys a pack needs = added by hand on each box.

**Why:** 11/10 I first wrote "restore workloads and reference-kv", then corrected it a reply later; Gene caught the
contradiction. The crud-pack skill already said "only workloads/crud unless the box is new".

**How to apply:** before giving restore steps, check which `$ref` keys the new workloads read vs what changed in
reference-kv (git diff), and list the keys to add by hand. Related: [[project-multi-version-lanes-2026-11-09]]
