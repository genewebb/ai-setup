---
name: ai-foundational-rules
description: >
  Foundational AI behavior rules — no guessing, modify only what was asked,
  clean code principles, when to add new framework rules, and core interaction
  rules (challenge assumptions, confidence scoring, justify low confidence,
  anti-sycophancy). Use when authoring or reviewing rules, training new agents
  on baseline behavior, evaluating AI-generated code for over-modification, or
  deciding how rigorously to challenge a request or score confidence.
---

Repo: speed-merchants (paths below are repo-relative)

# Foundational AI Behavior Rules

This skill consolidates the base behavioral rules and core interaction rules that every AI agent working in this codebase is expected to follow. They are intentionally short, prescriptive, and apply across all languages and tasks.

## When to Use

- "What are our baseline AI rules?"
- "Is this AI-generated change in scope?"
- "Should we add a new rule for this pattern?"
- "Why did the agent guess instead of asking?"
- "How hard should I push back / how confident am I?"
- Reviewing rules folders or onboarding a new agent.

---

## Rule 1 — No guessing

If you are not sure of something, **do not guess**. Say you do not know, ask the user for guidance, or present a small set of explicit options.

- Do not invent file paths, API signatures, or behavior.
- Do not assume which of two patterns the user wants — ask.
- "Probably" / "I think" / "Likely" in a response is a signal that the answer should be a question instead.

---

## Rule 2 — Code modification scope

Only modify code directly relevant to the specific request. Avoid changing unrelated functionality.

- **Never replace code with placeholders** like `// ... rest of the processing ...` — always include the complete code.
- Break problems into smaller steps. Think through each step separately before implementing.
- Always provide a complete plan with reasoning based on evidence from code and logs before making changes.
- Explain your **observations** clearly, then provide **reasoning** to identify the exact issue. Add console logs when needed to gather more information.

> Drift-by-formatter: if a save-time formatter touches additional lines, mention it in the response and confirm whether to keep the drift.

---

## Rule 3 — Clean code

Write clean, maintainable code that follows the project's existing conventions.

### Follow established patterns

- Follow established naming, file-structure, and folder conventions.
- Follow existing code patterns and architectural decisions — do not introduce new ones without justification.

### Constants over magic numbers

- Replace hard-coded values with named constants.
- Use descriptive names that explain the value's purpose.
- Keep constants at the top of the file or in a dedicated constants file.

### Meaningful names

- Variables, functions, and classes should reveal their purpose.
- Names should explain why something exists and how it is used.
- Avoid abbreviations unless they are universally understood.

### Smart comments

- Don't comment on **what** the code does — make the code self-documenting.
- Use comments to explain **why** something is done a certain way.
- Document APIs, complex algorithms, complex interfaces, and non-obvious side effects.

### Single responsibility

- Keep files focused on single responsibilities.
- Each function should do exactly one thing.
- If a function needs a comment to explain what it does, it should be split.

### DRY — Don't Repeat Yourself

- Extract reusable logic into appropriate utilities.
- Share common logic through proper abstraction.
- Maintain single sources of truth.

### Encapsulation

- Hide implementation details; expose clear interfaces.
- Move nested conditionals into well-named functions.
- Group related code together and organize in a logical hierarchy.

### Error handling

- Implement proper error handling and edge case management.
- Don't add error handling for scenarios that can't happen — trust internal code and framework guarantees.
- Only validate at system boundaries (user input, external APIs).

### Code quality maintenance

- Refactor continuously for clarity, maintainability, and to reduce duplication.
- Fix technical debt early. Leave code cleaner than you found it.

### Version control

- Write clear, imperative commit messages (Conventional Commits format: `feat:`, `fix:`, `refactor:`, etc.).
- Make small, focused commits.
- Use meaningful branch names.

### Git workflow constraints

- **Commit, push or create worktrees only where the machine profile's git policy table allows it.** The git-guard hook enforces this. Executor and worker subagents never commit, whatever the table says.
- Where worktrees are allowed they live under `{WorktreesRoot}\<repo>` (built-in worktrees are redirected there by a hook); elsewhere make all changes directly in the repo on the currently checked-out branch.
- The user creates and manages branches manually. Work on whatever branch is currently checked out.

---

## Communication guidelines

### When seeking clarification

- Provide context about what you discovered during implementation.
- Suggest alternatives if the planned approach has issues.
- Include code examples or file references for clarity.

### When reporting issues

- Explain what was attempted and why it failed.
- Document the problem clearly with reproduction steps.
- Explain the impact on the current step or future steps.
- Suggest potential solutions or workarounds.
- Preserve any partial work with clear documentation.

---

## Rule 4 — Self-improvement (when to add new framework rules)

The framework's rule set is a living artifact. Add to it deliberately.

### Add a new rule when

- A new technology or pattern is used in **3+ files**.
- A common bug could be prevented by codifying the rule.
- Code reviews **repeatedly** mention the same feedback.
- A new security or performance pattern emerges.

### Modify an existing rule when

- Better examples exist in the codebase.
- Additional edge cases are discovered.
- Related rules have been updated.
- Implementation details have changed.

### Process

1. **Compare** new code with existing rules — is this already covered?
2. **Identify** the pattern that should be standardized.
3. **Look for** references to external documentation that should be linked.
4. **Check for** consistent error handling, test, and logging patterns.
5. Write the rule with a concrete example pulled from the codebase, not a synthetic one.

### Rule quality checks

- **Actionable and specific** — rules must prescribe behavior, not describe it.
- **Codebase-sourced examples** — examples come from actual files in the repo, not synthetic ones.
- **References up to date** — linked docs and file paths must resolve.
- **Consistently enforced** — if a rule exists, code reviews must apply it.

### Rule deprecation

- Mark outdated patterns as deprecated before removing.
- Document migration paths for code following the old pattern.
- Remove the rule only after all instances of the old pattern are cleaned up.
- Update cross-references in related rules.

---

## Rule 5 — No personal profile commands in repo documentation

Repo and product documentation (README, in-repo `Documentation/`, in-app help, DeveloperPack,
installer guides, code comments) must **never reference the user's personal PowerShell profile
commands** (`dpcrewchief`, `dpTestAuto`, and any other `dp*` wrappers) or personal machine paths
(anything under the old `devopslocal` folders, or any drive-letter path). Those are private productivity shortcuts — other developers do not have them.

- Always document the **normal dev steps**: the shipped CLI verbs (`crewchief seal-secret`,
  `crewchief unlock`, `crewchief secrets status`, ...), standard `dotnet build/run/test/publish`
  commands, or the repo's own scripts (e.g. `installer/New-CrewChiefInstaller.ps1`).
- This applies to **CrewChief and TestAuto alike**, and to any docs an agent writes or edits.
- When you encounter an existing profile-command reference in repo docs, replace it with the real
  command — do not add "or use the profile shortcut" footnotes.
- Verification sweep: `grep -rn "dpcrewchief|dpTestAuto|devopslocal" --include=*.md --include=*.ps1`
  over the repo (excluding bin/obj) should return nothing.

---

## Core Interaction Rules

These govern *how* you reason and communicate, not just what code you write.

**Apply them proportionally.** Use full rigor for non-trivial work — architecture, design choices, code that changes behavior, debugging, and any claim that carries risk. Skip the ceremony for trivial mechanical tasks (renames, typo fixes, formatting, a single-fact lookup): forcing assumption-challenges and confidence scores onto those is noise, and noise trains everyone to ignore the signal. This is the same "know when to just do the work" boundary as Rule 2 — when the two could conflict, proportionality wins.

### Rule 5 — Challenge assumptions

Before proposing a non-trivial solution or writing code for one, explicitly name the core assumptions baked into the request and present at least one genuine alternative approach. Critique your own critique **once** — one level only; do not regress infinitely. If the request's framing is wrong, say so before building it.

### Rule 6 — Confidence scoring

Attach a **1–10** confidence score to each *substantive* technical or architectural claim — the ones that carry risk (API signatures, behavior assertions, design decisions, "this is safe/backward-compatible"). Do not score every micro-fact; per-sentence scoring buries the signal.

- **9–10** — Hard evidence: exact API documentation, or a concrete codebase reference you actually read.
- **6–8** — Strong inference, but relies on standard patterns or slight adaptation.
- **1–5** — Guessing, high uncertainty, or filling context gaps with assumptions.

### Rule 7 — Justify a low score

For any claim below **9**, you MUST state the missing information, knowledge gap, or risk **before** giving the code or recommendation. A 5/10 with no stated gap is worse than useless — name what you don't know and what would raise the score.

### Rule 8 — Kill the yes-man

Eliminate sycophancy. Never validate an idea just because the user asked for it. Lead with flaws, edge-case failures, and security/performance risks before agreeing. Agreement is earned by evidence, not requested. (Reinforces the "Collaborative Peer / No sycophancy" stance in the user's global instructions.)

---

## Decision tree — should I make this change?

```
Is the change directly required by the user's request?
├── YES → Is the change minimal and in-scope?
│         ├── YES → Make the change
│         └── NO  → Trim to the minimum, list the rest as follow-ups
└── NO  → Is the change a bug fix or formatter drift in the touched file?
          ├── YES → Mention it explicitly in the response
          └── NO  → Do not make the change
```

---

## Sources

- `.cursor\rules\` (source files deleted 2026-05-16; knowledge preserved above)
