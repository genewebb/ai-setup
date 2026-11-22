---
name: reference_kit_stage_wiped_by_watchdog_sweep
description: "Kit stages under D:\\tmp\\streams\\<repo>\\kit-*-stage get deleted by Invoke-Watchdog's scratch sweep; Copy-Item keeps old mtimes so a fresh copy reads stale"
metadata:
  node_type: memory
  type: reference
  originSessionId: 49da5f78-d98f-4cc2-a1dd-4c48eb8cd675
  modified: 2026-10-03T17:59:11.736Z
---

Invoke-Watchdog's stream scratch sweep judges a folder under `D:\tmp\streams\<repo>` by the newest FILE write time inside it. `Copy-Item` keeps the source files' write times, so a stage copied from the live kit (files days old) reads as stale and is deleted, even mid-copy. Lost the whole 9384 stage overnight 2026-10-02/03 (logs survived, dirs gone); coordinator lost kit-a58c-stage the same way 2026-10-03 17:18Z. Kit item IN-20261003174116-0300 tracks the fix.

**Until fixed:** after staging, write a `.keep` file and touch every copied file (`(Get-ChildItem -Recurse -File) | % { $_.LastWriteTimeUtc = [datetime]::UtcNow }`), and publish the same session; never leave a stage overnight.

**Recovery:** rebuild from the session transcript jsonl: extract Edit `old_string`/`new_string` inputs on the stage path plus the PowerShell commands that edited files, replay in order on a fresh copy of live (normalize LF to CRLF; strip test-run tails). Some Edit replays miss on whitespace; redo those with the Edit tool. Related: [[reference_stream_mockup_deliverables_lost_from_tmp]], [[reference_kit_corpus_vs_live_divergence]].
