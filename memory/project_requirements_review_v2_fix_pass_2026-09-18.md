---
name: project_requirements_review_v2_fix_pass_2026-09-18
description: "Review_v2.md (Codex, 2026-09-18) fix pass on the Speedy requirements corpus — Gene's 12 reconcile decisions of 2026-09-18 ~13:15, scope = EVERYTHING NOW (fixes + full coverage trail + decompose the 4 parity holding targets), ask Gene in rounds as choices arise"
metadata: 
  node_type: memory
  type: project
  originSessionId: 1ceb05f7-04af-4045-9cbe-0fd9c141b9d1
  modified: 2026-09-18T17:12:19.687Z
---

**Trigger (2026-09-18 12:55):** Gene: "Review_v2.md fix these items when necessary present a prompt with options to
reconcile". Review_v2.md = Codex's independent review, 17 findings RV2-01..RV2-17 + maintenance items + 6 questions.
The earlier hold ("wait for another full review, no corpus edits") is LIFTED by this order.

**Gene's decisions (AskUserQuestion, 3 rounds, 2026-09-18 ~13:00-13:15) — apply these, do not re-ask:**
1. **Import collision (RV2-03):** create + rename refuse a duplicate name outright; step/workload BUNDLE import defaults to a
   new unique name and offers an explicit CONFIRMED replace; reference-data SET import keeps ADDITIVE merge (REQ-LIB-005).
   Owner FEAT-LIBRARIES-001. Q-CC-CANDIDATE-009 "every import" = steps + workloads.
2. **Setup gates (RV2-04):** ONE installation gate (FEAT-INSTALLER-001) = data folder, warehouse check, seed content,
   required reference data AND secrets store creation; nothing else reachable until all done. After install: never any
   confinement; if the store is later deleted/replaced only CrewChief's step-aside first-run notice applies
   (FEAT-SECRETS-EDITOR-001 owns that post-install state).
3. **Unlock scope:** grant belongs to the Entra-signed-in OPERATOR, held server-side, follows them across every screen/tab/
   device; other operators see locked; manual lock ends it everywhere. Runs resolve secrets under process identity regardless.
4. **Unlock expiry:** ABSOLUTE deadline set at unlock (default 15 min, max 8 h, no never-expires, no restart survival);
   activity never extends; re-open after lock/expiry needs the master password again.
5. **Execution boundary (review Q4):** every Speedy process (web, coordinator, agent) is a container. Windows work runs
   REMOTELY from the container (WinRM / PS remoting / SQL). Probers evaluate against the credential the step connects with;
   donor local run-as / local-admin checks become remote-target checks.
6. **Export leak (RV2-08):** export REFUSES and writes nothing when the name heuristic fires on a literal OR any field text
   contains a value currently stored in the (unlocked) secret store; refusal names the location. Donor warn-only = `change`.
7. **Store delete (RV2-12):** remove store files, wrapped master, every lockout counter, any in-memory unlock session. Donor's
   pre-delete backup copy RETIRED. No erasure/overwrite claim; verify by listing + failed open.
8. **Scope of this pass: EVERYTHING NOW** — all 17 findings + apply every recorded answer + coverage rows for all 248
   unmatched mappings + DECOMPOSE the 4 parity holding targets (CREWCHIEF/TESTAUTO/GENERATION/MUTATION-PARITY-001) into
   coherent outcome features WITH requirements.
9. **Chunks (Q-TDGM-001):** NO CHUNKS — mutation engine becomes one continuous stream with periodic checkpoints; twin
   suppression applies only to the very first unique of a run; REDESIGN with an ADR; checkpoint/resume must be redefined.
10. **Run queue (Q-TDGM-002):** FIFO queue per data store; config captured AT ENQUEUE; cancel of a queued run dequeues; cancel
    of the running run promotes the next; one-run-per-data-store applies to RUNNING only; queue visible on activity screen.
11. **Crypto params (RV2-06):** the sealed tier's verified figures are DECIDED for both tiers now: random 128-bit salt per
    stored value, PBKDF2-SHA256 300,000 iterations, random IV/nonce, one scheme for both tiers. Record as resolved metrics
    in DATA-SECRETS-001 with this answer as basis; no separate ADR. Cipher: read the donor's sealed tier (BEH-CC-009) and
    the port; do not invent.
12. **Decision flow:** ASK GENE IN ROUNDS (AskUserQuestion, 4 at a time) as new product choices arise during decomposition.
    Agents cannot prompt him: they write Q- with options + recommendation; the coordinator batches the prompts.

**Also settled by me under the standard (flag in report, no prompt needed):** RV2-05 process ambiguity — keep the
decision_status/status coupling; a previously authorised choice stays PROPOSED until its record is reviewed, with the prior
authorisation date in `decision.basis`; add one clarifying sentence to RequirementDesign §9.

**Work plan:** staging copy of the vault corpus in the scratchpad; agent T fixes reqtools.py (RV2-14..17 + negative
fixtures); content agents per cluster with exclusive write sets (secrets / libraries-backup-templates-refdata / platform /
4 parity decompositions incl. RV2-01 rerouting + the 42 files with the generic "Carry the answer into this artifact"
checklist, ~118 items); coordinator owns ids.yaml, manifest, review docs, pins (finalize.py), validate, Push-ToVault.ps1,
and the Gene prompts. Never commit; never write the vault directly.

Related: [[project_requirements_v1_build_2026-09-18]], [[project_speedy_requirements_system]],
[[feedback_requirements_system_review_gate_per_task]].

**Dispatched 2026-09-18 ~13:40 (7 opus agents, background; resume by SendMessage to the id):** T tooling `a24340de1ed903a9a`
(reqtools.py + tests, report at `C:\devops\repos\speedmerchants\tools\requirements\tests\REPORT-2026-09-18.md`);
S secrets `a79199e92aef87411`; L libraries `adb74d4bbd458bdb1`; P platform `a3a61c564d84953b3`; UI+load `aa53f4ab4445ae45d`;
TA parity `afa6c1637cdad8b89`; TD generation+mutation parity `a28011f0f15f16ac8`. Each writes `staging\agents\<folder>\REPORT.md`
and `QUESTIONS-FOR-GENE.md` (folders secrets/libraries/platform/ui/testauto/testdata). Staging root =
`C:\Users\agenewe\AppData\Local\Temp\claude\C--working\1ceb05f7-04af-4045-9cbe-0fd9c141b9d1\scratchpad\staging`
(copy of the vault corpus taken 13:25 + `agents\` with DECISIONS, COMMON-RULES, coverage-gaps, coordinator scripts).
Coordinator already did in staging: RequirementDesign §9 sentence (RV2-05), INTEGRATION snapshot note, FINAL-REVIEW
historical note. Still owed by coordinator: §12 sentences from T; CC candidate follow-ups + mark-done; retire fully applied
Q- (resolve_questions.py); allocate new IDs + resolve pins (finalize.py, root = staging); regenerate nothing under
`generated\` (Gene archived the views); validate with the NEW reqtools; Push-ToVault.ps1 -Staging <root>; Gene prompt rounds.

**Round 4 (13:50) Gene:** D13 rename with an unwritable referrer = refuse whole rename, name blockers; D14 versioned
shipped-content copies never auto-removed; D15 operator-saved templates = marked kind inside ordinary libraries (no
separate store); D16 installation gate seeds NO content (amends D2) — home-screen welcome offers templates afterwards.
Still with Gene: Q-TPL-003 (shipped-content list; recommendation = keep open with closing condition).
**Round 5 (13:52) Gene:** D17 deployment terminates TLS (product owns no certificate behavior); D18 installation gate
CREATES AND MIGRATES the warehouse (against recommendation; must not lose results); D19 CLI parity with NO exceptions;
D20 prober that cannot use the step's credential reports undetermined, never satisfied.
**Round 6 (13:58) Gene:** D21 shipped-content list stays open with a closing condition; D22 unmarking a reference set
allowed after stating what breaks (delete stays refused); D23 help docs carry a build-written checked-against revision
field. FEAT-CREWCHIEF-PARITY-001 stays DRAFT until Gene approves its retirement (needs review + approval per §9).
Progress 13:56: pending application items 235/354, requirements 328, rows 261 (16 unresolved), 37 files still generic.
**Rounds 7-8 (14:06) Gene:** D24 sync from TEST instances only (no production source); D25 two declared read types;
D26 machine keys never administer access nor write a secret; D27 directory down = signed-in stay, no new sign-in;
D28 secrets re-read live (no restart); D29 held-back/blank/missing/unreadable refused by name; D30 ALL FOUR load
features deferred until parity (dial v0.6 retained base). Libraries + UI workers DONE (reports in agents/<x>/REPORT.md);
CC candidate follow-ups from both applied by coordinator (mark-done + target_requirement_refs, script
agents/coordinator/candidate_followups.py). Secrets, platform, testauto, testdata still running.
**Round 9 (14:12) Gene:** D31 run durability = operator-driven recovery (failed with reason; resume re-executes only
never-completed work).
**Rounds 10-11 (14:27) Gene:** D32 meaning-shaped generator catalog only; D33 reproducible within one generator-set
version; D34 checkpoint = fixed 60 s wall clock; D35 queued run shown + cancellable in test-data console rail; D36 stopped
run = own outcome class (CLI exit code); D37 Gene REVIEWS AND APPROVES retirement of the 4 parity holding targets now
(coordinator records review+approval entries). ALL 6 CONTENT WORKERS FINISHED 14:24 (testdata/platform/ui resumed for
follow-ups). Reports: agents/<x>/REPORT.md (platform's saved by coordinator). Next: integration (allocate IDs, pins,
retire Q-, capability feature_refs, candidate mark-done, validate, push).
**Round 12 (14:33) Gene:** D38 apply the inclusion re-read (TA-004/005/017/018/019, TDG-012, TDGM-013 → PARTIAL with
container reason). TA + secrets + libraries workers resumed for follow-ups; platform/ui/testdata still on theirs.
CC candidate follow-ups from platform+secrets applied by coordinator. CAP feature_refs = coordinator (in progress).
