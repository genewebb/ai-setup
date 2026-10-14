---
name: reference-powershell-switch-param-shadows-local-var
description: "PowerShell variable names are case-insensitive, so a new [switch] $Json parameter silently becomes the loop-local $json and poisons every assignment to it"
metadata: 
  node_type: memory
  type: reference
  originSessionId: aa701f44-5fa5-4edf-ae81-2fc43ee32e4c
  modified: 2026-09-12T10:52:18.582Z
---

Adding a `[switch] $Json` parameter to a script that already used a loop-local `$json` made the two
**the same variable** — PowerShell variable names are case-insensitive. Measured 2026-09-12 in
`.loop\tools\Get-StaleReceipts.ps1` (speedmerchants).

The failure is silent and total:

1. `$json = $receipt | ConvertFrom-Json` now assigns an object to a `[switch]`-typed variable, which
   **throws**.
2. The throw landed in an existing `catch { $unparseable += ... }`.
3. **All 42 receipts were reclassified "not valid JSON"** and silently dropped to the weakest rule.
4. The new `-Json` switch itself produced **empty stdout and exit 1 with nothing on stderr**.

No grader caught it. It was found by diffing the tool's printed table against a capture taken before
the change.

**How to apply:** when adding a parameter to an existing script, grep the body for that name in ANY
casing before naming it. A parameter is just a variable, and a typed one poisons every later
assignment. Suspect this whenever a change makes a whole population fall to a fallback branch at
once, or when a `catch` block that used to be rare starts swallowing everything — the type error
looks like a data error from inside the catch.

Related: [[reference_backslash_escapes_become_control_bytes]] — same family, a change that alters
bytes/semantics invisibly and is only findable by comparing against a known-good capture.
