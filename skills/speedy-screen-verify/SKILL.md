---
name: speedy-screen-verify
description: The agent verification skill for Speedy screens (framework block B7a item 1). Before reporting a change that affects a Speedy web screen as done or built, open that screen on a private seeded host with the screen control command speedy-screen-drive (block B2), drive it with an action script whose steps name features from docs/surfaces/screen-map.json (block B1), read result.json and the screenshots, and report what was seen with the evidence paths. Use when a Speedy change touches src/Web pages, components, layout, navigation, routes or anything a screen shows; when a ticket or acceptance clause says a screen must show or do something; or when asked to check, look at, screenshot or verify a Speedy screen.
---

# speedy-screen-verify

Speedy repo: `{SpeedyRepo}`. Contracts this skill rests on, read them when a detail matters:

- `docs/requirements/quality/NFR-SCREENDRIVE-001.yaml`: the command, its grammar, exit codes and result file.
- `docs/requirements/quality/NFR-SCREENMAP-001.yaml`: the screen map, its features and the seeded start.
- `docs/quality/agent-verification/`: the framework (B1, B2, B7a) and the cross-contract decisions D1-D10.

The rule: **a screen change is not done until you have opened the screen, driven what changed, and looked at the
evidence.** Tests passing is not looking. A screenshot you did not open is not looking.

## When the command does not exist yet

The command is built by stream groups G41 (library), G42 (map and seed) and G43 (command). Check first:

```powershell
Test-Path "{SpeedyRepo}\tests\Testbed.ScreenDrive\Testbed.ScreenDrive.csproj"
Test-Path "{SpeedyRepo}\docs\surfaces\screen-map.json"
```

If either is missing, use the fallback below and say in the report that the command was not available. Never invent
its output.

**Fallback (no command yet).** Run the screenshot battery, which opens every route on a private host and photographs it:

```powershell
dotnet test "{SpeedyRepo}\tests\Tests.Browser" --filter "FullyQualifiedName~RouteScreenshotBattery"
```

Open the screenshots of the screens you changed (the test output names the folder) and look at them. The battery
cannot click or fill, so a behavior change (a button, a form) also needs a bUnit or Playwright test that drives it.

## 1. Pick the target

- **By name** (preferred): the surface's `name` in `docs/surfaces/screen-map.json`, lower case, for example `dial`.
  A surface with `drivable: false` cannot be opened by name; the command refuses and prints `notDrivableReason`.
- **By raw route**: a screen-input beginning with `/`, either a literal path or a route template from the route
  table. Parameter values go in the action script's `parameters`, query values in `query`, never in the route.
- **Git Bash rewrites a leading `/`** into a Windows path; the command refuses it as `route-malformed`. Run from
  PowerShell, or set `MSYS_NO_PATHCONV=1`.

## 2. Write the action script (when the change is behavior, not only looks)

UTF-8 JSON. Unknown members are refused, not ignored.

```json
{
  "schemaVersion": 1,
  "parameters": { "id": "abc123" },
  "query": { "tab": "history" },
  "steps": [
    { "action": "click", "feature": "new workload" },
    { "action": "fill", "selector": "#workload-name", "value": "smoke" },
    { "action": "press", "selector": "#workload-name", "key": "Enter" },
    { "action": "wait-for", "feature": "workload saved notice", "timeoutMs": 15000 }
  ]
}
```

- Actions: `click`, `fill` (needs `value`), `select` (needs `value`), `press` (needs `key`), `wait-for`.
- Each step has exactly one of `feature` (a feature name or synonym of the target surface in the map) or `selector`
  (a Playwright selector). Prefer `feature`: it is the map's stable name, and a missing feature is a map fault you
  should report.
- `timeoutMs` is 1 to 60000, default 10000.
- Any `fill` or `select` value, or query value, that is an absolute or UNC path outside the run's private state
  folder is refused. Do not drive a screen to write outside its temp folder.

## 3. Run it

```powershell
dotnet run --project "{SpeedyRepo}\tests\Testbed.ScreenDrive" -- <screen> --out <empty or new folder> [--actions <script.json>] [--map <map.json>]
```

Put `--out` under your scratchpad. The host is always private and seeded: it never touches a running Speedy, and
there is no option to point it at one.

On success the command prints one line on standard output:

```text
outcome=<outcome> exit=<code> result=<absolute path of result.json>
```

## 4. Branch on the exit code

| Exit | Outcome | Meaning | What you do |
|---|---|---|---|
| 0 | reached | The screen opened and every step completed | Read the evidence (step 5) |
| 1 | not-reached | The screen did not open as itself (`reachReason` says why) | The page is broken, or your target is wrong. Fix it; do not report done |
| 2 | refused | Your input was wrong; nothing started. One line per fault on standard error | Fix every listed fault, run again |
| 3 | harness-fault | The machine failed: no web build, no browser, host did not answer, sign-in refused | Not your change's verdict. Fix the environment or report it as a blocker, never as a pass |
| 4 | action-failed | The screen opened but a step failed (`steps[].error`) | Your script or the feature is wrong. Look at that step's screenshot |

## 5. Read the evidence

The `--out` folder holds exactly: `result.json`, `host.log`, `open.png`, and `step-001.png` onward.

- **Open `open.png` and the step screenshots** (the Read tool shows images). Check that what the ticket asks for is
  visibly there: the text, the control, the state after the action.
- In `result.json` check `reached`, `settled`, `finalAddress`, `title`, every `steps[].outcome` and
  `selectorPresent`, and `consoleErrors`. A console error your change introduced is a defect, even when exit is 0.
- `host.stateFolderRemoved` false means the run left state behind; say so.

## 6. Report what you saw

In the build report (or your answer), one block per screen:

```text
Screen check: <screen> -> outcome=<outcome> exit=<code>
  evidence: <absolute path of result.json>, open.png, step-00N.png
  saw: <one or two sentences of what the screenshots show, in plain words>
  console errors: <none | the entries>
  not checked: <anything the command could not show, and the test that covers it instead>
```

- Say what you saw, not what you expected to see.
- A screen you did not open is listed under `not checked`, never under `saw`.
- If the fallback was used, write `Screen check (battery fallback, command not available)`.

## Failure-mode log

`failure-modes.md` beside this file lists observed agent failures this skill answers. When you see an agent (or
yourself) skip a step above, add one line there: date, what happened, the evidence, and the skill line or check
that answers it. Prefer a check over a skill line (framework P2).
