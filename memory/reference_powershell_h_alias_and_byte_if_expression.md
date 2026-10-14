---
name: reference-powershell-h-alias-and-byte-if-expression
description: "PowerShell traps hit 9/30-10/1 - helper named H collides with Get-History alias; untyped if-expression turns byte[] into object[] (REST body sent as decimal text); an if returning @() yields $null"
metadata:
  node_type: memory
  type: reference
  originSessionId: e071532a-95ca-4f16-ae81-7a5cb0301769
  modified: 2026-10-01T12:54:34.347Z
---

- `h` is a built-in alias for Get-History, and an alias wins over a function. Never name a helper `H`.
- `$b = if (...) { [IO.File]::ReadAllBytes($p) }` enumerates into `object[]`, so Invoke-RestMethod sends "72 101 ..." as text. Write `[byte[]]$b = if ...` instead.
- `$x = if (...) { @() }` gives `$null`. Wrap the whole thing: `@(if ...)`.
- A function returning `,@(...)` must be flattened by the caller (`| ForEach-Object { $_ }`).
- StrictMode: a missing property throws. Probe it with `.PSObject.Properties['X']`.
- A thread job blocked in `TcpListener.AcceptTcpClient()` cannot be stopped. Poll `Pending()` against a stop flag held in a synchronized hashtable.

Related: [[reference-powershell-single-pair-array-flattens]].
