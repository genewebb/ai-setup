# Root Cause Investigation (opt-in)

Only run this after the data + Summary are written **and** the user said yes to investigating
root causes. It is best-effort: you are correlating code changes to a measured regression, not
proving causation. Be honest about confidence.

## When it's worth doing

A regression is worth investigating when it is **consistent and material** — e.g. ≥15% slower
across multiple attribute-count/user-load combos (high `ComboCount`), not a single thin-sample
blip. Pick the 1–3 clearest regressions; don't chase noise.

## How to investigate

The Azure DevOps MCP server exposes `mcp__azure-devops__*` tools (PRs, work items, file content).
The relevant repo for CDP record-save / CRUD changes is **`Products/_git/Cdp`**.

1. **Establish the window.** The regression happened between the baseline version and the version
   that regressed. Find the merge/release dates that bracket those two versions.
2. **List candidate PRs.** Use `mcp__azure-devops__azure_devops_pull_requests` on the `Cdp` repo,
   filtered to that date window. Prioritize PRs whose title/description mentions the hot path:
   record save, bulk copy, insert, update, delete, DQ/Evaluator, SqlQueryBuilder, DataAccess.
3. **Inspect the suspect.** Use `azure_devops_pull_request_by_id` / `azure_devops_pull_request_changes`
   to read the description and changed files. A PR that optimizes *bulk/volume* operations is a
   classic cause of *single-record interactive* regressions (fixed setup cost with nothing to
   amortize against) — see the worked example below.
4. **Write it up.** Document author, merge date, branch, PR link, what changed, and a plain-language
   explanation of *why* it would help one path while hurting the other. Always end with a concrete
   recommended fix.

## Worked example (the 26R1 → 26R2P User-CRUD write regression)

This is the canonical example the format was built around — use it as a quality bar, not a script.

> **PR 23080 — "CPTI: Make Record Updates Fast"** (merged to `Cdp/main` 2026-05-09) replaced how
> the **per-save input temp table** is populated — from `INSERT … OPENJSON(@json)` to `SqlBulkCopy`
> — not the delete or update SQL itself. At volume (20K records) that's an 80% win, which is why
> **Batch** Create/Update improved 22–45%. But `SqlBulkCopy` has fixed per-call setup overhead
> (target-table metadata query, build DataTable, bulk batch handshake) that a **single row** can't
> amortize. Any single-record interactive op that routes through that populate step regressed:
> User Create/Update ~18–21%, and **Delete *with rules* ~58%** — because deleting a rule-bearing
> record stages it into that same save/DQ-eval temp table so the evaluator can recompute issues.
> Delete *without* rules skips DQ evaluation, never hits the temp table, and did **not** regress —
> that with-rules/without-rules asymmetry is the diagnostic tell.
>
> **Verify, don't assume:** the DQ `Evaluator.cs` was also in this PR's file list but had *no
> executable changes* (diff-coverage "no executable changes"; file shrank 22 bytes) — so the rule
> engine is NOT the cause. Confirm by diffing files, not by file presence. Recommended fix: gate
> the temp-table populate behind a record-count threshold (~64–256 rows) — legacy OPENJSON below,
> SqlBulkCopy above — preserving the bulk win while restoring single-record latency.
>
> **Tooling note:** the `azure_devops_pull_request_file_content` MCP tool was returning malformed
> data (an undrained stream object, not file bytes) during this investigation — the verdict relied
> on the PR description, the author's review comments, per-file diff line counts, and byte-level
> blob sizes. If you need the literal changed lines, diff the merge commit from a working checkout.

## Section structure to append

```markdown
## Root Cause: {short description}

### PR {id} — "{title}"

| | |
|---|---|
| **Author** | {name} |
| **Merged** | {date} |
| **Branch** | `{branch}` |
| **ADO** | {repo/pullrequest/id} |

### What changed
{bullet summary of the diff}

### Why it caused the regression
{plain-language causal explanation; a small table mapping each affected area to the cause helps}

### Recommended fix
{concrete, actionable}
```

If you cannot find a convincing cause, say so — "no single PR clearly accounts for this; candidates
were X, Y" is a more useful answer than a forced narrative.
