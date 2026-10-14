---
name: feedback-stream-plan-no-approval-step
description: "2026-09-27 Gene removed /stream-plan approve: a plan releases to build as soon as its questions are answered; no owner gates on mockups; Gene adjusts at manual test"
metadata:
  node_type: memory
  type: feedback
  originSessionId: 19510dfa-ebfb-4e18-bc60-b0ca798f7f37
  modified: 2026-09-27T23:03:20.396Z
---

Gene, 2026-09-27: "Remove the requirement for me to approve I already did the requirements and I will adjust any implementation during manual testing ... just approve them to build".

- stream-plan v0.2: after the question rounds it publishes a record page and releases the group into tasks.json in the SAME turn. No `/stream-plan approve`, no "approve or tell me what to change".
- Mockups are checked by the build verifier, not an owner gate. The only owner gate per group is the final live look (manual test), which never blocks other tasks.
- Add-Tasks.ps1 now allows two open tasks to share a file when one depends (transitively) on the other. The later task builds on the earlier task's patch. Test-StreamKit 43/43.

**Why:** Gene owns the requirements, already approved them, and corrects the implementation during manual testing. An approval wait only idles the builders.
**How to apply:** Never end a stream-plan turn waiting for approval. Still ask the requirement/product questions (AskUserQuestion). Related: [[project-stream-kit-replaces-myloop]], [[feedback-auto-approve-recommendations-speedy-build]].
