---
name: feedback-g2-sessions-first
description: "After G1 closed (2026-10-02), Gene wants G2 work picked up before anything else whenever possible: G2 suites, G2 fix rows and G2 gates come ahead of other groups' drains"
metadata:
  node_type: memory
  type: feedback
  originSessionId: 4599ecab-4540-423c-841b-aeba6b8760d1
  modified: 2026-10-04T02:00:16.149Z
---

Gene, 2026-10-01 20:35 EDT, right after G1 closed: "Your priority is to pick up G2 sessions before anything else when possible".

**Why:** groups close in owner priority order (G1>G2>G3>G4>G5>G6). With G1 closed, G2 is next to close.

**G2 CLOSED 2026-10-04T02:00Z** on suites run 6 (snapshot 9140684). Under the same priority-order rule, the next group is now G3. Gene's literal instruction named G2, so confirm with Gene before treating G3 as binding.

**How to apply (historical, for G2):** as integrator, start the G2 step B run (G2.T90) as soon as main is free. Do not start a new drain of other groups' patches while G2 suites are waiting. Integrate G2 fix rows first. Route G2 failures and gaps immediately. As any other role, claim G2 rows before others. Related: [[feedback-group-closes-on-own-scope-in-priority-order]].
