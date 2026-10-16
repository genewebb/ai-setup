---
name: reference-q-drive-psdrive-dotnet-blind
description: "In Claude's PowerShell tool, Q:\\ works for cmdlets (Get-FileHash, Get-Content) but .NET [IO.File] says 'Could not find file': never read-modify-write vault files with [IO.File]; always $ErrorActionPreference='Stop' before any overwrite"
metadata:
  node_type: memory
  type: reference
  originSessionId: f0454aab-598a-49d1-b5bc-df925330f846
  modified: 2026-10-15T00:24:24.048Z
---

2026-10-14: adding a banner to two vault docs (Q:\Work\Work\99_Frequent\HowToInstall.md, My AI Sync.md) with
`[IO.File]::ReadAllBytes('Q:\...')` threw "Could not find file", the script did not stop (default
ErrorActionPreference), and Write-AIFile then OVERWROTE both docs with the banner only. Restored byte-exact from the
session transcript JSONL (tool_result text; sizes matched the earlier `wc -c`).

- In the PowerShell tool, Q: is visible to PowerShell providers (Get-FileHash, Get-Content, Get-ChildItem) but not
  to .NET file APIs (likely a PowerShell-only drive mapping in that process). Git Bash sees `Q:/` fine.
- Read vault files with `Get-Content -Raw -LiteralPath` or Bash `cat`; never `[IO.File]` on Q:.
- Any read-modify-write: `$ErrorActionPreference = 'Stop'`, and check the read content is non-empty before writing.
- Write-AIFile vault writes go through the Obsidian API: there is no recycle-bin copy of an overwrite
  (Q:\#recycle only gets deletes). The session transcript is the recovery source.

Related: [[reference-write-aifile-replaces-write-vaultfile]].
