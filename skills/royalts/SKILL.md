---
name: royalts
description: >
  Royal TS (Windows, V7) connection documents built, extended and inspected from PowerShell with the
  official RoyalDocument.PowerShell module: SSH terminals, credentials with key files, SSH Secure
  Gateways, RDP tunnelled through SSH to a Linux desktop (xrdp), and adding entries to an existing
  document (including the automatic entry for every new Proxmox container). Use when creating or
  fixing a Royal TS connection or .rtsz document, adding a host to an existing document, when Royal TS
  keeps asking for "a complete set of credentials", says access to the private key is denied, or an
  RDP-over-SSH (Secure Gateway) connection will not connect.
---

# Royal TS

## Ground rules

- **Never open Gene's existing documents** (`Connections (Gene Webb).rtsz`, `Connections (QA Automation).rtsz`).
  They hold stored credentials for every host. Create a NEW document; Gene opens it in Royal TS
  (File > Open) and adds passwords himself. Scripts here never write or print a password.
- **On the work laptop Royal TS runs as `CORP\genewe`**, not `CORP\agenewe` (the account Claude runs as). Any
  key file Royal TS uses must be readable by `genewe`. On a personal machine both run as the same user. Check
  the owner, never assume:
  ```powershell
  Get-CimInstance Win32_Process -Filter "Name='RoyalTS.exe'" | Invoke-CimMethod -MethodName GetOwner
  ```
- Windows OpenSSH (`ssh.exe` as agenewe) REJECTS a key another account can read ("UNPROTECTED PRIVATE KEY
  FILE"). So keep two copies: `~\.ssh\<key>` locked to agenewe for ssh.exe, and `{SecretsDir}\<name>\<key>`
  with `CORP\genewe:(R)` for Royal TS. Not on D: (NAS share; NTFS ACLs do not apply there).
- Find where the documents live from Royal TS's own recent-documents list (do not hard-code a drive):
  ```powershell
  Select-String -Path "$env:APPDATA\code4ward\code4ward.RoyalTS.UserPreferences.config" -Pattern '[A-Za-z]:\\[^"<|}]*\.rtsz' -AllMatches |
      ForEach-Object { $_.Matches.Value } | Sort-Object -Unique
  ```

## Quick start

```powershell
Install-Module RoyalDocument.PowerShell -Scope CurrentUser -Repository PSGallery   # once; official, Royal Apps GmbH
& "{ClaudeHome}\skills\royalts\scripts\New-RoyalSshTunnelDocument.ps1" -Path '<docs dir>\Linux Droplet.rtsz' `
    -HostAddress 138.68.42.81 -User gene -KeyFile '{SecretsDir}\do_droplet\do_droplet_ed25519' -Rdp -Name Droplet
& "{ClaudeHome}\skills\royalts\scripts\Show-RoyalDocument.ps1" -Path '<docs dir>\Linux Droplet.rtsz'
```

`New-RoyalSshTunnelDocument.ps1` refuses to overwrite. It creates: key credential, SSH terminal, and with
`-Rdp` a username-only desktop credential, an SSH Secure Gateway and an RDP connection to `127.0.0.1`
through it. `Show-RoyalDocument.ps1` prints hosts, ports, modes, key paths and which object each link
points to (`MISSING <id>` = broken link); a password is shown only as `hasPassword` Yes or No.

## Add entries to an existing document

Documents the owner created for Claude to maintain (the home-appliance documents "Home AI Linux" and
"Home AI Windows") may be opened and extended. The shared helpers live in `{ClaudeHome}\scripts\lib\RoyalTs.ps1`
and use the module, never hand-written XML:

```powershell
. "{ClaudeHome}\scripts\lib\RoyalTs.ps1"
Add-RoyalTsKeyCredential -DocumentPath $doc -Name 'HomeAI guest key (root)' -UserName root -PrivateKeyPath '<key file>'
Add-RoyalTsSshConnection -DocumentPath $doc -Name trading-db -Uri 192.168.8.220 -Description 'Proxmox LXC 200' -CredentialName 'HomeAI guest key (root)'
```

Both are idempotent (same Name or URI = nothing added, existing ID returned) and write a `.bak-<stamp>` beside
the document first. CLI twin: `{ClaudeHome}\scripts\Add-RoyalTsSshLink.ps1 -Name <host> -Uri <ip>`; it defaults to
the document in profile key `RoyalTsHomeAILinux` and the credential above.

Automatic: the PostToolUse hook `royalts-container-link` runs after `mcp__proxmox__create_container` and adds the
SSH entry (static IP from the call, else the hostname). Containers created outside that tool need the CLI.

Verify with `Show-RoyalDocument.ps1`; `cred=MISSING <id>` means a broken credential link. If Royal TS is running
with the document open, tell the owner to reload it (File > Open) before saving anything there, or the next save
in Royal TS discards the change.

## Duplicate object IDs across documents

**Never make a document by copying another .rtsz.** The copy keeps every object ID, and Royal TS then shows
"Duplicate Objects ... already exists in one of the documents" on load. Build new documents with
`New-RoyalObject` (fresh IDs) or the scripts above.

Check and repair (report only without `-Fix`; prints IDs, types and names, never credential fields):
```powershell
& "{ClaudeHome}\skills\royalts\scripts\Repair-RoyalDuplicateIds.ps1" -Directory '<docs dir>'
& "{ClaudeHome}\skills\royalts\scripts\Repair-RoyalDuplicateIds.ps1" -Directory '<docs dir>' -Fix -KeepDocument '<original doc name>'
```
`-Fix` refuses while RoyalTS.exe runs. It replaces each clashing ID as text across the whole copy, so its internal
links follow and encrypted fields stay byte-identical; backup `.bak-dupids-<stamp>` beside each changed file.

## RDP to a Linux desktop through SSH

The host firewall allows only SSH, so RDP must ride an SSH tunnel. In Royal TS that is a Secure Gateway:

| Object | Setting |
|---|---|
| Secure Gateway | host = Linux public IP, port 22, credential = key credential (user `gene`, key file) |
| RDP connection | computer `127.0.0.1`, port 3389, Secure Gateway usage **Always**, that gateway |
| RDP credential | `gene` + desktop password (xrdp uses PAM, so the password is required) |

`127.0.0.1` is resolved on the gateway side, so it means the Linux host itself.

## Diagnose from the Linux side

Royal TS errors are vague; the server log is exact. On the host (e.g. via `addLinux`):
```bash
journalctl -u ssh --since "-10 min" --no-pager | grep <your public IP>
journalctl -u xrdp -u xrdp-sesman --since "-10 min" --no-pager | tail -30
```

| Log line | Meaning | Fix |
|---|---|---|
| `Invalid user genewe from <ip>` | Royal TS sent the Windows username | Set the username explicitly on the credential/connection |
| `banner exchange: ... invalid format` | RDP traffic hit port 22 directly | RDP connection must use the Secure Gateway, port 3389 |
| no line at all from your IP | never reached the host | key not readable by genewe ("access denied"), wrong host |
| `Accepted publickey for gene` then xrdp `login successful` | tunnel + login fine | desktop-side problem (session, RAM) |

Dialog "needs a complete set of credentials" reappearing = the attempt failed; read the log above.

## Reference

Verified property names and numeric mode values: [REFERENCE.md](REFERENCE.md).
