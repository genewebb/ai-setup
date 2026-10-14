---
name: crewchief-ado-build-download
description: "CrewChief ADO build download feature — design approved 2026-08-27, 4 step types, doc in planning\\Design_CrewChief_AdoBuildDownload.md"
metadata: 
  node_type: memory
  type: project
  originSessionId: f8087fea-30b2-4b08-b87a-7343b8939220
  modified: 2026-08-28T03:01:03.240Z
---

IMPLEMENTED 2026-08-27 via /myworkflow loop: 11 iterations, 6/6 criteria, suite 3624/3624, 0 rollbacks, 3 ratified census amendments, integration test LIVE-GREEN vs real ADO. Report: `speed-merchants\.loop\LOOP_REPORT.md`. Spec + implementation deltas: `planning\Design_CrewChief_AdoBuildDownload.md`. Uncommitted-by-loop (user committed 4x mid-loop). PENDING: user rebuild/deploy, attended full-pipeline e2e (423MB path never moved real bytes), Task Scheduler wiring, PAT rotation calendar. Loop lesson: all 3 amendments were census-oracle shapes Batch-3b probes miss (token-resolution, property-reflection, enum censuses) — fold into orchestrator-worker skill.

Feature: download last successful Profisee platform build from ADO, unzip, verify, robocopy /MIR to CurrentBuild. 4 new step types: AdoBuildDownloadStep → BuildUnzipStep → BuildVerifyStep → BuildPublishStep, handoff via `latest-download.json` marker in download dir (tokens don't pipe step outputs). New Capability Advisor capability `AdoBuild` (PAT prober, preflight hard-block).

Ground truth (verified live): org profisee.visualstudio.com, project Products, pipeline `platform` defId **293**, branch refs/heads/master, buildNumber `26.3.0.767` → folder `26R3B767` (major+R+minor+B+last). Build has 2 artifacts: SymbolRequest (ignore) + Container `platform\26.3.0.767` (~423 MB) — artifact name embeds version, select by type==Container, fail if 0 or 2+.

User-side state: reference-data set `ado-configuration-values` created by user (live at C:\Deploy\CrewChief\web\data\reference-kv\), 7 keys incl. buildDownloadDirectory=c:\Deploy\Downloads, buildTargetDirectory=c:\Deploy\ReleaseToWeb\Currentbuild, buildRetentionCount=5. PAT added 8/27: Local Secrets section `AzureDevops`, key `adoPAT` → `{{$config:AzureDevops:adoPAT}}` (Build Read scope). KeyValueReferenceDataResolver accepts any set name, gated only on includeInReplacements.

Runs scheduled via Windows Task Scheduler → CrewChief.Cli run. Robocopy exit 0–7 success, ≥8 fail. Related: [[crewchief-standalone]], [[crewchief-capability-preflight]].
