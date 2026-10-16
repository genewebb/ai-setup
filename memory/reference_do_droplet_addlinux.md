---
name: reference_do_droplet_addlinux
description: "DigitalOcean Ubuntu 24.04 droplet 138.68.42.81 (SFO2, 2 GB) since 10/16; pwsh `addLinux` SSHes in with passphrase-less ~\\.ssh\\do_droplet_ed25519; XFCE+xrdp desktop via SSH tunnel; Royal TS doc Linux Droplet.rtsz"
metadata:
  node_type: memory
  type: reference
  originSessionId: b21df145-c9d9-425f-b5a8-72fa291dfd0f
  modified: 2026-10-16T18:54:09.994Z
---

Gene's Linux learning box = DigitalOcean droplet `ubuntu-genewebb-1vcpu-2gb-sfo2`, **138.68.42.81**, SFO2, Ubuntu 24.04.5, $12 plan (1 vCPU / 2 GB). Recreated 10/16: the first droplet (159.223.100.95, NYC1, 512 MB) could not be resized because NYC1 had no capacity for larger plans (plans greyed out; SFO2 was the only region offering the plan). That IP is gone.

- Rebuild = `D:\repos\Linux\setup-droplet.sh` (idempotent, run as root): 2 GB swap, sudo user `gene` with the same key, apt upgrade, XFCE + xrdp, multi-user target, ufw = OpenSSH only. Then Gene runs `passwd gene` himself. Also installs fail2ban (fixed jail), NOPASSWD sudo for gene, and disables root SSH last. Fresh droplet: scp to root, `addLinux -User root 'HOME_IP=<ip> bash /root/setup-droplet.sh'`.
- When creating a droplet, the DO account must have key `agenewe-do-droplet` (MD5 d4:20:c2:78...) ticked. DO key "Learning" = old `id_ed25519` (MD5 4d:f6:83:d1..., passphrase), so Claude cannot use it.
- `addLinux` (repo profile `pwsh\PowerShell\Microsoft.PowerShell_profile.ps1`, installed copy overwritten from it): `ssh -i ~\.ssh\do_droplet_ed25519 -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new root@<ip> [cmd]`; -User/-HostAddress/-KeyFile; `PositionalBinding=$false`; `-Desktop` = hidden `ssh -N -L 13389:localhost:3389` + mstsc localhost:13389.
- Key ACLs: `~\.ssh` grants CORP\genewe by inheritance, so Windows OpenSSH rejects keys there until the ACL is locked to agenewe/SYSTEM/Admins. Royal TS runs as CORP\genewe and uses the copy `C:\Deploy\Secrets\do_droplet\do_droplet_ed25519` (genewe R). D: is a NAS share, ACLs don't apply.
- Royal TS doc `D:\RemoteDesktops\Linux Droplet.rtsz`: key credential, SSH gateway, Linux Terminal, Linux Desktop (RDP 127.0.0.1:3389 via gateway). Gene confirmed Terminal + Desktop both work on the new droplet 10/16. Skill `royalts` covers building/inspecting/diagnosing.
- DO web Droplet Console injects literal bracketed-paste markers (`^[[200~` ... `~`) even with bracketed paste off; paste as `true; <cmd> #`.
- Hardened 10/16 (Gene's choices): root SSH login OFF (`/etc/ssh/sshd_config.d/00-no-root.conf`, 00- wins), password auth off, `gene` has NOPASSWD sudo (`/etc/sudoers.d/90-gene`) so Claude can still admin via `addLinux 'sudo ...'`; addLinux default user is now `gene`. No DO backups (Gene: not now). Only the laptop connects (no key copies to other machines).
- fail2ban sshd jail (`/etc/fail2ban/jail.local`): ignoreip includes Gene's home IP 174.85.188.248 (update if it changes), bantime 1h, mode aggressive. GOTCHA: Ubuntu 24.04 stock journalmatch is `_SYSTEMD_UNIT=sshd.service` but the unit is `ssh.service`, so the stock jail is silently blind; override `journalmatch = _SYSTEMD_UNIT=ssh.service + _COMM=sshd`. Normal mode ignores probe-and-drop bots ("Connection closed by authenticating user ... [preauth]" is F-NOFAIL); aggressive counts them. Verify with `fail2ban-regex <file> "sshd[mode=aggressive]"`.
