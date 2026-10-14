---
name: reference_docker_memory_limit_lowering_oom
description: "Lowering a container memory limit under a running SQL Server OOM-kills it — set max server memory first, apply the limit while stopped"
metadata: 
  node_type: memory
  type: reference
  originSessionId: c89b11b7-293e-4541-9e9d-95c030e9fe7c
  modified: 2026-08-16T16:09:24.574Z
---

Tightening a cgroup memory limit underneath a process that **already exceeds it** is itself the OOM trigger. This is not the usual "workload grows past its limit" warning.

Observed 2026-08-16 on `sql2022-speedmerchants`: container running unlimited with SQL holding ~28 GB, then `docker update --memory 12g`. SQL Server was killed instantly; the next `sqlcmd` failed with empty output against a server that no longer existed, and the container returned empty under `restart=unless-stopped`.

**Correct order when tightening:**

1. `sp_configure 'max server memory (MB)', <target>; RECONFIGURE;` — while the OLD limit is still in force
2. `docker stop <container>`
3. `docker update --cpuset-cpus … --memory …` — applied to a **stopped** container
4. `docker start <container>`

Applying the limit while stopped means it is enforced against a fresh process that never exceeds it. It also removes any need for a separate restart: SQL Server reads the cgroup only at startup, which is now exactly when it starts.

Raising a limit is always safe. Only lowering is hazardous — so this bites on the way INTO a pinned config, never on the way out.

Implemented in `C:\devopslocal\repos\container-perf-iso\scripts\Set-ContainerResourceConfig.ps1`. See also [[reference_docker_update_cannot_clear_limits]].
