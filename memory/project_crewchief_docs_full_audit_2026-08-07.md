---
name: crewchief-docs-full-audit-2026-08-07
description: Full CrewChief doc audit/update 2026-08-07 — what was added and what remains authoritative
metadata: 
  node_type: memory
  type: project
  originSessionId: 009eacec-06ba-4a48-9aec-b7bd692a2bd4
  modified: 2026-08-07T20:56:07.599Z
---

Full doc sweep of CrewChief docs (2026-08-07) against commits 4a9ee933..8070cd71 (8/4–8/7).

Added/updated:
- NEW `49_WorkloadConnectImport.md` (Workload Guides, order 60) — /connect-import page guide; cross-linked from 16_StepGuideConnEx tip and 30_OpsWebUi.
- `31_OpsSecretsAndNotifications.md` — new "Credential Masking in Logs" section (SecretScrubber two layers, `***` mask, min length 4, `{{` never registered, exception/template-literal gaps).
- `30_OpsWebUi.md` Pages list — added Templates, Connect Import, Backup & Restore, Secrets, Setup Verification (was 5 of 10 nav pages).
- `30_OpsCli.md` — grammar gained validate/backup/restore/seal-secret/unlock/secrets verbs; exit code 4 (preflight refusal); validate --strict semantics.
- `40_ReferenceConfigKeys.md` — added CrewChief:Preflight:* (2/2/5 defaults), WebUI page-size keys (25 / [10,25,50,100]), WebUI:Secrets:RevealGrantMinutes (30).
- Census 20/21→22: README.md, 01_DeveloperGuide, DeveloperPack 00 (tree+§4+§5), plus WebSiteStep row in 20_WorkloadComposing inheritance table; StepTypeRegistry XML comment six→seven box-prep.
- DeveloperPack: 00 §9 "Deltas since 2026-07-17" (Teams, Connect Import, masking, local-account auth, WindowsAccountName, WebSite, Configure custom actions; old "Session deltas" folded in, Open questions renumbered §10); 04 ConnEx row gained WaitForBatch; 05 H-2 update note (SecretOutputMasker at orchestrator choke point + enricher = substantially mitigated; residual: non-parameter secrets, attached exceptions); 07 inventory update note (2,748 methods/199 files unit, 36 integration).

Facts verified: 22 step types (registry), 61 switches / 60 default-on (catalog), [[crewchief-secretscrubber]] register sites = EffectiveIdentity, CapabilitySubsystemRegistration (DB-ops + SetApiKey), ConnExExecutor apiKey. WindowsAccountName + BuildProfiseeIdentityScript are DORMANT seams (tests only, no executor consumer yet) — do not document as behavior.

Callout convention in CrewChief Documentation/: UPPERCASE GitHub style (`> [!WARNING]`, `> [!TIP]`) with bold first sentence, no title on tag line.
