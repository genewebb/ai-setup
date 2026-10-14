# Lessons ledger — vNext UI campaign

Read at the **start** of every UI row. Append at the **close** of every UI row.
Hub: [[speedy-ui-screen-port]].

## How to use this file

One entry per screen row, newest last. An entry may say "nothing new" — that is a real result and
recording it is what proves the ledger was consulted.

**Entry shape**, exactly:

```markdown
## 52.05 — Workload editor — 2026-09-12

**What bit:** one or two sentences, concrete, naming the file and the symptom.
**Rule:** the generalised instruction, phrased so the next row can follow it without the story.
**Promoted to:** speedy-ui-bunit § Port fakes — or "not yet, single occurrence".
```

## Promotion, and why it matters

A lesson that generalises is **moved into the body** of whichever of the four skills owns it, and the
ledger entry keeps only the pointer. Without that step this file becomes a 53-entry wall nobody
reads, and the repetition the campaign's skills exist to remove comes straight back.

Promotion targets:

| Lesson about | Goes to |
| --- | --- |
| markup, tokens, routes, the frozen contract, donor drift | [[speedy-ui-screen-port]] |
| a component suite, a fake, a harness, a floor behaviour | [[speedy-ui-bunit]] |
| a registration, a resolution, a census | [[speedy-ui-composed-graph]] |
| a spec, a tag, a fixture, axe, the route census | [[speedy-ui-playwright-axe]] |
| a grader clause | `references/grader-authoring.md` |

A lesson seen **once** stays here. A lesson seen **twice** is promoted — the second occurrence is the
evidence that it generalises, and waiting for a third is how a pattern costs three rows instead of
two.

---

## Entries

### 2026-09-09 — campaign preparation (no row)

**What bit:** nothing yet — this ledger was created before row 52.01 was dispatched, alongside the
four campaign skills. Four facts were established while writing them and are recorded here because
no row discovered them:

1. `.loop\donor-baseline-speed-merchants.txt` is **empty (0 lines)**. It looks like a drift oracle
   and is not one, so the donor re-read is the only oracle. See [[speedy-ui-screen-port]] step 1.
2. Playwright is installed and working: `@playwright/test` 1.59.1, Chrome for Testing 147.0.7727.15
   (`chromium-1217`) in `%LOCALAPPDATA%\ms-playwright`, `npm run gate` clean (18 specs, 3 routes),
   and a real-browser run passed — preflight plus the workloads axe test, 2 passed in 7.9s.
3. Only **firefox and webkit are absent**. The config declares one `chromium` project, so that is not
   a gap; it becomes one only if a row adds a second browser project.
4. ~~The `ai-repo-management` skill's own paths still point at the retired
   `devopslocal\ObsidianVaults\...` root.~~ **Corrected later on 2026-09-09** — that skill now
   carries zero `devopslocal` paths. The live skills root is `{AIWorkRoot}\skills`.

**Rule:** verify a claimed baseline file is non-empty before treating it as an oracle.

**Promoted to:** [[speedy-ui-screen-port]] step 1 (the empty-baseline fact) and
[[speedy-ui-playwright-axe]] Prerequisites (the install facts).

### 2026-09-09 — review of the four skills and the 52.01 grader (no row)

**What bit:** the review ran the self-test the grader's header promised and never had. Measured, not
reasoned:

1. **The grader failed a correct implementation twice and passed a wrong one once.** G2 matched only
   the C#-escaped `"C:\\Temp"`, so a verbatim `@"C:\Temp"` was red; G4 found the editor suite by the <!-- example-path -->
   letters `Value` in its FILE NAME, so `CompositionEditorTests.cs` was invisible; G6 read the six tab
   labels in the RAW view of the whole tree, where five of the six words already occur and a doc
   comment saying `"Reference Data"` passed for the sixth. Its `Strip-Code` also stripped `//` before
   blanking strings, so a URL literal desynchronised every string after it. All fixed; the self-test
   (`{ScratchRoot}\u9-13-selftest.ps1`) proves 1 / 1 / 0 against the live tree, a wrong stub and a correct
   stub; the original is kept as `{ScratchRoot}\u9-13-value-editor.ORIGINAL.ps1`.
2. **The donor moved four commits past the plan's sha** (`7aee7cc..726dec92`): `FolderMoveDialog.razor`
   and `MoveToFolderBar.razor` are deleted, `SeparateFoldersNotice.razor` is new, `FolderTree` grew —
   Gene's 09-08 separate-folder-lists decision. Row 52.02 still lists the two deleted files as donor
   input. `SegmentedToggle` is 126 (44 + 82) at both shas; the plan's 140 was never true of it alone.
3. **52.01 has a plan defect the grader cannot see:** the donor's `TokenComposition.cs` calls six
   `TokenShapes` members vNext's `src\Infrastructure\Execution\TokenShapes.cs` lacks (`SplitFilters`,
   `FilterSeparator`, `BuildConfigRef`, `BuildRef`, `TryParseWholeConfigRef`, `TryParseWholeRef`), and
   the plan lands the engine in Domain / Application, which cannot reference Infrastructure. Row 1's
   file set omits `TokenShapes.cs`. Raise at dispatch.
4. **"Eighteen frozen strings" is seventeen.** Derived from the specs by grep: seventeen distinct
   locator strings; the audit's own list has seventeen entries; GOAL 9.6 / 10.7 / 11.7 and the plans
   say eighteen. The monitor `<PageTitle>` (`Speedmerchants — Cluster`) and nine notice sentences are
   also asserted and were listed nowhere.
5. **The `.d` skill described defect C1 as open.** Row 51.A removed the static `<title>` on 09-05 and
   `e2e-ui-smoke.ps1` flipped at 22:42 to FAIL a spec asserting `Speedmerchants Monitor`; the skill
   told fifty rows to do exactly that. The template's own header comment is stale the same way.
6. **The `.c` skill's example resolved `IWorkloadStore`,** which is not declared anywhere;
   `WorkloadFileStore` and `LibraryFolderService` are concrete singletons (`LibrariesModule.cs:144`,
   `:165`). `ProviderFor("Web")` is fine — `src\Web\appsettings.sample.json` exists.
7. **The six-behaviour floor had no greppable form** — GOAL 9.2 names `u9-bunit-floor.ps1`, which does
   not exist, and the skill described the six in prose. The exemplar `WorkloadsPageTests.cs` (17 tests
   in the page class, not "twenty") satisfies two of the six by name.
8. **Registration was misdescribed:** `criteria-uow9a.json` is the registry the sweep reads;
   `CRITERIA.json` is the 09-05 preflight snapshot. `Invoke-CriteriaSweep.ps1` exists since 09-08 and
   the skills did not name it.
9. `speedy.css` has **two** `@media` blocks (`max-width: 720px` at ~307, reduced-motion at the foot),
   not zero; "no new `@media`" needed a count to be gradable. Motion has three durations
   (`--motion-fast/base/slow`), not two.
10. The four skills were absent from `Overview\README.md` (`-Check` exit 1): `skill-taxonomy.ps1` had
    no rule for the `speedy-` prefix.

**Rule:** a grader is dispatched only after its self-test proves 1 / 1 / 0; every operand in a skill
or a grader (type, member, file, count) is verified against the declaration, not against a plan
sentence; frozen sets are derived by grep, never counted by hand; donor drift is measured with
`git diff --stat <plan sha>..HEAD`, never with `git log -15`.

**Promoted to:** [[speedy-ui-screen-port]] steps 1, 2, 3, 6, 7 and "Shared files are append-only";
`references/grader-authoring.md` (self-test, three views, three new clause shapes, registration, the
sweep); `references/frozen-contract.md` (the derived list, the title, the notice sentences, C1 closed);
[[speedy-ui-bunit]] (canonical tokens, component rows, the exemplar's real count);
[[speedy-ui-composed-graph]] (real registrations, operand verification, layering);
[[speedy-ui-playwright-axe]] (title is live, stack exclusivity, the smoke grader's forbidden list).
