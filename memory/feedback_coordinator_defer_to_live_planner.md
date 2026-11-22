---
name: feedback-coordinator-defer-to-live-planner
description: Coordinator must stop plan work when any Set-InboxItem take returns ALREADY; an idle planner (no history for 30+ min) can still be live
metadata:
  node_type: memory
  type: feedback
  originSessionId: 185f5665-8770-43d9-9ee7-eb0430a4dfbe
  modified: 2026-10-04T14:07:09.298Z
---

When a planner session exists, let it do the plan inbox. The owner said on 2026-10-04: "The planner is up and working let the planner do that work".

**Why:** On 2026-10-04 at 03:04Z the coordinator ran batch b77 on three plan items. Planner plan-23931cca had closed those items at 03:03Z. The planner's last history entry was 46 minutes old, so the 30-minute liveness check called it "not live". It was only sleeping. The take step printed `ALREADY ... done by plan-23931cca`, but the script went on and ran Revise-Task anyway. That overwrote the planner's G6.T011 title. Two planners editing one task is the 9/28 failure again.

**How to apply:**
- Treat any `ALREADY` or exit 8 from `Set-InboxItem -Status taken` as a hard stop. Run no Revise-Task for that item, and run the take as its own call before you build the batch.
- If a plan session ran at any time today, do not act as planner. Tell the owner if items wait more than about 45 minutes.
- Pass array params (removeWhy, addWriteSet) to Revise-Task through a `-File` batch. With `pwsh -File`, the inline form flattens them into one string and silently does nothing.

- The same applies to EVERY inbox, kit included. Take the item (`Set-InboxItem -Status taken`) BEFORE staging any fix, even for an item you filed yourself seconds ago. On 2026-10-04 at 13:42Z, kit-49da5f78 took kit item ad1f three minutes after the coordinator filed it. The coordinator never took it, built the same fix, and published over the holder's work in progress at 14:02Z.
- Before starting a planner or any other role session yourself, check for fresh `taken` holds. Old history alone is not enough: plan-23931cca had been silent for 10 h, then took items 21 s before the coordinator launched a plan runner.

Related: [[reference-stream-history-writer-is-by-not-session]]
