# AUTORESEARCH FOR MYLOOP

Addendum to the MyLoop replacement verdict (KEEP MYLOOP) and the hardening review. Question: can the experimental optimisation
pattern of `karpathy/autoresearch` become a capability that lets MyLoop improve MyLoop, without weakening correctness?
Autoresearch is not an orchestrator and is not compared as one.

## 0 · What autoresearch actually is (fetched from the repository, not remembered)

Repository `karpathy/autoresearch` (master, last pushed 2026-03-26): 1,019 lines of Python and 206 of Markdown. Three files
matter. `prepare.py` holds the fixed constants, data, tokenizer and the metric and "is read-only"; `train.py` is "the only file
you edit"; `program.md` is the agent's instructions and "is edited and iterated on by the human" (README.md:13-15, program.md:25-31).

| Design element | What the repository says | Where |
|---|---|---|
| Mutable surface | "Modify `train.py` — this is the only file you edit. Everything is fair game" | program.md:26 |
| Immutable evaluator | "Modify `prepare.py`. It is read-only ... The `evaluate_bpb` function in `prepare.py` is the ground truth metric" (under CANNOT) | program.md:29-31; prepare.py:339-341 |
| Fixed budget | `TIME_BUDGET = 300` seconds of training wall-clock, first 10 steps excluded, enforced in the loop | prepare.py:31; train.py:602-604 |
| Objective | `val_bpb`, lower is better, on a pinned validation shard | README.md:17; prepare.py:42-44, :343-365 |
| Keep rule | "If val_bpb improved (lower), you advance the branch ... If val_bpb is equal or worse, you git reset" — strictly lower, no tolerance | program.md:103-104 |
| Tie-break | "All else being equal, simpler is better ... An improvement of ~0 but much simpler code? Keep." | program.md:37 |
| Keep/revert mechanism | git commit BEFORE the run; keep = do nothing; revert = `git reset`; the agent decides, no script arbitrates | program.md:94-104 |
| Ledger | `results.tsv`: commit, val_bpb, memory_gb, status (keep/discard/crash), description; untracked by git; never read back by the loop's steps | program.md:66-78, :101-102; .gitignore:22-23 |
| Cadence | "approx 12 experiments/hour and approx 100 experiments while you sleep", single H100 | README.md:64, :23 |
| Unattended | "NEVER STOP ... The loop runs until the human interrupts you, period." | program.md:112 |
| Crash handling | a run with no `val_bpb:` line crashed; kill at 10 min; log `crash`, move on | program.md:101, :108-110 |
| Anti-cheat | prose only: no hash, no CI, no re-verification; the file boundary is the whole enforcement (`train.py:26` imports from `prepare.py`; nothing stops an edit) | program.md:29-31; grep of both files |
| Context hygiene | "redirect everything — do NOT use tee or let output flood your context"; grep back two scalars | program.md:99-100 |

Evidence it ran: branch `exp/H100/mar8` carries a real `results.tsv` of 126 experiments (23 keep, 102 discard, 1 crash) and a
2.83 % relative improvement of the metric over about a day; kept commits are single named knob moves ("RoPE base frequency 10K
to 200K", "warmdown 0.7 to 0.75"). Two things the ledger also shows: a pure seed change (`random seed 42 to 137`) scored 0.000695
worse and was DISCARDED as a regression, while several kept wins are smaller than that — the rule is finer than the run's own
noise; and "one hypothesis per experiment" is a pattern in the ledger, not a written rule. The `agenthub` branch is the author's
multi-agent form: every result posted, only improvements pushed, the frontier as a git DAG with leaves and children.

## 1 · Which autoresearch concepts transfer cleanly

| Concept | Transfers? | MyLoop form |
|---|---|---|
| Tightly bounded mutable code | YES | a named list of files and knobs under the skill's `scripts\` and `foreman.json`; everything else read-only to the researcher |
| Immutable evaluator | YES, and better enforced than the source | the replay scheduler, the crash + chaos suite (48.R11), `Test-MyFableNext.ps1`, the graders' verdict semantics; hashed before every score, outside the mutable surface |
| Reproducible experiment | YES for the scheduling, dispatch, collect and reconcile layers; NO for agent work | replay over a frozen workload is deterministic; a worker or author run is not, and needs a paired protocol |
| Objective measurement | YES, lexicographic, not scalar | section 5 |
| Keep/revert decision | YES, and made by a script from the artifact, not by the researcher (the source lets the agent decide) | section 9 |
| Persistent experiment history | YES, and READ before proposing (the source writes it and never reads it; its multi-agent form fixes that) | append-only ledger, one artifact per experiment |
| Autonomous repeated experimentation | YES inside the sandbox; NEVER into production | section 11; `/loop` is the NEVER-STOP rule we already run |
| No subjective acceptance | YES | the KEEP rule is computed; the researcher only proposes and interprets |
| Commit-before-run crash safety | YES, without git | the experiment artifact's intent is written before the run, so a dead researcher leaves a labelled state (the same shape as 48.R5's journal) |
| Context hygiene | YES, already the loop's shape | one fixed-size verdict line per trial (the `WAVE-JSON:` pattern), the full log on disk |
| Simplicity tie-break | YES, scoped | applies to code outside the invariant surface only; "fewer guards" must never read as "simpler" |

## 2 · Which concepts do not transfer, and why

- **One scalar.** Autoresearch minimises one number under one fixed budget. A loop has hard invariants (a false READY is not a
  slower loop, it is a wrong one) and several throughput figures that trade against each other. The answer is a lexicographic
  order with a hard-constraint gate on top, not a weighted sum.
- **"The only constraint is that the code runs without crashing" (program.md:33).** In a training run, not-crashing is a near
  complete proxy for validity. In a loop the dangerous failures do not crash: a lost lease, a double claim and a stranded row
  all complete "successfully" and may raise throughput. Validity must be a positive invariant check, or the optimiser learns to
  delete the safety.
- **A stateless, repeatable run and a keep rule finer than the noise.** The source discarded a seed change as a regression and
  kept deltas smaller than that. Only the scheduling layers are replayable here (deterministic, zero noise); anything an agent
  sees (author prompt, model routing, compression) must be measured live, paired, on matched rows, with a pre-registered
  decision rule and a minimum n — which is what the 09-15 Fable-vs-opus measurements did by hand.
- **Fixed wall-clock training time as the equaliser.** The MyLoop equivalent is a fixed WORKLOAD (same rows, dependencies,
  durations, outcomes), not a fixed time: two candidates must see identical work, then time or completed work is measured.
- **The agent edits the live file and commits.** The production skill folder is live under a running loop, commits are
  forbidden to agents by standing rule, and promotion is a reviewed row.
- **Prose-only anti-cheat.** With a scalar loss the incentive to tamper is low; when the objective is throughput and the
  constraints are invariants, "make it faster" and "weaken the check" are adjacent edits. This is the design choice replaced
  first: hashes, a runner that refuses out-of-surface paths, and the evaluator re-run from a pristine copy.

## 3 · Immutable (the researcher cannot touch; hash-checked before every score; any diff = REJECT and the experiment is logged as tampered)

- the frozen workload bundle: `events.jsonl` slice, compact row records, ticket frontmatter (after, exclusive, testProject,
  writeSet, est), recorded worker durations and outcomes, board order, with a manifest hash;
- the replay scheduler and its shadow oracle for false READY (MyLoop semantics as the reference);
- `tests\Test-MyFableNext.ps1`, `tests\Test-LoopChaos.ps1` (48.R11), the crash labels and their expected end states;
- the dependency fixtures and expected outcomes;
- the graders' verdict semantics, the class check lists (`checks\*.ps1`), the verifier requirement per class, the two human
  gates, the residual gate, the two-strike rule;
- the evaluator (`Measure-Fitness.ps1`), the hard-constraint list, the KEEP rule, the baseline records, the ledger's past entries;
- estimates and calibration inputs: from the frozen workload, never from the candidate.

## 4 · Initially mutable

- `Get-ReadySet.ps1` PACKING ORDER only (who wins a contested seat), never the legality tests;
- the auto-dispatch policy in `Sync-Board` (48.R9): when to refill, how many, backfill preference;
- `Collect-Wave` timing and ordering; verify-stage batching;
- `foreman.json` knobs: `maxParallel`, `monitorPollSeconds`, `overdueFactor`, the calibration formula (class vs size band, per
  MyLoopAnalysis §5), `workerModel`, `verifierModel`, `verifierModelByClass`;
- ticket supply: author concurrency, prefetch depth, standing accepted-queue size, author prompt size and evidence-pack shape,
  self-test construction strategy;
- prompt templates in `PROMPTS.md` for worker, verifier and author, EXCEPT the rule blocks they carry (never-commit, write set,
  no subagents, report shape), which are immutable text;
- context/output compression on worker shells (RTK or equivalent), as one experiment class.
Not mutable until a separate, stronger experiment class exists: dependency semantics, verification requirements, human gates,
security constraints, grader correctness rules.

## 5 · The fitness function

Two experiment classes, because two kinds of evidence exist.

**Class A — replay experiments** (scheduler, dispatch, collect, reconcile, knobs). Deterministic and cheap: the evaluator drives
the REAL scripts against a scratch `.loop` with a simulated clock and recorded workers (a worker "returns" its recorded outcome
after its recorded duration).

**Class B — live paired experiments** (authors, models, prompts, compression). Two arms on matched rows (same class, same
clause-count band), a pre-registration file written before the first row runs, minimum n = 6 pairs, both arms in the same day.

Lexicographic; a candidate is compared with best-known at the first level where they differ:

| Level | Measure | Rule |
|---|---|---|
| L0 correctness (hard) | false_READY (against the shadow oracle), invalid_CLOSE (closed without the class's checks, verdict or residual), lost_work (a key that vanished, an attempt with no terminal state), duplicate_execution (two live attempts of one key), state_corruption (an unparseable authoritative file), unrecoverable_crash (a RECOVERY-REQUIRES-HUMAN the baseline did not produce), stale_epoch_write, dependency_violation, exclusive_collision, verification_bypass (a code or security row with no verdict; a check list shorter than the class's) | every count ZERO, else REJECT |
| L1 reliability | reconcile repairs, manual interventions, retries per closed row, chaos-suite pass count | none worse than best-known |
| L2 useful throughput | Class A: est-minutes of CORRECTLY closed rows per simulated wall hour over the whole workload (an incomplete workload = REJECT); legal-seat fill (Σ in flight ÷ Σ legal); READY→dispatch and DONE→collect latency. Class B: correct completed rows per wall hour on the paired rows; for authors, ACCEPTED tickets per hour weighted by downstream worker success (a ticket whose row is later rejected counts 0) | the primary must improve by a margin: A ≥ 2 % (replay noise is zero; the margin stops churn); B: paired median ≥ 15 % with a sign test at p ≤ 0.1 |
| L3 token efficiency | tokens per correct closed row; tokens per accepted successful ticket | not worse by more than 10 % unless L2 improved by more |
| L4 operational simplicity | lines changed, knobs added, files added | tie-breaker only, and only outside the invariant surface |

Why est-minutes and not row count: the estimate is frozen in the workload, so a candidate cannot earn by preferring short rows;
a row counts only when the evaluator observed it closed with every check its class requires. Why lexicographic and not
weights: no measured exchange rate exists between a false READY and a minute of latency, and inventing one is how a scheduler
learns to be fast and wrong. Why a margin on a deterministic replay: the source's ledger shows what a zero-tolerance rule does —
kept deltas below the noise floor and a seed change logged as a regression.

## 6 · Metric gaming, and the defence for each

| Gaming move | Defence |
|---|---|
| less verification | verification_bypass is L0: the class check list and the verifier requirement are read from the immutable evaluator, never from the candidate |
| skip difficult tasks | the workload is fixed and scored whole; an unclosed row is an incomplete experiment = REJECT |
| prefer short rows | L2 counts frozen est-minutes, not rows |
| under-report failures | outcomes are what the evaluator observed (grader exit codes, record states it read), never the candidate's logs |
| change estimates | `est` comes from the frozen bundle; a candidate that writes estimates changes nothing the evaluator reads |
| reduce test coverage | suite case count and grader clause count are pinned in the evaluator; fewer = REJECT |
| delay accounting | the simulated clock is the evaluator's; live experiments stamp events from harness time |
| avoid expensive dependency classes | fixed workload; the exclusive rows are in it |
| change benchmark data or result interpretation | outside the mutable surface; hashed before scoring; any diff = REJECT, logged as tampered |
| widen the mutable surface quietly | the sandbox runner diffs the candidate against best-known and refuses any changed path outside the list |
| "simplify" by removing a guard | the simplicity tie-break is scoped to files outside the invariant surface; a guard removal is a diff inside it = REJECT |

## 7 · Can the existing replay + crash + chaos infrastructure serve as the evaluator?

Partly today, fully after 48.R11. What exists: the shadow-replay script from the verdict session (27 epochs, MyLoop semantics
as oracle; it lives in that session's scratchpad and must be rescued into the vault beside the verdict), `Inject-Faults.ps1`
(ten crash points, scratch copies), `Test-MyFableNext.ps1` (18 cases), `Get-Throughput.ps1` (every latency in section 5).
What each lacks for evaluator duty: the replay simulates the scheduler and does not drive the real scripts; fault injection is
by hand; the throughput report reads live events, not a simulated run.

## 8 · Missing benchmark infrastructure

1. **Frozen workload bundle** with a manifest hash: one script that cuts it from a live `.loop` at a chosen window.
2. **Loop simulator**: drives the real scripts on a scratch `.loop` with a fake clock and recorded workers — the largest piece,
   and shared with 48.R11 (crash labels at "after worker DONE" need it).
3. **`Measure-Fitness.ps1`**: runs L0–L4, writes the experiment artifact, decides KEEP/DISCARD.
4. **Sandbox runner**: copies best-known to `exp-<id>\`, applies the candidate, verifies the immutable hashes, runs the evaluator,
   refuses any path under the production skill folder.
5. **Ledger**: `experiments.jsonl` append-only plus one artifact folder per experiment, and a `Find-Experiment` query the
   researcher must run before proposing (the source's ledger is written and never read; its multi-agent form makes reading it
   step 1).
6. **Paired live protocol** for Class B: row matching, pre-registration file, the sign test.

## 9 · KEEP vs DISCARD

KEEP iff every L0 count is 0 AND no L1 figure is worse than best-known AND the L2 primary beats best-known by its margin AND L3
is within tolerance AND the immutable hashes match. Otherwise DISCARD, naming the first failing level. Both outcomes write the
same artifact: id, parent baseline id, hypothesis (one sentence), files changed (diff hash), expected improvement, correctness
result, crash result, chaos result, replay result, performance result, token result, decision, reason. The artifact's intent
half (id, parent, hypothesis, expected improvement, diff hash) is written BEFORE the run — the commit-before-run idea — so a
researcher that dies mid-experiment leaves a labelled state.

## 10 · Persisting best-known versions

Not git commits: agents never commit in this environment, and the skill folder is untracked on a share. Folder copies with a
manifest: `Loops\Autoresearch\best-known\` (scripts, `foreman.json`, a hash manifest, the artifact that made it best);
`Loops\Autoresearch\exp-<id>\` per experiment, kept, never deleted (a DISCARD keeps its diff so the ledger can show what was
tried). Best-known advances only by copying a KEEP experiment's folder over it and appending to the ledger. Every experiment
starts from best-known, never from another experiment. The source's frontier-as-DAG (agenthub) is the right shape if two
researchers ever run at once; one branch suffices for one.

## 11 · Promotion to production

A KEEP experiment becomes a MyLoop ROW: ticket with the hypothesis as WHY, the diff as the write set, a grader that re-asserts the
evaluator's L0/L1 results against the LIVE scripts plus a self-test, the staging-copy landing, the blind verifier, the lead's
read, the close. Nothing in the sandbox can write to the production skill folder; the runner refuses a path under it.

## 12 · Who runs the experiments

Evidence on record (MyLoopAnalysis §3, pre-registered on 09-15): Fable as verifier, −12 to −14 % tokens, faster, more findings;
Fable as ticket author, +21 % tokens, −18 % wall, one ticket undelivered; opus everywhere by default since 09-13. The division
that follows: **Fable** proposes the hypothesis (reads the ledger and the throughput report; low volume, high judgement),
interprets the artifact, and reviews a promotion ticket. **Opus** implements the bounded diff in the sandbox — the author-shaped
seat where Fable measured worse. **No model** runs the evaluator: it is a script. A cheaper model has no measured seat here yet.
This is a hypothesis to test on the first ten experiments, not a setting.

## 13 · Cost

Build: six rows after 48.R11 — workload bundle (1), simulator (2, the largest), fitness + ledger (1), sandbox runner (1),
researcher skill (1); about one and a half worker-days at the loop's measured 0.3–0.5× of estimate. Per experiment: Class A
about 15 min wall and 250–400k tokens (a Fable read plus an opus diff); Class B a day of paired rows and their real tokens.
The source runs 12 experiments an hour on one GPU; Class A here would run about 4 an hour, bounded by the chaos suite.

## 14 · Largest risks

Simulator fidelity (a scheduler that wins on recorded durations may lose on live ones — mitigated by promoting only through a
real row); overfitting to one frozen workload (rotate bundles; a KEEP must hold on two); evaluator drift (the immutable set is
hashed, and a change to it is itself a reviewed row); token burn on Class B; a researcher that edits production by path mistake
(the runner refuses); and the temptation to widen the mutable surface into dependency semantics because that is where 27 % of
blocked seats sit — that surface stays closed.

## 15 · First five experiments

1. (A) Seat refill: dispatch the legal set immediately after `Collect-Wave` returns vs on the next wake only. Expect READY→dispatch
   latency to fall; measures the 13 % lead-latency slice directly.
2. (A) ReadySet packing order: board order vs longest-`after`-chain-first vs shortest-est backfill. Expect higher legal-seat fill
   with zero L0 change (legality untouched).
3. (B) Ticket authors 3 vs 4 concurrent at prefetch depth 6: accepted-and-successful tickets per hour, tokens per accepted ticket,
   lead-read minutes. The 45 % bucket.
4. (B) Verifier routing: Fable vs opus on security rows only. Tokens, wall, findings that survive the lead's read.
5. (B) Author evidence pack: full file:line pack (today) vs pointer-only. Tokens per accepted ticket and rejection rate.
Then, sixth: (B) worker-shell output compression (RTK) measured on total completed-work economics, never on shell bytes.

## FINAL VERDICT

BUILD AFTER RELIABILITY HARDENING

Evidence: the evaluator's hard-constraint layer IS the hardening programme's proof (48.R11's crash and chaos suites, the
reconcile that makes stranded state deterministic); without it a candidate's stranding cannot be told from the baseline's, and
the baseline's own reliability figures are non-zero today (4 hand-marked LOST attempts, 42 of 84 override closes). The
orchestrator-addressable throughput slices (13 % lead latency, the collect wait) are being closed deterministically by
48.R8/48.R9 without experimentation. What remains — ticket supply at 45 % of seat capacity, model routing, prompt shape — is
the Class B territory where a controlled, ledgered, paired protocol beats occasional hand measurement: the 09-15 Fable runs
produced one real win and one real loss in the same evening, which only a repeatable process would catch every week. The
source proves the loop shape works (126 experiments, 23 kept, unattended); its own ledger also proves the two things that must
change for this domain — a keep rule wider than the noise, and an evaluator the agent cannot edit.
