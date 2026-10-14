---
name: skill-audit-with-update
description: >
  Skill audit and update workflow for Claude Code × speed-merchants — full scan, persistent backlog,
  per-item approval, deep description review, and baseline-independent full-corpus review against
  live code. Use when auditing skills, finding missed patterns in docs or source, continuing from a
  saved backlog, applying approved candidates, re-verifying the corpus against code, or reconciling
  an in-repo AGENTS.md into the skill+memory corpus.
---

# Skill Audit with Update — Claude Code × speed-merchants

Audits speed-merchants (docs **and** source code) for missing or weak skills, manages a persistent backlog across sessions, and applies approved changes with per-item granularity. The read-only `skill-audit` skill has been retired — since every action requires per-item approval, a separate read-only mode was redundant.

---

## Entry Points

Always ask the user which mode to run at the start of each invocation:

| # | Mode | When to use |
|---|---|---|
| 1 | **Fresh scan** | First run, or scheduled re-audit. Scans speed-merchants end-to-end and rebuilds the pending backlog. |
| 2 | **Continue from backlog** | Pick up where a previous session stopped. Shows pending and approved items for action. |
| 3 | **Apply approved** | No scanning. Implements all `Approved` items from the backlog immediately. |
| 4 | **Deep description review** | Audits existing skill descriptions for semantic accuracy against real code. Produces an approval-gated list of description rewrites. |
| 5 | **Reconcile in-repo agent docs** | Decomposes a repo-local `AGENTS.md`/`Agents.md` (often a live, tool-accreted memory file) into the durable corpus: facts → skills, preferences → memory, stale → flag. Use when the repo has agent-instruction files that overlap or duplicate skills. |
| 6 | **Full corpus review against code** | Baseline-independent re-verification of every speed-merchants-coupled skill's *full content* (not just descriptions) against live code. Use periodically even when the repo hasn't changed — as models improve, a re-review of an unchanged corpus finds errors and gaps earlier passes missed. |

---

## Inputs (Configuration)

| Setting | Default | Notes |
|---|---|---|
| **Skills source-of-truth root** | `{AIWorkRoot}\skills\` | All SKILL.md writes go here. Obsidian IS the source of truth — no separate sync needed. |
| **Claude Code skills directory** | `~\.claude\skills\` | Read-only — junction → `~\AI\skills` → vault `skills\<name>`. New entries created via linker only. |
| **Linker script** | `{AIWorkRoot}\link-to-ai.ps1` | Creates `~\AI\skills\<name>` junction for each new skill. |
| **Scan target** | `{SpeedMerchantsRepo}\` | Read-only source. |
| **Backlog file** | `{AIWorkRoot}\skill-backlog.md` | Persistent state across sessions. Already in Obsidian — no separate copy needed. |
| **Excluded subpaths** | `TestResults/`, `**/bin/`, `**/obj/` | Generated output — skip during scan. |

---

## Backlog File Format

Lives at `{AIWorkRoot}\skill-backlog.md`. Create on first run if it doesn't exist.

```markdown
# Skill Backlog

_Last audited: <YYYY-MM-DD> | baseline: <HEAD-commit-sha> | mode: <1-6> | yield: <N new, M ext, …>_

## Approved (awaiting implementation)

## Pending (awaiting review)

## Deferred

## Excluded

## Implemented
```

Each item in any section uses this format:

```markdown
### <id> — <skill-name>
- **Kind**: new | ext | hyg | gap | desc
- **Target**: <skill name to create or modify>
- **Score**: <0–10> (omit for hyg/desc kind)
- **Description**: <one-line summary of what this candidate does>
- **Sources**: `path/to/file.cs`, `path/to/other.md`
- **Added**: <YYYY-MM-DD>
- **Notes**: <reason for deferral, exclusion, or approval tweak>
```

IDs are stable across sessions: `<kind>-<kebab-name>` (e.g., `new-testauto-entity-resolution`, `ext-testauto-matching-scenarios`, `desc-dotnet-service-registration`). Never reassign an id.

---

## Process

### Mode 1 — Fresh Scan

#### Step 0 — Diff-since-baseline gate (do this FIRST)

Before any fan-out, decide whether a full scan is even warranted:

1. Read the backlog header's `baseline: <sha>` field (see Backlog File Format). This is the commit HEAD pointed at during the last audit.
2. Get the live state: current `HEAD` sha, working-tree status, and the commit list `baseline..HEAD`.
3. **If HEAD == baseline and the working tree is clean**, the committed surface is byte-identical to the last sweep. Per the idempotency rule a full re-scan yields ~zero. Say so plainly, show the evidence (last-audit date, baseline sha, "0 commits since"), and **confirm intent before fanning out** — offer a cheaper alternative (targeted subsystem scan, or stop). Do not auto-pilot a wasteful re-scan.
4. **If HEAD has moved**, prefer scanning the `baseline..HEAD` diff first (changed files are the highest-yield surface), then widen only if asked.
5. Record the new baseline (current HEAD sha) in the header when you write the backlog in Phase 6.

> No git baseline available (first run, or no commits)? Skip the gate and do the full Step 1–5 scan. Read-only git inspection (log/status/rev-parse) is fine; never run state-changing git here.

#### Step 1 — Inventory existing skills

1. List every entry under `{AIWorkRoot}\skills\`. For each, read `SKILL.md` frontmatter.
2. Build inventory table: Name | Description (first ~120 chars) | Has SKILL.md?
3. Drop plugin-cache entries from coverage matching — note them. (The `infographic-*` family that used to be excluded here was retired 2026-07-25 — zero invocations in 540 sessions, no target repo.)

#### Step 2 — Catalog the speed-merchants knowledge surface

Scan two layers:

**Layer A — Documentation**

| Source area | Glob | What it contains |
|---|---|---|
| Root instruction files | `AGENTS.md`, `CLAUDE.md` | Project-wide rules for AI agents |
| Repo docs | `docs/**/*.md`, `documentation/**/*.md`, `**/Documentation/**/*.md` | Structured repo-level docs |
| Root markdown | `*.md` at repo root | README, onboarding, references |

**Layer B — Source code** (skip `**/bin/`, `**/obj/`, `TestResults/`)

Use scoped grep/glob queries, one per topic area (e.g., `"service registration"`, `"scenario metrics"`, `"record transformation"`, `"matching configuration"`, `"stewardship operations"`), then glob the surrounding files. The returned file list is the evidence for scoring.

| Source area | Glob | What to look for |
|---|---|---|
| C# source | `**/*.cs` | Repeated helper patterns, service call conventions, naming rules, config patterns |
| Test/scenario files | `**/*Tests.cs`, `**/*Scenario*.cs` | Setup patterns, fixture conventions, recurring test shapes |
| Config files | `**/*.json`, `**/*.yaml`, `**/*.yml` at root or `config/` | Schema shapes, required fields, enum values an agent would need |

Flag: (a) comment blocks explaining a convention, (b) methods or classes appearing in 3+ files in similar form, (c) naming patterns not obvious from a single file, (d) TODO/FIXME comments pointing to undocumented constraints. Scope greps to a subsystem folder rather than globbing `**/*.cs` from the repo root — broad root globs are slow and noisy.

**Recommended method for large repos — parallel subsystem fan-out.** When the repo has many projects/subsystems (speed-merchants has 24+), don't sweep serially in one context. Partition into logical subsystems (e.g. matching/connect, scenarios/records, web/blazor, shared-infra, cli/utilities, docs) and dispatch one **read-only Explore agent per subsystem** in parallel. Critically, **hand each agent the existing-skill inventory as a filter** so the Step-3 "already covered?" decision happens at the leaf — each agent reports only *uncovered*, 3+-file, reusable patterns + evidence paths, plus suspected-stale docs. This keeps an idempotent re-scan from regurgitating covered patterns and returns conclusions, not file dumps. Treat agent findings as *claims to verify*, not facts (see the verification gate in Step 3 and Rules).

#### Step 3 — Classify each candidate

```
Ephemeral? (dated filename, TestResults/, generated code, per-bug file)
├── YES → Skip
└── NO  → Does an existing skill fully cover this?
         ├── YES → Already covered (note skill name)
         ├── PARTIAL → Extend existing (note skill + gap)
         └── NO → Reusable (>2 asks)? Stable? Non-derivable from running code?
                  ├── YES to all → New skill
                  └── NO         → Skip (too narrow / ephemeral)
```

**Coverage probe (how to answer "already covered?").** Don't read whole skills to decide. Grep the **skills corpus** (`...work-ai\skills\`) for the candidate's *distinctive term* (a class name, method, config key, convention phrase):

- 0 hits → genuine gap → candidate for **new**.
- hits, but the matched skill only mentions it in passing / one example → **PARTIAL → ext** (note the skill + the specific gap).
- hits with a dedicated section → **covered → skip**.

This is the fast, reliable way to confirm COVERED vs PARTIAL vs gap, and it's what keeps re-scans idempotent.

**Verification gate (mandatory).** Any claim that a class/method/doc is **stale, deleted, renamed, or "consolidated"** — whether it came from a sub-agent or your own grep — MUST be confirmed against live code before it becomes a candidate or an edit. Grep the scan target for the class/method by name; if it still exists, the claim is a false positive — drop it. (Real example: a sub-agent reported `ScenarioBaseCrud`/`ScenarioBaseMetadata` as deleted; both still existed. Trusting it would have written a wrong "fix.")

**Findings-routing — not every finding is a skill.** Route each finding to the right store:

| Finding type | Goes to |
|---|---|
| Reusable code pattern / convention (3+ files) | New or extended **skill** |
| Behavioral preference ("always do X", "prefer Y") | **Memory** (feedback type), NOT a skill |
| Stale **repo** doc (scan target is read-only) | **Informational** — surface to user; never auto-fix unless the user explicitly authorizes a repo edit |
| Skill citing a now-removed source file | **Hygiene** — annotate the dangling citation (see Phase 4C) |

#### Step 4 — Score each candidate

Apply to every `new` and `ext` candidate (skip `hyg` and `desc`):

| Factor | 0 | 1 | 2 | 3 | 4 |
|---|---|---|---|---|---|
| **Frequency** — distinct files/locations referencing the pattern | — | 1 file | 2–3 files | 4–7 files | 8+ files |
| **Recency** — last git-modified weight | >1 yr ago | 6–12 mo | 1–6 mo | <1 mo | — |
| **Onboarding gap** — would a new dev need this explained? | No | Maybe | Probably | Definitely | — |

Max score = 10. Sort all candidates descending. Present highest-score items first.

#### Step 5 — Load or create backlog, add new candidates

1. If `skill-backlog.md` exists, read it. Carry forward all existing sections. Never re-add an item whose id already appears in any section.
2. If it doesn't exist, create it from the template above.
3. Add all new candidates to `## Pending`, sorted by score descending.
4. Print: "Scan complete. X new candidates added to Pending. Backlog: Y pending, Z approved, W deferred."
5. Ask: "How many pending items would you like to review now?" Then proceed to Phase 3.

---

### Mode 2 — Continue from Backlog

1. Read `skill-backlog.md`.
2. Report counts: "Backlog: Y pending, Z approved, W deferred, V excluded, U implemented."
3. Ask: "What would you like to do?"
   - **Review pending** — walk through `## Pending` items via Phase 3
   - **Apply approved** — jump to Phase 4 for all `## Approved` items
   - **Both** — approved first, then pending
4. Proceed accordingly.

---

### Mode 3 — Apply Approved

1. Read `skill-backlog.md`.
2. Load all items in `## Approved`. If none, report and stop.
3. Skip Phase 3 — go directly to Phase 4 for each item in order.
4. After each item, move it from `Approved` to `Implemented` in the backlog.

---

### Mode 4 — Deep Description Review

For each skill in the inventory (excluding plugin-cache entries):

1. Read the full `SKILL.md` from the vault path: `{AIWorkRoot}\skills\<name>\SKILL.md`.
2. **Search actual source code first (Layer B)** — this is the primary signal:
   - Grep `**/*.cs` and `**/*Tests.cs` in speed-merchants for each trigger phrase in the description — the patterns, classes, or conventions the skill claims to cover. Scope to the relevant subsystem folder where possible.
   - Count how many distinct files contain usages of each pattern the description mentions.
   - Find patterns in the code that the description does **not** mention — these are missing triggers.
3. **Then cross-check docs (Layer A)** — AGENTS.md, CLAUDE.md, and any `docs/` markdown — for references that contradict or extend what you found in code.
4. **Use Obsidian search** for additional signal: `mcp__obsidian__search_simple` with key terms to find vault notes referencing patterns not yet mentioned in the skill description. These are missing trigger candidates.
5. Produce a gap table for the skill:

   | Claim in description | Found in code? | File count | Status |
   |---|---|---|---|
   | "Use when configuring X" | Yes | 6 | OK |
   | "Use when calling Y" | No | 0 | **Stale — remove** |
   | _(not mentioned)_ pattern Z | Yes | 4 | **Missing trigger** |

6. Flag any description that is (apply the **verification gate** from Step 3 — confirm a "0 files" result with a name-based grep across the whole scan target before calling anything stale; a scoped grep can miss real usages):
   - **Stale** — references patterns, files, or commands that appear in 0 code files
   - **Incomplete** — code contains 3+ files using a pattern the description doesn't mention
   - **Misleading** — description implies narrower scope than actual usage frequency warrants
   - **Format non-compliant** — doesn't follow `<noun phrase>. Use when <triggers>.`
7. Build a `desc-*` candidate for each flagged skill, with the proposed new description string and the gap table as evidence.
8. Add candidates to `## Pending` in the backlog, then proceed to Phase 3 for approval.

---

### Mode 5 — Reconcile In-Repo Agent Docs (`AGENTS.md` / `Agents.md`)

Repos often carry agent-instruction files (`AGENTS.md`, `Agents.md`, per-module guides). Some are **live, tool-accreted memory** — OpenCode and GitHub Copilot use repo-root `AGENTS.md` as their workspace-instructions file and append learned facts to it (signature headers: `## Learned User Preferences`, `## Learned Workspace Facts`). Claude Code uses `CLAUDE.md`, never `AGENTS.md`. This mode decomposes such a file into the durable corpus.

#### Step 1 — Find and read the agent docs
Glob the scan target for `AGENTS.md`, `Agents.md`, `**/AGENTS.md`, `**/*.agent.md`. Note: these may be **gitignored** (so `git ls-files` won't show them but the file exists on disk — check with Glob/Read, not just git).

#### Step 2 — Identify the writer (so the user knows it'll regenerate)
A clean module guide (hand-written, code-coupled) is a one-time migration. A file with `## Learned ...` accretion headers is **written by an external tool** (OpenCode/Copilot). Deleting it does NOT stop the writer — it regenerates on the next run. Tell the user which tool owns it and that redirecting future learnings is a change to *that tool's* config, outside this skill's reach.

#### Step 3 — Classify each line/section, then route (apply the Step-3 verification gate + findings-routing table)
| Line content | Route |
|---|---|
| Reusable code pattern/convention | Fold into the relevant existing skill — **gaps only** (use the coverage probe; don't duplicate) |
| Behavioral preference | **Memory** file (feedback type) — not a skill |
| Already covered by a skill | Skip (note which skill) |
| Stale (renamed/removed class) | **Verify first**; if truly stale, flag — don't migrate wrong info |
| Tool-specific / conflicts with an existing skill | Skip (note why, e.g. Cursor `.cursor/documentation` conflicts with `documentation-location`) |

#### Step 4 — Approval + apply
Present the disposition as a per-line table for approval (Phase 3 style — this is a mutation, approval is non-skippable). On approval: make the skill extensions (Phase 4B) and memory writes, then produce a **full line-by-line disposition report** so the user can delete the source file with confidence.

#### Step 5 — Hand off deletion
Do **not** delete the source file yourself (read-only scan target + the no-state-changing-git rule). Tell the user it's safe to delete and how. If skills cited the file in `## Sources`, run the dangling-citation hygiene check (Phase 4C).

---

### Mode 6 — Full Corpus Review Against Code

A baseline-independent re-verification sweep of the whole skill corpus against live code. Where Mode 4 audits only the `description:` frontmatter, Mode 6 audits **every factual claim in every skill's full body** (and `references/` files). The Step-0 diff gate does NOT apply — an unchanged repo is not a reason to skip this mode. Rationale: the reviewing model improves between sessions, so a re-review of byte-identical skills + code still surfaces errors, omissions, and misleading framing that earlier passes missed.

#### Step 1 — Scope the corpus
1. Inventory the vault skills root (as Mode 1 Step 1).
2. Keep only **speed-merchants-coupled** skills: those whose `## Sources` cite the scan target, or whose content documents classes/patterns/config living in it. Drop plugin-cache entries and pure meta/tooling skills (e.g. permissions/client-config) — note what was dropped and why.
3. Partition the in-scope skills into batches of roughly 4–8 by subsystem affinity (matching, connex, workflow, config-store, web/blazor, testing, shared-infra, …) so each reviewer greps one neighborhood.

#### Step 2 — Parallel review fan-out
Dispatch one **read-only Explore agent per batch**, in parallel. Each agent receives: the full paths of its skills, the scan target, and these instructions:

- Read each SKILL.md fully (plus its `references/`).
- Extract every *checkable* factual claim: class/method/property names, signatures, file paths, DI registrations, config keys, constants and their values, enum members, behavioral assertions ("X throws when…", "Y defaults to…"), tables of values.
- Verify each claim against live code by name-based grep + targeted read. Classify: **OK** / **STALE** (referent gone or renamed) / **WRONG** (referent exists but the claim misdescribes it) / **DRIFTED** (was true, code has since changed) / **GAP** (code has a closely-adjacent pattern, ≥3 files, the skill should cover but doesn't).
- Report ONLY non-OK findings, each with: skill, claim (quoted), evidence file:line in live code, and proposed correction. No file dumps.

Agent findings are **claims, not facts** — every non-OK finding goes through the Step-3 verification gate (confirm by your own name-based grep/read) before it becomes a candidate. Expect and discard false positives.

#### Step 3 — Candidate construction
For each verified finding build a backlog item: `desc-*` (frontmatter/description wrong), `hyg-*` (dangling citation, naming), or `ext-*` (WRONG/DRIFTED body content to correct, or GAP content to add — a body-content *correction* is kind `ext` with a **Notes: correctness fix** marker). Score `ext` candidates with the Step-4 rubric; `desc`/`hyg` are unscored. Add to `## Pending`, then run Phase 3 approval as usual.

#### Step 4 — Record the sweep
Write the backlog header with `mode: 6` and the current HEAD sha (recorded for provenance even though the mode ignores it), plus a note of corpus size reviewed vs. findings yield — this lets future sessions judge how often Mode 6 is worth re-running.

---

### Phase 3 — Per-Item Approval

For each item being reviewed, present a card. If the pending list is long, first ask: "There are N pending items. How many would you like to review this session?"

**Card format:**

```
─────────────────────────────────────────────────────────
[ext-testauto-matching-scenarios]  Score: 8/10
Kind: ext  |  Target: testauto-matching-scenarios
Description: Add source data file format conventions from MatchingScenarioBase.cs
Sources:
  src/TestAuto.Scenarios/Matching/MatchingScenarioBase.cs
  src/TestAuto.Scenarios/Matching/MatchDataLoader.cs
Proposed additions:
  • Table: supported source file formats + expected column names
  • Rule: file naming must match scenario name (case-sensitive)
  • Example: referencing a source file from config JSON
─────────────────────────────────────────────────────────
```

Approval options per card:
- **Approve as proposed** — move to `Approved` in backlog.
- **Approve with changes** — user provides a tweak; re-present the modified card before approving.
- **Defer** — move to `Deferred` with an optional note.
- **Exclude** — move to `Excluded` with a required reason (won't surface again).

Write the updated backlog after each card decision. Do not apply any candidate until it is in `Approved`.

---

### Phase 4 — Apply Changes

For each approved candidate:

#### A. Create a new skill

1. Choose kebab-case name (no `-agent` suffix, no editor branding, no `claude-` prefix).
2. Create folder: `{AIWorkRoot}\skills\<name>\`
3. Create `SKILL.md` using the template at the bottom of this skill.
4. Synthesize body from cited source files — include concrete examples, tables, decision rules.
5. Add a `## Sources` section citing all speed-merchants paths used.
6. If reference material is large, use a `references/` subfolder with a "Documentation Structure" section in the main file listing each reference file.
7. Move item from `Approved` → `Implemented` in backlog.

#### B. Extend an existing skill

1. Read the target `SKILL.md` from the vault skills path.
2. Identify the correct section to extend — do not blindly append.
3. Use targeted string-replace with enough surrounding context to be unambiguous.
4. Expand frontmatter `description:` if the extension adds new trigger phrases.
5. Move item from `Approved` → `Implemented` in backlog.

#### C. Hygiene fix

- **Naming** (e.g., `-agent` suffix, PascalCase, editor branding):
  1. Rename the folder under vault `skills\`.
  2. Update frontmatter `name:` to match.
  3. Update `link-to-ai.ps1` to reference the new name, and grep the vault for inbound references (`Overview/README.md`, `skill-backlog.md`, `[[wikilinks]]` in other skills) and update them.
  4. Warn: existing junction `~\AI\skills\<old-name>` must be deleted manually before re-running the linker.
- **Description framing**: Rewrite to `<noun phrase>. Use when <triggers>.` Preserve YAML block format.
- **Broken symlink**: Check whether source folder exists in vault. If yes — stale junction, tell user to re-run linker. If no — skill deleted; ask whether to remove the stale junction.
- **Dangling source citation**: When a source file is removed or migrated (e.g. a reconciled `AGENTS.md`), grep the skills corpus for that path. For each skill that cites it in `## Sources` (or body), annotate the citation — match the existing convention: `— *source removed <date>; content migrated to work-ai, this skill is now canonical*`. Don't silently leave citations pointing at files that no longer exist.

#### D. Description rewrite (`desc` kind)

1. Read the target `SKILL.md` from the vault skills path.
2. Write the new `description:` value using the approved wording.
3. Preserve all other frontmatter and body content exactly.
4. Move item from `Approved` → `Implemented` in backlog.

---

### Phase 5 — Update Linker and Refresh Junctions

For each new skill created in Phase 4A, add its name to the `$skills` array in `link-to-ai.ps1`. Preserve the existing multi-line grouped format. Do not add names that already exist in the array.

After updating the file, always run the linker immediately:

```powershell
pwsh "{AIWorkRoot}\link-to-ai.ps1"
```

This creates any missing junctions in `~\AI\skills\` and reports `EXISTS` or `LINKED` per entry. Do not ask the user to run it manually — run it here.

---

### Phase 5b — Regenerate the Overview README (mandatory)

`Overview\README.md` is the human-facing index of the corpus. It is a **derived artifact** built from every skill's `description:` frontmatter — never hand-edit it.

Any session that adds, removes, renames, or edits the description of a skill or agent **must** regenerate it:

```powershell
pwsh "{AIWorkRoot}\Overview\Generate-SkillsReadme.ps1"
```

Then prove it is current — this is the gate, not the generation:

```powershell
pwsh "{AIWorkRoot}\Overview\Generate-SkillsReadme.ps1" -Check
```

`-Check` exits `0` when the file on disk matches what the frontmatter would produce, and `1` when it is stale. **A session is not complete while `-Check` returns 1.**

Two failure modes to handle rather than ignore:

| Symptom | Cause | Fix |
|---|---|---|
| Script throws `Categories missing from $CategoryOrder` | A new skill landed in a category with no section | Add the category to `$CategoryOrder`, or map the skill in `$Overrides` |
| A skill appears under **General** unexpectedly | Its name carries no known prefix | Add an explicit line to `$Overrides` in the generator |

Because the "About" column is the part of each description **before** `Use when`, a skill whose description does not follow the house style renders badly here. That is a useful signal: fix the description, not the README.

---

### Phase 6 — Backlog State Write

Write the updated `skill-backlog.md` at the end of every session, even if the session ended mid-review. On any fresh scan, update the full header line — `_Last audited: <date> | baseline: <current HEAD sha> | mode: <n> | yield: <summary>_` — so the next session's Step 0 diff-gate can read the baseline machine-readably. This is what makes the workflow resumable. The backlog lives in Obsidian — no separate sync step is needed.

---

### Phase 7 — Report

```
Applied this session:
  New skills created:      <list of names, or "none">
  Skills extended:         <list of name + section, or "none">
  Hygiene fixes:           <list, or "none">
  Description rewrites:    <list, or "none">
  Linker entries added:    <count>
  Junctions refreshed:     <yes / no changes needed>

Backlog state:
  Approved (awaiting):     <count>
  Pending (unreviewed):    <count>
  Deferred:                <count>
  Excluded:                <count>
  Implemented (total):     <count>

Next steps:
  Restart Claude Code session                         ← pick up new skill index
  [if rename] delete ~\AI\skills\<old-name> first
```

---

## Taxonomy and Structural Conventions

| Convention | Rule |
|---|---|
| Name format | kebab-case, no `-agent` suffix, no editor branding |
| Description format | `<noun phrase describing what it is>. Use when <triggers>.` |
| Frontmatter | `name:` + `description:` required; `description:` may use `>` folded scalar |
| No branding | No "Cursor", "OpenCode", "Claude" in titles |
| Single source | Skills live only at `skills\<name>\SKILL.md` — no flat `work-ai\<name>.md` duplicates |

---

## Ephemeral vs. Skill-Worthy Heuristics

| Signal | Verdict |
|---|---|
| Filename contains a date (`_2026-04-28`, `Phase2_Final`) | Likely ephemeral |
| Filename has version suffix (`_v1`, `_v2`, `_v3`) | Look at latest only; older are ephemeral |
| Filename contains `Plan_`, `BUG_`, `ROOT_CAUSE_`, `Audit_`, `PRReview_` | Ephemeral unless it describes a **recurring** pattern |
| Contains schema tables, lookup tables, or enumerations an agent needs repeatedly | Skill candidate |
| Contains step-by-step CLI/setup instructions reused across repos | Skill candidate (often onboarding) |
| Methods or classes in 3+ files in similar form | Skill candidate (Layer B) |
| Comment blocks explaining a convention | Skill candidate (Layer B) |
| Grep returns 4+ files for this pattern with no covering skill | High-priority skill candidate |
| Located under `**/Results/`, `**/runs/`, `**/builds/<timestamped>/` | Ephemeral — skip |

---

## Impact Score Quick Reference

| Score | Action |
|---|---|
| 8–10 | High — prioritize in current session |
| 5–7 | Medium — do this session or next |
| 3–4 | Low — defer unless quick |
| 0–2 | Minimal — likely exclude |

---

## Rules

- **Never mutate without per-item approval.** Phase 3 is non-skippable (except Mode 3 which only processes already-approved items).
- **Write only to vault source-of-truth root.** Never write directly to `~\.claude\skills\` or `~\AI\skills\`.
- **No flat copies.** Skills live only at `skills\<name>\SKILL.md`. Obsidian indexes the whole vault recursively and Claude Code reads through the junction to the folder, so the old `work-ai\<name>.md` flat duplicates are not used — do not create them.
- **No path references to the retired roots** — the old `devopslocal\repos\work-ai` clone and the old local `MyWorkVault` vault. Both are archived — the vault moved to the NAS share (`{VaultWorkRoot}`) and the old local vault root now holds only `99 Documentation`. All paths use `{AIWorkRoot}\`. Corrected 2026-09-09, when every configured input in this skill was found pointing at the dead root.
- **Never overwrite an existing SKILL.md** when creating a new skill. If the target folder exists, ask: extend, rename, or skip.
- **Never delete files without explicit user confirmation.**
- **Never run state-changing git commands** (`git rm`, `add`, `commit`, `restore`, `mv`, `checkout`, …). The user does all git manually. To remove/move files, use filesystem ops on vault files you own, or hand the action to the user. Read-only git inspection (log/status/rev-parse/ls-files) is fine and is used by the Step 0 gate.
- **Verify before claiming stale/deleted.** Never record a "stale," "deleted," or "renamed" finding (yours or a sub-agent's) without a confirming name-based grep against live code. Sub-agent findings are claims, not facts.
- **Route findings correctly.** Behavioral preferences → memory (feedback), not skills. Stale repo docs → informational only (read-only target). Removed-source citations → annotate (don't leave dangling).
- **Write backlog state before ending the session**, even mid-run.
- **Regenerate `Overview\README.md` whenever a skill or agent is added, removed, renamed, or has its description changed** (Phase 5b), and end the session with `Generate-SkillsReadme.ps1 -Check` exiting 0. Never hand-edit that README — it is generated from frontmatter.
- **Cite source paths** in every new SKILL.md's `## Sources` section.
- **Deep description review** only runs in Mode 4 or when user explicitly opts in.
- **Full corpus review (Mode 6) ignores the Step-0 diff gate by design** — never decline it because "nothing changed"; the reviewer changed.
- **Do not edit files inside the scan target.** Read-only.
- **Idempotent.** Re-running on a synced framework with no new code changes adds zero new candidates to Pending.

---

## New Skill SKILL.md Template

````markdown
---
name: <kebab-case-name>
description: >
  <Noun phrase describing what it is>. Use when <comma-separated triggers>.
---

# <Human-Readable Title>

<One-paragraph overview of what this skill provides.>

## When to Use

- "<example user phrase 1>"
- "<example user phrase 2>"
- "<example user phrase 3>"

## <Topic Section>

...

## Examples

```<language>
<concrete example>
```

## Sources

- `{SpeedMerchantsRepo}\<path>`
- `{SpeedMerchantsRepo}\<path>`
````
