---
name: project_speedy_home_is_the_dashboard_g5t015_extends_it
description: "Speedy HomePage at \"/\" IS the owner-approved landing dashboard; G5.T015 makes it configurable rather than replacing it"
metadata: 
  node_type: memory
  type: project
  originSessionId: 791f1040-13cb-474c-8883-7a1bc9dc8c14
  modified: 2026-09-29T18:29:17.532Z
---

Decided 2026-09-29. `src/Web/Components/Pages/HomePage.razor:5` declares itself *"HOME: the landing
dashboard, in CrewChief's Home anatomy (owner-approved mockup, 2026-09-25)"*. It is NOT the monitor —
the monitor watches one load test live at `/monitor`.

So G5.T015 "configurable dashboard" **extends** HomePage instead of taking `/` from it:

- Home's approved tiles become the dashboard's DEFAULT panel set.
- Config mode is added to that same page.
- `<ContentWelcome>` stays exactly where it is at `HomePage.razor:60-62` — no re-siting, and the G2
  content-welcome banner collision is closed.
- `HomePage.razor` / `.razor.cs` come into G5.T015's write set; G5.T012 D1 (route left to G5.T015) is
  superseded.

**Why:** a `/dashboard` route would have left two dashboards, and replacing Home outright would re-lay-out
an audited screen, which discards its audit — see [[feedback_speedy_master_detail_layout]]. Publish default
IS exposed on the page, behind `SpeedyOperations.PublishDashboardDefault`, though no AC asks for it.

Related: [[project_stream_plan_g2_g6_released_2026-09-27]],
[[reference_stream_owner_queue_bullets_are_the_escalations]].
