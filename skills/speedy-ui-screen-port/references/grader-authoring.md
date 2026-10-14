
Repo: speedmerchants (paths below are repo-relative)

# Authoring a UI row's grader

Every UI row closes on a PowerShell grader in `.loop\criteria\`,
named `u9-<n>-<name>.ps1` / `u10-…` / `u11-…` where **`<n>` is the v3 row number** (9.13 →
`u9-13-value-editor.ps1`, 10.9 → `u10-9-exec-dashboard.ps1`) — never the loop row (52.01). Kit rows
carry no number (`u9-controls-kit.ps1`, `u10-ops-kit.ps1`); UoW-10's backend waves are `u10-w1-…`.
Use the name GOAL.md already gives the criterion.

A grader is authored, registered, **verified RED at baseline for a stated reason** and **proven able
to go GREEN** before the Executor is dispatched.

## The self-test, and why RED at baseline is only half of it

A grader that has only ever been run against absence proves it can say "no"; it has not proven it
can say "yes", and a clause that can never be green blocks a row that is genuinely finished — or,
worse, makes the Executor shape the product to the clause. Row 52.01's grader shipped with three
such clauses and was only found out by running its self-test (2026-09-09).

Every grader gets a sibling `<grader>-selftest.ps1`, copied from `{ScratchRoot}\u9-13-selftest.ps1`, that:

1. parses the grader (`[Parser]::ParseFile`) — two registered graders once shipped as parse errors;
2. builds a **wrong stub** (the artefacts exist and violate each clause a different way) and a
   **correct stub** (every clause satisfied, in the spellings a real implementer would choose: a
   verbatim `@"C:\Temp"`, a suite whose file name is not the obvious one, a comment that NAMES a <!-- example-path -->
   thing the product does not render);
3. runs the grader with `-StaticOnly` (no `dotnet`, no `docker`) against the live tree, the wrong
   stub and the correct stub, and asserts exit **1 / 1 / 0**;
4. is re-run after **every** edit of the grader. The Executor never edits the grader; the Verifier
   does, and runs the self-test before recording the fix.

Read the baseline output clause by clause and state, in the grader's header, which clauses are red
and why, and which are green by design. A clause that is green at baseline when it should be red is
vacuous: 52.01's first G2 accepted `.Trim()`, `Guid.TryParse` and `builder.Build()` anywhere in
`Tests.Unit` (19 / 7 / 29 files already matched), so only its path literal was doing any work.

**The limit of the self-test:** it validates a clause's MECHANICS, not its OPERANDS. The correct stub
is written from the same belief that produced the clause, so a wrong type name or member name passes
the stub and fails every real Executor. Verify every operand against the declaration
(`grep -rn 'class X\|interface X' src`) before writing the clause — the `.c` skill's own first draft
named an `IWorkloadStore` that does not exist.

## Three views of a file, one lexer pass

Every structural grader reads source in three views, produced by ONE tokenizer pass (see `Lex` in
`{ScratchRoot}\u9-13-value-editor.ps1`):

| View | Comments | String literals | Ask it |
| --- | --- | --- | --- |
| raw | kept | kept | nothing — it is the file |
| text | removed | **kept** | "does the product carry this LABEL / this NAME as a literal?" |
| code | removed | blanked to `""` | "is this a declaration / a call / a resolution?" |

One pass matters: stripping `//` first and blanking strings second eats a URL literal
(`"https://…"`) at its `//` and desynchronises every string after it. The lexer is one alternation
tried left to right, so a literal is consumed whole before its `//` can read as a comment.

## Clause shapes that fail — do not write these

Twenty-one defects measured across the campaign's graders, plus the three the 52.01 self-test found:

| Shape | Why it fails |
| --- | --- |
| adjacent tokens | `-match 'Foo.*Bar'` on one line breaks the moment a formatter wraps the call |
| banned substrings | forbids a string that legitimately appears in a comment or a test name |
| exact signatures | one added optional parameter turns a correct implementation red |
| lazy-brace slices | `(?s)class Foo.*?}` stops at the first inner brace, not the class's |
| under-derived censuses | a count nobody derived from the source; it drifts and nobody notices |
| two clauses that cannot both be green | mutually exclusive assertions, so the row is unclosable |
| a call that is a string literal | blank string literals **before** asking "is this a call?" |
| **a literal matched in one spelling** | `C:\\\\Temp` matches `"C:\\Temp"` and not `@"C:\Temp"`; match the STRING (`C:\\{1,2}Temp`), not one escaping of it <!-- example-path --> |
| **a subject found by file name** | `$_.Name -match 'Value'` misses `CompositionEditorTests.cs`; find the suite by what it RENDERS (`Render<X>` for an `X` declared where the plan puts it) |
| **a whole-tree word census for a visible label** | five of six tab words already occur in `src\`; scope to ONE file under `src\Web\Components` and match a literal or element text (`"Literal"` or `>Literal<`) in the text view |
| **a floor stated in prose** | "six named behaviours" with no token a grader can grep is a floor nobody can grade; [[speedy-ui-bunit]] now names the six tokens |

`IndexOf`-based ordering clauses have their own blind spot: a call split across lines reads as
absent and the clause passes silently — fail when any operand is −1.

## What a UI grader asserts

Per leg, and each clause names the artefact it is about:

| Leg | Clauses |
| --- | --- |
| `.a` port | the `data-speedy-<screen>` marker exists on exactly one element; each claimed figure has a `data-*`; every class token is defined in the sheets `App.razor` links (derived from `App.razor`, never a hard-coded list); no `<style>`, `style=` or `.razor.css`, and no stylesheet under `src\Web` beyond the vendored donor sheets and `speedy-crewchief.css`; that sheet carries exactly one `@media` (prefers-reduced-motion); the frozen names still render |
| `.b` bUnit | the six behaviours are present **by their canonical tokens** as `void <name>(` declarations in the suite bound to this screen's marker ([[speedy-ui-bunit]]); the suite derives from `MonitorComponentTestBase`; `dotnet test tests/Tests.Web` green |
| `.c` composed-graph | a resolution construct (`Get[Required]Service<IPort>` / `GetServices<IPort>` / `typeof(IPort)` in a census) exists for each port the plan's §1.1 row cites, in the code view; `dotnet test --filter CompositionResolutionTests` green |
| `.d` Playwright | the spec file exists, contains no `not written yet` throw, `routes.json` carries the route, `npm run gate` exit 0, the smoke set green at `--retries=0` |

A forbidding clause (no fork, no padding route) is green at baseline by design — say so in the
header, and write it against a construct that survives later rows: "no `@page` under
`src\Web\Components\Controls`" survives row 52.03 adding a page; "routes.json has three lines" does not.

## Vacuity floors

`e2e-ui-smoke.ps1` carries a spec-count floor that is a **ratchet**: 2 (E1) then 12 (E2/E3) then
raised when smoke tests are added, **never lowered**. A row that adds a screen raises the floor in
the same change. A row that cannot raise it says why in its report.

Two known grader defects to not re-create:

1. **Counting tags from bare `--list`.** Playwright prints no tags there. It counted 0, and an
   Executor padded two test *titles* to satisfy it. Count from `--list --grep @regression`.
2. **Reading a decision document through a dead path.** Absent read as "first run". Absolute paths in
   a grader are repointed when a document moves, in the same change.

## Registration — three files, and which one each tool reads

| File | What it is | Who reads it |
| --- | --- | --- |
| `.loop\criteria-uow9a.json` | **the registry**: every criterion as `{label, command}` (81 entries on 09-09). `Close-Plan.py`'s `next_criterion` appends here | `Invoke-CriteriaSweep.ps1` — "registered" means present here, and a registered criterion is expected green once it has ever passed |
| `.loop\GOAL.md` Done-when table | the human-readable list per unit | the Verifier, the handoff |
| `.loop\CRITERIA.json` | the preflight snapshot with recorded baselines (23 entries, last preflighted 09-05) | `Test-Criteria.ps1` (the loop skill's script) and the sweep's ever-green seeding |

Register in the first two at dispatch; re-preflight `CRITERIA.json` at the next quiet moment so the
sweep seeds the new criterion. A criterion that exists only in the PLAN is a criterion nothing runs.

**A unit's GOAL criterion is authored and registered in the iteration that CLOSES the unit, not
later.**

## The gate 6 gap, and the tool that closes it

Gate 6 runs the test suites and never the earlier criteria. A row can move code and leave a prior
grader red while every test stays green — two rows already did, and a 09-08 sweep found seven rotted
criteria. When a UI row touches shared markup (`_Imports.razor`, `speedy-crewchief.css`, `App.razor`,
`Routes.razor`, the Controls kit), or any file an earlier grader names, run at close:

```powershell
pwsh -NoProfile -File .loop\tools\Invoke-CriteriaSweep.ps1 -Filter 'u9-*'
```

It reports **REGRESSED** (exit 1) for a criterion ever seen green that is red now, and **OPEN** for
one never yet green. `-CheckDue` exits 10 when the daily unfiltered sweep is owed (Gene 09-08 16:01:
once a day, 30–35 minutes) — start it in the background and continue.
