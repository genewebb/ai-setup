---
name: speedy-ui-screen-port
description: >
  Per-screen procedure for the vNext (speedmerchants / speedy-web) Blazor UI parity ports — the
  UoW-9 / UoW-10 / UoW-11 rows 52.xx / 53.xx / 54.xx, each split into four legs (.a port,
  .b bUnit, .c composed-graph, .d Playwright-axe), including the component rows that add no route.
  Use when porting a speedy-web screen from the CrewChief.Web or TestAuto.Web donor (not when editing
  the donor itself — that is crewchief-web-ui / testauto-ui-patterns), reading a UoW-9/10/11 row,
  re-verifying a donor page that may have changed since the plan was written, choosing a route,
  consuming the approved CrewChief look (the vendored donor sheets plus one departures sheet), honouring the frozen `data-*` /
  visible-string contract, authoring a `u9-`/`u10-`/`u11-` grader, or recording a lesson learned at a
  row's close.
---

# Speedy UI screen port

The hub skill for the vNext UI campaign: **53 screens, four legs each**, in
`{SpeedyRepo}`. Its whole purpose is that the repeated work per screen is read
once, here, instead of re-derived 53 times.

Read this first, then the leg skill you are about to execute:
[[speedy-ui-bunit]] · [[speedy-ui-composed-graph]] · [[speedy-ui-playwright-axe]] — then
`references/lessons.md`. Read the plan **for your row only**: its §3 row section, its §1.1 line, and
the D-decisions that section names. The plans are 730–1,020 lines each; reading one whole per row is
the largest avoidable cost in the campaign.

## The shape of the work

| Unit | Rows | What the rows are | Route floor | Plan document |
| --- | --- | --- | --- | --- |
| UoW-9 (CrewChief authoring parity) | 52.01–52.18 | 16 screens + 2 shared component rows | 16 (GOAL 9.1) | `Design\UoW9_Plan.md` |
| UoW-10 (TestAuto operations parity) | 53.01–53.32 | 26 screens + 5 P3.9 backend waves + 1 kit row | 26 (GOAL 10.1) | `Design\UoW10_Plan.md` |
| UoW-11 (fleet / measurement) | 54.01–54.09 | 9 screens | 9 in the plan (§4 #1); GOAL 11.1 states no number | `Design\UoW11_Plan.md` |

Plans live in `{VaultDocsRoot}\speed-merchants\vNext\Design\`. Each screen row is
suffixed:

| Suffix | Leg | Skill |
| --- | --- | --- |
| `.a` | port / build the markup + code-behind | this skill |
| `.b` | bUnit component suite, six named behaviours | [[speedy-ui-bunit]] |
| `.c` | composed-graph resolution test | [[speedy-ui-composed-graph]] |
| `.d` | Playwright spec + axe (omitted for rows that add no route) | [[speedy-ui-playwright-axe]] |

**A row with no route has no `.d` leg.** 52.01 (value editor), 52.02 (Controls kit), 52.18 (help
corpus — 52.17 owns the route's spec) and 53.03 (ops kit) are component rows: adding a `routes.json`
line to satisfy a census is the padding the smoke grader was already tightened against
(`.loop\criteria\e2e-ui-smoke.ps1` header, 09-05 14:50). The six bUnit behaviours still apply to
them — [[speedy-ui-bunit]] says how they map onto a component. UoW-10's five P3.9 backend waves
(rows 1, 2, 4, 5, 6 of its plan) are not screen rows and do not take these legs.

## Step 1 — Re-verify the donor against the plan's sha. Never trust the plan's line counts.

Each plan records the donor commit it was read at — `UoW9_Plan.md`'s header: HEAD `7aee7cc`,
2026-09-05. The donor has moved since (four commits by 09-09: `d62b9908`, `aca019c3`, `c36ddbcf`
"folder updates", `726dec92` "workflow copy bug fix"). `.loop\donor-baseline-speed-merchants.txt`
is **empty (0 bytes)** — the diff from the plan's sha is the only oracle.

Donor repo for UoW-9 (CrewChief.Web / CrewChief.Engine) and UoW-10 (TestAuto.Web):
`{SpeedMerchantsRepo}`.

Per row, before writing any markup, with the plan's sha and the donor paths the row names:

```powershell
git -C {SpeedMerchantsRepo} diff --stat <plan sha>..HEAD -- <donor paths from the row>
```

```powershell
git -C {SpeedMerchantsRepo} log --format='%h %ad %s' --date=short <plan sha>..HEAD -- <donor paths from the row>
```

A file the diff shows as all deletions no longer exists; a file the diff does not mention is
unchanged since the plan. Count lines with `wc -l` or `(Get-Content <file>).Count`, never
`Measure-Object -Line` (it counts non-blank lines and undercounted three donor files once).

Three outcomes, and each has a required action:

1. **Unchanged** — proceed, and say so in the row report ("donor re-verified at `<sha>`, sizes match").
2. **Changed cosmetically** (size drift, no new behaviour) — proceed, record the new sha and size.
3. **New behaviour since the plan's sha** — the plan's split is now wrong. Port the behaviour that
   exists today, state the delta and the minutes it added in the row report, and append a lesson
   (`references/lessons.md`). Do **not** silently port the plan's description of a page that no
   longer looks like that.

**Drift already measured (2026-09-09, `7aee7cc..726dec92`) — read before dispatching 52.02, 52.04
or 52.06:** `Components/Controls/FolderMoveDialog.razor` (118) and `MoveToFolderBar.razor` (108) are
**deleted** in the donor; `SeparateFoldersNotice.razor` (86) is **new**; `FolderTree.razor` grew by
about 150 lines; `Steps.razor(.cs)` and `Workloads.razor(.cs)` changed with it. That is Gene's 09-08
decision that Steps and Workloads keep SEPARATE folder lists. The plan's Row 2 (Controls kit) still
lists the two deleted files as donor input — port what exists today. `SegmentedToggle` measures 126
(`.razor` 44 + `.razor.css` 82) at both `7aee7cc` and HEAD, so its mismatch with the plan's 140 is
not drift.

**Census the donor file's dependencies, not just its lines.** A donor engine file calls into
siblings that vNext may hold only in part, or in a different layer. Before sizing, list what it uses
and check each name against vNext's DECLARATION:

```powershell
grep -oE 'TokenShapes\.\w+' <donor file> | sort -u
```

Measured for 52.01: the donor's `TokenComposition.cs` uses six `TokenShapes` members vNext's
`src\Infrastructure\Execution\TokenShapes.cs` lacks (`SplitFilters`, `FilterSeparator`,
`BuildConfigRef`, `BuildRef`, `TryParseWholeConfigRef`, `TryParseWholeRef`), and vNext's
`TokenShapes` lives in **Infrastructure** while the plan lands the engine in Domain / Application,
which cannot reference it (Application → Domain only). Raise that at dispatch as a plan defect; never
silently duplicate a grammar vNext already owns.

**A donor control whose backend has no vNext port is not built mid-screen.** The plan's §1.1 "What
is missing" column and its row notes already name them (remote `FileBrowserDialog` → local paths
only; `IDocsCatalog` → built in 9.15). If a control needs a port the plan does not name, report
`deviation-blocked`; `src\Web` injects ports and never grows one.

Functionality re-verification is part of the port leg, not a separate task: for each donor control
the plan names, confirm the behaviour still exists in the donor before deciding whether vNext needs
it. A control the donor deleted is not a parity gap.

## Step 2 — Consume the approved design system: CrewChief's look and feel. Do not re-decide it.

Speedy's screens wear CrewChief's layout, sidebar, type and components, not a re-coloured kit, and
depart from the donor only where a departure is written down with its reason. The approved mockups
and their notes are the spec: `{VaultDocsRoot}\speedy\ui\` (`palette/`, `kit/`,
`dial/`, `index.html`), palette A. The older token layer (`speedy.css`, its `:root` tokens and its
two `@media` blocks, glyphs as inline SVG) described the dark instrument kit that this replaced; it is
retired by the 52.P1.8b rows and is not a rule for new markup.

The stylesheets, linked from `Components/App.razor` in this order and no other:

1. `css/crewchief/bootstrap.min.css` — the donor's Bootstrap, vendored unchanged;
2. `_content/Radzen.Blazor/css/material-base.css` — served by the pinned Radzen package, not copied;
3. the Material Icons font sheet, only where a screen uses the glyph font;
4. `css/crewchief/app.css` — the donor's app sheet, vendored unchanged;
5. `css/speedy-crewchief.css` — the ONE departures sheet: each rule is an approved departure or a
   donor component-scoped rule ported with a comment naming its donor file.

**Hard rules:**

- Every class a screen uses is defined in those sheets. Reach for Bootstrap and the donor's classes
  first; a new class goes into `speedy-crewchief.css` with its reason, and into the mockup notes.
- No `<style>`, no new `style=`, no `.razor.css`, no second sheet under `wwwroot`.
- `speedy-crewchief.css` sets no `font-family` and has no `@import`; its one `@media` is
  `(prefers-reduced-motion: reduce)`.
- The vault copy `_assets/speedy-crewchief.css` is kept equal to the product sheet (recorded in
  `_assets/SOURCE.json`), so the mockups keep rendering what the product serves.

Where the product and the mockups disagree, the mockup notes win until a gate says otherwise; record
the disagreement rather than silently following either.

Radzen **stays** for UoW-9 (D2). `_Imports.razor` imports `Radzen.Blazor` globally and
`MonitorComponentTestBase` registers Radzen's services, so list pages may use `RadzenDataGrid`.

## Step 3 — The frozen machine contract

The E2E suite asserts on the rendered surface, so parts of this UI are API. **Nothing in UoW-9/10/11
may rename any of it.** Full list: `references/frozen-contract.md`. The rules that bite every screen:

- One `data-speedy-<screen>` marker on the page root **and nowhere else**.
- One `data-*` attribute per figure the screen claims — and **an unmeasured figure emits no attribute
  at all**. No zero, no placeholder: em dash in the text, absent attribute in the DOM.
- `role="status"` on notice banners; `role="alert"` only for a problems list (`ClusterView.razor`).
- The frozen visible strings are **derived from the specs by grep, never counted by hand**:
  seventeen locator-matched strings today, plus the monitor's `<PageTitle>` and the notice sentences
  the specs read. The plans say "eighteen"; the derivation says seventeen — trust the grep in
  `references/frozen-contract.md`.
- A new UoW-10/11 page must not reuse a monitor attribute at page scope (criteria 10.7 / 11.7).

Criteria 9.6 / 10.7 / 11.7 are **ratchets**: green at baseline by design. A preflight that reports
them already passing is correct, not a broken grader.

## Step 4 — The route map

`/workloads` is already taken by the run-definition screen, and its marker plus three specs are
frozen, so the authoring library lives under `/library/*` (D7). Declared new routes:

```text
/home  /library/workloads  /library/workloads/edit/{name?}  /library/steps
/library/reference-data  /templates  /activity  /secrets  /secrets/bootstrap
/connect-import  /backup  /commit  /setup  /capabilities  /help/{*slug}
```

Donor aliases (`/execution`, `/history`, `/workloads/execution`) are **not** ported — every extra
`@page` is another `routes.json` line the census demands a spec for.

## Step 5 — Run the legs

Order matters: port, then bUnit, then composed-graph, then Playwright. Each leg has its own skill.
The per-screen contract for a UoW-9 screen (D8) is four artefacts, no exceptions:

1. the marker plus one `data-*` per claimed figure (step 3 above);
2. a bUnit suite deriving from `MonitorComponentTestBase`, floor of **six named behaviours**;
3. a composed-graph test resolving the screen's ports from a real `AddSpeedy` container;
4. a spec from `templates\screen.spec.ts.template` with all five tests written, a `routes.json`
   line, and axe clean at serious/critical.

**UoW-10 adds a fifth artefact and UoW-11 a sixth.** UoW-10 D9: on its nine measurement screens the
rendered figure equals what the CLI or SQL says (GOAL 10.5). UoW-11 D9: the absence contract on all
nine rows — every fact the system cannot yet measure emits **no** `data-*`, renders an em dash and
prints its basis (GOAL 11.6). Read your unit's D9 before assuming four.

**Composition is already done for you.** `src\Web\Program.cs` calls `AddSpeedy`, so the authoring
host already composes the entire A1–A8 graph. No screen composes anything; it injects.

## Step 6 — The grader

Every screen row closes on `pwsh -NoProfile -File .loop\criteria\u9-<n>-<name>.ps1` (`u10-`,
`u11-`), where **`<n>` is the v3 row number**, never the loop row: 9.13 → `u9-13-value-editor.ps1`,
10.9 → `u10-9-exec-dashboard.ps1`. Kit rows carry no number (`u9-controls-kit.ps1`,
`u10-ops-kit.ps1`); UoW-10's waves are `u10-w1-…`. GOAL.md and the plans already name most of them —
use the name they name.

A grader is authored, **registered** (an entry in `.loop\criteria-uow9a.json` plus the GOAL Done-when
row), **verified RED at baseline for a stated reason** and **proven able to go GREEN against a correct
stub** before the Executor is dispatched. The self-test that proves both, the clause shapes that fail,
and the registration mechanics are in `references/grader-authoring.md`. Row 52.01's grader lives at
`{ScratchRoot}\u9-13-value-editor.ps1` with its self-test beside it (`u9-13-selftest.ps1`); copy the pattern.

## Step 7 — Close the row

1. Run the leg graders and the row grader; quote the failing line, never a summary.
2. Re-run the earlier UI criteria — gate 6 runs the test suites and never the earlier graders, and
   two rows have already closed green over a red criterion:

```powershell
pwsh -NoProfile -File {SpeedyRepo}\.loop\tools\Invoke-CriteriaSweep.ps1 -Filter 'u9-*'
```

   Then `-CheckDue`: exit 10 means the daily full sweep is owed (Gene 09-08 16:01: once a day); kick
   it off in the background and carry on.
3. Report actual minutes per leg against the plan's split, on one greppable line — Row 1's actual is
   the calibration for every later row (plan §5):

```text
ACTUAL 52.xx: port <m> · bUnit <m> · composed-graph <m> · Playwright-axe <m> (plan <a>/<b>/<c>/<d>)
```

4. Stamp the row Complete in the schedule artifact **in the same turn the gates pass**.
5. Append a lesson to `references/lessons.md` — see below. This is not optional.

## Shared files are append-only

`_Imports.razor`, `speedy-crewchief.css`, `App.razor`, `Routes.razor`, `routes.json` and the Controls kit are
touched by many rows. A row **adds** to them — a `@using` line, a CSS section under a comment naming
the row, a route line — and never rewrites, reorders or reformats them: a rewrite from a stale copy
silently drops an earlier row's line, no test says so, and only the re-run in step 7.2 finds the
residue. The loop runs one Executor at a time, so the hazard is a stale paste, not a concurrent edit.

## The lessons ledger

`references/lessons.md` is read at the start of every row and appended at the end of every row. One
entry per screen, and an entry may be "nothing new". A lesson that generalises gets promoted out of
the ledger into the body of whichever of the four skills owns it, and the ledger entry then points
at it. That promotion is what stops the ledger becoming a 53-entry wall nobody reads.

## Sources

- `{VaultDocsRoot}\speed-merchants\vNext\Design\UoW9_Plan.md` (§0.4–0.6, §1, §2 D1–D8, §3, §5, §7)
- `{VaultDocsRoot}\speed-merchants\vNext\Design\UoW10_Plan.md` (§2 D9, §3), `UoW11_Plan.md` (§2 D9, §4)
- `{VaultDocsRoot}\speed-merchants\vNext\UI\UIPolishAudit_vNext.md` (frozen contract, §3 mockups, §4)
- `{SpeedyRepo}\.loop\GOAL.md` (UoW-9 / UoW-10 / UoW-11 Done-when tables)
- `{SpeedyRepo}\.loop\tools\Invoke-CriteriaSweep.ps1` (the criteria regression sweep)
- `{VaultDocsRoot}\speedy\ui\` (the approved mockups and their NOTES.md: the look to build)
- `{SpeedyRepo}\src\Web\wwwroot\css\speedy-crewchief.css` (the one departures sheet)
- `{SpeedMerchantsRepo}` at `7aee7cc..726dec92` (the measured drift)
