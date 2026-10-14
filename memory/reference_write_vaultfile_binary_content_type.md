---
name: reference-write-vaultfile-binary-content-type
description: "Obsidian REST API text-decodes any text/* PUT body, corrupting PNGs; Write-VaultFile.ps1 now sends image/png / octet-stream for binaries (fixed 2026-09-26, hash-verified)"
metadata:
  node_type: memory
  type: reference
  originSessionId: 1c475457-1e54-4237-a0cd-5cdd61ea1bc1
  modified: 2026-09-27T03:23:37.187Z
---

Obsidian Local REST API PUT /vault/<path> with a `text/*` Content-Type decodes the body as text: non-UTF-8 bytes become EF BF BD (PNG 71,260 B grew to 126,156 B). Sent as `image/png` the bytes land exactly (SHA-256 matched draft).

`C:\Users\agenewe\.claude\skills\myloop\scripts\Write-VaultFile.ps1` maps .png→image/png, .jpg→image/jpeg, gif/webp/mp4/pdf/zip/woff→application/octet-stream. Any other copy of that script (vault tooling, other skills) with the old text/markdown default still corrupts binaries — check before putting images.

Always verify a binary vault write by hashing the Q: file after the put. Related: [[reference-obsidian-smb-vault-watcher-blind]], [[reference-write-vaultfile-large-put-times-out]].
