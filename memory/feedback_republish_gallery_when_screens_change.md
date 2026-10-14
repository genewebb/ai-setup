---
name: feedback_republish_gallery_when_screens_change
description: "The mockup gallery Artifact is what Gene actually looks at; republish it whenever a mockup row changes screens, not only when the gate is ready"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: a2ce2bbb-6850-4044-9304-dc65407c6c01
  modified: 2026-09-15T08:42:47.380Z
---

Gene opened the gate-73 gallery Artifact (https://claude.ai/artifact/U2SNNUczR39FtL8EGGUiwX) and found it "still all black, not the correct palette": the page was the old dark instrument-kit publish from before the CrewChief redraw, because the loop was holding the republish until the batch verifiers passed. Hours of redraw and fix rows had landed in the vault while the only page he can see showed none of it.

**Why:** a gallery held back for a clean verdict reads as "the work is not done" and wastes the approver's look. The vault files are the source of truth, but Gene reviews through the Artifact.

**How to apply:** whenever a mockup row closes (or a batch of screens changes), rebuild the scratchpad copy per the PROMPTS.md batch-Artifact recipe and republish the gallery to its recorded URL in `.loop\tools\artifact-urls.json` (label it with what is still pending), then republish again after the batch verifiers. Publishing to an artifact not viewed this session needs `Artifact action: read` first. Remove superseded published paths with `null` entries in `files`. Related: [[feedback_gate_requires_viewable_navigable_ui]], [[feedback_republish_on_file_not_just_on_close]].
