---
name: project-corpsql03-profisee-recovery-simple
description: CORPSQL03 profisee DB switched FULL->SIMPLE on 2026-08-17 to stop unbounded log growth during 120M-record Connect load; was pseudo-FULL with zero log backups
metadata:
  type: project
---

On 2026-08-17 I changed the `profisee` database on **CORPSQL03** from FULL to SIMPLE recovery and raised its log autogrow from 64 MB to 4096 MB, while a 120M-record Profisee Connect load was running from CORPVMHA1.

**Why:** The database was "pseudo-FULL" — FULL recovery model with **zero log backups ever taken** (`msdb.dbo.backupset` had only type `D` rows; last full 2026-08-12 21:09, 159 GB). `log_reuse_wait_desc = LOG_BACKUP`, so the log never truncated. It grew to 65928 MB at 99.5% used, adding ~13 GB per 5 minutes. 838 of 840 VLFs were active. Connect's 50k batching was working correctly — every sampled transaction was 0 minutes old — so batching was never the problem. Commit makes log records inactive; only truncation reclaims space, and in FULL that requires a log backup.

**Result:** used dropped 65604 MB -> 4399 MB (99.51% -> 6.49%), active VLFs 838/840 -> 97/1063. File stayed ~67 GB and now recycles in place. `log_reuse_wait_desc` became `OLDEST_PAGE`, which is benign — `target_recovery_time_in_seconds = 60` means indirect checkpoints are on, so the oldest dirty page briefly trails the checkpoint LSN under heavy write.

**How to apply:**
- `ALTER DATABASE ... SET RECOVERY SIMPLE` is an online metadata change — safe mid-load, no rollback, no single-user mode. A *shrink* is not safe mid-load.
- Manual `CHECKPOINT` via sqlcmd is blocked by the Claude Code auto-mode classifier. Not needed — automatic checkpoints truncated within ~3 minutes.
- Log volume `L:\` on CORPSQL03 has ~3.5 TB free; log max_size is 2 TB. There was never an imminent 9002.
- Instant File Initialization never applies to log files, so 64 MB autogrow increments cost real zero-fill stalls during a load.

**Still owed after the load finishes:** take a full backup; decide whether `profisee` returns to FULL (only alongside a real log backup schedule, else this recurs); shrink-and-regrow the log once to collapse the 1063 VLFs.

Related: [[reference_corpsql03_hardware_profile]], [[project_connect_import_sequence_race]], [[reference_scenariomgt_db]]
