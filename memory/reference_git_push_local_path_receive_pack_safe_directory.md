---
name: reference_git_push_local_path_receive_pack_safe_directory
description: git push to a folder/UNC path owned by another account fails "dubious ownership" even with -c safe.directory=*; pass --receive-pack="git -c 'safe.directory=*' receive-pack"
metadata:
  type: reference
---

`git -c safe.directory=* push //SMVMTR1/D$/devops/repos/ai-setup ...` from CORP\agenewe into genewe's clone fails: `fatal: detected dubious ownership ... Could not read from remote repository`. The local transport spawns its own `receive-pack` and does not pass the caller's `-c` config (fetch/upload-pack in the same direction worked). Fix, verified 2026-10-17 by dry run: `git push "--receive-pack=git -c 'safe.directory=*' receive-pack" <path> <refspec>` (the string runs through sh, the single quotes stop `*` globbing). Applied in prof's `Invoke-GenePushToTarget` (Gene.Profile\Sync.ps1). See [[project_manageprofile_hub_2026-10-17]].
