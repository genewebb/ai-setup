---
name: reference_pin_fixpoint_regex_traps
description: Two traps in a textual pin-propagation fixpoint over the Speedy requirements corpus (found 2026-09-26, backup-location-install-r1)
metadata:
  type: reference
---

A textual re-pin script over `relations` blocks misses pins in two ways:

- **Key order varies.** Some relations put `reason:` between `target:` and `revision:` (e.g. FEAT-TESTDATA-GENERATION-001 -> FEAT-TESTDATA-RUN-001). A `target:\n revision:` regex skips them; the validator then shows `impact review due`. Allow an optional multi-line `reason:` block.
- **Re-runs forget intermediate digests.** If an edit is made after a first fixpoint run, pins now hold the run-1 digest, which is neither the live digest nor current. Take "superseded" from the LIVE corpus revisions and also treat any pin value absent from the live file text as introduced-by-this-operation.

Check: zero `impact review due` warnings beyond baseline, and a masked structural compare (revision/status/status_reason/relation pins) of every pin-only file against live. Installer/CLI edits fan out to ~46 artifacts.
Related: [project_speedy_requirements_amendment_protkey_2026-09-20](project_speedy_requirements_amendment_protkey_2026-09-20.md).
