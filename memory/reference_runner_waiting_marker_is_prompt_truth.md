---
name: reference-runner-waiting-marker-is-prompt-truth
description: "Whether a -Live stream builder still waits on a permission prompt is read from its runner .waiting.json marker, not inferred from side effects"
metadata:
  node_type: memory
  type: reference
  originSessionId: 28c88d04-48e0-401b-b479-5ac38afd10e0
  modified: 2026-10-11T11:06:13.277Z
---

A -Live runner unit that hits a permission prompt writes `.streams\logs\runner\<runner>\<unit>.json.waiting.json`
(`{"waiting":true,"since":<ms>,"tool":...,"reason":...}`). The file is never deleted: answering the prompt flips
`waiting` to false. So the signal is `waiting:true` AND the session still holds a live claim (units that ended while
prompted, e.g. 194b and 2708 on 10/11, keep a stale `waiting:true`).

On 2026-10-11 the coordinator told the owner Builder 5's prompt "looks answered" because the temp folder the prompt
wanted to delete (D:\tmp\g5r4f1live) had vanished. Wrong: the marker was still present and the worktree had no edits
for 2 h. The G5 close-critical fix sat idle meanwhile.

Also wrong on 10/11: calling Builder 1 and 3 escalations "stale" because they held no claim. Their units were still
alive and prompted for 7-9 h, so status counted them "idle" while they could not claim. Ground truth for every builder:
`.streams\runners\runner-build-*.json` unitPid alive (Get-Process) and lastStart not advancing = unit stuck in its tab.

**How to apply:** before calling a prompted builder unblocked, check that its `.waiting.json` is gone AND that its
worktree or history moved. Never infer from a side effect. Related: [[reference-stream-prompted-unit-goes-stale-after-reclaim]].
