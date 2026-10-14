---
name: inherit-legacy-style
description: >
  Extracts a codebase's implicit conventions into an enforceable
  .ai-style-rules.md so AI-generated code stops drifting toward mainstream
  idioms the project does not use. Scans four meta-architecture dimensions,
  auto-suppresses weak conflicts, and resolves real ones one question at a time.
  Use when onboarding AI onto an existing codebase, when generated code keeps
  fighting house conventions, when parity with existing patterns matters more
  than novelty, or to refresh the rules after a large change.
---

# Inherit Legacy Style

Prevents style drift — the model imposing its pretrained defaults on a codebase
that already made different, deliberate choices.

Aligns **meta-architecture only**: where things live, how they are named, how
errors flow. It never judges syntax, tooling, or stack quality.

## When to Activate

- Onboarding an agent onto an existing codebase
- Generated code keeps "improving" conventions that were intentional
- Parity with existing patterns matters more than novelty
- After a large change, to refresh the rules

## Step 0 — Auto-detect mode

Check for `.ai-style-rules.md` at the project root.

| File exists? | Mode |
|---|---|
| No | **Branch A — first-time full scan** |
| Yes | **Branch B — incremental sniff** |

Announce the mode in one line. Never ask the user to choose.

## Branch A — First-time full scan

### A1. Measure scale, pick a tier

```powershell
$exts = '*.cs','*.razor','*.ps1','*.sql'
(Get-ChildItem -Path . -Recurse -Include $exts -File |
    Where-Object { $_.FullName -notmatch '[/\\](obj|bin|node_modules|\.git|packages|TestResults)[/\\]' }
).Count
```

| Tier | Source files | Strategy |
|---|---|---|
| Small | ≲ 50 | Close-read every file |
| Medium | 50–500 | Infrastructure layer read in full; business layer sampled 2–3 per dimension |
| Large | ≳ 500 | Strict sampling with a budget cap; summarise first, then targeted reads |

**Do not skip this step.** Sampling a 30-file project starves it; full-reading a
5,000-file repo blows the budget.

### A2. Scan four dimensions

**1. File anatomy**

- `using` ordering and grouping; `global using` usage
- File-scoped vs block namespaces
- Declaration order within a type (fields → ctor → public → private)
- `.razor` / `.razor.cs` split conventions — see `blazor-code-behind`
- One type per file, or grouped?

**2. State and control flow**

- Async method naming and whether the `Async` suffix is universal
- `CancellationToken` threading — always, sometimes, never?
- Nullable reference types on or off; how null is expressed
- `Result<T>` vs exceptions for expected failures — see `result-pattern`
- Guard-clause style vs nested `if`

**3. Infrastructure placement**

- Where DI registration lives — see `dotnet-service-registration`
- Where extension methods live — see `record-mapper-extension-methods`
- Where constants and magic values live — see `dotnet-entity-constants`
- Configuration access: `IOptions<T>`, direct `IConfiguration`, or a typed wrapper
- Data access shape — see `dotnet-sql-data-access`

**4. Error handling and logging**

- Throw, return `Result`, or log-and-continue
- Structured logging shape and required tags — see `dotnet-logging-schema`,
  `testauto-log-tags`
- What counts as expected vs exceptional

### A3. Signal-threshold noise reduction

Do not interrupt the human for weak signals.

| Signal | Rule |
|---|---|
| **Weak** — minority < 5% **and** count < 10 | Auto-suppress. Majority wins; minority goes to DONTs. |
| **Strong** — near-even split, or a semantic fork on a core dimension | Escalate to the user. |
| **Small-project exception** — ≲ 50 files | "3 vs 2" is not a majority. Escalate. |

An 843-vs-8 naming split resolves itself. Asking about it wastes the one thing
this skill is spending: the user's attention.

### A4. Grilling protocol — one conflict at a time

For each strong-signal conflict, ask exactly **one** question with four options:

```text
Evidence: <pathA> uses style X (n=41); <pathB> uses style Y (n=38)
Risk:     mixing both fractures the convention
Choose:   1) follow X   2) follow Y   3) this is deliberate evolution, record both
          4) I have a different rule
```

Wait for the answer, then move to the next. **Never stack questions.**

### A5. Generate `.ai-style-rules.md`

Three mandatory sections:

- **`[Golden Files]`** — real paths, each annotated with what it demonstrates.
  These are the exemplars future work copies. Never invent a path.
- **`[Naming & State-Control Rules]`** — concrete and checkable. "Async methods
  end in `Async`" is a rule; "use good names" is not.
- **`[DONTs]`** — anti-patterns that must not propagate, including the suppressed
  minority styles from A3.

The header records the scale tier and the current commit hash, so Branch B can
diff from a known point.

### A6. Install the soft hook

Add a reference to `.ai-style-rules.md` from the project `CLAUDE.md` so it loads
every session.

**Soft hook only.** Do not offer a blocking `PreToolUse` hook: that slot is
already held by GateGuard, and stacking two blocking gates on `Edit|Write` makes
routine work miserable. If mechanical enforcement is wanted later, the right
move is to extend GateGuard's fact list, not add a second gate.

## Branch B — Incremental sniff

1. Read the existing `.ai-style-rules.md` and its recorded commit hash.
2. `git diff <hash> HEAD --stat` to find the delta. For very large diffs, work
   from the summary and sample only the largest changes.
3. Compare new code against the recorded rules.
4. Run any conflicts through the same A4 grilling protocol.
5. **Append** an evolution log entry — never overwrite existing rules:

```markdown
### [2026-07-25] Style Evolution Log
- New: <rule> (evidence: <paths>)
- Changed: <old> -> <new>, per user decision
```

## Per-turn enforcement

Once `.ai-style-rules.md` is loaded via `CLAUDE.md`, every code-writing task
should open by naming the exemplar being followed and the DONTs being avoided.
One line, not a ceremony.

## Anti-Patterns

- Skipping the scale measurement
- Stacking multiple conflict questions
- Overwriting old rules in Branch B instead of appending
- Judging syntax quality or the tech stack — out of scope by design
- Copying bugs out of an exemplar file. Reuse the structure; flag the defect.
- Inventing a golden-file path. Every path must exist.

## Related Skills

- `blazor-code-behind`, `dotnet-project-structure` — the conventions this
  discovers are often already documented there; check before asking the user
- `result-pattern`, `dotnet-logging-schema` — dimension 2 and 4 references
- `improve-codebase-architecture` — the opposite intent. This preserves the
  existing style; that one changes it. Do not run both in one pass.

---

Adapted from ECC (MIT, © 2026 Affaan Mustafa) — <https://github.com/affaan-m/ECC>
