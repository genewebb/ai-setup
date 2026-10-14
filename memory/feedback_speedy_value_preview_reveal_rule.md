---
name: feedback_speedy_value_preview_reveal_rule
description: "Speedy value-editor preview must show resolved values - reference data always, non-sensitive secrets always, sensitive secrets masked unless management unlocked (CrewChief parity, Gene 9/23)"
metadata:
  node_type: memory
  type: feedback
  originSessionId: 0359fc02-cccc-4830-81fb-20a4bcd43ea3
  modified: 2026-09-24T00:06:42.724Z
---

Value editor runtime preview (RuntimeReadout chip) shows RESOLVED values, not names:
- reference data: the entry's value
- secret entry effectively NOT sensitive: its resolved value, always
- sensitive secret: masked; actual value when the viewer's management unlock (ManagementGrantState.Valid) is valid
- composed templates follow the same rule per part

**Why:** Gene 9/23: duplicate CrewChief behaviour ("you see a preview of reference data, secrets, etc"). Earlier Speedy design said "names only, never a value in the page" — Gene overrode it for the editor preview. He said there were TWO CrewChief behaviours to duplicate but only stated this one.

**How to apply:** values come via ValueEditorCatalog.SecretPreviews / ReferenceValues built by ValueEditorCatalogBuilder.BuildAsync(names, owner, secretsUnlocked, ct) from the owner's DEFAULT profile, using InternalReferenceGraph.TryResolve + IsEffectivelySensitive (same as runs). Never widen beyond this rule (e.g. step output stays masked). Related: [[feedback_ui_parity_before_new]].
