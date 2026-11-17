---
name: feedback-gene-does-smvmtr1-installs
description: Gene runs every install/upgrade on SMVMTR1 himself unless he explicitly asks me; I build installers and hand over the path
metadata:
  type: feedback
---

Gene does all installs on SMVMTR1 (TestAutoIsolation, TestAutoManager, CrewChief, etc.) unless he specifically asks me to do one. I may build the installer and tell him where it is; I never copy-and-run Setup.exe there via Invoke-Command.

**Why:** 2026-11-17 I ran a silent TAI 8.0.1 install over WinRM while Gene was running his own 9.0.0 installer interactively; the two raced (his won, no damage). He said "I will do any installs on SMVMTR1".

**How to apply:** Build, report the path and what changed, stop. Read-only checks on SMVMTR1 (service status, version, logs) are still fine. Related: [[feedback-user-rebuilds-app]]
