---
name: project_requirements_v1_build_2026-09-18
description: "Version-1 Speedy requirements corpus built 2026-09-17/18 — 5 tasks, 4 parallel opus inspectors + port surveyor, ~155 live artifacts, pushed to the vault, question log for Gene"
metadata: 
  node_type: memory
  type: project
  originSessionId: 0fa99639-dc89-4618-8dfb-1e6151d3320f
  modified: 2026-09-18T03:34:24.724Z
---

**Gene's order (2026-09-17 21:34):** 1 requirements from the existing loop; 2 CrewChief; 3 TestAuto; 4 Test Data and
Mutation (TDGM = `TestData.Mutation`); 5 Test Data Generation (TDG). Follow RequirementDesign + samples; verify against
code; partial = say what is done and not; incomplete = tag and move on; questions to a log Gene answers when v1 is done.
Choices (AskUserQuestion): task 1 = Speedy programme rows only (not MyLoop tooling); depth = inventory + SRC + candidates;
4 parallel opus inspectors under RequirementDesign §14 with me as coordinator; run all five, ONE report.

**DONE 2026-09-18 23:35, all five tasks.** Staging tree `<scratchpad>\staging`, PUSHED to
`Q:\...\speedy\requirements` through `Write-VaultFile.ps1` (never a direct write); the vault copy validates
independently at **0 errors, 7 warnings** (2 are the sample package's own demos, 5 are a reviewed advisory lint).
**173 live artifacts**: CAP-SPEEDY-001 + 5 capabilities; 26 targets (8 with requirements + wired rows, 11 deliberately
requirement-free and bounded, 4 umbrella); 5 ADRs; NFR/DATA/API/UX for secrets; 66 SRC / **378 BEH**; 66 candidates
(54 INCLUDE, 11 PARTIAL, 1 EXCLUDE, 378 mappings); 5 inventories / 209 surfaces; 62 requirements, 51 acceptance,
17 verification plans, 100 coverage rows. **194 questions, 155 blocking** in `generated/BACKLOG.md` + the grouped
reading view `generated/QUESTIONS-BY-SUBJECT.md`. Check record: `review/INTEGRATION-2026-09-18.md`; port survey:
`review/PORT-INVENTORY-2026-09-18.md`. Nothing is READY or ACCEPTED; no independent review yet (all one tool).

**Verified security finding worth remembering:** CrewChief's LOCAL secret store reproduces TestAuto's fixed literal salt
`"TestAutoSecrets.v1"` at 10,000 PBKDF2 iterations and derives the IV from the password too, so identical secrets encrypt
identically; its own SEALED tier uses a random 128-bit salt per seal at 300,000 iterations. Speedy adopts the CrewChief
model, so it inherits the weaker local tier unless Gene decides otherwise — that is Q-SECRETS-007 on DATA-SECRETS-001.

**Coordinator scripts live in `staging\agents\coordinator\`** and are the way to repeat any of this: `finalize.py`
(digest → resolve pins → allocate every live ID → validate), `gen_caps.py`, `gen_targets.py`, `gen_adrs.py`,
`wire_secrets_rows.py`, `wire_rows_2.py`, `gen_questions_view.py`, `stats.py`, `Push-ToVault.ps1` (hash-verified).

**Traps that cost real time — check these first.** A colon+space inside an unquoted YAML value breaks the whole file
("mapping values are not allowed here"). An unquoted date is a timestamp and is rejected. `sha256: null` is a type error,
and sha256 is REQUIRED whenever `revision` is a date. A coverage row with treatment `unresolved` MUST reference a BEH item,
so a "rows not written yet" target uses `coverage: []` plus a blocking question instead. NEVER run `digest --write` on an
`inventory.yaml` (it is document_kind inventory, the added revision block then fails validation). Relation pins use a
64-zero sha256 placeholder that `finalize.py` resolves and refreshes while the artifact is DRAFT/REVIEW and unapproved.

**Why parallel agents nearly lost everything:** the first dispatch let each inspector spawn its own sub-agents; ~20
concurrent opus agents hit the account rate limit and every unwritten finding was lost. The re-dispatch banned sub-agents
and required write-as-you-go. Keep both rules.

**How to apply:** on resume, run `finalize.py`, then `gen_questions_view.py`, then `Push-ToVault.ps1`. Verify a sample of
agent claims against donor code before trusting a record; six of six sampled were exact. Related:
[[project_speedy_requirements_system]], [[project_speedy_requirements_samples_review_2026-09-17]],
[[feedback_requirements_system_review_gate_per_task]].

**ANSWER PASS 1, 2026-09-18 09:40.** Gene answers in `generated/QUESTIONS-BY-SUBJECT-ANSWERS.md` (his own copy of the
generated view, edited in place in the vault) — WATCH THAT FILE, he works through it in order and it runs ahead of what
he pastes into chat. Diff it against `generated/QUESTIONS-BY-SUBJECT.md` by question id to find what is answered.
110 of 196 answered; 107 transferred into the owning YAML with attribution, state ANSWERED_PENDING_APPLICATION and a
per-question application checklist. 12 put again with real options where he asked ("restate", "lets go through this in
detail") or where two contradictory options were both ticked (Q-CC-CANDIDATE-022, Q-TA-CANDIDATE-006, and
Q-TA-CANDIDATE-013 against -014). New coordinator scripts in `agents/coordinator/`: `apply_answers.py` (surgical text
patcher, answers AND restates, refuses to write a file that stops parsing; ALL inserted prose is a folded block scalar
so colon-space and bare dates cannot break it), `add_questions.py`, `resolve_questions.py` (mark application items done;
retire only when every item is done, appends the ids.yaml retire event), `batch1..8.py` (the answer data).
`gen_questions_view.py` now takes `--open-only` and writes `generated/QUESTIONS-REMAINING.md` with the answered ones
left out. New artifact **NFR-UI-DONE-001**, Gene's five-part screen gate as a shared contract; the approved colour
scheme it cites is palette A in `speedy/ui/palette/NOTES.md` (CrewChief as shipped, one link-colour departure), pinned
by digest. Q-SPEEDY-002/003/004 RETIRED into CAP-SPEEDY-001 local decisions.

**Gene dropped accessibility entirely** (Q-SPEEDY-006). The WCAG assumptions are gone, but REQ-SECRETSUX-061 (announce
to assistive technology) was NOT deleted on an inference; Q-SPEEDY-007 asks how far the exclusion reaches. Questions
raised by his own answers: Q-SPEEDY-007 (exclusion scope), Q-SPEEDY-008 (hosting, container versus Windows service —
his deliverable names containers, Q-CC-CANDIDATE-033 assumes a service), Q-SECRETS-018 (local-tier derivation, since
answered by Q-CC-CANDIDATE-003), Q-SECRETS-019 (unlock-session period default and range). Corpus now 174 live
artifacts, 196 questions / 160 blocking; vault validates 0 errors, 7 warnings after the push.

**ANSWER PASS 2 + GENERATED ARCHIVED, 2026-09-18 10:40.** Gene answered all 193 blocks in his answers file and then
took ~30 more decisions through AskUserQuestion prompts. All transferred. Corpus: 175 live artifacts, 197 questions,
161 blocking, 0 errors / 7 warnings in the vault. The 23 still unanswered are the donor-code questions, none blocking.
**Programme-level decisions taken 9/18 that change everything downstream:** hosting is CONTAINER ONLY (the Windows
service host, the service-account verb and its two grants are retired; the installer becomes a container image plus
the application's own first-run screens); scenarios are CODE-declared with a GENERATED parameter editor, which
SUPERSEDES recorded decision D2; the native engine runs everything and TestAuto's background-job server is retired;
Entra ID sign-in for screens plus scoped API keys held in Speedy's own secret store; all nine capabilities; all 27
step types with no staging plus TestAuto's monitor step; accessibility excluded TOTALLY, so REQ-SECRETSUX-061 retires;
unlock session default 15 min / max 8 h, no never-expires, no survival across restart; one run per DATA STORE;
cancelled beats everything as the terminal state; reference data required at installation with a build-time drift
test, and an entry delete is refused while any definition references it.

**Gene ARCHIVED the generated views on 2026-09-18** to `99 Documentation/speedy/archive/` as
`BACKLOG-2026-09-18.md`, `QUESTIONS-BY-SUBJECT-2026-09-18.md`, `QUESTIONS-REMAINING-2026-09-18.md` and
`QUESTIONS-BY-SUBJECT-ANSWERS-2026-09-18.md` (his own answer file). `requirements/generated/` is now EMPTY and
`Push-ToVault.ps1` no longer lists `generated` in its include array — do not regenerate or re-push the views until he
asks. The manifest still declares `generated_backlog: generated/BACKLOG.md`, which is where the backlog would be
written if regenerated; the validator does not require the file and the vault validates 0 errors without it.
**He then asked to WAIT for another full review of all requirements — do not make further corpus edits unprompted.**
Moves in the vault go through `mcp__obsidian__vault_move`, not SMB, for the same reason writes go through
Write-VaultFile.ps1.
