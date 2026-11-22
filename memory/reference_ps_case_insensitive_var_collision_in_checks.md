---
name: reference-ps-case-insensitive-var-collision-in-checks
description: "PowerShell variable names are case-insensitive; a loop var $cls overwrites a script var $Cls, silently disabling a grader/check branch"
metadata:
  node_type: memory
  type: reference
  originSessionId: 1913cdde-afda-4717-9d00-4dc3c3f40fcf
  modified: 2026-10-03T19:44:06.448Z
---

PowerShell variable names are case-INSENSITIVE. In a stream-kit check (2026-10-03, `.streams\checks\G3.T143.ps1`),
`foreach ($cls in @($spec.Class))` overwrote the script variable `$Cls`, so `if ($cls -eq $Cls)` was always true and
every impact entry judged only named tests: a failing impact test could never turn the check red. Verifier (blind,
0.93 PASS) and integrator both missed it; found only when the same template misbehaved in the next row's check.

**How to apply:** in any grader/check `.ps1`, never reuse a name differing only by case (`$cls`/`$Cls`,
`$name`/`$Name`). When a "whole class must pass" entry is new, prove it can go red (inject one failing outcome or
read a known-failing class) before trusting PASS. Also: a class entry must ignore `NotExecuted`/`Inconclusive`
(e.g. `CliExitUnificationFamiliesTests` is Inconclusive without a built `speedy` exe). Related: [[reference-grader-trx-datarow-name-has-trailing-space]].
