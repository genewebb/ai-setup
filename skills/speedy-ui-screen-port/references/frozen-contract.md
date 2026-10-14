
Repo: speedmerchants (paths below are repo-relative)

# The frozen machine contract

Frozen by `{VaultDocsRoot}\speed-merchants\vNext\UI\UIPolishAudit_vNext.md`. The E2E
suite asserts on the rendered surface, so this is **API, not decoration**. Nothing in UoW-9, UoW-10
or UoW-11 may rename any of it. Criteria 9.6 / 10.7 / 11.7 are the ratchets that enforce it, and they
are green at baseline by design.

Styling, spacing, elevation, colour, motion and layout are free. **The words, the roles and the
`data-*` names are not.**

**The list below is derived, not remembered.** The specs are the authority; re-derive before trusting
any count in a plan or in this file:

```powershell
grep -rhoE 'getBy(Role|Label|Text)\([^)]*\)|toHaveTitle\([^)]*\)|toContainText\([^)]*\)|toHaveText\([^)]*\)' tests\Tests.E2E\tests | sort | uniq -c
```

## Root markers

`data-speedy-monitor` (`MonitorPage.razor`) · `data-speedy-workloads` (`WorkloadsPage.razor`) ·
`data-speedy-throttle` (`ThrottleControl.razor`) · `data-speedy-ramp` (`RampPanel.razor`) ·
`data-speedy-notice` (the workloads notice) · `data-run-profile` (`RunProfilePanel.razor`)

One marker per page root, and on nothing else. A new screen adds `data-speedy-<screen>`; it does not
reuse one of these. (`data-speedy-monitor` appears twice in `MonitorPage.razor` — once in the razor
comment explaining it, once on the element. A grep for the name is not a count of elements.)

## Monitor root figures

`data-run-state` · `data-run-live` · `data-run-completeness` · `data-run-id` ·
`data-active-workers` · `data-commanded-users` · `data-agent-completions` ·
`data-queue-completions` · `data-published-items` · `data-stalled-claims` · `data-agent-roster`

**And the rule behind them: an unmeasured figure emits no attribute at all.** No zero, no `"—"` in
the attribute, no placeholder. Em dash in the visible text, attribute absent from the DOM, and the
basis printed. UoW-11's criterion 11.6 states this as its own artefact: *no zero appears in its
region*.

A UoW-10 or UoW-11 page must **not** reuse any of these at page scope (D8 / criteria 10.7, 11.7).

## Throttle hooks

`data-throttle-run` · `data-throttle-ceiling` · `data-throttle-gap` · `data-throttle-selected` ·
`data-throttle-notice` · `data-throttle-parked`

## Row and run hooks

- `data-workload="<name>"` on each `<tr>` (`WorkloadsPage.razor`) — asserted by three E2E specs
  (`define.spec.ts`, `control.spec.ts`, `launch.spec.ts`). This is why the authoring library could
  not take the `/workloads` route.
- `data-launched-run` on the LAUNCHED panel (`WorkloadsPage.razor`).
- `data-ramp-*` on `RampPanel.razor`.
- `data-profile-field` / `data-profile-kind` / `data-profile-value` on `RunProfilePanel.razor`.

## ARIA roles

`role="status"` on the notice banner (`WorkloadsPage.razor`), the throttle notice
(`ThrottleControl.razor`) and the ramp line (`RampPanel.razor`) — `getByRole("status")` is read six
times across the specs.

`ClusterView.razor` uses `role="alert"` for the problems list. **That difference is deliberate**: a
status region is polite, an alert interrupts. A new screen's notice is `status`; only a problems list
is `alert`.

Present and not yet asserted, and still to be kept: `role="img"` with an `aria-label` on the
tachometer's `<svg>`, and `role="region"` + `aria-label="Defined workloads"` on the table's scroll
wrapper (row 51.B's H6 fix — a scroll region without a name is a new axe finding).

## Exact visible text — seventeen locator-matched strings

Derived from the specs on 2026-09-09 (the command above). Matched by `getByLabel` / `getByRole`, so a
changed word is a failing spec:

```text
NAME                                       getByLabel, exact
TARGET URL
ITEMS
TARGET USERS
CLAIM SIZE
DURATION (s)
API KEY VARIABLE (a NAME, never a key)
REASON (required)
RUN
Target workers                             the slider's aria-label
SAVE WORKLOAD                              button
LAUNCH                                     button
TURN THE DIAL                              button
ABORT RUN                                  button
OPEN THE THROTTLE                          button
DEFINE & LAUNCH A WORKLOAD                 link
WATCH THIS RUN                             link
```

**Seventeen, not eighteen.** `UoW9_Plan.md` §0.6 and GOAL criteria 9.6 / 10.7 / 11.7 say "eighteen
frozen strings"; the audit's own list has seventeen entries and the specs assert seventeen distinct
locator strings. No eighteenth could be found in the specs or the audit — the count was written by
hand. GOAL.md is not edited from this skill (`.loop\` belongs to the loop session); a contract grader
must derive its list from the specs, not from that word.

`RUN` and `TARGET USERS` are frozen even though they collide semantically with other fields; row
51's H9 disambiguates them with form-level accessible names rather than renaming either.

## Also frozen: the document title and the notice sentences

Since row 51.A removed `App.razor`'s static `<title>` (C1, 09-05 22:42), `monitor.spec.ts` asserts
the monitor's own `<PageTitle>`:

```text
Speedmerchants — Cluster
```

and the specs read these notice sentences through `toContainText` / `toHaveText` — reword one and a
spec fails, exactly as for a label:

```text
Stored workload '<name>'.
Launched '<name>' as run <id>
Run <id> dialled to <n> target users.
Run <id> is Cancelled: <reason>
This run is Cancelled.
Commanded <n> workers.
NOT YET APPLIED | NO WORKER COUNT REPORTED YET       (the throttle gap sentence, regex)
<name> · <items> items published · surface ui        (the launched line)
RUN <id>                                             (getByText on the launched panel)
```

A new screen that reuses the notice component inherits these shapes; a new screen with its own
notices adds its sentences to this list in the row that asserts them.

## The six Critical audit defects (row 51, closed 2026-09-05 23:32)

Closed by rows 51.A and 51.B, listed here so a screen does not re-open one:

| # | Defect | Status today |
| --- | --- | --- |
| C1 | dead `<PageTitle>` — `App.razor` emitted a static `<title>` before `<HeadOutlet />` | **closed**: `App.razor` carries no `<title>`; each page's `<PageTitle>` is what the browser shows, and `e2e-ui-smoke.ps1` now FAILS a spec that asserts the old `Speedmerchants Monitor`. The template's header comment still describes the defect — it is stale, see [[speedy-ui-playwright-axe]] |
| C2 | `color-contrast` axe violation on ABORT RUN | closed (`--accent-limit: #FF5C67`) |
| C3 | two panels with no CSS | closed |
| C4 | the unstyled table | closed |
| C5 | no heading element anywhere (`FocusOnNavigate Selector="h1"` targeted nothing) | closed; 52.07 (home) re-checks that its `h1` is the first |
| C6 | the busy indicator that can never be seen | closed |
