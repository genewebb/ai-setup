---
name: feedback-api-key-after-every-restore-configure
description: "Every CrewChief pack workload that restores a Profisee DB or runs Configuration must set AND verify the API key itself, no exceptions; Test-Pack R-key enforces"
metadata:
  node_type: memory
  type: feedback
  originSessionId: 95f5b98f-d94c-408a-8901-e309c3b37709
  modified: 2026-11-10T00:39:25.245Z
---

Every workload that restores a Profisee database or runs Profisee Configuration sets AND verifies the API key itself
(SetApiKeyStep, then gateway v1/Entities + Data v1/Rules check) after its last restore/configure — no exceptions,
even when the workload makes no authenticated REST call itself (e.g. a base-create that only backs up).
Gene 11/09: "ALL workloads need to make sure the API key is set no exception"; scope confirmed = restore/configure
workloads + a Test-Pack lint rule (R-key) across all four packs. Not every root/child workload.

**Why:** a base backed up or left behind without the standard key makes the next run fail red (DATA00030 / 401);
relying on a caller to set it later is the exception Gene ruled out.

**How to apply:** when generating or reviewing a pack workload with a DatabaseOperationsStep restore of the Profisee
DB or a ConfigureStep, require a key-set child (`<family>-api-key-set`) or SetApiKeyStep after it. A reviewer
saying "no REST call, so no key needed" is wrong under this rule. Related: [[reference-pack-base-backup-must-match-build]],
[[feedback-red-is-red-declared-inputs]].
