---
name: reference-gitbash-grep-cr-count-lies
description: "Git Bash grep -c $'\\r' reports every line as matching on LF-only files; count CRLF with python bytes instead"
metadata:
  node_type: memory
  type: reference
  originSessionId: 0ea61e79-068c-4a42-9300-94ed42155416
  modified: 2026-09-24T17:38:24.874Z
---

On this box, Git Bash `grep -c $'\r' file` returned the full line count for vault YAML files that are pure LF (python `read_bytes().count(b'\r\n')` = 0). On 2026-09-24 I trusted it, "restored" CRLF on four staged requirement files, and made whole-file diffs. Separately, a Python `read_text()` then `write_bytes()` silently normalises CRLF to LF.

**How to apply:** check line endings only with `python -c "b=open(p,'rb').read(); print(b.count(b'\r\n'), b.count(b'\n'))"`. The Speedy requirements vault files are LF. Related: [[reference-backslash-escapes-become-control-bytes]].
