---
name: reference_write_tasklist_row_silently_dropped
description: A malformed row tuple in .loop\tools\Write-TaskList.ps1 parses clean and then vanishes from schedule.json without any error
metadata:
  type: reference
---

In the speedmerchants loop, an edit that leaves a row tuple as `@('key','task','status',,, 40, 50),`
(extra commas, usually from a scripted status replacement that both keeps and re-adds the closing
`',`) **passes `[Parser]::ParseFile` cleanly**, and then `Write-Schedule.ps1` drops the row from
`schedule.json` **silently** — no warning, no error, exit 0. The published artifact then shows a row
that is dispatched as if it did not exist.

Caught 2026-09-10 only because I grepped `schedule.json` for the row I had just marked Started.

**How to catch it every time:** `Build-Schedule-Html.py` prints `N tasks` on every run. Watch that
number — it must go UP by exactly the rows added and never move when a status is edited. It read
`182 tasks` with a row missing and `183 tasks` after the repair.

Related: [[reference_schedule_json_is_the_backup]] — `schedule.json` is the only backup of
`Write-TaskList.ps1`, so a silently dropped row is also a silently dropped backup.

**Root cause of the malformation, so it stops recurring (twice in one hour, 2026-09-10).** The
status-replacement idiom is:

```python
k = seg.index(q + 'OLD STATUS OPENING WORDS')
j = seg.index(q + ',', k) + 1          # <-- +1 lands just past the QUOTE, NOT past the comma
old = seg[k:j]                          # so old ends with ' and the source comma still follows
```

Writing `new = q + ... + old[1:-2] + ... + q + ','` then adds a second comma **and eats one real
character of the old text**. Use `old[1:-1]` and append only the closing quote — or set
`j = seg.index(q + ',', k) + 2` and keep appending `q + ','`. Either way, **regenerate and check the
`N tasks` count before publishing.**

**Tuple order gotcha (2026-09-13 19:1x):** `Write-TaskList.ps1` rows are `@(key, task, status, CALIBRATED est, PLAN est)` — calibrated FOURTH, plan FIFTH (header comment line 8). Write-Schedule reads `row[3]` as the estimate. The §6–§8 dial rows were first filed as (plan, cal) and every code row was double-counted until corrected; check the "Est (plan) / Est (opus)" columns on the schedule after filing.
