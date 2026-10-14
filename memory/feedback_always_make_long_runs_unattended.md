---
name: feedback_always_make_long_runs_unattended
description: "Gene's standing instruction: any long or overnight run must be set up to advance on its own with /loop — do it by default, without being asked"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: ef743ea7-ebbb-46a3-a46a-a4316a6c4d42
  modified: 2026-09-09T14:12:29.531Z
---

Gene, 2026-09-09 10:11, after the vNext loop sat idle for seven and a half hours overnight and reached
one row instead of six: *"yes fix it to work while I am away and always do that unless otherwise
instructed."*

**Why:** a finished background `Agent` does **not** wake a dormant session — see
[[reference_loop_does_not_wake_on_subagent_completion]]. So an orchestrator-worker loop, or any
multi-step run that hands work to subagents, advances **one step per message from Gene** unless
something re-enters the session on a timer. He plans around an eight-hour window and expects the machine
to use it. Telling him afterwards that the minutes fit but nothing ran is the failure he is correcting.

**How to apply — this is a DEFAULT, not a thing to ask about:**

1. When a run is going to outlast the conversation — an overnight loop, a long campaign, anything with a
   "keep going until X" instruction — **set it up to self-drive with `/loop`** and say that you have.
   Dynamic mode (no interval) lets the model self-pace via `ScheduleWakeup`; pick the delay from what is
   actually being waited on, and keep a long fallback (1200s+) so the loop survives a hung subagent.
2. **Keep the loop's own input SHORT** and put the standing context in files the session reads on each
   tick (for vNext: `.loop\RESTART.md`, `.loop\PROGRESS.md`, `.loop\PLAN.md`). The loop input re-fires
   verbatim every tick, so a huge pasted brief is paid for repeatedly; a pointer is paid for once.
3. The loop input must be **idempotent and resumable** — `/myworkflow --resume <repo>` is, because it
   re-reads state from disk rather than assuming where it left off.
4. **Say the cost and the stop condition up front**, and state plainly if the arithmetic says the target
   is out of reach — before the run, not after it.
5. Only skip this when he says so explicitly ("stay with me", "one row then stop", a dry run).

Related: [[reference_loop_does_not_wake_on_subagent_completion]],
[[feedback_never_stop_to_report_between_rows]], [[feedback_implement_autonomously]],
[[reference_claude_account_switching]] (the other way a long run dies).

**Addendum 2026-09-12 22:1x (Gene, mid-loop): "If you run out of tokens wait and automatically continue at
the next window".** A usage-limit pause is not a stop. Never end a turn of a running loop without a wake
source armed (ScheduleWakeup heartbeat 1200s+ plus a Monitor per in-flight row), so the loop resumes by
itself when the next token window opens. Do not ask Gene to re-prompt after a limit.

**Measured 2026-09-12/13:** ScheduleWakeup alone does NOT satisfy the token-limit rule. The 22:41 and 23:02
wakeups fired INSIDE the session limit, were consumed, and nothing re-armed after the 02:00 reset — the loop
sat idle ~7 h until Gene typed. Backstop: a recurring `CronCreate` (e.g. `17 * * * *`, prompt = the
idempotent `/myfable --resume <repo>`) — it keeps firing after the window reopens. Session-only, 7-day expiry.
