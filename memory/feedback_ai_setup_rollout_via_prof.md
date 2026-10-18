---
name: feedback_ai_setup_rollout_via_prof
description: "After any ai-setup change, the rollout recipe is the prof hub (prof setup reload, prof setup push -Machine SMVMTR1 -AllowSecrets, prof streams update -RestartSessions), never raw install.ps1 / publish.ps1 advice (Gene 2026-10-18)"
metadata:
  node_type: memory
  type: feedback
  originSessionId: f72b1fa1-4f0b-4455-a732-6236fcf25583
  modified: 2026-10-18T14:42:14.959Z
---

Rollout after editing anything in the ai-setup clone (skills, stream kit scripts, profile, memory):

```powershell
prof setup reload                                   # install from the local clone on this machine
. $PROFILE
prof setup push -Machine SMVMTR1 -AllowSecrets      # publish to GitHub + copy + install on the target (-User defaults from machines.yaml = CORP\genewe)
. $PROFILE
prof streams update -RestartSessions                # rolling update of the RUNNING board: stop runners cleanly, install kit, restart same layout + Planner
```

`-AllowSecrets` is needed while `Test-StreamKitRecovery.ps1` carries the Add-Lesson refusal fixture (conn-password rule). Never quote that fixture in a memory file: it trips the guard again.

**Why:** 10/18 I pointed Gene at `install.ps1 -NoPull -Yes` and `publish.ps1`, then at a manual install on SMVMTR1, because the prof hub was uncommitted WIP from another session and I had not read `Gene.Profile\Verbs.ps1`. Gene: "why not prof setup reload ... prof setup push ... prof streams update -RestartSessions". The hub wraps all of that, including the runner restart that raw install never does.
**How to apply:** before recommending any sync/install/restart command, grep `pwsh\PowerShell\Modules\Gene.Profile\*.ps1` (Verbs.ps1 usage lines, StreamsGroup.ps1) for the hub command; give the `prof` form. Raw scripts only when the hub has no verb for it. See [[project_manageprofile_hub_2026-10-17]], [[project_stream_profile_commands_proposal_2026-10-17]], [[feedback_verify_no_guessing]].
