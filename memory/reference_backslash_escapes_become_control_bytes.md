---
name: reference_backslash_escapes_become_control_bytes
description: Writing PowerShell/regex backslash sequences through a bash heredoc into Python silently produces control bytes — \b and \a are VALID escapes so nothing warns.
metadata: 
  node_type: memory
  type: reference
  originSessionId: aa701f44-5fa5-4edf-ae81-2fc43ee32e4c
  modified: 2026-09-11T15:54:57.050Z
---

Measured 2026-09-11 in `speedmerchants`, three separate times in one hour.

## The failure

Editing a grader through `python - <<'PYEOF'` to insert a PowerShell regex like `'ReachableShape\b'`
produced a pattern containing a literal **backspace byte (0x08)** instead of the two characters
backslash-b. The clause then matched nothing and reported `no ReachableShape` about a file containing
four occurrences of it. `od -c` was what finally showed it.

Two mechanisms compound:

1. **The heredoc collapses `\\` to `\`.** Even quoted (`<<'PYEOF'`), the sequence arriving at Python
   was single-backslash.
2. **`\b` and `\a` are VALID Python escapes** (backspace, bell). Unlike `\s`, `\w`, `\p`, which emit
   `SyntaxWarning: invalid escape sequence`, these produce **no warning at all** — they just silently
   become control characters. The warning you *do* see for `\s` trains you to think the ones without a
   warning are fine.

A sweep of the whole corpus found a second, older instance: `Write-TaskList.ps1` carried a BELL where
`.loop\proof\adapter-input-refusals.json` should read — same cause, months of quiet.

## The habit

- **Never write backslash sequences through a heredoc.** Write the script to a file (Write tool), then
  `python that_file.py`. Nothing collapses anything.
- Build literal backslashes as `chr(92)` rather than typing them, when the content must survive layers.
- After any edit that touched backslashes, sweep for control bytes — it is one line and catches
  the invisible ones:

```python
sum(pathlib.Path(f).read_bytes().count(bytes([x])) for x in (7, 8, 11, 12))
```

- A grader asserting a token that demonstrably exists in the file is this bug until proven otherwise.
  Check the bytes before re-reading the logic.

Same family as [[reference_loop_criteria_quote_mangling]] and the earlier `.loop\tools` →
`.loop<TAB>ools` mangling; that one was a TAB (`\t`), which is also a valid escape and also silent.
