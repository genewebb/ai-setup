---
name: speedy-ui-playwright-axe
description: >
  The `.d` leg of every vNext (speedmerchants) UI row — the Playwright browser spec plus axe pass for
  a speedy-web screen, in `tests\Tests.E2E`. Use when writing a screen spec from the template,
  adding a `routes.json` line, choosing tags, seeding through the `cli` fixture instead of the UI,
  asserting the document title, running the static gate or the smoke grader, deciding whether the
  compose stack is free to use, reading an axe violation, or diagnosing a spec that passes vacuously.
---

Repo: speedmerchants (paths below are repo-relative)

# Speedy UI Playwright + axe leg

`tests\Tests.E2E` in `{SpeedyRepo}`. TypeScript, `@playwright/test` pinned
**exactly 1.59.1**, `@axe-core/playwright` 4.13.0. 20 plan minutes per screen row (the plans give
every UoW-9 row 20), and skipped entirely for rows that add no route.

Hub: [[speedy-ui-screen-port]]. Siblings: [[speedy-ui-bunit]] · [[speedy-ui-composed-graph]].

## Prerequisites, in order

1. **The compose stack must be up, and it must be yours to disturb.** There is no `webServer` in the
   config, deliberately; the `preflight` project GETs `/monitor` on 5310 and fails with a sentence if
   nothing answers. The smoke grader goes further: it **stops the fleet**, runs
   `docker compose up -d --build --wait warehouse web` and rebuilds the `cli` image. Run a browser
   leg only inside your own row, never while another Executor or a proof is in flight — check
   `docker ps` and `.loop\tools\dispatched.json` first. A review session must not run it at all.

```powershell
docker compose -f compose.yaml up -d web fleet
```

2. **`SM_SA_PASSWORD` must be set.** `helpers/cli.ts` refuses **at import time**, before any docker
   call, rather than falling back — a fallback literal is a password the repository ships. Set it in
   the shell, or copy `.env.example`. The criteria sweep reads it from the User scope, so a shell
   started before it was set misses it.

3. **Chromium must be installed.** The config uses `channel: "chromium"`, which is Chrome for
   Testing, not the bundled build.

```powershell
npx playwright install chromium
```

## Write the spec from the template. Never from scratch.

`templates\screen.spec.ts.template` is the contract, copied to `tests\<area>\<screen>.spec.ts`.
Replace `<Screen>`, `<route>`, `<feature-tag>`, `<PageTitle>`, `<screen>`. It carries **five tests**:

| # | Test | Note |
| --- | --- | --- |
| 1 | renders its title and its machine marker | asserts the page's own `<PageTitle>` and that `[data-speedy-<screen>]` is visible |
| 2 | completes the screen's primary job and shows the success outcome | arrange via the `cli` fixture |
| 3 | refuses the one high-risk wrong input **by name** | not a generic error |
| 4 | the figure it renders equals the figure the store holds | read the `data-*`, compare with CLI/SQL — UoW-10's fifth artefact on its nine measurement screens |
| 5 | no serious or critical WCAG 2.0 A/AA violations | axe, `wcag2a` + `wcag2aa` |

Tests 2–4 ship in the template as `throw new Error("not written yet")`. **A template test must never
pass vacuously, and it must never be left throwing** — criteria 9.4 / 10.4 / 11.4 are worded exactly
that way. Deleting a test to make the suite green is the failure the smoke grader was tightened
against. UoW-11 rows add the absence assertion (no `data-*`, an em dash, a printed basis) as their
sixth artefact.

## The document title is LIVE — defect C1 is closed

Row 51.A (2026-09-05 22:48) removed `App.razor`'s static `<title>`; each page's `<PageTitle>` is now
what the browser shows, and `monitor.spec.ts` asserts `Speedmerchants — Cluster`. At 22:42 the same
day `e2e-ui-smoke.ps1` was flipped: a spec that asserts the OLD shadowed title
`toHaveTitle("Speedmerchants Monitor")` **fails the grader**. So:

- give the new page a `<PageTitle>` and assert exactly that text in test 1;
- ignore the template's header comment, which still describes the defect as live — it predates 51.A.
  The first `.d` row to copy the template may delete that comment in the same change (it is a repo
  file; the loop session owns the tree).

## routes.json and the census

Every `@page` under `src\Web\Components` must be named in `routes.json` with an existing spec:

```json
{ "/library/steps": "tests/library/steps.spec.ts" }
```

`check-route-coverage.mjs` fails on three things, each by name: `ROUTE UNCOVERED` (an `@page` nobody
listed), `ROUTE STALE` (a listed spec that does not exist), `ROUTE GONE` (a `routes.json` line no
`@page` declares). It also fails `ROUTE CENSUS VACUOUS` if it finds no `@page` at all. The route
floor in `e2e-ui-smoke.ps1` is a **ratchet**: 3 today, 16 at UoW-9's close, 26 at UoW-10's. Never
lowered; the row that adds a screen raises it in the same change (that is an edit under `.loop\`, so
the loop session makes it).

## Tags

Enforced by the eslint rule `require-test-tags` and censused by `check-test-tags.mjs`, which uses
`playwright test --list` — so **every spec must collect without a live environment**: no
`process.env` read and no `test.skip(` at module scope (the smoke grader checks both by name).

- Feature tag on the `describe`, repeated on each test.
- Tier: `@smoke` (in the gate, run at `--retries=0`), `@critical`, or `@regression`.
- Concurrency: `@parallel` or `@serial`.
- `@a11y` on the axe test.

Counting `@regression` from bare `--list` output is a known grader defect (fixed 09-05 14:50):
Playwright prints no tags there, it counted 0, and an Executor padded two test *titles* to satisfy
it. Count from `--list --grep @regression` (`"Total: N tests"`).

## Seed through the CLI. The browser is for the behaviour under test.

`fixtures/index.ts` is the **one** extended `test`. Import from there, never from
`@playwright/test` directly:

```typescript
import { test, expect } from "../../fixtures";
```

| Fixture | What it gives you |
| --- | --- |
| `cli` | `defineWorkload` / `launch` / `abortRun` inside the compose network |
| `workloadName` | `e2e-<workerIndex>-<8 hex>` — unique per worker and per test |
| `definedWorkload` | a definition seeded through the CLI |
| `launchedRun` | a launched run, **aborted in teardown whatever the test did** |
| `abortAfter(runId)` | for tests that launch through the UI: register the id so teardown aborts it |
| `fleetUp` | worker-scoped, read past the `docker compose ps` race |

There is no `delete-workload` verb; unique names keep definitions apart. The sa password is masked
out of every line of CLI output before it travels.

## What the smoke grader forbids in any spec or helper

Each is checked by name in `e2e-ui-smoke.ps1`, so a spec carrying one fails the gate:

- `page.waitForTimeout(` — a hard sleep;
- an operator install port (`5147`, `5145`, `5047`, `5045`) — `5310` only;
- an API-key VALUE (`SM_WORKLOAD_APIKEY = "…"`) — names only, values in `.env.local`;
- `console.log(` in `helpers/cli.ts` — the connection string travels through it;
- a caret or tilde in any `devDependencies` pin — every pin is exact.

## Locators

Role and label first, `data-*` for the machine contract, CSS last:

```typescript
await expect(page.locator("[data-speedy-steps]")).toBeVisible();
await page.getByRole("button", { name: "SAVE WORKLOAD" }).click();
await expect(page.getByRole("status")).toContainText("saved");
```

`helpers/panels.ts` scopes a section by its title text — needed where one page holds two forms with
identical labels. Frozen visible strings are matched exactly, and a new screen's notice sentences
join the frozen list the moment a spec reads them; see [[speedy-ui-screen-port]] step 3.

## Axe

`serious` and `critical` only, `wcag2a` + `wcag2aa`. The assertion prints the violation list as its
own failure message so the failure names the rule and the node count:

```typescript
const results = await new AxeBuilder({ page }).withTags(["wcag2a", "wcag2aa"]).analyze();
const blocking = results.violations.filter((v) => v.impact === "serious" || v.impact === "critical");
expect(blocking, JSON.stringify(blocking, null, 2)).toEqual([]);
```

`moderate` and `minor` are not gated. Do not raise the bar mid-campaign without a row for it. Note
that `page-has-heading-one` is a best-practice rule outside these tags — absence from the report is
not evidence a heading exists.

## Running it

Static gate — no stack needed, and it is what the smoke grader shells into:

```powershell
npm --prefix tests\Tests.E2E run gate
```

Smoke, no retries:

```powershell
npm --prefix tests\Tests.E2E run test:smoke
```

One spec while iterating:

```powershell
npx playwright test tests/library/steps.spec.ts --reporter=list --retries=0
```

The unit-level wrapper (criterion 9.1 / 10.1, not a per-row grader):

```powershell
pwsh -NoProfile -File .loop\criteria\e2e-ui-smoke.ps1
```

That grader **stops the fleet first** — two smoke tests assert on figures that only hold when no
worker is reporting. Bring it back with `docker compose up -d fleet` afterwards. It also SHA-256 pins
`eslint-rules\require-test-tags.mjs` and `check-test-tags.mjs` as verbatim harvest copies: editing
either turns the grader red by design.

## Sources

- `tests\Tests.E2E\` (`playwright.config.ts`, `fixtures/index.ts`, `helpers/cli.ts`, `helpers/panels.ts`, `templates/screen.spec.ts.template`, `check-route-coverage.mjs`, `routes.json`, `tests/monitor/monitor.spec.ts`)
- `src\Web\Components\App.razor` (no static title since 51.A)
- `.loop\criteria\e2e-ui-smoke.ps1` (the forbidden list; the title flip of 09-05 22:42)
- `{VaultDocsRoot}\speed-merchants\vNext\Testing\Plan_UiTests_Playwright.md`
- `{VaultDocsRoot}\speed-merchants\vNext\Testing\Reference_PlaywrightConventions_vNext.md`
