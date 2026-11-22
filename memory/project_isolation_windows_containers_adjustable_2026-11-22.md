---
name: project_isolation_windows_containers_adjustable_2026-11-22
description: Gene 11/22 - settings can be adjusted on the real Windows (Profisee) containers when they are used; the Linux isolation stack need not settle every tuning question first
metadata:
  node_type: memory
  type: project
  originSessionId: 7986e46e-eb36-4bdb-a0ee-12f91e19b099
  modified: 2026-11-22T14:34:00.004Z
---

Gene, 2026-11-22 09:33: "We can make adjustments to the real windows containers if needed when we use them just note that".

**Why:** the isolation tests run on a Linux test stack; the real workload will be Profisee Windows containers on a WS2025 VM (next phase, after the final isolation verdict).

**How to apply:** do not hold the isolation verdict for tuning that can be done on the Windows containers later. Note such items as "adjust on Windows containers if needed". Recorded in note 11 Log and the plan page. Related: [[project_isolation_test_plan_page_2026-11-17]], [[feedback_isolation_status_frame_container_isolation_2026-11-19]].
