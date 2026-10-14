---
name: orchestrator-worker-loop
description: Interview the user to define a coding goal, then run a cost-tiered orchestrator-worker loop (reasoning tier plans+verifies, fast/balanced tier executes). Use when the user asks to run a Ralph-style autonomous loop, overnight coding loop, tiered-model loop, plan-execute-verify loop, orchestrator-worker loop, or references the pattern doc "Orchestrator-Worker Pattern for Coding.md".
---

# Orchestrator-Worker Coding Loop

Two-phase skill: **INTERVIEW** the user, then **RUN** the loop using cost-tiered models.

This file owns the interview and the run procedure. The `/myworkflow` command is only a router
(argument handling) — it does not define its own interview. If they ever disagree, this file wins.

## Skill files

| File | Purpose |
|---|---|
| `SKILL.md` | You are here. Interview + run procedure. |
| `PROMPTS.md` | Verbatim prompt templates for Orchestrator, Executor, Verifier, Final Report. |
| `EXAMPLES.md` | Filled-out reference artifacts (GOAL.md, PLAN.md, PROGRESS.md, Executor responses). |
| `TEST-PROBLEM.md` | Safe scratch test problem. Point the user here for their first run. |
| `MODELS.md` | Tier → concrete model slug per CLI, including this one. |
| `scripts/` | The gate tooling — see the table below. |

## External references (read once at skill invocation)

| Path | Why |
|---|---|
| `{VaultDocsRoot}\Goals\HOW-TO-WRITE-A-GOAL.md` | Best-practice guide for composing a goal — point users here |
| `{VaultDocsRoot}\Goals\Orchestrator-Worker Pattern for Coding.md` | Full pattern spec — roles, memory files, handoffs, gates |
| `{VaultDocsRoot}\Goals\GOAL.template.md` | GOAL frontmatter schema and section layout |

## Subagent dispatch is authorized

Invoking this skill (or `/myworkflow`) IS the user's request to dispatch subagents. Use **one
subagent call per iteration** — a single Executor, serially. Never fan out with a parallel
workflow tool: the Executor mutates files, and concurrent executors would corrupt each other's
work and the constraint gate.

---

## The scripts

All under `scripts/`, all dot-source `LoopCommon.ps1`. Exit codes are the wire protocol.

| Script | Job | Exit codes |
|---|---|---|
| `Initialize-Loop.ps1` | One-command setup: `.loop\`, `state.json` (**started_at**), PROGRESS/PLAN seed, baseline, criteria preflight, permission list | 0 ready / 1 ready-with-warnings / 2 error |
| `Get-Baseline.ps1` | Snapshot file hashes → `BASELINE.json`. **Re-run after every PASSING iteration** with `-Iteration N` | 0 / 1 |
| `Test-Constraints.ps1` | Gate 3: only allowed files changed since baseline | 0 clean / 1 violation / 2 error |
| `Get-ChangedFiles.ps1` | Gate 4 input + PROGRESS "Files changed". Counts **new/untracked** files that `git diff` hides | 0 / 2 |
| `Test-Criteria.ps1` | Preflight + gates 5/6: runs the Done-when commands, records `CRITERIA.json` | 0 all pass / 1 some fail / 2 error |
| `New-Checkpoint.ps1` | Restore point via `git stash create` — **no commit**, HEAD/branch/index untouched | 0 / 1 no-git / 2 error |
| `Invoke-Rollback.ps1` | Restores tracked files AND (with `-AllowClean`) deletes new untracked files | 0 complete / 1 partial / 2 error |
| `Test-Budget.ps1` | Stop conditions: iterations, wall-clock, consecutive failures, no-change thrash | 0 continue / **10 stop** / 2 error |

**Passing multiple values.** Under `pwsh -File`, each array element is a separate token and can
mis-bind to another parameter. Always pass array parameters as ONE comma-separated token:

```powershell
pwsh -File scripts\Test-Constraints.ps1 -RootPath <repo> -Allowed 'src/A.cs,src/B.cs'
```

For criteria (shell commands full of quotes and commas), use `-CriteriaFile <json>` instead.

---

## Phase 1: INTERVIEW

Ask in **short batches**. Use the CLI's structured-question tool for choice questions; plain
prose for free-form answers (globs, shell commands, paths — those cannot be multiple-choice).
Offer defaults so the user can say "default" and move on.

If the user asked for speed (`--defaults`, "just use sensible defaults"), skip to the Preview step
with: repo = cwd, branch = current, scope = whole repo minus generated code, tiers = the defaults
below, budget = Conservative, mode = dry-run. Still require the Done-when criteria — those cannot
be defaulted, because they define termination.

### Batch 1 — What and where
1. **What are you trying to accomplish?** (1-3 sentences)
2. **Which repo?** (default: cwd from `Get-Location`)
3. **Which branch?** Read `git branch --show-current` and **show the user the actual name** — do not
   silently accept it as "default". If the name's shape disagrees with the goal's shape, say so once
   and let them decide:

   > Current branch is `bug/connect_testing/genewebb`, but this goal adds a new feature. Run here
   > anyway, or switch first?

   A user who answers "default" to a bare "which branch?" has not seen the branch name. Asking costs
   one line; landing a feature on someone's bug branch costs a cleanup.

If the goal is vague, ask ONE clarifying question, then proceed.

### Batch 2 — Definition of done
**Critical.** Fuzzy criteria → runaway budget.

Get the *exact command* for each criterion. Every command must **exit 0 if and only if the
criterion is satisfied**. Watch the polarity trap:

> `rg -c 'pattern' src/` exits **1** when there are ZERO matches. So "no occurrences remain"
> written as "rg returns 0" can never pass. Invert it explicitly:
>
> ```powershell
> rg -q 'GetValue<' src/; if ($LASTEXITCODE -eq 1) { exit 0 } else { exit 1 }
> ```

And the trap in the other direction:

> **The vacuous-pass trap.** `dotnet test --filter <no match>` exits **0**. On .NET SDK 10.0.302 it
> printed `No test matches the given testcase filter`; on **10.0.400 it prints NOTHING** — no match
> line and no `Passed!`/`Failed!` summary, only "A total of 1 test files matched the specified
> pattern" (measured 2026-09-07). So "my new tests pass" is TRUE before the tests exist — and "the
> tests pass" is the most natural way to phrase a Done-when criterion for a test-backed goal. Any
> criterion naming a not-yet-existing test must prove the filter actually matched something, and the
> proof is the PRESENCE of a summary line, never the absence of a phrase:
>
> ```powershell
> $o = dotnet test <proj> --filter FullyQualifiedName~MyNewTests 2>&1 | Out-String
> if ($LASTEXITCODE -eq 0 -and $o -match 'Passed!\s+-\s+Failed:\s+0,\s+Passed:\s+(\d+)' -and [int]$Matches[1] -ge $Floor) { exit 0 } else { exit 1 }
> ```
>
> The same shape applies to any runner that treats "nothing selected" as success — check yours rather
> than assuming. `pytest` exits 5, `go test -run` exits 0, `jest --passWithNoTests` exits 0.
>
> Generalize it: **a criterion must fail at baseline for the RIGHT REASON.** The preflight tells you a
> criterion fails; it does not tell you why. For any criterion referencing an artifact that does not
> exist yet, confirm it fails because the artifact is missing — not because the command is malformed,
> and not because it silently selected nothing.

Common shapes:
- `dotnet test --filter "FullyQualifiedName~Foo"` — exit 0 = pass
- `dotnet build --no-restore` — exit 0 = clean
- absence check — inverted wrapper above
- count check — `if ((Select-String -Path Y -Pattern 'X').Count -eq N) { exit 0 } else { exit 1 }`

Push back on preferences ("cleaner", "faster"): "That's a preference, not a verifier. Give me a
command I can run."

**Separate achievements from invariants.** A "Done when" criterion must be FALSE now and become
true — that is what makes it a termination condition. Something already true that must merely *stay*
true ("AppConfig.cs is untouched", "the fast suite still passes") is an invariant: put it in
`regression-command`, which runs every iteration. An invariant in "Done when" is a no-op that
verifies nothing about progress, and the setup preflight will flag it as already-passing.

### Batch 3 — Scope
- Entire repo (`bin/`, `obj/`, `node_modules/`, `.git/`, `.loop/` are excluded automatically at any depth)
- Specific subfolders
- Specific glob

Then: **any explicit out-of-scope areas?** (defaults: legacy folders, generated code, integration tests).
Include at least one nearby-but-forbidden area so the constraint gate has something to catch.

### Batch 3b — Census probe (run this, do not ask about it)

Before finalizing scope, probe for **coverage assertions**: tests that enumerate a registry, table, or
DI collection exhaustively. These are invisible to code tracing — they live in test oracles that only
fail once the change is made, so no amount of "any other files?" reaches them. They also make a change
**INDIVISIBLE**: they go red the moment the thing they count changes, so every file they touch must
land in ONE iteration.

Run these against the test tree, substituting the identifier being extended:

```powershell
# exhaustive-oracle shapes
rg -n 'AreEqual\(\s*\d+\s*,.*\.(Count|Length)' <test-root>
rg -n 'CollectionAssert\.AreEqual|ToHashSet\(\)|\.Except\(' <test-root>
rg -n 'foreach.*(AllTypes|Registrations|GetServices)' <test-root>
```

For each hit, decide: is it **self-referential** (compares a thing against itself — harmless) or a
**hardcoded oracle** (compares against a literal or a hand-transcribed list — must be in scope)?

Worked example from a real run that added one step type to a large .NET solution:

| Source of truth | Sites it reports |
|---|---|
| The subsystem's own how-to skill | 4 |
| Tracing what the CODE touches | 12 |
| Tracing what the TEST SUITE asserts | **14** |

The two extra were pure census oracles: a hand-transcribed list of every accepted type string asserted
to match the registry EXACTLY (no extras), and an `Assert.AreEqual(20, executors.Count())` executor
count. Another test in the same suite compared `all.Length` against a filtered count of itself —
self-referential, correctly left out of scope.

Record the answer in the GOAL as an explicit **"indivisible set"** note, naming the assertion that
forces each file. The Orchestrator needs that to size iteration 1 (see `PROMPTS.md § 1` step 6).

### Batch 4 — Hard constraints
**Always** included (user may add, not remove):
- Never run `git commit`, `git push`, `git reset --hard`, `git rebase`, `git merge`, `git cherry-pick`
- Never touch files outside the in-scope list
- Never modify `bin/`, `obj/`, `node_modules/`, or generated code

Ask: **any additional hard rules?**

### Batch 5 — Model tiering
See `MODELS.md` for concrete slugs. Recommend from the task shape:

| Task shape | Executor tier | Why |
|---|---|---|
| Trivial rename, one-line fixes, mechanical regex edits | **fast** | Much cheaper, sufficient for known-pattern work |
| Multi-file coordinated edits, typed refactors | **balanced** | Understands cross-file context |
| Novel patterns, architectural change, ambiguous spec | **reasoning** | Defeats the savings, but needed when the Executor must reason |

Orchestrator: **reasoning** (recommended). Verifier: **same session as Orchestrator** (recommended)
or a separate fresh agent for stricter isolation.

### Batch 6 — Budget and safety caps
- **Max iterations?** [default 10]
- **Max wall-clock?** [default 2h] — enforced from `state.json.started_at`
- **Max consecutive Verifier failures?** [default 3]
- **Stop after N no-change iterations?** [default 2 — thrash detector]
- **Max cost (USD)?** [advisory only; recorded, not enforced — most CLIs expose no per-subagent cost]

### Batch 7 — Execution mode
- **Dry run** — run ONE iteration, then stop for review (**recommended for any first-time goal**)
- **Full run** — iterate until a stop condition fires
- **Plan-only** — generate GOAL/PLAN, run no Executor

### Preview and confirm
Render the GOAL.md content back to the user in a fenced block, then offer exactly three choices:
**Ready to run** / **Edit manually** (wait for save, re-confirm) / **Cancel**.

---

## Phase 2: RUN

### Step 1 — Initialize

Loop state lives in **`.loop\`** inside the target repo, never the repo root — it must not
pollute `git status` in a repo where the user commits by hand.

```powershell
pwsh -File scripts\Initialize-Loop.ps1 -RootPath <repo> -GoalPath <approved GOAL.md> `
     -CriteriaFile <criteria.json> -MaxIterations 10 -MaxDurationMinutes 120 `
     -MaxConsecutiveFailures 3 -MaxNoChangeIterations 2 `
     -OrchestratorModel <slug> -ExecutorModel <slug> -Mode dry-run -ExcludeLocally
```

**Use `-ExcludeLocally`, not `-AddGitIgnore`.** It writes `.loop/` to `.git\info\exclude` — local
only, invisible to `git status`, nothing to commit. `-AddGitIgnore` still works but appends to the
TRACKED `.gitignore`, which dirties a file the user then has to commit on the loop's behalf. In a repo
where the user hand-commits, that is the wrong default. Pass `-AddGitIgnore` only when the ignore rule
genuinely belongs to the whole team.

That single call creates `.loop\{GOAL.md, PLAN.md, PROGRESS.md, BASELINE.json, CRITERIA.json,
state.json}`, records `started_at`, preflights the criteria, and prints the permission list.

**Read the preflight output before continuing.** Exit 1 means at least one criterion already
passes at baseline — that criterion is a no-op, and the loop would declare victory having done
nothing. Fix the GOAL and re-initialize. This check costs a second and is the cheapest bug it is
possible to catch.

### Step 2 — Pre-flight the permission model (unattended runs)

An unattended loop stalls forever on the first approval prompt. Before a Full or overnight run,
show the user the command list `Initialize-Loop.ps1` printed and have them allow-list it (the
`permissions-yaml` skill covers the canonical file). Never suggest disabling permission checks.

Also check the CLI's rate-limit/quota display if it has one. If a window is ≥80%, warn:

> Your usage window is at N%. This loop may throttle or stall. Continue anyway? (y/n)

### Step 3 — Iterate

Per iteration N:

**a) Orchestrator turn** (this session, orchestrator model) → `PROMPTS.md § Orchestrator Turn`.
Rewrites `.loop\PLAN.md` with the single next action, its files-allowed list, its success
criterion, and its **expected diff shape** (gate 4 needs that operand).

**Prefer the next action that FLIPS a Done-when criterion** over one that does not. The queue's
declared order is a suggestion; reordering to front-load measurable criteria is free and pays twice —
progress becomes legible (3/5 → 4/5 → 5/5 early rather than all at the end), and if the budget runs out
you stop having banked criteria instead of having polished something no criterion measures. In one real
run, moving the test iterations ahead of UI polish was what de-risked a budget overrun.

**b) Checkpoint** — `New-Checkpoint.ps1 -RootPath <repo> -Iteration N`. No commit; records a
stash SHA in `state.json`. **Exit 1 means checkpointing is unavailable** (not a git repo, or a repo
with no commits — `git stash create` needs a HEAD). That is a warning, not an iteration failure:
continue, and note `Checkpoint: none` in the PROGRESS entry. Per-path rollback still works, because
`git restore` reads the index and `git clean` needs no history.

A **clean worktree** also returns exit 0 with "nothing to checkpoint" — there is no diff to stash. Also
harmless, but write the reason down rather than leaving the field ambiguous:
`Checkpoint: none (worktree clean; HEAD is the restore point)`. A bare `none` reads like a failure six
iterations later when you are working out what you can still restore to.

**c) Executor turn** — one subagent dispatch, fresh context, `model: <executor-model>`, prompt from
`PROMPTS.md § Executor Task Prompt`. Pass the explicit file list and forbid repo-wide search: the
Executor's read tokens are the bulk of loop cost, and an unscoped grep defeats the cheap tier.

**d) Verifier turn** (this session) → `PROMPTS.md § Verifier Turn`. Six gates, in order:

| # | Gate | How |
|---|---|---|
| 1 | Format | Executor response has the required fields |
| 2 | Deviation | `DEVIATIONS` is none, or informational-only (see taxonomy below) |
| 3 | Constraint | `Test-Constraints.ps1 -Allowed '<comma list>'` → exit 0 |
| 4 | Diff shape | `Get-ChangedFiles.ps1` vs PLAN's expected diff. Never trust the Executor's `LINES` |
| 5 | Success criterion | The iteration's command, exit 0 |
| 6 | Regression | `regression-command` if set; compare to prior state |

**e) On PASS — advance the baseline.** This is not optional:

```powershell
pwsh -File scripts\Get-Baseline.ps1 -RootPath <repo> -Iteration N -Quiet
```

The `-Allowed` list is per-iteration but the baseline is cumulative. Skip this and iteration N+1's
constraint gate reports iteration N's legitimate edits as out-of-scope violations, then rolls back
good work. **Never re-baseline after a FAIL** — that would launder the changes the gate exists to catch.

**f) Append the PROGRESS entry** (Verifier writes it; format in `PROMPTS.md`).

**g) Budget check** — `Test-Budget.ps1 -RootPath <repo> -Format json`. Exit 10 = stop, with the
reason slug. Exit 0 = continue to iteration N+1.

**h) If mode is dry-run** — stop after iteration 1 and report, whatever the gates said.

**i) When ALL criteria pass — sweep before declaring done.** "Criteria met" is not "task finished". The
criteria are a floor you chose in advance; they cannot see defects the run itself introduced. Before
the final report, check for staleness the work created — a comment, doc, count, or sample that the
change made wrong. One real run spent an extra iteration past 5/5 fixing a demo file whose description
said "all 20" when the file now held 21 entries; no criterion measured it, and shipping it would have
been shipping a known lie. If the sweep finds something, do one more iteration; if not, say so in the
report so the reader knows the sweep happened.

### Step 4 — Failure handling

1. **First failure** → retry the same iteration once, same model, sharpened prompt.
2. **Second failure** → auto-upgrade the Executor tier for THIS iteration only
   (fast → balanced, balanced → reasoning); reset to the configured tier next iteration.
3. **Third failure** → roll back, log, escalate to the user:

```powershell
pwsh -File scripts\Invoke-Rollback.ps1 -RootPath <repo> -Paths '<comma list>' -AllowClean
```

`-AllowClean` is what deletes the files the Executor CREATED; without it `git restore` leaves them
behind and the gate keeps flagging them. For a full worktree restore use `-UseLatestCheckpoint`.

**A constraint-gate violation (gate 3) is an immediate hard fail** — roll back the violating files
first, then count it as a failure for the ladder above.

**A `deviation-blocked` iteration does NOT enter that ladder.** It is a PLAN defect: the Executor was
given an impossible task. Do not retry it identically and do not upgrade the tier — that spends money
re-deriving a diagnosis you already have. Amend scope under the ratification protocol, then re-dispatch
with the corrected file list. Log it as `partial` in PROGRESS, not `fail`, so the consecutive-failure
counter stays clean.

### Step 5 — Final report

On any stop, write `.loop\LOOP_REPORT.md` from `PROMPTS.md § Final Report`, print it, and state
plainly that **no commits were made**. Do NOT `git commit`.

---

## Deviation taxonomy (gate 2)

The old rule ("DEVIATIONS must be none, else reject") rolled back iterations for merely *reporting*
something useful. Split them:

| Kind | Example | Verdict |
|---|---|---|
| **deviation-scope** | Touched a file not in files-allowed; took an approach the GOAL forbade | FAIL + rollback |
| **deviation-note** | "The adjacent middleware has the same problem; I left it alone" | PASS; log it and queue it as a future action |
| **deviation-blocked** | "I finished my task, but `Foo.cs` — which I am forbidden to touch — must also change for the suite to pass. I did not touch it." | Iteration FAILS, but do NOT roll back and do NOT retry identically. Amend scope via the ratification protocol below and re-dispatch. Counts as a PLAN defect, not an Executor failure |

An Executor that flags a note correctly is doing its job. Rewarding that with a rollback teaches
nothing and wastes an iteration.

`deviation-blocked` is the case the first two kinds cannot express: the Executor did its work
correctly, then discovered a FORBIDDEN file must also change for the success criterion to pass, and
correctly refused to touch it. Calling that a "note" understates it (the iteration cannot pass);
calling it "scope" is false (nothing was violated). The correct response is neither retry-identically
nor roll back — it is **amend scope and re-dispatch**. Do not spend the consecutive-failure budget on
it: the Executor's diagnosis was the useful output of the iteration.

---

## Scope ratification protocol

**GOAL.md is immutable as to INTENT. Its file enumeration MAY be amended under this protocol, and
never by the Executor.**

The old blanket rule ("never modify GOAL.md; if it is wrong, stop and re-interview") conflates two
different situations. Re-interviewing is right when the objective is wrong. It is wrong when the only
defect is a missing test-oracle file — restarting discards correct, suite-green work and hits the
identical wall next iteration. In one real run the scope list was wrong four times, every time because
of a coverage assertion no interview could have surfaced.

The Verifier MAY ratify an out-of-scope edit — recording it instead of rolling it back — when ALL of
these hold:

1. Gates 4, 5, and 6 PASS. The work is correct and the suite is green.
2. The Executor **self-reported** it as `deviation-scope` or `deviation-blocked`. A violation the
   Executor concealed is NEVER ratifiable — gate 3 exists to catch exactly that.
3. The file is the **same class** as a file already in scope (another test oracle, when a test oracle
   is already listed), OR the suite cannot go green without it.
4. The diff **ADDS** to the file. It does not weaken, loosen, delete, or comment out any assertion.
   Read the diff and confirm this by eye — a ratified edit that neuters a guard is the worst possible
   outcome of this protocol.
5. The amendment is written into `.loop\GOAL.md` inline AND into the PROGRESS entry, both marked
   `RATIFIED SCOPE AMENDMENT` with the reason.

Anything else: roll back and count a failure. In particular, **an Executor that changed production
code to make a test pass is never ratified.**

Record the count of ratified amendments in the final report. More than two or three means the
interview's scope discovery is broken — fix the census probe (Batch 3b), not the protocol.

---

## Resuming an interrupted loop

Overnight runs die: context compaction, a crash, a closed session. All state is on disk, so resume
rather than restart. `/myworkflow --resume <repo>`:

1. Read `.loop\{GOAL.md, PLAN.md, PROGRESS.md, state.json, CRITERIA.json}`
2. Highest `## Iteration N` in PROGRESS = last completed; resume at N+1
3. **Re-baseline first** (`-Iteration N`) — the tree has moved on since the last snapshot
4. Run `Test-Criteria.ps1` and `Test-Budget.ps1` before planning: the goal may already be met, or
   the wall-clock cap may already be blown
5. Continue the loop unchanged. Do NOT re-interview and do NOT edit GOAL.md

---

## Keeping context small

- **PROGRESS.md compression** — over ~50 lines, compress all but the last 3 entries to one line
  each (`## Iter N — pass — Files: X — Notes: Y`).
- Read only the last 20 PROGRESS entries per Orchestrator turn.
- Narrow `Get-Baseline.ps1 -Include` to the GOAL's in-scope globs on a large repo; the gate hashes
  what it enumerates, and directory pruning already skips `bin`/`obj`/`node_modules` at any depth.

---

## Anti-patterns (never do these)

- **Never let the Executor decide "done"** — that is the Verifier's job.
- **Never skip the Verifier** to save tokens — it is the entire safety layer.
- **Never reuse Executor context between iterations** — always a fresh subagent.
- **Never skip the post-pass re-baseline** — the gate turns against you.
- **Never re-baseline after a failure** — it launders unverified changes.
- **Never run parallel Executors** — they corrupt each other's files and the gate.
- **Never `git commit`** — the user commits manually. Even if a goal implies it.
- **Never change GOAL.md's INTENT during the loop** — the objective and Done-when criteria are
  immutable; if those are wrong, stop and re-interview. The file enumeration is amendable, but only by
  the Verifier and only under the scope ratification protocol above. Never by the Executor.
- **Never let an iteration run long** — if it drags, the action was too broad; split it.

## Chaining with other skills

The Orchestrator's PLAN can include a final action that invokes a code-review, simplification, or
verification skill once the core work passes.

## References

- Anthropic orchestrator-worker (source pattern): https://www.anthropic.com/engineering/multi-agent-research-system
- Anthropic verification loops: https://claude.com/blog/building-verification-loops-in-claude-code-with-skills
