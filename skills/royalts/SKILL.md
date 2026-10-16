---
name: royalts
description: >
  Royal TS (Windows, V7) connection documents built and inspected from PowerShell with the official
  RoyalDocument.PowerShell module: SSH terminals, credentials with key files, SSH Secure Gateways, and
  RDP tunnelled through SSH to a Linux desktop (xrdp). Use when creating or fixing a Royal TS
  connection or .rtsz document, when Royal TS keeps asking for "a complete set of credentials", says
  access to the private key is denied, or an RDP-over-SSH (Secure Gateway) connection will not connect.
---

# Royal TS

## Ground rules

- **Never open Gene's existing documents** (`Connections (Gene Webb).rtsz`, `Connections (QA Automation).rtsz`).
  They hold stored credentials for every host. Create a NEW document; Gene opens it in Royal TS
  (File > Open) and adds passwords himself. Scripts here never write or print a password.
- **Royal TS runs as `CORP\genewe`**, not `CORP\agenewe` (the account Claude runs as). Any key file Royal TS
  uses must be readable by `genewe`. Check the owner, never assume:
  ```powershell
  Get-CimInstance Win32_Process -Filter "Name='RoyalTS.exe'" | Invoke-CimMethod -MethodName GetOwner
  ```
- Windows OpenSSH (`ssh.exe` as agenewe) REJECTS a key another account can read ("UNPROTECTED PRIVATE KEY
  FILE"). So keep two copies: `~\.ssh\<key>` locked to agenewe for ssh.exe, and `{SecretsDir}\<name>\<key>`
  with `CORP\genewe:(R)` for Royal TS. Not on D: (NAS share; NTFS ACLs do not apply there).
- Find where the documents live from Royal TS's own recent-documents list (do not hard-code a drive):
  ```powershell
  Select-String -Path 'C:\Users\genewe\AppData\Roaming\code4ward\code4ward.RoyalTS.UserPreferences.config' -Pattern '[A-Za-z]:\\[^"<|}]*\.rtsz' -AllMatches |
      ForEach-Object { $_.Matches.Value } | Sort-Object -Unique
  ```

## Quick start

```powershell
Install-Module RoyalDocument.PowerShell -Scope CurrentUser -Repository PSGallery   # once; official, Royal Apps GmbH
& "{ClaudeHome}\skills\royalts\scripts\New-RoyalSshTunnelDocument.ps1" -Path '<docs dir>\Linux Droplet.rtsz' `
    -HostAddress 159.223.100.95 -User gene -KeyFile '{SecretsDir}\do_droplet\do_droplet_ed25519' -Rdp -Name Droplet
& "{ClaudeHome}\skills\royalts\scripts\Show-RoyalDocument.ps1" -Path '<docs dir>\Linux Droplet.rtsz'
```

`New-RoyalSshTunnelDocument.ps1` refuses to overwrite. It creates: key credential, SSH terminal, and with
`-Rdp` a username-only desktop credential, an SSH Secure Gateway and an RDP connection to `127.0.0.1`
through it. `Show-RoyalDocument.ps1` prints hosts, ports, modes, key paths and which object each link
points to (`MISSING <id>` = broken link); passwords appear only as `hasPassword=Yes/No`.

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
