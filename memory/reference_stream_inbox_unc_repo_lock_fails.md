---
name: reference-stream-inbox-unc-repo-lock-fails
description: "Send-InboxItem.ps1 with a UNC -Repo (\\\\SMVMTR1\\d$\\...) always fails \"inbox lock busy for 15s\"; map a drive letter first"
metadata:
  node_type: memory
  type: reference
  originSessionId: afae390a-5c8d-4b78-91ac-028a93fcf051
  modified: 2026-10-21T23:55:01.803Z
---

Filing onto the live SMVMTR1 board from the laptop (2026-10-21): `Send-InboxItem.ps1 -Repo '\\SMVMTR1\d$\devops\repos\speedmerchants'` threw `inbox lock busy for 15s` with NO lock file present. The resolved path carries the `Microsoft.PowerShell.Core\FileSystem::` prefix, which `[IO.File]::Open` in `lib\Inbox.ps1` Invoke-InboxLocked cannot open, so every try fails as if busy.

**How to apply:** `net use W: \\SMVMTR1\d$ /persistent:no`, run the script with `-Repo W:\devops\repos\speedmerchants`, then `net use W: /delete /y`. Live board path on SMVMTR1 = `D:\devops\repos\speedmerchants\.streams` (laptop's `.streams` is a stale copy). Same family as [[reference-q-drive-psdrive-dotnet-blind]]. Not yet filed as a stream-kit bug.
