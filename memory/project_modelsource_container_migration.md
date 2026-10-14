---
name: modelsource-container-migration
description: "ModelSource DB migration to SQL 2022 Docker container — COMPLETED 2026-08-14 (container sql2022-modelsource, port 14322)"
metadata: 
  node_type: memory
  type: project
  originSessionId: 6f077cd3-fc8d-428d-a30e-664d93c1b807
  modified: 2026-08-14T22:25:07.611Z
---

Migrating local ModelSource DB (SQL 2022 Developer, default instance) into a SQL Server 2022 Linux container with persistent named volume.

**DONE 2026-08-14:** restored into container **sql2022-modelsource** port **14322** (not the planned name "sql2022"), fresh 8/14 backup, counts validated vs local, profisee SQL login (db_owner) pre-staged. SSD wait dropped — Docker vhdx moved to `C:\devopslocal\Containers\` instead. Local ModelSource still online/authoritative until Profisee repointed. Details: [[testauto-linux-container-plan]].

**State (2026-08-13, historical):**
- Log shrunk 65 GB → 4 GB (SIMPLE recovery, was nearly empty)
- Compressed backup DONE: `C:\tmp\sqlbackup\ModelSource.bak`, 81.1 GB, WITH CHECKSUM, RESTORE VERIFYONLY passed
- Container build DEFERRED until external SSD arrives (Docker WSL2 vhdx would grow ~200 GB on C:; plan is migrate Docker storage to SSD first — see [[docker-aspire-class-setup]])
- Local ModelSource still online/authoritative — backup goes stale if it changes; re-backup before restore if so

**Plan doc:** `52 Technical\Containers\SQL Server\Migrate ModelSource to SQL 2022 Container.md` (vault) — resume at step 3. Container: name sql2022, image mssql/server:2022-latest, host port **14322** (14333 taken by sql2025 class container), volume sql2022-data at /var/opt/mssql, backup folder bind-mounted at /backup. Restore command with all 8 MOVE clauses (mdf + F/G/H/I/K/L ndf + log) pre-built in doc.
