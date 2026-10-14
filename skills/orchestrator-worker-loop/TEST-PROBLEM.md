# Test Problem — Verify the Skill Works

A tiny, safe, mechanical task that exercises every part of the loop: setup, criteria preflight, all
six Verifier gates, baseline advancement, multiple iterations, PROGRESS appending, and a stop
condition. Runs entirely in `{ScratchRoot}\loop-test\` — nothing production is touched.

## Task shape

**Normalize a set of markdown files** by applying three deterministic transformations to each:

1. Ensure frontmatter includes `updated: 2026-08-02`
2. Convert bare `TODO:` markers to bold `**TODO:**`
3. Convert bare `NOTE:` markers to bold `**NOTE:**`

## Why this problem

| Test aspect | How this problem exercises it |
|---|---|
| Interview flow | Walk Batches 1-7 with realistic answers, OR point the skill at the pre-filled GOAL.md |
| Criteria preflight | All criteria must FAIL at baseline. If any passes, the preflight says so and the goal is wrong |
| Model tiering | Pure regex substitution → **fast**-tier Executor is safe and proves the tier saves cost |
| Multi-iteration | 3 files × 3 transformations = 3-9 iterations depending on how the Orchestrator splits |
| **Baseline advancement** | Iteration 2+ MUST NOT flag iteration 1's edits. The single most important thing this test proves |
| Gate 1 (format) | Executor returns the structured response |
| Gate 2 (deviations) | `file2.md` has `TODO:` inside a fenced code block — a good Executor raises a `deviation-note`, which must PASS, not roll back |
| Gate 3 (constraint) | `out-of-scope.md` contains `TODO:` and must never be touched |
| Gate 4 (diff-shape) | Small deterministic diffs; `Get-ChangedFiles.ps1` also proves new files are counted |
| Gate 5 (success criterion) | Three exact commands, each exiting 0 only when satisfied |
| Gate 6 (regression) | The GOAL's `regression-command` asserts the decoy file stays unmodified — an invariant, checked every iteration (it is deliberately NOT a Done-when criterion, since it is already true at baseline) |
| Stop condition | Loop stops when all criteria pass (usually iteration 3-9) |
| Thrash detector | If the Orchestrator spins without changing files, `Test-Budget.ps1` stops it after 2 such iterations |

## Setup (run once)

```powershell
pwsh -File {ScratchRoot}\loop-test-setup.ps1
```

Creates `{ScratchRoot}\loop-test\` with `docs\file1.md`, `file2.md`, `file3.md` (need normalizing),
`docs\out-of-scope.md` (decoy — must not be touched), `GOAL.md` copied from the vault, and
`criteria.json`. It `git init`s the folder and stages `docs\` — **no commit is made anywhere in this
test, by the setup script or the loop.**

**Why staging alone is enough.** `git restore -- <path>` reads the **index** by default, so
staged-but-uncommitted content is a perfectly good rollback source; `git clean -f -- <path>` and
`git status --porcelain` need no history either. The one thing a commit-less repo cannot do is
`git stash create`, so:

- `New-Checkpoint.ps1` detects the missing HEAD and **skips with exit 1** (a warning, not a failure).
  The loop continues; per-path rollback still works.
- `Get-ChangedFiles.ps1` falls back to `BASELINE.json` hashes and reports `"mode": "baseline"`.
  Without a HEAD, git would report every *staged* file as a brand-new addition, so gate 4 would see
  the entire repo as this iteration's diff.
- `Invoke-Rollback.ps1 -Paths ... -AllowClean` works normally. Only `-UseLatestCheckpoint` is
  unavailable (exit 2 with a clear message).

If you want the checkpoint path exercised too, make one commit in the scratch repo yourself — but it
is not required for any other gate.

## Initialize the loop

```powershell
pwsh -File <skill>\scripts\Initialize-Loop.ps1 -RootPath {ScratchRoot}\loop-test `
     -CriteriaFile {ScratchRoot}\loop-test\criteria.json `
     -MaxIterations 9 -MaxDurationMinutes 30 -MaxConsecutiveFailures 2 `
     -OrchestratorModel opus -ExecutorModel haiku -Mode dry-run -ExcludeLocally
```

Expected: `.loop\` created with GOAL/PLAN/PROGRESS/BASELINE/CRITERIA/state, and a preflight showing
**every criterion FAILING** plus "All criteria currently FAIL at baseline". Exit code 0.

If the preflight reports a criterion already passing, stop — that criterion is a no-op and the loop
would declare victory having done nothing.

## Running the loop

1. From `{ScratchRoot}\loop-test\`, prompt: **"Run the orchestrator-worker loop against the GOAL.md in this repo"**
2. The skill should read the GOAL and skip the interview. If it doesn't, prompt:
   **"Skip the interview — GOAL.md is already filled in. Use its frontmatter and start Phase 2."**
3. Confirm the GOAL summary.
4. Observe iteration 1 (dry-run stops there by default).
5. If iteration 1 looks right, approve the full run.

## Expected outcome

**Success signals:**

- `(Select-String -Path {ScratchRoot}\loop-test\docs\file*.md -Pattern 'updated: 2026-08-02' | Measure-Object).Count` = **3**
- Prose (outside fenced code blocks) has zero bare `TODO:` / `NOTE:` — check with `{ScratchRoot}\loop-test-verify.ps1`, which is fence-aware
- `docs\out-of-scope.md` **unchanged** (`git status --porcelain docs/out-of-scope.md` is empty)
- `file2.md`'s fenced `// TODO:` and `// NOTE:` comments are **still literal**
- `.loop\PROGRESS.md` has one entry per iteration, each passing one carrying
  `**Baseline advanced**: yes (iteration N)`
- `.loop\BASELINE.json` `iteration` equals the last passing iteration — not 0
- `.loop\LOOP_REPORT.md` exists with `Stop reason: all-done-when-passed`
- `git rev-list --all --count` returns **0** — no commit was ever made
- PROGRESS entries show `**Checkpoint**: none` (expected: no HEAD, so checkpointing skipped)

**Failure modes to watch for:**

| Symptom | What is broken |
|---|---|
| Iteration 2+ fails gate 3 citing iteration 1's file | Baseline is not being advanced after passes (`Get-Baseline.ps1 -Iteration N`) |
| Gate 3 fails citing `bin/`, `obj/`, `.loop/` or similar | Exclude handling regressed (should be pruned at any depth) |
| Executor edited `out-of-scope.md` | Constraint gate broken |
| A `deviation-note` about the code block caused a rollback | Gate 2 taxonomy regressed — notes must pass |
| Loop "completes" instantly with nothing changed | A criterion already passed at baseline; preflight was skipped or ignored |
| Loop stops after 1 iteration without checking criteria | Verifier isn't running gate 5, or dry-run mode wasn't lifted |
| Loop never stops | Stop-condition detection broken — `Test-Budget.ps1` should exit 10 |
| A gate treated a script error (exit 2) as a pass | Verifier isn't distinguishing exit 1 from exit 2 |
| Gate 4 lists every file in the repo as changed | `Get-ChangedFiles.ps1` used git without a HEAD instead of falling back to baseline hashes |
| The loop halts because checkpointing "failed" | A skipped checkpoint (exit 1) is being treated as fatal — it isn't |
| **Any commit at all** (`git rev-list --all --count` > 0) | Policy violation — investigate immediately |

## Independent verifier

`{ScratchRoot}\loop-test-verify.ps1` runs the same checks the loop's Verifier should have run. It is
fence-aware: prose TODO/NOTE count separately from code-block TODO/NOTE, and `file2.md`'s fenced
markers are expected to remain literal.

## After the test

```powershell
Copy-Item {ScratchRoot}\loop-test\.loop\PROGRESS.md "{VaultDocsRoot}\Goals\goal-loop-verification-test-results.md"
Copy-Item {ScratchRoot}\loop-test\.loop\LOOP_REPORT.md "{VaultDocsRoot}\Goals\goal-loop-verification-test-report.md"
```

If everything worked, the skill is validated — start using it on real work. If something failed,
keep `.loop\PROGRESS.md` and `.loop\LOOP_REPORT.md`, identify which gate or step failed, and fix
`SKILL.md` / `PROMPTS.md` / the script involved.

## Script-level smoke test (no models, no tokens)

To check the gate tooling alone — faster than a full loop, and it isolates plumbing bugs from model
behaviour:

```powershell
$s = '<skill>\scripts'
$d = "$env:TEMP\loop-smoke"
Remove-Item $d -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory "$d\docs" -Force | Out-Null
New-Item -ItemType Directory "$d\src\App\bin\Debug" -Force | Out-Null
Set-Content "$d\docs\a.md" 'a'; Set-Content "$d\docs\b.md" 'b'
Set-Content "$d\src\App\bin\Debug\app.dll" 'bin1'
Set-Content "$d\GOAL.md" "---`ngoal-name: smoke`n---"

pwsh -File "$s\Initialize-Loop.ps1" -RootPath $d -SkipPreflight        # baseline counts 2 files, not 3
Set-Content "$d\docs\a.md" 'a v2'
Set-Content "$d\src\App\bin\Debug\app.dll" 'bin2'                      # a "rebuild" — must NOT trip the gate
pwsh -File "$s\Test-Constraints.ps1" -RootPath $d -Allowed 'docs/a.md' # expect exit 0
pwsh -File "$s\Get-Baseline.ps1" -RootPath $d -Iteration 1 -Quiet      # advance
Set-Content "$d\docs\b.md" 'b v2'
pwsh -File "$s\Test-Constraints.ps1" -RootPath $d -Allowed 'docs/b.md' # expect exit 0 — NOT a complaint about a.md
Set-Content "$d\src\x.cs" 'oops'
pwsh -File "$s\Test-Constraints.ps1" -RootPath $d -Allowed 'docs/b.md' # expect exit 1, violation src/x.cs
```

The second-to-last command is the regression test for the bug that made every multi-iteration loop
self-destruct: without baseline advancement it reports `docs/a.md` as an out-of-scope violation.
