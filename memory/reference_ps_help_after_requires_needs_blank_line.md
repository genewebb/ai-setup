---
name: reference-ps-help-after-requires-needs-blank-line
description: "A comment-help block directly under `#Requires` is invisible to ScriptBlockAst.GetHelpContent(); a blank line between them fixes it"
metadata:
  node_type: memory
  type: reference
  originSessionId: 82f13339-3769-4200-8135-0a63b88a6897
  modified: 2026-10-01T20:49:37.470Z
---

In pwsh 7, `[Management.Automation.Language.Parser]::ParseFile(...).GetHelpContent()` returns empty Synopsis and
Description when the `<# .SYNOPSIS ... #>` block sits on the line directly after `#Requires -Version 7.0`. The two
comments are adjacent, so the parser does not see the block as help. One blank line between them makes it work.
Putting the help block above `#Requires` also works, but then the `#Requires` text leaks into the Synopsis.

Measured 2026-10-01 on G3.T015. Grader clause C13 read the help of `scripts/e2e/Invoke-PublishPathPortProof.ps1`
and `Invoke-SealedCentralConnectionProof.ps1` through GetHelpContent, and both scripts on main had this shape. The help
text was correct and the clause still failed until the blank line was added.

**How to apply:** when a grader or tool reads script help through the AST and finds nothing, check the first two lines
before rewriting the help. Related: [[reference-grader-line-anchor-unreachable-in-crlf]].
