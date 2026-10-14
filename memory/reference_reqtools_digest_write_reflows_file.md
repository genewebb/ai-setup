---
name: reference-reqtools-digest-write-reflows-file
description: reqtools digest --write re-dumps the whole YAML (reflows reviews/given text); for minimal pin-only diffs compute the digest and replace only the top-level revision sha256 line
metadata:
  node_type: memory
  type: reference
  originSessionId: 95aca75a-d861-42bc-b11b-f81f9361f105
  modified: 2026-09-25T12:05:00.631Z
---

`reqtools.py digest --write <file>` rewrites the entire artifact through `dump_yaml`, so hand-wrapped text (reviews `given`, findings, status_reason) gets reflowed. A pin-only file then shows 40+ changed lines instead of only `sha256:` lines, which muddies the pin-only claim a reviewer must check.

**How to apply:** run `digest <file>` without `--write` (it prints `MISMATCH <computed sha>`), then replace only the top-level `revision:\n  canonical_form: speedy-canonical-v2\n  sha256: <x>` line textually, and re-run `digest` to confirm MATCH. The digest is formatting-independent, so the result is identical. A helper doing this was used in the trip-wires-cadence-r1 build (finish tracker row A5, 2026-09-25). Related: [[project-requirements-finish-tracker-2026-09-24]].
