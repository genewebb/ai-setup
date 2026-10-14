---
name: skill-compare-performance-by-versions
description: >-
  Compares Profisee CRUD performance across 1..N platform versions and writes a markdown report from
  the perfDashboard summaries. Use whenever the user wants to compare, benchmark, or analyze CRUD
  performance, latency, throughput, or regressions BETWEEN Profisee versions ("26R1 vs 26R2P", "did
  the latest release regress create performance?"), including a single-version snapshot. NOT for
  matching results, record-count migration, logs, or inspecting a workflow's stored config.
---

# Compare Performance By Versions

Produces a `{V1}-vs-{V2}[-vs-{V3}...]-Comparison.md` report comparing CRUD performance across the selected Profisee versions, mirroring the established house format.

## What you are building

A markdown report with, in order: a **Batch CRUD** table, a **User CRUD** table, a **Summary**
(Wins / Regressions), and — only if the user opts in — a **Root Cause** section. The headline
metric is the **Winsorized average response time** (outlier-trimmed mean); throughput and
P50/P95 are secondary.

The hard part — an apples-to-apples "common runs" aggregation across N versions — is handled
by the bundled script. Your job is orchestration and rendering.

> **Terminology:** this is **CRUD performance data**. "Common runs" means
> the AttributeCount × UserLoad run combinations that exist across all compared versions (a set
> intersection).

## Inputs

- **Versions (required):** 1 to N Profisee version tags. Prompt the user if not given. Valid
  tags currently in the data: `25R1, 25R2, 25R3, 25R4, 26R1, 26R2P`. Confirm the exact list
  before proceeding — get the spelling right (`26R2P`, not `26R2`). **When you prompt for the
  versions, also remind the user that business rules must be run manually before the rebuild
  procs (see step 1).**
- **Order:** Treat the versions oldest → newest. The **first** version is the delta **baseline**.
  If the user lists them out of order, sort chronologically and tell them which you picked as baseline.
- A single version (N=1) is valid: produce the same tables with no delta columns — a snapshot.

## Workflow

Follow these steps in order. Create a TodoWrite item per step.

### 1. Confirm versions and refresh the summary tables

Confirm the version list with the user (see Inputs).

> **Prerequisite — tell the user this when you prompt for versions:** business rules must be run
> **manually** against the relevant data **before** the stored procedures are executed. The
> summary procs aggregate already-executed run data; if the rules haven't been run for a version,
> its CRUD timings will be missing or stale and the comparison will be wrong. Confirm the user has
> done this before proceeding to the rebuild.

The two summary tables are rebuilt from raw execution data by two stored procedures. **This runs
against PRODUCTION — confirm with the user before executing.** Explain plainly: "These procs
rebuild `perfDashboard.BatchCrudSummary` and `perfDashboard.UserCrudSummary` from raw run data on
the prod database. Run them now?"

On approval, run via the `speedmerchants-prod-mssql` MCP `execute_query` tool:

```sql
EXEC perfDashboard.CreateBatchCrudSummary;
EXEC perfDashboard.CreateUserCrudSummary;
```

If the user declines the rebuild, proceed with existing table data and note in the report that
the summaries were not refreshed.

### 2. Generate the comparison SQL

Run the bundled script to get tidy, common-runs-filtered SQL. Pass versions oldest → newest:

```bash
python "<skill-dir>/scripts/build_comparison_sql.py" --versions 26R1 26R2P
```

`--metric batch|user|both` (default `both`). The script validates version tags and bakes in the
common-runs filter (only fine-grained AttributeCount × UserLoad combos present in **all** N
versions are counted). Read `references/data-model.md` if you need to understand or hand-modify
the query.

### 3. Run the queries

Execute each emitted statement via the `speedmerchants-prod-mssql` MCP `execute_query` tool. You get LONG format: one row per `(Scenario, Operation, RuleCount, PlatformVersion)` with
`WinsorizedAvgMs`, `P50Ms`, `P95Ms`, `ThroughputRecPerSec`, and `ComboCount`.

If a query returns zero rows for a version, that version has no common runs for those combos —
surface that to the user rather than silently dropping it.

### 4. Render the report

Pivot the long rows into wide tables (one metric column per version). Build the doc from the
template in `references/report-template.md`. Key rendering rules:

- **Friendly Scenario label** (Batch table): derive the leading verb from the scenario name —
  `CreateRecordsByPageAndBatchScenario` → `Create`, `GetRecordsByPageAndBatchSeqScenario` → `Get`,
  `DeleteRecordsByPageAndBatchScenario` → `Delete`, `UpdateRecordsByPageAndBatchScenario` → `Update`.
- **Delta columns:** for each non-baseline version, compute `Δ% = (version − baseline) / baseline` vs the baseline (first) version. For exactly 2 versions also include `Δ (ms)` to match theclassic format. Bold any delta with magnitude ≥ ~15%. Negative latency delta = improvement.
- **Batch table** shows Winsorized avg (ms) + Throughput (rec/s) per version. **User table** shows
  Winsorized avg (ms) + P50 + P95 per version (throughput isn't meaningful for single-record ops).
- **Summary:** read the deltas and write the Wins / Regressions tables in prose — call out the
  largest improvements and any regression. This is interpretation, not just transcription.

### 5. Offer root-cause investigation (ask at runtime)

After the data + summary are written, **ask** the user: "Want me to investigate likely root
causes for the regressions in ADO?" If yes, see `references/root-cause.md` for how to search
Azure DevOps PRs in the version window and draft the Root Cause section. If no, finish without it.

### 6. Write the file

Save to the metrics folder:

```
{VaultDocsRoot}\metrics\{V1}-vs-{V2}[-vs-{V3}...]-Comparison.md
```

Filename joins versions with `-vs-` in chronological order (e.g. `25R4-vs-26R1-vs-26R2P-Comparison.md`).
For N=1 use `{V1}-Snapshot.md`. Report the path back to the user.

## Reference files

- `references/data-model.md` — table/column reference, the common-runs logic, the base views.
- `references/report-template.md` — the exact markdown structure to fill in.
- `references/root-cause.md` — how to attempt ADO root-cause investigation (step 5, opt-in).

## Guardrails

- This always targets the production DB via `speedmerchants-prod-mssql`. Never run the rebuild
  procs without explicit user confirmation (step 1).
- Never invent numbers. Every value in the report must come from a query result. If a cell has no
  data, render `—`, not a guess.
- Do not commit anything (per global rules). Just write the markdown file.
