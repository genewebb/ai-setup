---
name: reference_pwsh_call_operator_breaks_npx
description: In pwsh, `& npx <cmd>` silently mangles the command name (npx -> px) because npx.ps1 strips InvocationName.Length chars; call npx without & or use npx.cmd
metadata:
  type: reference
---

`C:\Program Files\nodejs\npx.ps1` rebuilds its argument string as
`$text.Substring($MyInvocation.InvocationName.Length)`. Under the PowerShell call operator the
InvocationName is `&` (length 1), so exactly ONE character is stripped off the command text:
`& npx playwright test --list` reaches npm as `npm exec -- px playwright test --list`.
npm then fetches the unrelated registry package `px@0.1.2`, which has no bin, and fails with
`npm error could not determine executable to run`, exit 1, no stdout.

Verified on SMVMTR1 2026-09-29 in both a worktree and the main tree:
- `& npx playwright test --list ...` -> exit 1, that error
- `npx playwright test --list ...` (no `&`) -> exit 0, correct listing
- `& npx.cmd playwright test --list ...` -> exit 0, correct listing

It is NOT a node_modules-junction problem and NOT a missing package. A grader or script that
swallows stderr (`2>$null`) reads the empty output as "0 tests found" and blames the code.
All 8 Speedy Playwright graders hit this after the 9/28 host move; the same graders ran fine on
CORPLTR94 on 9/27. Write `npx <cmd>` bare, or call `node_modules\.bin\playwright.cmd` directly.

Related: [[reference_stream_kit_update_task_needs_beat]]
