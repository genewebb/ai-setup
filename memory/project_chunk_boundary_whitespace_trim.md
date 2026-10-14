---
name: chunk-boundary-whitespace-trim
description: ScenarioConfigStore chunking lost a boundary space (DROP TABLE → DROPTABLE SQL error) because Profisee trims attribute whitespace; fixed by whitespace-safe split points
metadata: 
  node_type: memory
  type: project
  originSessionId: 1e7a964d-bbf9-45a1-b95e-b6dc6d70720b
---

Profisee **silently trims leading/trailing whitespace from every attribute value**. `ScenarioConfigStore` (chunked config, ChunkSize=3900, attr `ScenarioJsonData` on entity `TestAutoScenarioConfiguration`) split the JSON by raw char index, so a 3900 boundary could land on whitespace. That edge whitespace was trimmed on the round-trip, and `ReassembleChunksAsync` (plain `string.Concat`) then mashed the adjacent tokens. For an inline SQL step this turned `DROP TABLE` into `DROPTABLE` → `SqlException 102 Incorrect syntax near 'DROPTABLE'` (thrown in SqlScriptExecutor, but the bug was NOT there — GoBatchSplitter/TextTemplater/pass-fail-wrap all preserve whitespace).

**Verified via live data:** non-final chunks read back at 3899/3898/3894/3889 (should be exactly 3900), and 0/30 chunks start or end with whitespace — proof of the trim. Most configs survived because their boundary whitespace was *structural* JSON whitespace (parser ignores it); only whitespace INSIDE a string value (the space in `DROP TABLE`) corrupts.

**Why:** correctness of any large (chunked) scenario/workflow config containing significant interior whitespace.

**How to apply:** fix is `SplitIntoChunks` backing each boundary up until it sits between two non-whitespace chars (`char.IsWhiteSpace(source[cut-1]) || source[cut]`), with hard-limit fallback for a >3900 all-whitespace run (accepted hole). Reassembly unchanged → backward compatible on read. **Existing DB configs already corrupted are NOT auto-repaired — must be re-saved.** Test: `Persist_ChunkBoundaryWhitespace_SurvivesProfiseeTrim` sweeps payload lengths (prepend padding to slide boundaries) + simulates trim via `.Trim()`. Related: [[reference_scenariodatadisplay_4000_ceiling]], [[testauto-scenario-config-store]], [[configuration-compression-codec]].
