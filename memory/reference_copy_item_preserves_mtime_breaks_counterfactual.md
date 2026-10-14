---
name: reference_copy_item_preserves_mtime_breaks_counterfactual
description: "A restore-by-copy can silently certify the BROKEN build, because Copy-Item preserves the source mtime and MSBuild then skips the rebuild"
metadata: 
  node_type: memory
  type: reference
  originSessionId: 73f55c4e-169d-4da4-8b70-935bfca53948
  modified: 2026-09-10T08:11:27.844Z
---

`Copy-Item` (and `cp`) preserve the source file's `LastWriteTime`. In a counterfactual — copy aside, break, rebuild, measure, copy back — the restore therefore lands sources that are **older than the assemblies built from the broken code**, MSBuild decides nothing needs recompiling, and the "restored" tree keeps rendering the broken build's behaviour. The proof then measures the defect and calls it the fix.

**Stamp `LastWriteTimeUtc` on the way BACK, not only on the way in.** Found 2026-09-10 by 48.RV1b's Executor in the speedmerchants vNext loop, whose own proof assertions caught it; a freshness gate that checks "source newer than assembly" **structurally cannot** catch this, because after the copy the source is older by design.

Two companions from the same programme:
- A receipt's assembly hash is provenance, not discrimination: 48.RV1b's first draft hashed `Speedmerchants.Application.dll`, which is byte-identical on the passing and broken builds of a row that changes neither. Hash the assembly that carries the thing under test.
- `$?` after a shell pipeline reports the LAST command in the pipe. Capture `$LASTEXITCODE` from pwsh directly, or a proof that exits 1 reads as 0.

See [[feedback_copy_before_probe_never_git_checkout]] for why the copy exists at all, and [[feedback_loop_practices_that_caught_defects]].

**And never hash an apphost `.exe` as provenance for managed code** (measured 2026-09-10, row
48.RV1c). `speedy-agent.exe` came back `0A1C3BD6…` on the fixed build **and on the broken one** — the
`.exe` is only the launcher stub. The IL lives in `speedy-agent.dll` (`EF3C595A…` vs `DB6B5DE7…`).
Same shape as 48.RV1b's byte-identical neighbour, one layer subtler.

**The strongest form of this check is behavioural, not a timestamp.** 48.RV1c's proof loads the
shipped assembly by reflection and asserts what the predicate ANSWERS, so it goes red on a stale or
mis-restored assembly regardless of what any mtime says — which is the guarantee a freshness check
structurally cannot give.
