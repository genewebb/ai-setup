---
name: project_profisee_db_start_settings_2026-11-20
description: Gene 2026-11-20 - Profisee SQL on Linux databases start with the isolation final-setup settings (TAI 14.4.0) after the isolation tests; sized per box
metadata:
  node_type: memory
  type: project
  originSessionId: 7986e46e-eb36-4bdb-a0ee-12f91e19b099
  modified: 2026-11-21T18:43:34.714Z
---

Gene decided (2026-11-20 13:21) that the Profisee databases (SQL Server on Linux, P8 and after) start with the
isolation test "final setup" settings once the isolation tests finish: SQL 2022 CU28 image pinned by digest
(`mcr.microsoft.com/mssql/server@sha256:4525e3ef...`), TF 3979 + writethrough=1 / alternatewritethrough=0 (FUA),
TF 8002, PROCESS AFFINITY CPU range, explicit `MSSQL_MEMORY_LIMIT_MB` (10-20% below the container limit), XFS data
disk with noatime and read-ahead 4096 sectors, mssql TuneD sysctls, THP always, 2 GB swap, host C-states C1 only.

**Why:** these are Microsoft's SQL on Linux performance and memory recommendations, built into TAI 14.4.0 with a
read-back gate for each, and they are what the final container isolation verdict is measured on.

**How to apply:** size per box, never copy the test values: affinity range = the container's CPU count, memory limit
= about 85% of the container limit, max server memory 3,072 MB was a test value. Check before use: tempdb file count,
FUA honoured end to end on that storage (TF 3979 relies on it), data and log on separate disks.

**UPDATE 2026-11-21 (supersedes the 2022 verdict line below):** isolation stack moves to SQL 2025 CU11 NOW (digest
`sha256:05644dad...`, 17.0.5065.9), thick LVM disks (no thin pools; thin pool flush worker on host CPUs was the proven
cross-impact path), data/log split (log disk at `/var/opt/mssql/tlog`, NOT `/var/opt/mssql/log` = errorlog folder),
tempdb on tmpfs (8x64 MB in 1 GB tmpfs, container +1 GB), ADR + optimized locking + RCSI ON. Built in TAI 14.6.0 /
agent 1.7.0; design `docs\isolation\design\SQL-Disk-Layout.md`. P8 Profisee DBs should start from this layout.

**SQL version (Gene 2026-11-20 15:00):** P8 runs on SQL Server 2025 (CU11, pinned by digest); Profisee SaaS runs
SQL 2025 today. (Old: isolation verdict on 2022 CU28 with a 2025 confirmation after; replaced 2026-11-21.) **SaaS = Azure SQL Managed Instance (SQL 2025)** (Gene 15:05), where ADR and optimized locking are always
on, so P8 runs with ADR + optimized locking ON (they are off by default on boxed SQL Server 2025). RCSI: lab Profisee
DB (`profisee` on SMVMDB1) has RCSI ON + snapshot isolation ON, so P8 keeps RCSI as the Profisee install sets it.
Compatibility level as created, read back. tmpfs tempdb tested alone later. Open: Gene has no SaaS SQL access yet;
confirm RCSI, compatibility level, tier (General Purpose / Business Critical) against SaaS when he does.

**P8 plan (Gene 15:50, after the isolation verdict):** Profisee `profiseeplatform:2026r3.0-win25` (release, Windows
container, process isolation) on a NEW Windows Server 2025 VM on CorpProxMox01 with its own pinned threads, one
container per VM; real app + small workloads; harness P7-style blocks on iso1-3 during workload windows measure the
VM's impact on the SQL VMs. Windows-container-to-Windows-container isolation not covered. Check first: free host
threads, WS2025 license/ISO. Registry details: [[reference_profisee_container_registry_2026-11-20]].

**P8 setup design (Gene 15:55):** port TAI's SQL container launcher + read-back INTO CrewChief (not call TAI); CrewChief
gains container, SQL-container (ssh transport), and Proxmox VM steps. Container config = `Setup.ps1` entrypoint env vars
(Configure.ps1 is image-build only). OIDC always on; needs license, OIDC provider, admin, URL. Never set
`ProfiseeConfigurationLogDebug` (logs SQL password). Note: `docs\isolation\design\P8-Profisee-Container-Setup.md`.
**CrewChief plan:** `planning\Design_CrewChief_ProfiseeContainerTesting.md` (2026-11-20 16:30): C1 ssh transport,
C2 SqlContainer, C3 LinuxHostTune, C4 WindowsContainer, C5 SqlSettingsGate, C6 ProxmoxVm (later), C7 TAI hand-off via
existing HTTP steps; 6 phases; census today 30 registrations / 29 executors / 12 box-prep. Config script runs as admin.
Answers 17:12-17:20 (D9-D15): ssh.exe; secrets as mounted files + preinit.ps1; license
`C:\Deploy\License\Prof_2020_3Inst_3Nodes_..._@.corp.profisee.com_...plic` -> `C:\Data\profisee.plic`; SQL login admin;
admin account `corp\speedmerchants`; URL = VM IP first; Docker CE (install-docker-ce.ps1); no portal sign-in for P8.
D16 (17:27): app VM = Windows Server 2025 EVALUATION image; host ISO storage `local` empty, 82 GB free; download
eval ISO + VirtIO ISO only after the isolation verdict.
D17-D20 (17:27-17:40): OIDC used; values from `C:\Temp\ChuckSetup.ps1` (non-container Configuration.exe call; its
Write-Output line prints all secrets, never copy): tenant profisee1.onmicrosoft.com, app reg 7a0c8d21-... reused (owner
adds P8 https redirect), claims .../claims/name etc. Admin account now `speed.merchants@profisee.com` (replaces corp\).
HTTPS OPEN (VM not domain-joined; DNS/cert/TLS end TBD by Gene). First run HTTP by IP: configure + API key + REST.
D21 (17:45): NEW license requested for non-domain-joined container box (corp.profisee.com .plic likely domain-bound);
ask issuer what a container license binds to (decides HTTPS DNS name too). D11 file = fallback only.
D22 (17:39): P8 license = `C:\Deploy\License\corpproxmox01_Prof_2020_..._McpOn.plic` (13,824 B, sha256 8d804d2d...,
works on ANY domain per Gene 17:41; prefix is only a file name). OIDC = ChuckSetup.ps1 settings; user/admin =
speed.merchants@profisee.com (Gene confirmed twice); its password source `C:\Deploy\Secrets\speedmerchants.txt` (never print).
D23 (17:50): HTTPS = local lab root CA + per-box server cert (New-SelfSignedCertificate), name
p8app.corp.profisee.com via hosts file first, TLS in IIS inside container via postinit.ps1; ExternalDNSUrl https.
Entra needs https only (browser-side redirect). Remaining: app reg 7a0c8d21 owner adds redirect (path via AADSTS50011). Full list: note 11 Log
2026-11-20 10:45 / 11:15 / 13:21 in `docs\isolation\host\`. Related: [[project_isolation_test_plan_page_2026-11-17]].
