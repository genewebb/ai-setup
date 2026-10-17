---
name: feedback_agents_control_repo_scratch_access_rows
description: "Gene 2026-10-17 - agents may do whatever is needed inside the repo and scratch areas AND every folder they routinely read/write/delete (profile '## Claude access' rows); the goal is control over what they read, write and delete, no prompts there"
metadata:
  node_type: memory
  type: feedback
  originSessionId: 3754e77a-a9e8-42e9-b3f4-cd17c62e480c
  modified: 2026-10-17T19:15:33.107Z
---

Gene, 2026-10-17 (verbatim): "All agents should be able to do whatever is needed in the scratch or repo areas as
those are either temporary or under git control" and "If there are things that are outside of the repo or the
scratch area that they routinely write to they should be treated the same, the goal is that they have control over
things they write and read and delete".

**Why:** builders and authors stalled on permission prompts nobody could answer, then timed out and exited. Repo
work is under git, scratch is temporary, and the access rows already name what the agents own on this machine.

**How to apply:** the automatic yes ([[reference_permissionrequest_hook_scoped_autoapprove_2026-10-17]]) covers
ReposRoot, WorktreesRoot, ScratchRoot, temp and every `## Claude access` row without a deny, whatever its rights.
Outside those, and for machine-wide or by-name process kills, a real prompt stays. Never answer a prompt with a
timer; make the in-scope case not prompt. Related: [[feedback_machine_portable_ai_config]],
[[feedback_connect_never_delete_entities]] (Connect entities are NOT inside this policy).
