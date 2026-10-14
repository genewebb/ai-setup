---
name: feedback-loop-practices-that-caught-defects
description: "Four orchestrator-worker loop practices proven across UoW-8b/8c — census rule, executor-never-edits-its-grader, mandatory falsification, verify-the-premise-before-dispatch"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 34c06f04-ada7-44f8-a3e4-66dc2a3c5365
  modified: 2026-09-07T04:25:52.176Z
---

Four practices earned across 11 loop iterations (UoW-8b + 8c, 2026-09-01/02). Each caught real defects,
and **in most cases the defect was the operator's, not the Executor's.**

**1. When a census test is in scope, the file it censuses is in scope too.** A *census* is any
assertion that counts against a literal, encodes a count in its NAME, constructs a type positionally,
or implements the port being widened. UoW-8b's file list was one census short in **three consecutive
iterations, each a different shape**: `expectedHostedServices = 3`; `MonitorHarness` building
`MonitorQuery` positionally; `StubRampScheduleStore : IRampScheduleStore`. Naming every known census up
front in UoW-8c produced **zero scope amendments** against the previous unit's three.
A census hides in a NAME — `RegistersAllThreeHostedServices` is invisible to a grep for a number.

**2. The Executor must never edit the file that grades it.** Every operator defect surfaced because
its only options were comply or report a reproduction: a GOAL premise that was false, a file list one
short, a criterion naming a path that did not exist, a "fix" that was impossible as written.

**3. Require the Executor to break its own guard and report what it saw.** *A guard nobody has watched
fail is a guard nobody has tested.* This found **two holes in one guard before it shipped** — the
subtle one being that a "no whitespace in this row" check PASSED while the helper was broken, because
*a still-nested row is a collection, and a collection has no whitespace in it; it only grows some when
something finally renders it.* Elsewhere it produced a diagnosable signature: removing a dial guard
replaced the operator's level with the ramp's rung every time — 3→2, 5→16, 7→128, 9→1024, **every one a
power of two**, which no operator level ever was.

**4. Verify the GOAL's premise against code before dispatching.** Twice a sentence written into a
planning document became a GOAL's premise and then an Executor's brief without anyone checking it:
*"per-item pass/fail already exists"* (it does not) and *"one transaction spanning table A and table
B"* (different catalogs — impossible). The Executor was the first thing in the chain that read the
code. Catching the second one **before** dispatch cost minutes; the first cost an iteration's framing.

**Corollary, learned the hard way:** do not conclude "dead code" from a grep. A method called from a
Blazor component whose own handler shares the method name looks unreferenced — the caller absorbs the
hit. Read the call site.

Builds on [[project-orchestrator-worker-loop-hardening]]; applied in
[[project-speedmerchants-uow8b-8c]].

**Added 2026-09-03 (UoW-9a iterations 12–13):** two consecutive Orchestrator scoping defects, both caught
only because the Executor REPORTED instead of working around: (12) the PLAN offered an Infrastructure home
for a Composition-declared interface — circular project reference; (13) the PLAN's four allowed files could
not compile because the Cli project lacked the concrete `Microsoft.Extensions.DependencyInjection` package
(`deviation-blocked`, ratified as one added line). **Practice to add before every dispatch: confirm every
type the task will reference is reachable from every project in the allowed-file list** (project references
AND package references — `grep ProjectReference/PackageReference` on each csproj, and check
`Directory.Packages.props`). Also: reading the diff found a semantic drift no gate saw (a per-run object
became a process-wide singleton with a monotonic counter) — "verify the Executor rather than accepting it"
means reading the diff for lifetime changes, not just for correctness of the lines that changed.

**Added 2026-09-04 (UoW-9a iteration 17):** a grader census that greps production source for a literal
(e.g. `StoreErrorKind.BrokenStub`) is satisfied by a `///` doc comment naming it — sabotage (c) removed the
behaviour and the census stayed green; only the test caught it. **Practice:** strip `//` and `///` lines before
censusing a literal in production source (CompositionResolutionTests.StripLineComments already does this for the
AddSpeedy* census), and pair every literal census with a test that watches the behaviour fail. Also: a sabotage
that turns MORE tests red than predicted is a finding worth recording (iteration 17: bypassing the library layer
also bypassed the kebab path guard — two guards lived in one seam).

**2026-09-04 (UoW-9a iterations 17–19) — three grader defects, all found by the Executor READING the grader:** a literal census satisfied by a doc comment (strip `//`/`///` first); a regex `<[^>]+>` that cannot match a nested generic (`StoreResult<IReadOnlyList<string>>` — use `<.+>`); a "subfolder is named" census that only checked the string was PRESENT in the file, not USED at the `Path.Combine` site (an unused private const is not a warning). Rule: a literal census anchors on the USE site. Also: an Executor that bends code to a grader defect (an alias) must report it as a note; fix the grader between iterations and remove the workaround next iteration — never leave code shaped by a bad regex.

**2026-09-04 iteration 20/20b — a flaky test is READ, not re-run.** New end-to-end test failed 2 of the first 4 full-suite runs, then 0 of 26; no message (bare `Assert.IsTrue(x.IsSuccess)`). Reading the write path found A3 §1 member 12 "EXTEND — two additions" had shipped (a) only: the grader censused one addition. (b), the overwrite-move retry, was decided and unbuilt for four iterations. Falsifying the fix showed the old base THREW `UnauthorizedAccessException` (not an IOException) out of every store when the target was held. Rules: one census per spec addition; when a gate flakes, read the code path before re-running; every StoreResult assert carries the message; the Verifier requires N consecutive green full runs before PASS after a flake.

**2026-09-04 21:10 — five registered graders were silently broken; nobody had run them since.** The first `CRITERIA.json` re-preflight in two days found b34/b34b as PowerShell PARSE ERRORS (an inline `# comment` inside an `if (…)` condition; an unescaped apostrophe in a single-quoted message — both from post-close "fix the grader" edits that were written and never executed), b31 pinning a transitional "not yet" state, b32 matching a literal inside doc prose, b36a pinning "exactly TWO files". Rules: (1) **every grader edit is RUN before it is recorded as fixed** (`pwsh -File` exit code, plus `[Parser]::ParseFile` for syntax); (2) a registered grader that runs for the rest of the loop may not pin "exactly N" or "not yet" — name the set, and the row that changes the set updates the grader in the same iteration (the PLAN lists which registered graders it will move); (3) all literal censuses over production source strip `//` and `///` lines; (4) re-preflight `CRITERIA.json` after every grader edit and at least once per unit close — a criteria file nobody re-runs is a list of assumptions.

**2026-09-04 iteration 25 — a test that pins a TRANSITIONAL state is a census the NEXT row must be allowed to update.** Iteration 24 (A4a, mechanics only) wrote `TemplatesCompositionTests` asserting "0 seeders registered, 0 shipped resources, exactly the two starter steps" — true that day, guaranteed false the next row (A4b ships the content). PLAN 25 forbade every existing test, so the Executor finished the whole task and reported `deviation-blocked` on three assertions it could not touch. Rule: when a PLAN writes an assertion about "nothing yet" / "exactly N today", record it in the PLAN's queue note for the next row and put that test file in the next row's allow list with the strengthened target values spelled out. Corollary from the same iteration: a "never does X" test can pass VACUOUSLY when a sabotage makes the code do nothing at all — pair it with a positive "does Y in the same scenario" assertion, and word falsifications as the DEFECT ("memory forced empty"), not as an edit ("ignore the argument") that admits a harmless variant.

**2026-09-04 (between iterations 23 and 24) — a unit's GOAL criterion is authored in the iteration that CLOSES the unit.** A3 closed at iteration 22 with every per-iteration grader green, yet GOAL criterion 3 (`b3-libraries.ps1`) had never been written — the 21 registered criteria were sub-task graders, and nothing sweeps the GOAL table against the criteria folder. Also found: `CRITERIA.json` (what `Test-Criteria.ps1` reads) held only criterion 1 from the initial preflight because criteria were appended to the SOURCE list (`criteria-uow9a.json`) and never re-preflighted; the loop had been running gate 5 from the PLAN's grader directly. Rules: (1) when the last row of a unit closes, author + register the unit's GOAL criterion in the same close (it passes at baseline by design — label it an invariant); (2) after appending to the criteria source list, re-preflight `CRITERIA.json` at the next quiet moment; (3) at every resume, diff the GOAL's Done-when commands against `.loop\criteria\` — a missing file is a gap, not a future task.

**2026-09-04 iteration 23 — a word-PRESENCE census cannot see a swapped branch.** Grader b2h's D4 line checked that `AccessDenied` and `FolderInaccessible` both appear in the file; sabotage (i) swapped the AccessDenied and FolderMissing branches and both words survived elsewhere (the `Inspect` method, the create/Save catch blocks) — the census stayed GREEN. Its sibling (an ORDER check: index of `Probe()` < index of the first `Exists`/`File.`/`Directory.`) caught it. Rule: a census about behaviour asserts ORDER or PROXIMITY (`IndexOf` comparisons, "within N chars after") or is paired with a test that watches the behaviour fail; presence of two identifiers proves only that they were typed. Also: verify the PLAN's exception contract against the IMPLEMENTATION, not the port doc — `ILocalSecretStore` promised `CryptographicException` and the store wraps it in `InvalidOperationException` (`SecretStorageEnvelope.cs:165-169`); the Executor caught it, the PLAN did not.

**2026-09-04 iteration 22 — a Claude Code "restart" does NOT kill the old session or its Executor.** Gene opened the new session at 15:48:34; the old claude.exe (started 14:59) stayed alive with its opus Executor still writing files until 15:48:26, then stalled mid-falsification with a sabotage LIVE on disk. The handoff said "killed at ~15:38, zero test files" — the tree said all five tests existed, grader PASS, regression PASS. **Rules for every `--resume`:** (1) before trusting the handoff's state, `ls -la --time-style` the iteration's files and compare mtimes to NOW; (2) `Get-CimInstance Win32_Process -Filter "Name='claude.exe'"` — any claude.exe older than this session with a live subagent transcript (`~\.claude\projects\<proj>\<session>\subagents\agent-*.jsonl`, check LastWriteTime) is a running Executor; (3) read that transcript's tail (tool_use/tool_result pairs) to learn the true phase and whether a sabotage is un-reverted; (4) never dispatch while it lives — ask, then `taskkill /PID <old> /T /F`; (5) recover by COMPLETING (RESUME preamble stating exactly what landed and what is sabotaged), never by restarting. Also: a stash checkpoint made by `git stash create` has only two parents — untracked files are NOT in it, so gate 4 for previously-untracked edits cannot diff against the checkpoint; measure new files by `wc -l` and tracked edits by `git diff --numstat <stash>`.

**2026-09-04 iteration 21 — two PLAN-authoring rules.** (1) A falsification step must never require editing a file the same PLAN forbids (my sabotage (v) did; the Executor edited, proved red, reverted by hash — honest, but the PLAN was wrong). Sabotage only what the allowed files reach, or allow the file for the sabotage explicitly. (2) Store-family estimates: production ≈ 2.2 × donor lines (house doc prose is ~55% of the file), tests ≈ production. Three consecutive 30–50% overruns before this was written down.

- **Orphan drill, second catch (2026-09-04 22:12, iteration 26 A4c).** Gene restarted the CLI at 21:49 while the opus Executor was mid-falsification (v); the in-process subagent died with the session and left the sabotage (a wrong `<exception>` doc block on `ILocalSecretStore.GetSections`) LIVE on disk. Three commands found it: `Get-CimInstance Win32_Process -Filter "Name='claude.exe'"` (old PID gone), subagent transcript LastWriteTime (== session death), transcript tail (last tool_use = the sabotage Edit, no revert). Handling that worked: run the grader on the orphaned tree FIRST (banks the falsification red), revert the sabotage in the Orchestrator turn when it is a few lines the Executor already wrote once (cheaper than a RESUME dispatch), then re-run every gate. Never trust a dead Executor's earlier green gates until the tail is read.

- **Census the refusal KIND's producer, not the API call the guard uses (2026-09-05 00:40, iteration 27 A5).** The b5 grader's zip-slip census looked for `GetFullPath(` and `StartsWith(` in `BackupService.cs`; the Executor's falsification (i) deleted the guard and the census stayed green — both words survived at unrelated sites (the constructor, `IsArchiveFileName`). Only the behavioural test caught it. Fix: require the service to PRODUCE `BackupErrorKind.EntryOutsideRoot` / `EntryOutsideParts` — a guard that exists yields its refusal kind, and deleting the check deletes the producer. Rule for every future grader: a word census over a whole file is satisfiable by coincidence; a producer census (`Failure(Kind.X` / `Kind.X,` in the comment-stripped source) is not. Verify a new census with a REAL negative (swap the kind for a sibling kind, not a suffix rename that the regex still prefix-matches — my first negative check was exactly that mistake).

- **A PLAN names donor members and their tests; it never paraphrases behaviour (2026-09-05 04:36, iteration 31 A7c-1).** PLAN 31 described the credential guard as "refuses an artifact whose credential settings carry a plaintext value" — the donor's `FindUnusableCredentials` does the opposite (flags credentials that would import EMPTY). The Executor read the donor and its tests, kept the donor semantics and proved the no-echo property; following the PLAN's sentence would have refused every legitimately tokenized import. Rule: describe a donor behaviour by `Member` + `TestName`, never by a re-worded sentence.
- **Census probes must cover METHOD-level oracles inside files already in scope (same iteration).** Two methods in `TemplatesCompositionTests` pinned the shipped-file names; the probe found one. The Executor caught the second (allowed file) — but a probe that greps a file for every literal it pins, not just the first hit, is the fix.
- **Band model for ports of an UNDOCUMENTED donor: ≈2.5–3× donor lines** in house style (every public member carries a WHY doc; per-exception typed catches). Rows 27/29/30/31 overshot at 1× and 2× models. A DOCUMENTED donor port ran at ≈0.5 of the time model (rows 29, 31) — time and lines diverge.
- **PowerShell grader trap: inside `@( ... )` the comma binds tighter than `+`.** `@($ex + 'Name.cs', $var)` builds `$ex + ('Name.cs', $var)`, a garbled string, so an absence census silently passes. Parenthesise computed names: `@(($ex + 'Name.cs'), $var)`. Found at baseline verification of b7c2 (the verification exists for exactly this — every census must be SEEN to fire before dispatch).
- **Memory-constrained boxes kill background graders.** The harness stopped a background bash under low memory (3 GB free of 64; SQL Server held 30 GB). Run graders in the foreground and tell Executors to run one `dotnet test` at a time.
- **Pre-build before graders on a memory-starved box (2026-09-05 06:25).** A grader with seven `dotnet test` filters ran for an HOUR twice and was killed by the harness; after one `dotnet build Speedmerchants.sln` (10 s warm) the same grader passed in 43 s. Each filtered `dotnet test` does an incremental build, and under 4 GB free a cold build thrashes. Rule: `dotnet build` once, then run graders in the foreground; and tell Executors the same.
- **A design-doc "PORT" lives in Application/Ports; grep the landed PATH, not the type name (2026-09-05 08:12, iteration 33b).** PLAN 33 listed `ICapabilityAdvisor`/`PreflightResult` under `src/Infrastructure/Capabilities/` although the A6 doc §3.6 classified both as PORTS; PLAN 33b then put `PreflightGate` in `src/Application/Services/` and the Executor hit CS0234 in six minutes (Application cannot reference Infrastructure). Handled as `deviation-blocked` → PLAN defect → scope amended (move the two files) → re-dispatch; no failure counted. Two rules: (1) when a PLAN names a file path for a type, check the landed path of every type it references across projects, in the direction Composition → Infrastructure → Application → Domain; (2) any type the design doc labels PORT goes under `src/Application/Ports/` in the PLAN that creates it — never beside its implementation.
- **Two more (2026-09-05 09:28, iteration 34):** (1) when a PLAN extends an INTERFACE, the census probe must list every fake/implementation of it under tests/ — the Executor had to edit a forbidden test file's private fake (ratified, adds-only); grep `: IInterfaceName` across tests before fixing the allow list. (2) PowerShell `Measure-Object -Line` counts NON-BLANK lines; `wc -l` counts all — donor sizes measured with the former undercount (129/187/294 vs my 120/167/265). Use `wc -l` (or `(Get-Content f).Count`) for line counts that other documents will quote.
- **Two more (2026-09-05 10:43, iteration 35):** (1) a test that COMPOSES the graph under test (e.g. `RunStepsPreflightTests` builds `AddSpeedyExecution + AddSpeedyCapabilities(PreflightOptions)` and injects its own fake prober) is a hidden oracle for ANY registration change -- the Executor had to register the new prober in only one overload to keep a forbidden test green. Before fixing an allow list for a DI change: `grep -rn "AddSpeedyX\|Compose(" tests/`. (2) PowerShell variables are case-insensitive: `$S` (a path) was silently clobbered by `$s` (a file body) in one tool call -- one Copy-Item failed. Never reuse a letter in two cases.
- **(2026-09-05 11:13, iteration 36):** (1) a census over registered implementations should FAIL for one with no declared rule (A6e's `PlatformRuleFor` `Assert.Fail`s for an undeclared prober) -- it forces the next row's author to declare rather than letting the census silently skip; put the affected test file in the next PLAN's allow list. (2) `Copy-Item` preserves `LastWriteTime`: restoring a sabotaged source from a backup leaves MSBuild's incremental build thinking the assembly is current -> a stale binary produced a spurious grader line. After a revert-from-backup, touch the files or build `--no-incremental`. (3) A Linux-container proof of a .NET slice is cheap here: `docker run --rm -v <repo>:/src mcr.microsoft.com/dotnet/sdk:10.0 dotnet test <proj> --filter ... --artifacts-path /tmp/artifacts` ran 202 tests in 41 s on Rancher Desktop without touching the host `bin/obj` (pre-pull the 1.25 GB image in the background first).
- **(2026-09-05 12:20, iteration 37):** every "exactly N" census in a CLOSED grader (prober count, IsWindows count, "still unprobed" test name) is transitional the moment a later row moves N -- the Executor hit one as a `deviation-blocked` (b6d's "exactly TWO probers" when A6f added the third). PLAN template addition: a line "graders whose counts this row moves: <list>" so they are retired at that row's close (b6c's were pre-declared in PLAN 35 and went smoothly; b6d's was not). Also: PowerShell single-quoted strings need doubled apostrophes (`37''s`) -- a retirement edit produced a ParserError, caught only because every grader edit is RUN before it is recorded.
- **(2026-09-05 12:58, iteration 38):** the composing-test-oracle rule bit a THIRD time, from the other side: `grep` listed `FleetVerbCompositionTests.cs` among a port's test consumers and I filed it as "the port is unchanged so the fakes still compile" without reading the hit. It asserted the CONCRETE registration (`Assert.IsInstanceOfType<SqlClientLoadWorkloadStore>`), which the row deleted by design → compile error → `deviation-blocked` → amend + re-dispatch (38b). Rule: for every test file a census grep returns, READ the hit lines; `IsInstanceOfType<...>` / `typeof(...)` over an implementation type puts the file in scope whenever that implementation is replaced.
- **(2026-09-05 14:20, iterations 38d/39):** (1) "A stated mount is not a mount": PLAN 38 quoted the design's "the fleet box must reach the definitions root -- a mount, stated in A8's plan" and forbade `compose.yaml`; nothing materialised it and every proof that seeds through the `cli` container silently broke until E2's fixtures were planned. Rule: when a design says "X must reach Y", the PLAN that lands the files names the row that lands the reach -- or does it itself. (2) Regex censuses over multi-line blocks need `(?m)` on `^`/`$` -- an anchor without it forced an Executor to reshape `compose.yaml` to satisfy the grader. (3) `Test-Constraints.ps1` hashes the TREE, not the git index: generated, git-ignored folders (Playwright `test-results/`) show up as violations -- remove them before every baseline. (4) The first browser test found a defect no bUnit test or `Invoke-WebRequest` proof could see (a static `<title>` shadowing every `<PageTitle>`): both read markup, only a browser reads `document.title`.

- **A falsification must remove the PROPERTY the census measures, not one instance of it (row 45, 2026-09-05).** "Delete one option" only falsifies a `>= 2` census when the decision has exactly two; "rename `### Critical` to `### Critical items`" passes a substring match. Write the falsification as the strict negation (a single option; a bucket that no longer matches) or the grader is never shown red.
- **A design audit found four product defects no test could see (row 45):** unstyled component classes with no CSS rule, a table borrowing a rule-less class, zero heading elements while `FocusOnNavigate` targets `h1`, an animation gated on a flag that is always reset before render. Browser tests assert what they are told to; a read of the stylesheet against the markup is a separate probe worth one row before any UI implementation.

**Added 2026-09-05 23:30 (rows 51.A/51.B):**
- **Census structurally, not lexically.** A grader that checks for the WORD (`prefers-reduced-motion`, `rotate(`) stays green when the feature is deleted and only a comment mentions it. Falsification caught both; the fix is to match the structure (`@media (...) { ... { transition }`, the element carrying the attribute). Apply the same to every future "the sheet has X" check.
- **Census by SELECTOR before forbidding tests.** Two test files selected `polygon.tach-needle`; the PLAN named the one whose class name matched the component. Grep the test tree for every selector/attribute/count the row changes, and list those files as allowed from the start (or expect a `deviation-blocked`).
- **A test or grader that pins a known DEFECT is a time bomb for the fixing row** (the E2E spec asserted the shadowed title; the E2 grader forbade asserting the PageTitle). Tag such lines with the row that will flip them.
- **The auto-mode classifier refuses to delegate test-assertion edits to subagents** even under a ratified amendment; the Verifier applies the one-liner by hand and records it. Plan for that; do not burn two dispatches.
- **`git diff --numstat` counts re-pointed lines as +1/−1 pairs**; a "re-point N declarations" PLAN should budget ≈ 2N, not 0. CSS/markup rows ran 0.27–0.36× plan for opus.

## A census can only ask what its operand preserves (4th instance, 2026-09-06)

Three lexical censuses passed wrongly on 09-05 because the asserted word sat in a comment. The fourth was
worse: a grader clause asked `docker compose config` whether a service used `${SM_SA_PASSWORD:-...}`, but
compose INTERPOLATES that before the grader sees it, so the variable name survived zero times and every one
of five services read as carrying a hard-coded literal. The clause was unsatisfiable by construction and
would have fired on pre-existing services too.

**Why:** a census over GENERATED output can only ask questions the generator preserves. Interpolation,
minification, formatting and templating all destroy the very tokens a source-level question is about.

**How to apply:** before writing a census, name the operand out loud and ask whether it still contains the
thing being asserted. "Does the SOURCE use the shared secret default" is a question about the source file,
not about the rendered config. Falsify every census in BOTH directions on the operand it actually reads.

## An Executor that refuses an easy lie is the loop working (2026-09-06, 47.J)

The 47.J Executor could have made its proof green two dishonest ways: a second mount papering over a real
`FleetVerb` defect, or a decorative env key satisfying the broken secret clause. It took neither, reported
both as `deviation-blocked` with the measurements, and left the forbidden files untouched.

**Why:** `deviation-blocked` is a PLAN defect, not an Executor failure. Retrying it identically or bumping
the model tier spends money re-deriving a diagnosis you already have.

**How to apply:** on `deviation-blocked`, do NOT retry and do NOT roll back. Verify the claim independently,
amend scope under the ratification protocol, record it in GOAL.md and PROGRESS as `partial` (never `fail`,
so the consecutive-failure counter stays clean), then re-dispatch with the corrected file list and a prompt
that tells the next Executor which work is already in the tree and must not be redone.

## Semantic scoping beats positional scoping in a census (2026-09-06, 47.B then 47.B2)

I wrote the same vacuous-pass bug twice in one night. First form asked three questions of a FILE: does it hold a
test attribute, the member name, and an equality assertion. An unrelated file answered all three alone. I fixed
it to "same statement" and, one row later, wrote a new clause that again asked "type anywhere in the file" plus
"assertion anywhere in the file" and never that the two meet. A near-miss file satisfied it at baseline.

**Why:** file-proximity and statement-proximity are both PROXIES for the claim. The claim was "a positive
quantity arrived through the path under test". Asserting zero arrived, or that an unsupplied value is null,
satisfies every proximity test while proving nothing.

**How to apply:** write the census against the CLAIM, not the neighbourhood. Prefer "asserts a positive count on
a value it did not hand-feed" over "mentions the type and asserts something". Then verify by DISCRIMINATION -
run the clause over the known near-miss and confirm it now fails - which is one cheap command, where mutating
the real test needs a full suite run and can be confounded by a second legitimate satisfier.

## An interface signature change is never a small file set (2026-09-06, 47.B2)

My PLAN allowed a port's signature to change but listed only one implementer, and named the wrong one. The build
produced 13 errors across six unlisted files. All mechanical, all correct, all technically out of scope.

**Why:** a signature change on a port is indivisible - every implementer and call site must move in the same
iteration or nothing compiles. Rolling the Executor back would have punished it for my planning omission.

**How to apply:** before planning a row that alters any interface, census the implementers and call sites
(`grep -rn "<Method>(" src tests`) and name every one in files-allowed. Ratify rather than roll back when the
overflow is mechanical and self-reported.

## A silent empty output is worse than a crash (2026-09-06)

An unescaped apostrophe inside a single-quoted PowerShell string truncated a 154-row array to 1. Invoke-Expression
did not throw; it defined the truncated array happily. The generator then wrote an empty schedule over the real
one and published a blank page to the live artifact before I noticed.

**How to apply:** any generator that reads a large structure must assert a floor on what it parsed and refuse to
write when it is not met. Doubling the apostrophe fixes the instance; the floor check fixes the class.

## A counter measures where it is incremented (2026-09-06, 47.E)

Row 47.E added `PoolRunResult.JournalFlushes` so a live proof could show appends bounded by the batch. It did.
Falsification 2 then unrolled the production decorator into per-sample appends: **no test and no live assertion
failed**, because the counter sits in the pool and counts the appends the pool MADE, not the appends the journal
RECEIVED. Only a static grader clause on the decorator's body, plus the compiler (the member was made ABSTRACT
for exactly this reason - a default interface method would have let the decorator silently un-batch every run),
stood between production and a knob that does nothing.

**How to apply:** when a number is offered as evidence, say which side of a seam it is incremented on before
trusting it about the other side. Pair every pool-side counter with a test on the seam below it (a fake inner
journal counting batched vs per-sample calls). When adding a member to a port whose production binding is a
decorator, make it abstract so the compiler censuses every implementer - never a default body.

## A required string that CONTAINS a forbidden string is a grader that can never pass (2026-09-06, 47.D3)

Grader 47.D3 demanded `rm --force --stop $ThrottleService` in one clause and forbade `stop $ThrottleService` in
the next. The first contains the second. The RED baseline cannot reveal this - both clauses fail at baseline for
the right reason - so it surfaced only when the Executor finished, measured `-match` on both patterns, and
reported it as a deviation-note instead of editing the grader. Fixed with a lookbehind `(?<!-)stop`.

**How to apply:** at authoring time, feed every "must contain X" literal into every "must not contain Y" regex of
the same grader (X matched against Y must be false). One line per pair. A RED baseline proves absence, never
consistency.

## When a census finds ONE hardcoded oracle, grep the file for all its siblings (2026-09-06, 47.D3)

PLAN 47.D3 named `RampScheduleMigratorShapeTests:199` (`Columns.Count - 2`) as the indivisibility for a new column.
The same file also held `Count - 6` and `Count - 4` for two earlier shapes; the PLAN did not name them and all
three had to move. Third row in a row where the tree disagreed with my census and the Executor measured.

**How to apply:** an oracle of shape `AreEqual(<expr> - N, ...)` never comes alone in a file that lists accepted
shapes. After the first hit, search the same file for every `Count - <digit>` and name every one.

## Proof scripts are sized from their SIBLING, never from their task list (2026-09-06, third instance)

47.D2 +3% over band; 47.E budgeted ~380 lines for a proof whose sibling was 732 (landed 607); 47.D3 budgeted
~250 for a section whose sibling section j was ~330 (landed 427). Every miss was the proof script, every time in
the same direction, and the product/test halves were inside budget each time.

**How to apply:** budget a new or extended e2e proof at 1.3x the nearest sibling section's measured line count
(`Measure-Object -Line` on the section), not from what it "needs to do". The repo's proof idiom (Assert-* per
figure, receipt block, teardown, the WHAT THIS DOES NOT PROVE paragraph) is what costs the lines.

Fourth instance (47.F, 2026-09-06): PLAN sized the proof at ~450 against a 1700-line sibling; it landed at 1180 and
put the diff 2× over band. The 1.3× rule was in this file and not applied. Read the rule before sizing.

## A census claim about a NEGATIVE is the weakest kind (2026-09-06, 47.F)

PLAN 47.F §1.1 said `AgentHostCompositionTests.cs:188 resolves the delegate but never invokes it`. It invoked it
twice, nineteen lines below the resolve. The census stopped at the first hit for the type name and asserted a
universal ("never") from a single sighting. Result: `tests/Tests.Unit` did not compile, the regression floor was
unmeasurable, and two of three falsifications could not be observed by test name — `deviation-blocked`, scope
amended, re-dispatch.

**Why:** "X is never called here" needs every occurrence in the file read; "X is called here" needs one. The two
cost different amounts and the census treated them the same.

**How to apply:** when a PLAN sentence contains "never", "only", or "but not", grep the FILE for the variable the
resolve produced (`dials(`), not just the type name, and read every hit. A delegate that is resolved is almost
always invoked somewhere in the same test.

## A harness builder is in scope whenever the snapshot it builds gains a property (2026-09-06, 47.F)

`MonitorComponentTestBase.LiveSnapshot(...)` constructs the `MonitorSnapshot` every Tests.Web component test renders
from. The row added `CommandedScope` to the snapshot; the builder set none, so every component fed by it rendered
`(SCOPE UNKNOWN)`, and the two tests asserting the caption (`ClusterViewTests`, `MonitorPageTests`) failed —
neither was in scope, and the fix for one of them would have been a WEAK oracle without the builder edit.

**How to apply:** when a row adds a property to a DTO/snapshot that tests construct, grep tests for `new <Type>` and
for every helper that returns it (`LiveSnapshot`, `ScriptLiveRun`, `Sound()`), and put those files in scope with the
value they should set. Then grep tests for the RENDERED string the property changes (`OF 48 COMMANDED`) — not just the
component's own test file — and list every file that asserts it.

## A falsification is reverted by REVERSE EDIT, never by `git restore` (2026-09-07, 47.G)

The 47.G Executor reverted falsification 1 with `git restore <file>` on two files it had itself edited earlier in the
same uncommitted row. `git restore` puts back HEAD, not "the state before the sabotage", so it discarded its own
finished work in `SqlClientWorkStore.cs` and `FakeSqlWorkStore.cs`; it rebuilt both by hand and re-verified.

**Why:** while a row is uncommitted there is no git object holding "my work minus the sabotage"; the only revert that
exists is the inverse of the sabotage edit.

**How to apply:** the Executor prompt's falsification section says it verbatim: "revert each falsification by applying
the inverse edit (or from a copy you took first — `Copy-Item` to the scratch dir before sabotaging); never `git
restore`/`checkout`/`stash`, which return the file to HEAD and erase everything this row has written to it."

## Read every "null/absent is supported" comment against the PLAN's decision (2026-09-07, 47.G)

PLAN D-E said a launcher with NO presence source must REFUSE a workload that requires a role. The Executor shipped
`if (RequiredRole.Length > 0 && _presence is IAgentPresence p)` — null presence launches blind — and wrote a
confident comment ("absent means the launcher never consults a roster, which is precisely the behaviour every host
had before this row") plus a DI `GetService` with the same rationale, reported only the DI choice as a note, and never
tested required-role-with-no-presence. Every gate was green; the proof could not see it because every production site
wires a presence.

**Why:** a well-argued comment on the wrong branch reads like design. The five gates measure what the PLAN's grader
asked and what the tests assert; a decision the Executor quietly replaced is invisible to both unless the grader
pinned that exact branch.

**How to apply:** at verification, list the PLAN's decisions that name a NULL/ABSENT/EMPTY case and read the landed
branch for each one against the sentence — do not stop at the tests' names. When a decision has a refusal message in
the PLAN, make the grader require that literal (the D-E "no presence source" sentence was in the PLAN and not in the
grader; the roster-empty sentence was in both and landed).

## 2026-09-10 21:0x — a PLAN's receipt field names must be COPIED FROM the grader, never retyped

48.RV8's plan specified `fragmentUrl.cacheBusterInQuery`; the grader's U6e actually reads
`$frag.busterInQuery`. The Executor spotted the disagreement and wrote **both keys from the same
measurement** rather than guessing which reader mattered — the right call, and it reported it as a
`deviation-note` instead of silently picking one.

Nobody was harmed because the Executor was careful, but the failure mode is obvious: an Executor that
trusted the PLAN would have written a receipt the grader scores as missing an arm, and the row would have
failed on a typo in MY document. **Generate the receipt block in a plan by reading the grader's own
`$r.<field>` accesses**, the way `grep -o '\$r\.[A-Za-z.]*'` over the criterion file lists them.

Two other practices paid again on the same row:
* **Telling the Executor to MEASURE something I had not**: I wrote "check the empty-batch case yourself
  before you fix anything… I am not going to tell you an answer I have not measured." It turned out the
  empty batch was already guarded at `:229` and was never part of the finding — so a fix aimed at it would
  have been invented work.
* **Counterfactual from the Executor's OWN copies**, twice, each reproducing its defect with the real
  exception type and the real wrong URL. See [[feedback_copy_before_probe_never_git_checkout]].
