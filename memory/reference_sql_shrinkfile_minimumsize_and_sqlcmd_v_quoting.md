---
name: reference_sql_shrinkfile_minimumsize_and_sqlcmd_v_quoting
description: "SQL Server facts learned 2026-10-28 on CORPSQL03 - SHRINKFILE never goes below a file's creation size, proportional fill leaves ~64 MB holes per growth, log shrink lands on VLF boundaries, sqlcmd -v values with commas/colons need embedded double quotes, CORPSQL03 c$ and PS remoting denied from the laptop"
metadata:
  node_type: memory
  type: reference
  originSessionId: 159810d1-4d6d-45ae-9499-11e3880c4774
  modified: 2026-10-28T18:07:47.193Z
---

Verified on CORPSQL03 (SQL 2022 Developer) 2026-10-28:

- `DBCC SHRINKFILE (f, TRUNCATEONLY)` stops at `MinimumSize` = the size the file was CREATED with (or last set by MODIFY FILE). A file pre-sized too big can never be trimmed below that without page movement. Size files from real used pages + small margin instead of generous estimates.
- Proportional fill: the first ~8192 page allocations (64 MB) after a create or growth go to one file before the weights recalculate, leaving ~64 MB holes in the other files per growth event. Negligible on big loads, large relative to a 150 MB file. Autogrow-from-tiny therefore makes small DBs WORSE.
- Log shrink lands on a VLF boundary: asking for 512 MB with 128 MB VLFs gives 639 MB (5 VLFs) because 4 VLFs = 511.7 < 512. Aim ~5% under the target.
- `sqlcmd -v name=value`: a value containing `,` or `:` breaks sqlcmd's own parser ("Invalid argument") unless the quotes reach sqlcmd: from PowerShell pass `'BackupFile="D:\x.bak"'`. Plain drive lists go as letters (`DFGHI`).
- `CHECKSUM_AGG` rejects bigint; use `CHECKSUM_AGG(BINARY_CHECKSUM(*))` (int) and treat NULL as failure.
- From the laptop as CORP\agenewe: SQL to CORPSQL03 works (sysadmin), but `\\CORPSQL03\c$` and `Invoke-Command -ComputerName CORPSQL03` are both "Access is denied" (same cached-logon pattern as [[reference_smvmtr1_smb_access_denied_cached_logon]]; try `cmdkey /add:CORPSQL03 /user:corp\agenewe /pass`).
- Instant file initialization is ON for the CORPSQL03 service, so data file growth is free.
