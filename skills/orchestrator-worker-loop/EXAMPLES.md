# Reference Examples

Filled-out artifacts showing the exact expected format for each of the loop's memory files.

Model slugs here use placeholders (`<reasoning-slug>`, `<balanced-slug>`, `<fast-slug>`). Substitute
the concrete slug for your CLI — for Claude Code that is `opus` / `sonnet` / `haiku` (see `MODELS.md`).

All loop state lives in `<repo>\.loop\`.

---

## Example GOAL.md (mid-complexity typed refactor)

```markdown
---
goal-name: strongly-typed-options-migration
target-repo: {ReposRoot}\<repo>
target-branch: refactor/typed-options
created: 2026-08-02
estimated-iterations: 25
max-iterations: 25
max-duration: 3h
max-consecutive-failures: 3
max-no-change-iterations: 2
max-cost-usd: 15            # advisory only — not enforced (see MODELS.md)

orchestrator-worker: true
orchestrator-model: <reasoning-slug>   # e.g. opus
executor-model: <balanced-slug>        # e.g. sonnet
verifier-mode: same-session

rollback-command: pwsh -File scripts/Invoke-Rollback.ps1 -RootPath {{repo-root}} -Paths {{files_changed}} -AllowClean
regression-command: dotnet test --filter "FullyQualifiedName~TestAuto.Web" --no-build
---

# Goal: Migrate GetValue<T>() to strongly-typed options pattern

## Objective

Replace all `IConfiguration.GetValue<T>()` calls in `TestAuto.Web.Services` and
`TestAuto.Web.Controllers` with strongly-typed options classes registered via `services.Configure<T>()`.

## Done when

Each criterion is a command that exits 0 IF AND ONLY IF it is satisfied. Note the inverted wrappers:
`rg` exits 1 when it finds nothing, so an "absence" check written as "rg returns 0" can never pass.

- [ ] Zero `GetValue<` calls in Services:
      `rg -q 'GetValue<' src/TestAuto.Web/Services/; if ($LASTEXITCODE -eq 1) { exit 0 } else { exit 1 }`
- [ ] Zero `GetValue<` calls in Controllers:
      `rg -q 'GetValue<' src/TestAuto.Web/Controllers/; if ($LASTEXITCODE -eq 1) { exit 0 } else { exit 1 }`
- [ ] All existing tests pass:
      `dotnet test --filter "FullyQualifiedName~TestAuto.Web"`
- [ ] Build clean:
      `dotnet build --no-restore`

## Constraints (hard rules — do NOT violate)

- Never modify AppConfig.cs (frozen for backward compat)
- One options class per settings section — never merge sections
- Register options in Program.cs via services.Configure<T>() — not manually
- Never commit — user handles all git commits manually
- Never touch files under src/TestAuto.Web/Legacy/**

## Approach hints

- Work file-by-file, smallest first (fewer GetValue calls = simpler)
- After each file, run that file's tests before moving on
- If a change breaks >3 tests, revert and re-plan

## Files in scope

- src/TestAuto.Web/Services/**/*.cs
- src/TestAuto.Web/Controllers/**/*.cs
- src/TestAuto.Web/Program.cs (for registration)
- src/TestAuto.Web/Options/**/*.cs (new files created here)

## Files EXPLICITLY out of scope

- src/TestAuto.Web/Legacy/**
- **/*.g.cs, **/*.Designer.cs
- src/TestAuto.Web.Tests/** (read-only for verification)
```

### Matching criteria file (`criteria.json`)

Pass this to `Initialize-Loop.ps1 -CriteriaFile`. A file avoids the quoting and array-binding traps
of putting several shell commands on one command line.

```json
[
  { "label": "no GetValue< in Services",    "command": "rg -q 'GetValue<' src/TestAuto.Web/Services/; if ($LASTEXITCODE -eq 1) { exit 0 } else { exit 1 }" },
  { "label": "no GetValue< in Controllers", "command": "rg -q 'GetValue<' src/TestAuto.Web/Controllers/; if ($LASTEXITCODE -eq 1) { exit 0 } else { exit 1 }" },
  { "label": "tests pass",                  "command": "dotnet test --filter \"FullyQualifiedName~TestAuto.Web\"" },
  { "label": "build clean",                 "command": "dotnet build --no-restore" }
]
```

---

## Example PLAN.md (mid-loop, iteration 8)

```markdown
# Plan

## Strategy

Working through Services first, then Controllers. Currently on `EmailService.cs`, which has 3
GetValue calls for SMTP settings. Creating `SmtpOptions`. Two Services left after this, then 5
Controllers.

## Iteration 8 — planned
- **Task**: Extract SMTP-related GetValue<T>() calls from EmailService.cs into a new SmtpOptions
  class in src/TestAuto.Web/Options/SmtpOptions.cs. Register in Program.cs. Update EmailService to
  inject IOptions<SmtpOptions>.
- **Files allowed**: src/TestAuto.Web/Services/EmailService.cs,src/TestAuto.Web/Options/SmtpOptions.cs,src/TestAuto.Web/Program.cs
- **Files forbidden**: everything else, especially src/TestAuto.Web/Legacy/**, AppConfig.cs, and any
  *.g.cs / *.Designer.cs
- **Success criterion**: `rg -q 'GetValue<' src/TestAuto.Web/Services/EmailService.cs; if ($LASTEXITCODE -eq 1) { exit 0 } else { exit 1 }`
- **Expected diff**: +40 -10 (approximate)
- **Executor model**: <balanced-slug>
- **Constraints (subset from GOAL)**:
  - Never modify AppConfig.cs
  - One options class per settings section
  - Register in Program.cs via services.Configure<T>()

## Next actions (queue)
- [ ] Iteration 9: SmsService.cs (2 GetValue calls, TwilioOptions)
- [ ] Iteration 10: NotificationService.cs (4 GetValue calls, split into two options classes)
- [ ] Iteration 11-15: Controllers folder
- [ ] From iteration 12's deviation-note: AuthMiddleware.cs still reads Auth settings directly
```

Note the **Files allowed** line is a single comma-separated token — the form the gate scripts expect
(`-Allowed 'a,b,c'`).

---

## Example PROGRESS.md entry (successful iteration)

```markdown
## Iteration 8 — 2026-08-02 10:15

**Result**: pass
**Executor model**: <balanced-slug>
**Estimated cost**: $0.24
**Files changed**: src/TestAuto.Web/Services/EmailService.cs, src/TestAuto.Web/Options/SmtpOptions.cs, src/TestAuto.Web/Program.cs
**Diff**: +47 -14 (expected +40 -10)
**Checkpoint**: 9c1f2ab7d4e5f6a8b9c0d1e2f3a4b5c6d7e8f9a0
**Verifier gates**:
  - Format: pass
  - Deviations: none
  - Constraint (out-of-scope): pass (Test-Constraints.ps1 exit 0, baseline iteration 7)
  - Diff-shape: pass (+47 -14 vs expected +40 -10 — the new file accounts for the extra adds)
  - Success criterion: pass (rg found nothing, wrapper exited 0)
  - Regression: pass (EmailServiceTests: 4/4 still green)
**Baseline advanced**: yes (iteration 8)
**Blockers**: none
**Rollback**: no
**Next hint for Orchestrator**: Same pattern applies to SmsService.cs — should be similar work
```

`Files changed` came from `Get-ChangedFiles.ps1`, which counted the NEW `SmtpOptions.cs` — bare
`git diff --numstat` would have reported +0 -0 for it.

---

## Example PROGRESS.md entry (failed iteration — scope violation)

```markdown
## Iteration 12 — 2026-08-02 10:47

**Result**: fail
**Executor model**: <balanced-slug>
**Estimated cost**: $0.31
**Files changed**: src/TestAuto.Web/Controllers/AuthController.cs, src/TestAuto.Web/Options/AuthOptions.cs, src/TestAuto.Web/Middleware/AuthMiddleware.cs
**Diff**: +38 -12 (expected +30 -8)
**Checkpoint**: 4b7c9d1e2f3a5b6c8d9e0f1a2b3c4d5e6f7a8b9c
**Verifier gates**:
  - Format: pass
  - Deviations: scope-fail — Executor reported `deviation-scope:` for editing AuthMiddleware.cs, which was not in files-allowed
  - Constraint (out-of-scope): FAIL — Test-Constraints.ps1 exit 1, violation: src/TestAuto.Web/Middleware/AuthMiddleware.cs
  - Diff-shape: n-a (skipped after the constraint hard fail)
  - Success criterion: n-a
  - Regression: n-a
**Baseline advanced**: no — iteration failed (advancing here would launder the unverified middleware edit)
**Blockers**: Executor assumed the middleware refactor belonged with the controller. Defensible, but out of scope for this iteration.
**Rollback**: yes — `Invoke-Rollback.ps1 -Paths 'src/TestAuto.Web/Middleware/AuthMiddleware.cs' -AllowClean` restored the tracked edit; no new files to clean
**Next hint for Orchestrator**: Retry with an explicit "middleware is out of scope" line, OR split middleware into its own queued iteration
```

---

## Example Executor response (well-formed)

```
ITERATION: 8
FILES CHANGED: src/TestAuto.Web/Services/EmailService.cs, src/TestAuto.Web/Options/SmtpOptions.cs, src/TestAuto.Web/Program.cs
LINES: +47 -14
SUMMARY: Extracted SMTP GetValue<T>() calls into SmtpOptions, registered in Program.cs, updated EmailService to inject IOptions<SmtpOptions>.
DEVIATIONS: none
VERIFIER HINT: The GetValue calls used inconsistent key casing ("smtp:host" vs "Smtp:Host"); I normalized to PascalCase to match adjacent files.
```

---

## Example Executor response (deviation-note — PASSES)

The good kind of deviation: the Executor noticed adjacent work and correctly left it alone. Gate 2
passes it, logs the note, and the Orchestrator queues the follow-up. Rolling this back would punish
the Executor for being useful.

```
ITERATION: 12
FILES CHANGED: src/TestAuto.Web/Controllers/AuthController.cs, src/TestAuto.Web/Options/AuthOptions.cs, src/TestAuto.Web/Program.cs
LINES: +32 -8
SUMMARY: Extracted GetValue<T>() calls from AuthController into AuthOptions and registered it in Program.cs.
DEVIATIONS: deviation-note: AuthMiddleware.cs reads the same "Auth" section keys via IConfiguration. It is out of scope, so I did NOT modify it. Flagging that Auth settings are now split between AuthOptions injection (controller) and manual reads (middleware). Recommend queueing AuthMiddleware.cs.
VERIFIER HINT: none
```

## Example Executor response (deviation-scope — FAILS)

```
ITERATION: 12
FILES CHANGED: src/TestAuto.Web/Controllers/AuthController.cs, src/TestAuto.Web/Options/AuthOptions.cs, src/TestAuto.Web/Middleware/AuthMiddleware.cs
LINES: +38 -12
SUMMARY: Extracted GetValue<T>() calls from AuthController and also migrated AuthMiddleware for consistency.
DEVIATIONS: deviation-scope: I edited AuthMiddleware.cs, which was not in files-allowed. It shared the "Auth" keys and I judged the split confusing.
VERIFIER HINT: none
```

---

## Example LOOP_REPORT.md (successful completion)

```markdown
# Loop Complete

**Stop reason**: all-done-when-passed

## Summary
- **Iterations**: 22
- **Elapsed**: 1h48m
- **Estimated total cost**: $6.83 (from per-iteration telemetry; treat as an estimate)
- **Files changed**: 18 (14 Services/Controllers modified, 4 new Options classes)
- **Verifier failures**: 3
- **Rollbacks**: 1
- **Checkpoints**: 22 (restore any with `git stash apply <sha>` — see .loop/state.json)

## Done-when criteria status
- [x] No GetValue< in Services — baseline exit 1 -> latest exit 0
- [x] No GetValue< in Controllers — baseline exit 1 -> latest exit 0
- [x] All tests pass — baseline exit 0 -> latest exit 0 (127 tests green)
- [x] Build clean — baseline exit 0 -> latest exit 0

## What was accomplished
- Extracted 41 GetValue<T>() calls into 4 strongly-typed options classes (SmtpOptions, TwilioOptions, AuthOptions, DatabaseOptions)
- Registered all new options in Program.cs via services.Configure<T>()
- Updated 14 Services/Controllers to use IOptions<T> injection
- Preserved behaviour throughout (regression gate green every iteration)
- One iteration rolled back after a scope violation, then retried successfully

## What remains
- Nothing — all criteria met.
- AuthMiddleware.cs still reads config directly (raised as a deviation-note in iteration 12 and
  correctly kept out of scope). Worth a follow-up loop.

## Files ready for human review
- 18 modified files (see `git status --porcelain -uall`)
- 4 new files in src/TestAuto.Web/Options/
- **No commits made** — you commit manually per policy.

## Recommended follow-up
Review the diff, run the full integration suite, and commit. For the middleware, create a new goal
targeting src/TestAuto.Web/Middleware/** with the same pattern and the same criteria shape.
```

Note the criteria table shows **baseline exit -> latest exit**. A criterion whose baseline already
passed would have been caught by `Initialize-Loop.ps1`'s preflight as a no-op before the run started.
