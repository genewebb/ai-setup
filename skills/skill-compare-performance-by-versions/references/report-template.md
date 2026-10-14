# Report Template

Fill this in. `{...}` are placeholders. The two-version example below is the canonical shape;
for N>2 add one metric column per extra version and one delta column per non-baseline version.

---

```markdown
# {V1} vs {V2}[ vs {V3}...] Performance Comparison

**Generated:** {YYYY-MM-DD}  
**Database:** `pc-speedmr-prd-db`  
**Source:** `perfDashboard.BatchCrudSummary` / `perfDashboard.UserCrudSummary`

---

## Batch CRUD

Sourced from `data.tRecordApiExecution`. Each row is averaged across attribute count and user
load combinations where all compared versions had common runs.

| Scenario | Operation | Rules | {V1} WinzAvg (ms) | {V2} WinzAvg (ms) | Delta (ms) | Delta % | {V1} Throughput (rec/s) | {V2} Throughput (rec/s) | Throughput Δ |
|----------|-----------|-------|------------------:|------------------:|-----------:|--------:|------------------------:|------------------------:|-------------:|
| Create | Create | 10 Rules | 12,487 | 9,217 | -3,270 | **-26%** | 78.5 | 105.6 | +27.1 |
| ... |

---

## User CRUD

Sourced from `data.tRecordInteractiveApiExecution`. Values are averaged across attribute count
and user load combinations with common runs.

| Operation | Rules | {V1} WinzAvg (ms) | {V2} WinzAvg (ms) | Delta (ms) | Delta % | {V1} P50 | {V2} P50 | {V1} P95 | {V2} P95 |
|-----------|-------|------------------:|------------------:|-----------:|--------:|---------:|---------:|---------:|---------:|
| Create | 10 Rules | 136 | 163 | +27 | **+20%** | 135 | 165 | 144 | 181 |
| ... |

---

## Summary

### Wins in {newest version}

| Area | Improvement |
|------|-------------|
| {area} | {e.g. "53–62% latency reduction; throughput 4K → 9–10K rec/s"} |

### Regressions in {newest version}

| Area | Change |
|------|--------|
| {area} | {e.g. "~20% slower across all attribute counts and user loads"} |

{One or two sentences interpreting the overall picture — which path (read/write, batch/interactive)
improved or regressed and roughly by how much.}
```

---

## Formatting notes

- Thousands separators on ms and rec/s values (`12,487`, `9,255`).
- Right-align numeric columns (`---:` in the header separator).
- Negative latency delta = faster = a win. Positive throughput delta = a win.
- **Bold** any `Delta %` whose magnitude is ≥ ~15% so big moves jump out. Use `flat` for 0%.
- For **N>2 versions**: keep one `WinzAvg (ms)` column per version in chronological order, then a
  `Δ% vs {baseline}` column for each non-baseline version. The `Delta (ms)` column is optional once
  there are 3+ versions (it gets wide) — `Δ%` is the priority.
- For **N=1 (snapshot)**: show the per-version metric columns only, no delta columns; title the
  file `{V1}-Snapshot.md`.
- The **Root Cause** section (from `root-cause.md`) is appended only when the user opts in.
