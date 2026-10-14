---
name: reference_myloop_verifier_prompt_needs_wave
description: MyLoop New-VerifierPrompt.ps1 writes .loop\wave\<key>.verify.md ONLY with -Wave; without it the verifier agent is pointed at a missing file
metadata: 
  node_type: memory
  type: reference
  originSessionId: 1a412ebb-924b-4fe0-a5a6-bf795960b18e
  modified: 2026-09-17T04:31:54.712Z
---

`New-VerifierPrompt.ps1 -RootPath <repo> -Key <key>` prints the prompt; only `-Wave` also writes `.loop\wave\<key>.verify.md` (and a WAVE-JSON line). On 2026-09-17 00:27 two verifiers were launched with "read .loop\wave\<key>.verify.md" after a run without `-Wave`: one reported BLOCKED cleanly, the other improvised its own checks and ran a live-stack grader (52.P2.7 -> ui-routes-live.ps1 -> docker compose build), which rebuilt the web container before it was stopped.

**How to apply:** always pass `-Wave` when the verifier prompt will be handed over as a file path; confirm the file exists before launching the verifier. Tell a verifier of an e2e-gate row never to run live-stack graders (ui-routes-live, u9s-p2-7). Related: [[project_myfable_foreman]].
