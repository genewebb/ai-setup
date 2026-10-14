
# Speedy context and authority

Verify these sources on each use. This is operating context, not product decisions or approval.

| Purpose | Location |
|---|---|
| Requirements root | `{VaultDocsRoot}\speedy\requirements` |
| Obsidian relative root | `99 Documentation/speedy/requirements/` |
| Authority | `RequirementDesign.md`, `manifest.yaml`, matching templates/schemas and `schemas/canonical-form.md` under that root |
| Implementation | `{SpeedyRepo}` |
| Read-only donor applications | `{SpeedMerchantsRepo}` |
| Tool | `{SpeedyRepo}\tools\requirements\reqtools.py` |
| Authoring skill | `{AIWorkRoot}\skills\requirements-writing\SKILL.md` |
| Goal clarification skill | `{AIWorkRoot}\skills\goal-builder\SKILL.md` |
| Handoff outputs | `review/handoffs/` below the requirements root unless the user specifies another location |

Read the current task/checkpoint for its area and order. Do not store the evolving queue, question answers, counts or approval state in this skill. Secrets is an example, not its permanent scope.

YAML owns normative definitions. Generated Markdown, handoff notes and prompts cannot override it. SRC/BEH records describe donors, candidates own inclusion/mappings, and targets/supporting contracts own intended obligations.

The current standard uses whole-artifact readiness and tool-computed normative revisions excluding approvals/evidence. Binding consumers pin prerequisite revisions. ANSWERED_PENDING_APPLICATION blocks until its effect is fully applied and checked. Consult live review/approval rules, the complete author list and scoped delegations. A fresh Claude or Codex session does not independently review that same tool's authored revision. Preparing a prompt does not grant approval.

Preserve exact approved contents in a bundle or outside live discovery so duplicate YAML IDs cannot enter validation. Source evidence and excluded examples remain distinct from obligations. Validate required source-reference integrity as well as the definition closure.

Use the named tool and canonical form on a local snapshot; inspect supported commands rather than inventing an area-release subcommand. Do not change application code, tooling or .loop orchestration merely to prepare a handoff.

Vault writes use Obsidian's Local REST API so its index sees them. An existing authenticated connector/API or this helper is suitable:

```text
pwsh "{ClaudeHome}\bin\Write-AIFile.ps1" -Path "{VaultDocsRoot}\speedy\requirements\<relative-path>" -Source <local-file>
```

Read before writing, reconcile unexpected changes, and verify readback. Never embed the API key or assume a new session has the previous session's credential file.

Evidence follows the current schema and `evidence/<artifact-ID>/<revision>/<VERIFY-id>.yaml` convention, preserving attempt and implementation identities. If the implementing session cannot publish through the authorized vault writer, it stages evidence for the coordinator; it does not silently write directly to the share.
