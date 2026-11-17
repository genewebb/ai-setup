---
name: reference-home-proxmox-unreachable-from-office
description: Home Proxmox box (192.168.8.210) cannot be reached from the office laptop; its files must come from Gene at home
metadata:
  node_type: memory
  type: reference
  originSessionId: 1fff7e8f-2a59-46f9-803d-464e8cfcf58c
  modified: 2026-11-16T20:23:25.999Z
---

The home Proxmox box (192.168.8.210, key `~\.ssh\pve_home_ed25519`) is NOT reachable from the work laptop at the office (Gene 2026-11-16; ssh timed out). Do not try; ask Gene to copy what is needed when home, or rebuild it.

Its host customisations (repos, `/usr/local/bin/pve-nonag.sh` + `/etc/apt/apt.conf.d/99-pve-nonag`, ZFS cap) are listed in vault `99 Documentation\homeai\HomeAI - Access.md` section "Host customisations"; script contents are not in the vault. Related: [[project-corpsql03-proxmox-conversion-2026-11-09]].
