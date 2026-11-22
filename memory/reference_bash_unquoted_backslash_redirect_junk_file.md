---
name: reference-bash-unquoted-backslash-redirect-junk-file
description: "Git Bash redirect to an unquoted Windows backslash path writes a junk file named D<U+F03A>tmp... into the cwd (repo root)"
metadata:
  node_type: memory
  type: reference
  originSessionId: 63467b00-779c-4e7e-bf25-13432d1bfd23
  modified: 2026-10-04T23:01:56.516Z
---

In the Bash tool (Git Bash), `cmd > D:\tmp\claude\...\scratchpad\out.txt` without quotes does not write to D:\tmp. Bash
treats each backslash as an escape and strips it. MSYS then maps the drive colon to U+F03A. The result is one flat file
in the cwd, usually the repo root, named like `D<U+F03A>tmpclaude...out.txt`. Measured 2026-10-04 with a G3.T057
verifier subagent (kit item IN-20261004224625-9f42). The watchdog reported the file as JUNK.

**How to apply:** in Bash, write paths with forward slashes (`D:/tmp/...`) and quote them. Any verifier or subagent
prompt that names a scratch path must give it with forward slashes. stream-build SKILL.md v0.7, step 7, now requires
this.
