---
name: reference-myloop-tasklist-must-be-lf
description: "MyLoop Write-TaskList.ps1 must stay LF; Set-Content on Windows writes CRLF and Set-BoardStatus then matches no tuple, so Close-Row throws after committing the record"
metadata:
  node_type: memory
  type: reference
  originSessionId: 1c475457-1e54-4237-a0cd-5cdd61ea1bc1
  modified: 2026-09-27T19:19:54.415Z
---

`Set-BoardStatus` (myloop scripts\RowCommon.ps1) finds a row's tuple with a multiline regex ending `('\s*,[^\r\n]*)$`. In .NET `$` matches before `\n` only, so on a CRLF file the `\r` is left over and every key reports "expected exactly one tuple ... found 0".

Hit 2026-09-27: a `Get-Content | ... | Set-Content` rewrite of `.loop\tools\Write-TaskList.ps1` turned it CRLF. Close-Row then committed the RD-24 record and actuals, but threw at the board step, and `Reconcile-Rows -Repair` did not finish it.

**Fix:** rewrite loop tool files with `[IO.File]::WriteAllText($p, $text, [Text.UTF8Encoding]::new($false))` using `\n`, or use the Edit tool. To finish a close stranded this way, dot-source RowCommon.ps1, run `Set-BoardStatus $P '<key>' '<DONE line>'`, then `Invoke-ScheduleRegen`.

Related: [[reference-python-print-crlf-breaks-bash-loops]], [[feedback-one-row-per-write-set]].
