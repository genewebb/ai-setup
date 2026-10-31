---
name: reference_sed_inplace_strips_crlf_on_d_drive
description: Git Bash `sed -i` on D:\PowershellScripts (NAS) silently strips CRs from many CRLF lines; edit those files with the Edit tool
metadata:
  type: reference
---

`sed -i` from the Git Bash tool on `D:\PowershellScripts\CrewChiefConnect\New-ConnectWorkloads.ps1` (CRLF, D: = NAS) changed one line but shrank the file ~1.1 KB: CRs dropped on many lines (diff showed ~2,400 changed lines). Seen twice (10/15 and 10/30).

**How to apply:** for CRLF files on D: use the Edit tool, never `sed -i`. Back up first; after any shell edit compare size + `diff | wc -l` against the backup. Related: [[reference_profile_load_nas_clearseq]].
