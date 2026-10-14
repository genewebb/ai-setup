---
name: schedule-json-is-the-backup
description: ".loop/tools/Write-TaskList.ps1 is untracked by git, so schedule.json is its only backup — it carries every row's full status prose and can rebuild the $rows array"
metadata: 
  node_type: memory
  type: reference
  originSessionId: 25a6f180-ace3-4c16-9718-60b837d6c54c
  modified: 2026-09-08T00:27:15.354Z
---

`C:\devops\repos\speedmerchants\.loop\tools\Write-TaskList.ps1` holds the vNext schedule's `$rows` array —
158 rows, each `@(key, task, status, est, plan)`, with the status field carrying a paragraph of close prose.
**`.loop/` is in `.git/info/exclude`, so the file is UNTRACKED: there is no `git restore`, no `git show
HEAD:`, no reflog.** Destroy it and git offers nothing.

**The backup is `.loop/tools/schedule.json`**, rewritten by `Write-Schedule.ps1` on every run. Its `rows[]`
carries `key`, `task`, **`status` (the full prose)**, `est`, `plan`, plus derived `state`/`actual`/`completed`.
Rebuilding the `$rows` array from it is mechanical: quote each field, double every `'`, emit `$null` for a
missing `plan`, leave integer keys unquoted. `schedule.html` is NOT a backup — the HTML keeps only the
derived Complete/Queued/Started label and the plain-English line from `descriptions.json`.

The header (`param(...)`, `$OutPath`, `$Base`, `$StatusKv`, `$OrchestrationMinutes`) is not in
`schedule.json`. Recover it from a session transcript under
`C:\Users\agenewe\.claude\projects\C--devops-myworkspace\*.jsonl` — grep for `@('52.01'`, parse the JSON
line, take the longest string containing both that and `param(`, and strip the Read tool's `^\d+\t`
prefixes. `Write-Schedule.ps1` only PARSES the `$rows` array out of the file (it never dot-sources it and
passes no parameters), so an older header is safe to reuse.

**Why:** on 2026-09-07 20:26 an `IndexOf` on a non-BMP emoji (`[char]0x1F504` throws — a surrogate pair
will not fit a `Char`) returned no index, and the `Substring` arithmetic built from it silently cut the file
from 158 rows to 7. Full recovery took about ten minutes because `schedule.json` existed.

**How to apply:**
- Never compute `Substring` offsets from an `IndexOf` whose result was not checked for `-lt 0`, and never
  search for an emoji through `[char]` — match the literal in a single-quoted string instead.
- Prefer the Edit tool over offset arithmetic for changing one row's status field.
- Before any scripted rewrite of this file, copy it to `C:\tmp` first — see
  [[feedback_vnext_schedule_format]] and [[feedback_no_commits]] (the file being untracked is deliberate,
  not an oversight to fix).
