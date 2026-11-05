---
name: project_connect_empty_model_bootstrap_2026-11-04
description: "Connect empty-model bootstrap (spec-driven Dba domains + entities, P2P target baseline) - status at 11/04 pause, clean-install direction, resume prompt path"
metadata:
  node_type: memory
  type: project
  originSessionId: 34a49909-8fbf-493a-ab83-eee68b7ef6e7
  modified: 2026-11-04T19:45:58.795Z
---

Connect bootstrap now builds Main and the P2P target from an empty Maestro model using the checked-in spec (C:\devops\repos\speed-merchants\CrewChief\connect-model-spec, Gene commits). Generator D:\PowershellScripts\CrewChiefConnect\New-ConnectWorkloads.ps1.

Status 11/04 12:28 (paused by Gene for a clean Profisee install): all Task 3 live negatives pass on SMVMTR2 (wrong model id, foreign entity fail-fast, interrupted rerun); connect-1k-bootstrap, testauto-setup, P2P export run 1 pass. 4.5 run 2, smoke round and 26R2 queue remain. Resume prompt: C:\scratch\claude\4a72a11b3ea84e15\c233553b-f77d-4b9e-8e31-0e62ebe2831b\scratchpad\resume-prompt-20261104-cleaninstall.md; ledger empty-model-ledger.md in the same folder.

Gene decisions 11/04:
- Target API key ALWAYS set by the P2P bootstrap (TargetApiKeySet flag removed) so clean installs need nothing pre-seeded.
- After this works: retrofit the 26R3 CrewChief work, final test on a fresh clean install. Future runs 26R3+ only (SMVM2 shared-target issue moot).
- Baseline .bak files only matter during a run; old SMVM3 matching/log data (8 GB target baseline) is fine.
- ModelSourcePDATA*.bak never change.
- Releases BEFORE 26R3 have a Profisee Windows service ('Profisee <ver> (<instance>)'); 26R3 and later have NONE. The CrewChief workflow differs: service stop/start steps exist only pre-26R3 (generator MainServiceName/TargetServiceName = $null on 26R3+). Apply in the 26R3 retrofit.
- 11/04 14:27 race: removing scratchpad pause-all woke a leftover 11/03 finish-queue script that was blocked on it; two queues overwrote the TR2 runner's queue.txt (wrong RESULT lines, a run skipped). Before removing pause-all: `ps -ef | grep -E "queue|run-cc-host"` and kill old queue scripts.
- Clean install: legacy-cleanup-preview fails 401 before the first bootstrap (no key yet) - skip it there.

**Why:** Gene wants a repeatable from-scratch Connect setup. **How to apply:** don't re-litigate these; resume from the prompt file. Related: [[feedback_connect_no_local_profisee]], [[project_connect_test_board_2026-10-30]], [[feedback_connect_never_delete_entities]].
