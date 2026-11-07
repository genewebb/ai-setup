---
name: project-smvmtr1-packs-verified-2026-11-07
description: "SMVMTR1 Connect + Matching 1K verified 11/07; SMVM2 repurposed as SMVMTR1's P2P target (Gene approved), all setups passed"
metadata:
  node_type: memory
  type: project
  originSessionId: 8ecc9a58-e238-47c7-875f-417dfa1ed23f
  modified: 2026-11-07T07:44:46.635Z
---

11/07/2026 verification on SMVMTR1 (Main SMVM1/SMVMDB1, P2P target SMVM2/SMVMDB2):
- connect-setup: first run stopped at Synapse prepare (pool "not currently available", transient); rerun 03:09 PASSED all 5 steps (every export + import prepare).
- connect-preflight PASS; Connect smoke round (1K SQL Server export + import) PASS.
- matching-setup, matching-preflight, matching-1k-scenario1-load PASS; tRetailClient = 1000, profisee_Matching_1K_loaded.bak written.

SMVM2 previously held another box's MAIN Connect model (likely SMVMTR2). Gene chose "Use SMVM2 anyway": deleted only the Main-role import entities there (pack-created) so the P2P target build could run.

**Why:** that other box must rerun its own connect-setup; two boxes running Connect against SMVM2 clash.
**How to apply:** before Connect runs on SMVMTR2 or any box pointing at SMVM2, check its role. Related: [[feedback_red_is_red_declared_inputs]].
