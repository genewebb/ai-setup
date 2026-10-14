---
name: ds918-nas-deployment
description: "Personal Synology DS918+ / Mountain Duck / OneDrive deployment — doc set, verified facts, decisions, plan location"
metadata: 
  node_type: memory
  type: project
  originSessionId: 748fcaea-7c89-4f73-b5d7-99008df2fed2
  modified: 2026-08-20T15:44:47.300Z
---

Personal (non-work) project in `MyPersonalVault\Technical\DS918\`. Four docs: Guide (75 §), Deployment Checklist (phases 0–12 + 4a/7a), Configuration_Values (authoritative — decisions D1–D13, §15 share-migration playbook), Implementation_Plan (created 2026-08-19: proper order + automation A1–A9 + manual steps + gates).

Verified 2026-08-19: DS918+ max DSM = **7.3.2-86009 Update 4** (7.4.x not offered); Mountain Duck 5.3.1 current; Tailscale DSM7 inbound works without TUN; SMB3 Multichannel ⊕ LACP mutually exclusive; Hyper Backup has NO OneDrive destination (Cloud Sync does); Win11 24H2 Pro requires SMB signing by default.

Key decided architecture: per-thing shares `devopslocal` + `OneDriveArchive` (single `Files` share retired, D6); NAS `SynologyDS918` @ 192.168.8.2; upload ceiling 22.86 Mb/s; OneDrive Personal ~550 GB of 1 TB (Business tenant out of scope, D11). Open decisions at plan time: D1 (admin split), D2 (LAN2), D4 (Cloud Sync encryption — recommend OFF).

**2026-08-20 revision — Mountain Duck DROPPED, mapped SMB drives adopted.** Mountain Duck rejected after flakiness (icon churn, orphaned Explorer sidebar bookmarks — shell-namespace jank). New model: direct SMB drive mappings to 192.168.8.2 (personal vault on `Q:`), same mapping carried by user's existing WireGuard tunnel when traveling. SUPERSEDES D7d/D8 "vaults stay local": user moved devopslocal AND Obsidian vaults onto mapped drives 2026-08-20. How-to doc: `Q:\Personal\MyPersonalVault\Technical\DS918\Mapped_Drive_Setup.md` (authored in C:\tmp, user copies). Drives (both accounts genewe+agenewe, deployed 8/20): D:=devopslocal, F:=Family, O:=OneDriveArchive, Q:=obsidian, V/Z=corpnas01. Hosts entry `192.168.8.2 SynologyDS918` + EnableLinkedConnections=1 + Credential Manager target `SynologyDS918` (user Gene) all verified. Claude's shell (non-elevated agenewe) sees the drives. 8/20 path migration: all live `C:\devopslocal` refs rewritten to `D:` in both PowerShell profiles, loaded Gene.GitTools module (Documents\PowerShell\Modules — the D:\ MyProfile copy is git backup only, diverged), and 9 scripts/configs in D:\powershellscripts (34 replacements). ImportArtifacts.ps1 paths (CLU\NETx\Profisee.MasterDataMaestro.Utilities, EncryptDecrypt) were already stale pre-move — exe actually at D:\EncryptDecrypt\Profisee.Platform.Utilities.Internal.EncryptDecrypt.exe. C:\devopslocal remnant: SnagitCaptures with one Snagit-locked file — Snagit still configured to save there; folder path deny-listed from Claude removal, user deletes after repointing Snagit.
