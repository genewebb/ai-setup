---
name: reference-tracker-concurrent-sessions-check-output-exists
description: Finish-tracker /goal sessions sometimes run twice at once; check the output path and tracker row before any vault write
metadata:
  node_type: memory
  type: reference
  originSessionId: 22613bcb-330c-46ee-82bf-d275bf2bff73
  modified: 2026-09-25T11:57:23.598Z
---

Twice on 2026-09-24, two `/goal REQUIREMENTS-FINISH-TRACKER` sessions ran the same row at the same time (P0-1, then A2r). In A2r the second session wrote its report to the same vault path and overwrote the first session's recorded report. It was restored from the other session's scratchpad (`%TEMP%\claude\<project-slug>\<session>\scratchpad\`, found by searching for the SHA-256 recorded in the tracker).

**How to apply:** before writing any row output through Write-VaultFile.ps1, check (1) whether the target file already exists and (2) whether the vault tracker changed since you read it. If either is true, save under a distinct name (e.g. `-second-session`) and log it in the tracker; never overwrite.

**Check at the start too, not only before writing.** On 2026-09-25, A5 ran twice (sessions started in speedmerchants and in myworkspace). The vault output did not exist yet, but the other session's `%TEMP%\claude\*\*\scratchpad\<row>\` folder had files modified within the last few minutes. Worse, it had put Q-TRIP-WIRES-004 to Gene again and got a different cadence from the one the tracker recorded. At row start, look for fresh `scratchpad\<row-id-lowercase>\` folders under the other project slugs (list only the top-level dirs; a recursive `*.py` search of `%TEMP%\claude` times out), and run ListAgents. If one is active, ask Gene which session continues and write nothing. Related: [[reference-obsidian-smb-vault-watcher-blind]].
