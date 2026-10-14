---
name: reference_write_tasklist_is_lf_writealllines_breaks_close
description: "Write-TaskList.ps1 is LF; [IO.File]::WriteAllLines turns it CRLF and every Close-Row then throws \"expected exactly one tuple, found 0\" AFTER the record commits"
metadata: 
  node_type: memory
  type: reference
  originSessionId: 1a412ebb-924b-4fe0-a5a6-bf795960b18e
  modified: 2026-09-17T04:56:48.018Z
---

`.loop\tools\Write-TaskList.ps1` (speedmerchants board) is LF-only. Filing a row with `[IO.File]::WriteAllLines` rewrote it CRLF; `Set-BoardStatus` (myloop `RowCommon.ps1:924`) matches tuples with `(?m)...[^\r\n]*$`, so it found 0 tuples and three `Close-Row.ps1` runs threw after record + started.json + actuals, before the board line and `close-committed`.

`Reconcile-Rows -Repair` does NOT repair that shape: its close repair keys on a live `dispatched.json` entry, which the board close had already cleared. Finish with RowCommon's own `Set-BoardStatus` + `Add-LoopJournal 'close-committed'`, status built as `Close-Row.ps1:136-139` builds it.

**Second shape (9/17 00:51):** row text is a single-quoted PowerShell string, so an apostrophe typed inside it ("shell's", `'hardware'`) breaks the parse. `Dispatch-Row` then committed the row record (epoch 25) and threw before writing the prompt file or `dispatch-committed`. Recovery: double the quotes, `Reconcile-Rows -MarkLost <key> -Epoch <n>`, re-dispatch.

**How to apply:** every apostrophe in row text is `''`. After ANY board edit run `[System.Management.Automation.Language.Parser]::ParseFile(<board>, [ref]$null, [ref]$e)` and require 0 errors before dispatching or closing. Edit the board with Edit, or ReadAllText/Replace/WriteAllText; after any board edit check `[Text.Encoding]::UTF8.GetString(bytes).Contains("`r")` is False and the schedule task count moved by the rows added. Related: [[reference_write_tasklist_row_silently_dropped]], [[reference_schedule_json_is_the_backup]].
