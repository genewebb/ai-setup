---
name: reference-grader-line-anchor-unreachable-in-crlf
description: "A grader regex ending in [^\\r\\n]*$ can never match in a CRLF file, so the clause goes red on correct content; normalise line endings when the file is read and end the pin with (?![^\\r\\n])"
metadata: 
  node_type: memory
  type: reference
  originSessionId: 4fa4d47c-18da-4fae-b534-7237a701b368
  modified: 2026-09-30T02:59:39.786Z
---

In .NET, `$` under `RegexOptions.Multiline` matches only immediately before a `\n`, and `[^\r\n]*` cannot consume the
`\r` of a CRLF pair, so a single-line grader pin written as `(?m)^[^\r\n]*TOKEN...[^\r\n]*$` is **unreachable** in a CRLF
file and the clause fails even when the required line is present and correct. Measured in pwsh 7 on
`"one\r\nx --check --trust y\r\nthree\r\n"`: the `$` form is False with CRLF and True with LF under every option set
(None, Multiline, Singleline, `IgnoreCase, Singleline`); `(?![^\r\n])` in place of `$` is True for both. `(?![^\r\n])` is
better than `(?=\r?\n|$)` because it also covers a lone `\r` and `\r\r\n`.

The real fix is upstream: **normalise line endings where the grader reads the file**
(`[IO.File]::ReadAllText($p) -replace "\r\n?", "`n"`), because a comment-stripping helper makes the endings
INCONSISTENT inside one file. Measured on `.streams/graders/G1.T16.ps1`: its `PsCode` cuts a trailing `#` comment and
takes the `\r` with it (233 CR in the file, 156 after `PsCode`), so a pinned line that carries a trailing comment ends in
`\n` and satisfies the `$` form, while the same line without the comment keeps its `\r` and does not. On the kept G1.T16
writer both pinned lines carry trailing comments, so the `$` pins matched (1 match each) and the clause looked healthy;
with the comments stripped and nothing else changed, the same pins matched 0 times. A trailing comment is therefore an
accidental workaround, not a fix.

This bites every stream-kit grader that pins "one command line carries A and B", because the speedmerchants working tree
is CRLF: `core.autocrlf=true` in the machine-wide git config, and `.gitattributes` pins only `docs/requirements/**` to
`eol=lf`. A patch exported with LF is checked out as CRLF, so the clause also goes red on main after the integrator
commits — for a reason that has nothing to do with the code.

Watch the second half of this trap: an anchor that never matches makes the clause **fail closed**, which hides a loose
pin. When the anchor was fixed on G1.T16, a `Write-Host "recreate: --force-recreate --no-deps for web, cli and fleet"`
and a `throw "... run dotnet dev-certs https --check --trust once"` both started passing, because the pins asked for any
LINE carrying the tokens. Pin the COMMAND: require the tool name on the same line and refuse a line that carries
`throw` or `Write-Host`/`Write-Output`, and match against text with backtick continuations joined.

Related: [[reference-grader-needs-regex-leading-pipe-always-matches]], [[reference-myloop-tasklist-must-be-lf]].
