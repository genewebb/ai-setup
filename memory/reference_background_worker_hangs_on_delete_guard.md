---
name: reference_background_worker_hangs_on_delete_guard
description: "A background loop worker that runs rm -rf / Remove-Item hits the harness delete guard and waits forever; no report, no error, the wave never completes"
metadata: 
  node_type: memory
  type: reference
  originSessionId: a2ce2bbb-6850-4044-9304-dc65407c6c01
  modified: 2026-09-15T10:37:24.892Z
---

52.P1.8i attempt 1 (2026-09-15) ran `rm -rf "$S/stage"; cp -r ...` in Bash to stage a grader run. The harness guards deletes; in a background workflow agent the refusal/prompt has no one to answer, so the agent sat on that tool call for 60 minutes with its transcript untouched, the wave never notified, and the vault got nothing. The lead's own Remove-Item calls had been blocked twice the same day — and even a command whose TEXT merely contains `Remove-Item` / `rm` in a string literal is refused (`Remove-Item on system path '\<file' is blocked`).

**How to spot it:** a dispatched row well past its calibrated estimate whose agent transcript (`subagents\workflows\wf_*\agent-*.jsonl`) has not been written for many minutes, last entry a `tool_use` with a delete. Check the transcript mtime, not the wave output file (empty until the end).

**How to apply:**
- Recovery: `TaskStop` the wave, `Reconcile-Rows.ps1 -MarkLost <key>` (LOST is not a strike and is exempt from the unchanged-ticket guard), amend the ticket, re-dispatch.
- Prevention: worker preamble rule 8 in myloop `PROMPTS.md` forbids deletes; stage into new timestamped folders. When the lead writes a script that must mention delete commands in text, write it to a file with the Write tool and run the file.
Related: [[project_myfable_foreman]], [[reference_myloop_orphan_recovery_and_script_gaps]].
