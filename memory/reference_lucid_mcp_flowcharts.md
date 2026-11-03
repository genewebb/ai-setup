---
name: reference-lucid-mcp-flowcharts
description: Lucid MCP (claude.ai Lucid) works for code-derived flowcharts; first doc = UnifiedMatchingScenario flow 2026-11-02
metadata:
  node_type: memory
  type: reference
  originSessionId: 62c265a6-dcf5-4d96-8247-fe0dac9d10ce
  modified: 2026-11-02T15:13:20.330Z
---

Lucid MCP connected and verified 2026-11-02. Gene approved the output.

- First doc: UnifiedMatchingScenario execution flow — https://lucid.app/lucidchart/bdd93a62-8830-4a8d-afa5-8f8f3f59f7ba/edit
- Working recipe: read `lucid://skills/readme` + `lucid://skills/diagram-specification`, then `lucid_create_diagram_from_specification` with `use_assisted_layout=true`, elbow smart lines (no endpoint positions), no containers; verify with `lucid_export_document_as_PNG`.
- Gotcha: assisted layout keeps fixed box sizes, so long text shrinks (text-fit warnings ~56 chars per 280x100 box). Keep shape text short or box sizes proportional.

**Why:** reuse the recipe for future diagrams without re-deriving.
**How to apply:** when Gene asks for a Lucid diagram of code flow, read the code first (skill docs can be stale — see [[testauto-matching-scenarios]] topology ref), then use this recipe.
