---
name: project-travel-kit-nas-sync-2026-11-23
description: "C:\\Travel kit for working away from SynologyDS918 - baseline 3-way Sync-Travel.ps1, drive-letter switcher (both shells), MapSyn both-shells, prof travel / prof nas groups (branch work/travel-nas-prof, uncommitted)"
metadata:
  node_type: memory
  type: project
  originSessionId: c6d7c6c1-f76a-499d-859b-02a827d248cf
  modified: 2026-11-23T17:18:02.748Z
---

Built 2026-11-23 on CORPLTR94 for Gene's trips (NAS hard to reach on the road).

- `C:\Travel\Sync-Travel.ps1` engine (pwsh 7): drives D=devopslocal, O=OneDriveArchive, Q=obsidian, checklists DriveX-Folders.md. Baseline `C:\Travel\.sync\DriveX.baseline.csv` written only on -Apply. ToTravel: PULL/DEL-LOCAL/DEL-FOLDER, unsynced local edits = CONFLICT. ToNas: PUSH/DEL-NAS (only if NAS unchanged since baseline), both-changed = CONFLICT, NAS-CHANGED info. Abort drive on listing error, cap NAS deletes 50. Q skips .obsidian\workspace*.json. Plans in C:\Travel\logs\Sync-*.csv.
- Launchers Sync-NasToTravel.ps1 / Sync-TravelToNas.ps1; Use-TravelDrives.ps1 Travel|Home|Status (subst vs MapSyn). All scripts have -Help. Old CopyDrive*.ps1 kept (Gene did not pick retire), help marks them superseded.
- Decisions (Gene): baseline 3-way; delete on NAS only if NAS unchanged; Containers (258 GB Docker vhdx) unchecked - Docker actually uses C:\devopslocal\Containers; Q checklist with junk `c` folder unchecked; drive maps must cover admin AND normal shells.
- Both shells: from a normal shell the script reruns itself elevated via `Start-Process -Verb RunAs` (UAC) and prints the child's transcript; from admin it tells Gene to rerun in a normal shell. Admin->normal hop via scheduled task was blocked by the auto-mode classifier - don't retry it without Gene's OK. The UAC hop itself is not yet tested end to end (needs a normal shell + UAC click).
- `C:\Deploy\Scripts\MapSyn.ps1` changed: -ThisShellOnly, -Help, skips subst letters; backup MapSyn.ps1.bak-20261123.
- prof: NasGroup.ps1 (status/map/credential) + TravelGroup.ps1 (status/to-laptop/away/to-nas/home/folders) in ai-setup Gene.Profile, branch `work/travel-nas-prof`, not committed or reloaded at write time.
- **Why:** HowTo.txt's old claim "NAS does not change while away" was false (94 vault files changed on the NAS 11/22-23), so plain local-to-NAS mirroring would lose work.
- **How to apply:** for any travel/NAS sync question, use `prof travel ...` / `prof nas ...`. Rollout follows [[feedback_ai_setup_rollout_via_prof]] and [[project_ai_setup_branch_workflow_2026-10-18]]. Stale letters: see [[reference_nas_drive_letters_stale_after_reboot]].
