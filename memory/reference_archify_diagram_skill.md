---
name: reference-archify-diagram-skill
description: "archify skill — Gene's installed diagram tool for architecture, sequence, data-flow and state diagrams; use it instead of hand-writing SVG or raw Mermaid"
metadata: 
  node_type: memory
  type: reference
  originSessionId: 34c06f04-ada7-44f8-a3e4-66dc2a3c5365
  modified: 2026-09-02T21:52:22.235Z
---

**`archify` is installed and Gene asked for it to be used** (2026-09-02 17:51, when he added it).
Invoke it with the Skill tool: `Skill(skill="archify")`.

**What it makes:** polished, validated diagrams as **standalone HTML with inline SVG** — dark/light
themes, optional trace motion, and export to PNG/JPEG/WebP/SVG/WebM. It takes either plain-language
requirements or pasted Mermaid (`flowchart`, `sequenceDiagram`, `stateDiagram`), and **it will read
repository evidence when the diagram has to reflect real code** rather than a sketch.

**Reach for it when the answer is a picture:** system architecture, infrastructure and
cloud/security/network topology, technical workflows, API call sequences, request lifecycles, data
pipelines, ETL/ELT, data lineage, state machines — or to convert and beautify existing Mermaid.

**Do not hand-roll these any more.** Before writing SVG path data by hand, or pasting a raw Mermaid
fence into an artifact, or building a diagram out of divs and CSS, invoke `archify` instead. The
prior habit was `artifact-diagramming` plus hand-authored markup; this supersedes it for diagram
work.

**Good first targets in the speedmerchants vNext work** — all of them currently live only as prose in
`[[reference-vnext-plan-doc-v3]]`:

- The **run lifecycle** — declared → captured → observed, the ramp climbing from 1, break vs
  operator-stop as opposite endings. A state diagram, and the one most often explained in words.
- The **orchestrator-worker loop** — plan → checkpoint → Executor → six gates → re-baseline →
  PROGRESS → budget, with the rollback and `deviation-blocked` branches. See
  [[project-orchestrator-worker-loop-hardening]].
- The **two-catalog write path** — `dbo.RunRampStep` in the warehouse and `dbo.DesiredState` in the
  transport, which cannot share a transaction. That constraint has produced several defects and is
  hard to hold in the head from prose.

Related: [[feedback-publish-artifacts-and-archive]].
