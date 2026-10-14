---
name: project_fable_foreman_quality_first
description: "Fable Foreman is installed in work-ai (symlinked, third-party) and re-policied quality-first — Fable plans/verifies/accepts, opus implements; an upstream update silently reverts it."
metadata: 
  node_type: memory
  type: project
  originSessionId: aa701f44-5fa5-4edf-ae81-2fc43ee32e4c
  modified: 2026-09-11T06:58:36.779Z
---

Installed 2026-09-11 from `https://github.com/olsenbrands/fable-foreman` (MIT, v0.5.0). It is the **only
third-party entry** in `work-ai`: skill at `work-ai\skills\fable-foreman`, its five `foreman-*` agents in
`work-ai\agents`, both registered in `link-to-ai.ps1` and symlinked into `~\AI` like everything else.

**Gene's routing policy replaced upstream's.** Upstream's First Law was "cheapest model that clears the
quality bar". It is now: *use the strongest economically reasonable implementation model by default; step
down only when the task is sufficiently mechanical or bounded that doing so is unlikely to reduce quality.*
Cost alone is never the argument.

    FABLE plans/decomposes/routes -> OPUS implements -> SONNET/HAIKU only when clearly suitable
    -> FABLE blind-verifies -> repair -> FABLE accepts

Agent frontmatter: `foreman-worker` = **opus**/high (was sonnet), `foreman-verifier` = **fable**/high (was
`inherit`), `foreman-scout` = haiku/low (unchanged). Grok was demoted from "first-choice implementation
seat" to adversarial review + explicitly-requested alternative; Codex and Grok support otherwise intact.
Pre-approval = authorization, never preference.

**AN UPSTREAM UPDATE OVERWRITES ALL OF IT.** Nine files were edited. The re-apply record and its
verification snippet live in `work-ai\skills\fable-foreman\LOCAL-CUSTOMISATION.md`; backups of every
pre-edit file are in that skill's `.backups\20260911-022449\`. `link-to-ai.ps1` carries a TO UPDATE note
pointing at it.

**Known residual risk, not fixable on disk:** a per-dispatch `model` override still outranks agent-file
frontmatter — that is the harness's design and removing it would break legitimate routing. The guard is
procedural: a step-down below `opus` on code-writing work requires a ledger rationale, so a defeat is
*visible* rather than prevented.

Do not migrate it out of the vault or treat its `NATIVE`/third-party status as drift.
See [[ai-repo-management]] conventions and [[reference_skill_linker_needs_symlinks_not_junctions]].
