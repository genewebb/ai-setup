---
name: reference-powershell-script-contract-gotchas
description: "Six PowerShell traps that silently break agent-driven scripts — swallowed exit codes, pwsh -File array binding, empty-array returns, -like as a glob, Measure-Object returning Double, and Set-Item Env: leaking secrets under -WhatIf"
metadata: 
  node_type: memory
  type: reference
  originSessionId: 5c01d683-306d-40a4-9e1b-4be20be0ef9c
  modified: 2026-08-02T17:27:51.398Z
---

Four traps that all produce *wrong behaviour with no error*, found while hardening the
orchestrator-worker-loop gate scripts (see [[project-orchestrator-worker-loop-hardening]]).

**1. `Write-Error` + `exit N` never reaches the exit code.** With `$ErrorActionPreference = 'Stop'`,
`Write-Error` is terminating: the script aborts and pwsh exits **1**, so a following `exit 2` is dead
code. Any caller branching on "1 = violation, 2 = script error" silently sees every error as a
violation. Fix: write to stderr without throwing —
`[Console]::Error.WriteLine("ERROR: $msg")` then `exit N`.

**2. `pwsh -File` binds array arguments as separate positional tokens.** `-Paths 'a','b'` from a
parent shell sends two tokens; the second binds to whatever parameter is next in declaration order.
Fix both ends: declare `[Parameter(Mandatory=$true, Position=0)]` on the first parameter (that makes
every *other* parameter name-only, since explicit positions disable implicit ones), and accept one
comma-separated token (`-Paths 'a,b'`) which the script splits. For values containing quotes/commas
(shell commands), take a JSON file parameter instead.

**3. Returning an empty array from a function yields `$null`.** `return @($x)` where `$x` is empty
unrolls to nothing, so a caller doing `$result.Count` dies under `Set-StrictMode` with
"The property 'Count' cannot be found on this object". The leading-comma idiom (`return ,$arr`) fixes
that case but **double-wraps if the caller also writes `@(...)`** — you get an array-of-array, every
element is an array instead of the real object, and matching/comparison silently fails everywhere.
Pick one convention: plain `return $arr` in the function, `@(...)` at every call site.

**4. `-like` is not a glob.** `*` spans `/`, so `'bin/*'` is root-anchored and never matches
`src/App/bin/x.dll`, while flattening `**` to `*` makes `src/**/*.cs` miss direct children like
`src/x.cs`. Convert globs to anchored regex instead: `/**/` → `(?:.*/)?`, trailing `/**` → `.*`,
`*` → `[^/]*`, `?` → `[^/]`, and match directory exclusions per path **segment** so `bin`/`obj`/
`node_modules` are caught at any depth.

---

## Two more, both found 2026-08-30, both in code whose job was to be careful

### 5. `Measure-Object -Maximum` answers `System.Double`, so `IndexOf` against an `Int32[]` never matches

```powershell
$targets = @(4, 24, 4)
$peak    = ($targets | Measure-Object -Maximum).Maximum   # System.Double, NOT Int32
[array]::IndexOf(@($targets), $peak)          # -1   <- always
[array]::IndexOf(@($targets), [int]$peak)     #  1   <- with the cast
```

Verified on **PowerShell 7.6.5**. `Int32.Equals(Double)` is false, so the search silently fails and
answers `-1`. Any guard shaped `if ($index -le 0) { fail }` then fires on **every** run.

**Why this one is nastier than it looks:** it made a loop's acceptance criterion fail
*unconditionally*, whatever the thing under test actually did — so the symptom was "the product is
broken", pointing the investigation at the wrong half of the system entirely. It was written twice,
in two criteria, and would have re-appeared three iterations later with nothing to connect the two.

**Fix:** cast at the source, not at the comparison — `[int](($xs | Measure-Object -Maximum).Maximum)`
— or skip `IndexOf` and scan.

**Generalise it:** `Measure-Object` is an aggregation cmdlet and returns aggregation types. Never feed
its output to an identity-based search or a type-sensitive comparison without casting first.

### 6. `Set-Item Env:\<name>` prints the VALUE under `-WhatIf` — a credential leak in the code path meant to prevent one

```powershell
Set-Item -Path "Env:\SM_WORKLOAD_APIKEY" -Value $key
# dpv2 -Dial -WhatIf  ->
# What if: Performing the operation "Set Item" on target "Item: SM_WORKLOAD_APIKEY Value: c455a7...".
```

`Set-Item` supports `ShouldProcess`, and the target string it renders **includes the value**. So a
function that carefully passes a secret through the environment *precisely to keep it off the command
line* prints it to the console the moment anyone previews the call.

**Fix:** use the .NET call, which has no `ShouldProcess` participation and narrates nothing:

```powershell
[Environment]::SetEnvironmentVariable($name, $value, 'Process')
```

**The general rule:** any cmdlet that supports `-WhatIf` will describe its target, and "the target"
often means the data. Before routing a secret through a cmdlet, run the command with `-WhatIf` and
read what it prints. Found exactly that way.

Both of these belong to the same family as the four above: **wrong behaviour, no error.** See also
[[feedback_verify_no_guessing]] — in both cases the defect was found by *running* the thing and
reading the output, not by reasoning about the code.
