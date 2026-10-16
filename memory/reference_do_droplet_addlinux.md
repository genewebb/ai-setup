---
name: reference_do_droplet_addlinux
description: DigitalOcean Ubuntu 24.04 droplet 159.223.100.95; pwsh profile command addLinux SSHes in as root with passphrase-less ~\.ssh\do_droplet_ed25519 (WORKING 10/16)
metadata:
  node_type: memory
  type: reference
  originSessionId: b21df145-c9d9-425f-b5a8-72fa291dfd0f
  modified: 2026-10-16T17:14:50.066Z
---

2026-10-16: Gene's learning box = DigitalOcean Ubuntu 24.04.5 LTS droplet `ubuntu-s-1vcpu-512mb-10gb-nyc1`, public IP 159.223.100.95. Verified login works.

- Profile function `addLinux` (laptop pwsh profile, after `psql`): `ssh -i ~\.ssh\do_droplet_ed25519 -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new root@159.223.100.95 [cmd]`; params -User/-HostAddress/-KeyFile; `PositionalBinding=$false` so a trailing string is the remote command, not -User. Claude can run `addLinux '<cmd>'` non-interactively.
- Dedicated key `do_droplet_ed25519` (no passphrase, Gene's choice: learning box), ACL inheritance removed, explicit CORP\agenewe + SYSTEM + Administrators only.
- Why the first attempt failed: `~\.ssh` folder grants CORP\genewe access by inheritance, so Windows OpenSSH rejects any key there ("UNPROTECTED PRIVATE KEY FILE") until ACL is locked; old `id_ed25519` is also passphrase-protected (BatchMode cannot use it). `D:\repos\Linux\mysshKey.txt` is only a public key.
- Desktop (10/16): XFCE + xrdp installed, default target multi-user (no local display manager), `/home/gene/.xsession` = xfce4-session, 2 GB `/swapfile` in fstab. User `gene` (uid 1000, sudo, same key; password set by Gene himself). ufw ACTIVE: only OpenSSH allowed, so xrdp 3389 is reachable ONLY via SSH tunnel (verified: direct 3389 blocked, tunnel gets RDP TPKT reply). `addLinux -Desktop` = hidden `ssh -N -L 13389:localhost:3389` + mstsc localhost:13389. Royal TS RUNS AS CORP\genewe (not agenewe), so it uses a second copy `C:\Deploy\Secrets\do_droplet\do_droplet_ed25519` (genewe R; agenewe's ~\.ssh copy must stay genewe-free or OpenSSH rejects it; D: is a NAS share, ACLs don't apply there). Droplet sshd: passwordauthentication no. Royal TS = Secure Gateway (SSH 22, key credential) + RDP localhost:3389. Gene chose resize to 2 GB RAM (CPU/RAM only).
- Royal TS doc `D:\RemoteDesktops\Linux Droplet.rtsz` (10/16, built with RoyalDocument.PowerShell): key credential, SSH gateway, Linux Terminal, Linux Desktop (RDP 127.0.0.1:3389 via gateway); desktop credential has username only, Gene adds the password. Gene CONFIRMED Terminal + Desktop both work in Royal TS (10/16), so the 127.0.0.1-through-Secure-Gateway recipe is proven. Everything Royal TS = skill `royalts` (skills\royalts in ai-setup: scripts New-RoyalSshTunnelDocument.ps1 / Show-RoyalDocument.ps1). addLinux also lives in the repo profile `pwsh\PowerShell\Microsoft.PowerShell_profile.ps1` (installed copy is overwritten from it).
- DO web Droplet Console injects literal bracketed-paste markers (`^[[200~` ... `~`) even after `bind 'set enable-bracketed-paste off'`. Workaround: paste commands as `true; <cmd> #` so the junk hits a throwaway word and a comment.
