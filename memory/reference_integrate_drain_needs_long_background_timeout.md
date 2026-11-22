---
name: reference-integrate-drain-needs-long-background-timeout
description: "An integrate drain launched with Bash run_in_background and no timeout is killed at 30 min, mid-apply; launch with timeout 7200000 and check for a partial apply after any kill"
metadata:
  node_type: memory
  type: reference
  originSessionId: 4599ecab-4540-423c-841b-aeba6b8760d1
  modified: 2026-10-04T03:35:18.683Z
---

On 2026-10-04 01:12Z, drain 1003r (drain-by-id.ps1 via Bash `run_in_background`, no `timeout`) was killed at the default 30-minute background limit.
It died in G3.T267 after the `git apply` and before the grader verdict. The main tree was left holding the whole patch, uncommitted, with the row still `built` and no integrate-patch.lock left behind.

**Recovery:** run `git apply --numstat <patch>` and compare it to `git diff --numstat`. If they match, run `git apply -R --check`, then `git apply -R`, then `git update-index -q --refresh`. This reverses only the integrator's own apply. Then re-drain.

**How to apply:** launch every drain with the **PowerShell tool** (not Bash, whose token has SeRestore enabled and gives ACL graders a false SUSPECT) and `timeout: 7200000`. A drain that pulls in rows built by other sessions while it runs can last longer than 30 min. After a killed notification, always check `git status` against the last row the drain log names. Related: [[reference_integrate_drain_overlap_same_session]], [[reference_beat_loop_dies_with_background_limit]].
