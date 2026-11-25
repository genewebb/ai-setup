---
name: project_pack_generators_in_speed_merchants_2026-11-25
description: "Connect + common pack generators moved 11/25 from unmerged ai-setup branch to speed-merchants CrewChief/packs/tools/generators (0ea86a68)"
metadata:
  type: project
---

Gene 2026-11-25 09:46 (design D28 in planning/Design_CrewChief_ProfiseeContainerTesting.md): `gen_connect.py` and
`gen_common.py` (+ tests, source/, golden) now live in `CrewChief/packs/tools/generators/{connect,common}` in
speed-merchants, beside packgen. Before, they existed only on ai-setup branch `bug/ai-setup-updates/gene` (67d0b32,
never merged to main), so a box with ai-setup main had no generator at all.

Move proven byte-identical (both packs regenerate unchanged), generator tests 13 + 37 pass, Test-Pack PASS
(`-Family common` for common; default family is connect, so common without it fails "reference folder missing").

**Why:** generator and generated pack change in one commit; the Connect container lane (D27/D28) edits both.
**How to apply:** run `python CrewChief/packs/tools/generators/connect/gen_connect.py CrewChief/packs/connect`; the
install, matching and CRUD generators are still in ai-setup skills. packgen `__pycache__/*.pyc` are tracked in git and
get rewritten by every run: leave them unstaged. Related: [[project_crewchief_container_steps_2026-11-25]].
