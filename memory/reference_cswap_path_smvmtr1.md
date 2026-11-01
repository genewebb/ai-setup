---
name: cswap-path-smvmtr1
description: "cswap (Claude account switcher) lives in ~\\.local\\bin; on SMVMTR1 that is C:\\Users\\speedmerchants\\.local\\bin, added to User PATH 2026-09-29"
metadata:
  node_type: memory
  type: reference
  originSessionId: c296038e-86c2-4f5b-a1d9-4a0e86eb9d7a
  modified: 2026-09-29T16:15:50.493Z
---

`cswap.exe` (e.g. `cswap switch gene.webb@live.com`) installs to `~\.local\bin`, which is NOT on PATH by default.

- Laptop CorpLTR94: `C:\Users\agenewe\.local\bin\cswap.exe` (on PATH).
- SMVMTR1: `C:\Users\speedmerchants\.local\bin\cswap.exe`. Added to that user's **User** PATH via
  `[Environment]::SetEnvironmentVariable('Path', ..., 'User')` on 2026-09-29; Gene confirmed fixed.
  Registry-scoped, so it does not travel with the shared pwsh profile — repeat on SMVMTR2 if needed.
- DADPC: `C:\Users\Gene\.local\bin\cswap.exe`. PATH was already fine; the tool simply was not installed.
  Fixed 2026-11-01 by Gene running `uv tool install claude-swap` (v0.29.0). The auto-mode classifier
  blocks Claude from running that install, so on a new machine hand Gene the command.
- First check on any machine where "cswap not found": `uv tool list` — empty means install, not PATH.

Related: [[claude-account-switching]], [[stream-host-smvmtr1]], [[profile-machine-config]].
