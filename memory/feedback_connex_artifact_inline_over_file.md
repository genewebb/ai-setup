---
name: feedback_connex_artifact_inline_over_file
description: Prefer inline artifactJson in the ConnEx step over a file on disk; only use a file if forced
metadata: 
  node_type: memory
  type: feedback
  originSessionId: df74bf7b-6453-4a7b-be5d-cc30f76c3a42
---

For ConnEx import steps (MultiStepUtilityScenario / ConnExStep), store the artifact **inline** as `artifactJson` in the step's CustomParms rather than pointing `artifactFile` at a JSON file on disk — as long as it fits (a SQL ServiceConfiguration artifact is ~1.5–2K; the whole ScenarioConfiguration is BROTLI-compressed anyway, so it fits comfortably under the 4000-char Profisee attribute limit). Only fall back to `artifactFile` if the artifact genuinely can't fit.

**Why:** inline travels with the scenario (portable across machines — no per-machine file distribution), is visible/editable in the stored config, and goes through the tokenization flow. A stray raw-export **file** on one machine is exactly what caused the [[project_connex_import_vaultid_bug]] (untokenized vaultId credentials).

**How to apply:** when generating/fixing ConnEx import scenarios, set `artifactJson` to the tokenized artifact and leave `artifactFile` null. See [[connex-import-tokenization]]. ConnExExecutor already supports either (exactly one of ArtifactFile/ArtifactJson).
