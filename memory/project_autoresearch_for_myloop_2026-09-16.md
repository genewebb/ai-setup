---
name: project_autoresearch_for_myloop_2026-09-16
description: "Verdict BUILD AFTER RELIABILITY HARDENING on adapting karpathy/autoresearch as a MyLoop self-optimisation track; the fitness model, immutable/mutable surfaces and first experiments, and where the write-up lives"
metadata: 
  node_type: memory
  type: project
  originSessionId: f05770bc-91fd-4bec-8a9f-274266258205
  modified: 2026-09-16T15:05:12.623Z
---

**Verdict (2026-09-16): BUILD AFTER RELIABILITY HARDENING.** Written as section 14 of the replacement verdict
(`03 Shared/work-ai/Loops/LoopOptions/MyLoop-Replacement-Verdict.html`, Artifact UuVnRHcuft9iJNob7Cks2D) and as
`MyLoop-Autoresearch-Evaluation.md` beside it. The repo facts were fetched verbatim (program.md, train.py, prepare.py,
results.tsv on branch exp/H100/mar8), not remembered.

**What autoresearch is:** one mutable file (`train.py`), one read-only evaluator (`prepare.py`, `evaluate_bpb`), a fixed
300 s training budget, `val_bpb` strictly-lower keeps, git-commit-before-run then `git reset` on worse, a 5-column untracked
`results.tsv`, "NEVER STOP" prose, ~12 experiments/hour on one H100; 126 real experiments, 23 keeps, 2.83 % gain. Its own
ledger shows a seed change discarded as a regression (the keep rule is finer than its noise) and the ledger is never read
back before proposing; anti-cheat is prose only (no hash, no CI).

**MyLoop adaptation decided:** lexicographic fitness — L0 hard constraints all zero (false_READY vs shadow oracle,
invalid_CLOSE, lost_work, duplicate_execution, state_corruption, unrecoverable_crash, stale_epoch_write,
dependency_violation, exclusive_collision, verification_bypass) → L1 reliability not worse → L2 est-minutes of correctly
closed rows per simulated hour (Class A replay, ≥2 % margin) or paired live rows (Class B, n≥6, median ≥15 %, sign test) →
L3 tokens per correct row (≤10 % worse) → L4 simplicity tie-break outside the invariant surface. Immutable: workload bundle
(hashed), replay oracle, Test-MyFableNext + Test-LoopChaos (48.R11), class checks, verifier rules, gates, evaluator, ledger.
Mutable at first: ReadySet PACKING order only, auto-dispatch/collect timing, foreman.json knobs, author concurrency/prompt/
evidence pack, model routing, shell-output compression. Best-known = folder copies + hash manifest, never git commits
(agents never commit here). Promotion = a normal MyLoop row with grader + blind verifier, never automatic. Fable proposes and
interprets; opus implements; the evaluator is a script.

**Why after hardening:** the evaluator's L0 layer IS 48.R11's chaos suite plus the deterministic reconcile; the baseline's
own reliability figures are non-zero today, so no candidate can be judged on L1. Missing infrastructure: frozen workload
bundle, a loop simulator driving the real scripts with a fake clock and recorded workers (shared with 48.R11), Measure-Fitness,
sandbox runner, ledger + Find-Experiment, the paired protocol. About six rows.

**First experiments:** (A) refill seats right after Collect-Wave vs next wake; (A) packing order variants; (B) 3 vs 4 ticket
authors at prefetch 6; (B) Fable vs opus verifier on security rows; (B) full vs pointer-only author evidence pack; then RTK
compression on total completed-work economics.

**How to apply:** do not start the autoresearch rows until 48.R11 is closed; rescue `replay.py` from the verdict session's
scratchpad into the vault first (it is the shadow oracle). Related: [[project_myloop_hardening_2026-09-16]],
[[project_myloop_replacement_evaluation_2026-09-16]], [[feedback_switch_to_opus_when_fable_burns_tokens]].
