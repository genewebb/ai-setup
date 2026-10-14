---
name: reference-git-status-vs-diff-no-head
description: "In a commit-less git repo, `git status --porcelain` reports staged files as `A ` forever — use `git diff --name-only` (worktree vs index) for \"was this file touched?\" checks"
metadata: 
  node_type: memory
  type: reference
  originSessionId: e0f6679b-77c7-4d86-960f-c1c46ac24d04
  modified: 2026-08-02T18:17:27.704Z
---

A freshly `git init`ed repo with staged-but-uncommitted files has no HEAD. `git status --porcelain <path>`
compares **index vs HEAD**, so with no HEAD it prints `A  <path>` permanently. Any invariant written as
"this file is unmodified → git status output is empty" can therefore never pass.

Use `git diff --name-only -- <path>` instead: it compares **worktree vs INDEX**, which is the real
baseline in a commit-less fixture. Empty at baseline, non-empty the moment the file is edited, and it
needs no commit.

Found 2026-08-02 in the orchestrator-worker-loop test fixture (`C:\tmp\loop-test`): the GOAL's
`regression-command` and `loop-test-verify.ps1` both used the status form, so the decoy-file invariant
failed on iteration 1 of a perfectly clean run. Both fixed.

The loop's own gate scripts already handled the no-HEAD case correctly — `Get-ChangedFiles.ps1` falls
back to BASELINE.json hashes and `New-Checkpoint.ps1` skips `git stash create` with exit 1. Only the
hand-written GOAL command and the standalone verifier had the bug.

Related: [[project_orchestrator_worker_loop_hardening]], [[feedback_verify_no_guessing]]
