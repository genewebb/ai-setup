---
name: reference-connect-synapse-12t-dw100c-timeout
description: "Connect Synapse 1M 12T export fails on DW100c: ConnEx UPDATEs queue for slots and hit the 120 s SQL timeout; read-only pool check workload on SMVMTR3"
metadata:
  node_type: memory
  type: reference
  originSessionId: 2758a18c-eddd-4fd0-98a4-1142fcc8e388
  modified: 2026-11-13T19:03:11.812Z
---

26R4 mid-release, 11/13/2026: `connect-test-synapse-export` 1M 12T failed (TestAuto execution 10000621, "Poll Strategy Synapse Export" saw the batch Failed). 4T and 8T passed.

- ConnEx log (SMVM1 `...\26.4.0\Services\ConnEx\LogFiles\SystemLog.log`): from 11:13 EST "SQL retry attempt #n of 8. Error -2: Execution Timeout Expired"; 12:33 "Fatal error on write to [ConnectTest].[PDataSynapseExport]" (Synapse 111202 query cancelled).
- Pool check: rndsynpaseworkspace pool is **DW100c**. Only the Connect service principal used it. Export table ROUND_ROBIN + CLUSTERED COLUMNSTORE. UPDATE (join on Code with temp table) averaged ~114 s, ~53 s of it queued; cancelled at ~122 s (ConnEx 120 s timeout). INSERT ~7 s. 999,000 of 1M rows landed.
- Cause: 12 threads vs DW100c concurrency; not a pack error.
- Profisee DB is restored by the next item, so Connect batch history and tSystemLog of a failed run are gone; use the ConnEx file log.
- Check workload: `synapse-pool-check` in `\\SMVMTR3\c$\Deploy\CrewChief\web\data\workloads\diag\` (read-only DMVs, writes `cli-runner\out\synapse-pool-check-result.txt`, because the CLI does not keep PowerShell output). Run: `run-cc-host.sh SMVMTR3 synapse-pool-check`. SMVMTR3 has the same Synapse secrets (Gene). Laptop Entra sign-in to the pool is refused.
- Gene 11/13: rerun as-is (round orders 30/31). If 12T fails again, drop 12T from Synapse runs; no DW200c (doubles cost).
- TAM round edit: after:all items must keep the highest orders, or Resume says "must come after every other item of its lane".

Related: [[reference-connect-databricks-fresh-table-delta-conflict]]
