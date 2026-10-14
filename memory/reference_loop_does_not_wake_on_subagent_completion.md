---
name: reference_loop_does_not_wake_on_subagent_completion
description: "A finished background Agent does NOT wake a dormant Claude Code session — the orchestrator-worker loop stops after one row unattended, measured over 7.5 hours on 2026-09-09"
metadata: 
  node_type: memory
  type: reference
  originSessionId: ef743ea7-ebbb-46a3-a46a-a4316a6c4d42
  modified: 2026-09-09T12:53:57.091Z
---

**Measured 2026-09-09.** Gene asked for the vNext loop to run to the CP-3 gate "before 7 AM". Row 48.A's
Executor finished at roughly **01:04**. The session was not invoked again until **08:45**, when Gene next
typed something. Nothing dispatched behind 48.A, so the loop sat idle for about **seven and a half
hours** and reached one row instead of six.

**The mechanism.** A background `Agent` completing raises a `task-notification`, and that notification is
delivered on the session's next activation — it does **not** itself activate a dormant session. The same
is true of a backgrounded Bash command. So the Orchestrator/Verifier turn that would close the row and
dispatch the next one never runs while nobody is watching.

**What this means for planning an overnight run:** budget arithmetic is beside the point. An
orchestrator-worker loop in this harness completes **exactly one Executor dispatch** per human
interaction, however many hours are nominally available. Do not promise a multi-row overnight run, and do
not present a row count as achievable purely because the minutes fit — say plainly that the loop advances
one row per wake-up.

**What to do instead, in preference order:**

1. **Say so before the run starts.** Gene planned an eight-hour window on the assumption the loop would
   keep going. That assumption was mine to correct and I did not.
2. **Front-load everything that does not need the Executor.** Authoring the next rows' graders, taking
   blocking decisions, verifying credentials and de-risking dependencies all work fine in one sitting, and
   that work is what made 48.A close in ten minutes. On the night measured here, six graders were authored
   ahead — so the wasted time cost dispatches, not preparation.
3. **A `/loop` or `CronCreate` schedule is the only thing that actually re-enters a dormant session.** A
   dynamic `/loop` wake-up, or a cron routine, fires without a human. Pair a long fallback interval with
   the task-notification rather than relying on the notification alone.
4. **Check `/tasks` before walking away** — a watch or task listed there is not the same as a session that
   will wake to act on it.

Related: [[feedback_never_stop_to_report_between_rows]] (which is about not idling *within* a turn, and is
unaffected), [[feedback_mark_row_started_at_dispatch]], [[reference_claude_account_switching]] (the other
way a long run dies — account switching kills the session and any in-flight Executor).
