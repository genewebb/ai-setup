---
name: reference-pwsh-sshkeygen-empty-passphrase
description: "ssh-keygen -N '\"\"' in pwsh 7 sets a literal \"\" passphrase; key then fails BatchMode auth even though server \"accepts key\""
metadata:
  node_type: memory
  type: reference
  originSessionId: 70e0e446-378b-4cf7-8669-a34150c63598
  modified: 2026-10-27T00:33:30.354Z
---

In PowerShell 7 (native arg passing), `ssh-keygen -N '""'` passes the two quote characters as the passphrase. Symptom: `ssh -v` shows "Server accepts key" then "No more authentication methods" / Permission denied under `-o BatchMode=yes`.

Fix: create keys from the Bash tool (`-N ''`), or repair with `ssh-keygen -p -f <key> -P '""' -N ''` (Bash).

Seen 2026-10-26 making `~\.ssh\pve_home_ed25519` for [[project-home-lab-gmktec-evo-x1]].
