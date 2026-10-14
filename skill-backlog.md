# Skill Backlog

_Last audited: 2026-09-09 | baseline: c36ddbcf | mode: 1 (fresh scan, diff-first over baseline..HEAD) | yield: **33 candidates (13 new, 12 ext, 3 desc, 5 hyg) added to Pending — none approved yet.**_

_Method 2026-09-09: Step-0 diff gate PASSED — 196 commits and 801 non-generated changed files since baseline `15401a46`. Five read-only Explore agents in parallel, one per subsystem (CrewChief.Web 203 files, CrewChief.Engine+Data 96, TestData.Mutation 209, TestData.Generation 142, TestAuto/Enrichment/installers 151), each handed the 151-skill inventory as a coverage filter so the already-covered decision happened at the leaf. Every non-OK finding re-verified by the orchestrator with a name-based grep before becoming a candidate. Four candidates were proposed twice under different names and are MERGED; `inno-setup-installer` was hit independently by three agents. **The five configured input paths in the `skill-audit-with-update` skill were found pointing at the retired `C:\devopslocal\ObsidianVaults\...` root and corrected to `Q:\` the same session** — the dead path had made this very file read as absent, i.e. as a first run. <!-- history -->

_Corrections worth keeping: two of the orchestrator's OWN greps were the faulty party rather than an agent — `HangfireUnavailableFallbacks` returned 0 hits because the FILE carries that name while the CLASS inside is `HangfireUnavailable`, and an `awk` enum range truncated at a doc comment and undercounted `StepCapability` as 7 when it holds 9. One agent claim WAS corrected: the installer port subsystem is not identical across the two installers — the write seams are deliberately OPPOSITE._

_Method: no agent fan-out. All 150 descriptions extracted mechanically from frontmatter, then two prefilters run in the main session. (a) **Zero-hit identifier scan** — ~250 distinctive identifiers named in descriptions were extracted and checked against live code in ONE `rg -o -w -f patternfile` pass over the repo (bin/obj/TestResults excluded), then grouped by hit count. Only 3 zero-hits and 16 ≤2-hits emerged; each was re-verified individually with context. (b) **Body-vs-description coverage** — every skill's H2 headings were tested for representation in its own description; skills with many unrepresented headings were read to separate real missing-triggers from generic-heading noise. Format check: only 2 of 150 descriptions lack a `Use when` clause._

_Signal that mattered: the **declaration-only identifier** — exactly ONE repo-wide occurrence, i.e. the type/member exists but has zero consumers. This is a distinct, sharper variant of the zero-hit class: a grep "finds" it, so nothing looks wrong, yet the skill points at an API nobody calls. Confirmed instances: `LogConstants` (11 tag constants, zero production call sites — `LogTagConstants` is the live one), `ControllerTestBase` and `BaseRestClientTest` (zero inheritors, though both descriptions imply tests inherit them), `CreateVersionRequest` (dead DTO — the controller takes `[FromBody] ScenarioConfiguration` + `[FromQuery] versionNotes`), `CountCompressionLayers` (no callers), `LoadConfigurationValidator` (declaration + own ctor only, nothing registers it)._

_Highest-value finding — **`testauto-log-tags` taught a wrong example, and the mechanical signal under-sold it.** The scan said only "LogConstants is dead". Verifying it exposed a bracket asymmetry: `LogTagConstants` values are BARE (`"METADATA_CRUD"`) because the `*WithTag` helpers wrap them as `[TAG]` via `PrependTag`, while `LogConstants` values are PRE-BRACKETED (`"[METADATA_CRUD]"`) for hand-built message strings. Production: ~2,909 `WithTag(` call sites, **zero** raw `LogTagConstants.X + "…"` concatenations. Two of the skill's "All of these are correct" examples concatenated a bare tag — the structured properties survive, so nothing looks broken, but the tag emits UNBRACKETED and the `WHERE Message LIKE '%[TAG]%'` search that the whole convention exists to serve silently never matches. A skill that teaches a wrong example is worse than one with a stale line number: the reader copies it and the failure is invisible._

_Verification-gate catches, both directions: `sqlSource`/`sqlDestination` returned zero hits, but case-insensitive re-grep proved the real keys are `sqlSourceConnectionSecretName`/`sqlDestinationConnectionSecretName` (`SqlStep.cs:17-27`) — a truncated trigger term, not a fabricated one. Conversely `testauto-scenario-version-history`'s BODY was already correct about BOTH flagged items (`:101` explains the controller splits the fields; `:148` documents the in-memory stub) — the defect is description-only, and a body "fix" would have rewritten accurate prose. Every numeric claim tested held: CrewChief 7 `StepCapability` members / 4 `CapabilityStatus` states / `CliExitCodes.PreflightFailed = 4` / 4 seeders / 6 csproj, and TestAuto.Utilities' "eight IStepExecutor implementations" is exactly 8._

_Prior: 2026-08-10 (AM) | baseline: 15401a464568d9ade9dee6d7f922b1d15a983e02 | mode: 1 (diff scan 4c367fe6..15401a46 — **127 commits / 516 files / +78,894 −5,134**, the largest surface any audit here has covered) | yield: **7 new skills + ~45 skill files extended/corrected — ALL ~96 consolidated findings applied, none deferred.** Two passes: "fix all items you find" (~37 items), then "finish all work that was not done before" (the remaining 18). `## Pending` is empty by exhaustion, not by triage._

_Method: 7 read-only Explore agents fanned out over subsystem partitions of the diff (CrewChief Web / Engine-Data-Cli / shipped-content-docs-installer / tests · TestAuto hosting-HTTPS-installer / Production-Sync-Web-UI / Connect-Utilities-Records), each handed the 143-skill inventory as a coverage filter so the "already covered?" decision happened at the leaf. ~96 raw findings consolidated to 7 new + ~30 ext after dedup (four agents independently found the capability-preflight subsystem; two independently found the `DefaultReferenceData/` relocation). **Every correctness claim was re-derived first-hand in the main session before any edit** — no agent finding was transcribed on trust._

_Highest-value finding — **CrewChief `Ref`/`Overrides` retirement**, which invalidated dedicated sections in FOUR skills. `WorkloadStepEntry` now carries only `Inline` + `Label`; `UpdateStepReferences`, `StepLibrarySnapshot`, `resolveRef` and `CountLibraryReferences` all have **zero repo-wide hits**. The hazard is silent: Newtonsoft ignores unknown properties, so a legacy `{"ref": "..."}` entry deserializes to an EMPTY step that runs as a no-op **and reports success** — hence `LegacyWorkloadRefGuard` refuses the file at load. Two skills advertised the dead `UpdateStepReferences` in their `description:` frontmatter, i.e. in a trigger phrase._

_Defect classes this pass: (a) **reverse-staleness — a documented BUG that got fixed**, now the single most common class (5 instances: the 30 s `MaxTimeSeconds` hardcode, `SmartJsonEditor`'s "still a stub" loader, `BaseApiController`'s `Forbid()` body loss, `MetricsCard`'s `chart-bar` default, and the `crewchief-default-templates` note warning that a Program.cs comment was stale — the comment had since been rewritten). A skill that keeps warning about a repaired defect sends readers to "fix" working code; (b) **census drift** — box-prep family 6→7, `AllTypes` 19→22, LogTags 11→12, and a THIRD census oracle (`WorkloadRunAsInheritanceTests:353`) that no earlier audit had found, defined by reflection over "types declaring a `CredentialSecretName` property" rather than by a list; (c) **whole subsystems with zero coverage** — capability preflight, Production Sync, raw-JSON panes, Connect import, HTTPS hosting, Windows-service hosting._

_Verification-gate catches: `step-reference-resolution` was checked against the `Ref` retirement and **cleared** — it documents TestAuto `{{STEP:N}}` CustomParms tokens, an unrelated mechanism. `LogTagConstants.Teams` was confirmed to have 3 real production call sites (so 11→12), while `CheckPort`/`WebSite` have none and were NOT invented as constants. Agent 5 self-dropped its own flagged candidate after finding the `secrets-bootstrap-middleware` skill already carried the 2026-08-08 WIRED callout._

_Prior: 2026-07-27 | baseline: 4c367fe6ee6ea1789470f427211f61e3dc2fbb32 | mode: 2 (drain the backlog — Opus 5/1M) | yield: **ALL 71 approved items APPLIED same session** across 12 parallel apply agents on non-overlapping skill files; **2 backlog findings proved FALSE and were dropped**; **7 new candidates surfaced → Pending**. Overview README regenerated, `-Check` exits 0._

_Method that made it safe: every claim re-derived against live code at HEAD `4c367fe6` before any write — the 2026-07-26 verdicts were pinned to 6f30e17e with 10 commits of drift on top, so backlog line numbers were treated as HINTS, never transcribed. The three "⚠️ fix would itself introduce an error" guards and the "⚠️ ALREADY EXACT" cite lists were passed verbatim to the owning agents. Two of the "already exact" cites had in fact drifted and were corrected on evidence; the genuinely-exact ones were left. **The gate earned its keep: it caught 2 false backlog findings, 1 false claim the ORCHESTRATOR introduced by over-generalising a house rule, and ~15 claims that were directionally right but mechanically wrong.**_

_Defect classes worth carrying forward: (a) **zero-hit identifiers** — skills naming symbols with no repo-wide hits (`BuildPlannedStepNames`, `NavigateToCustomParmsEditor`, `LubcMatchingScenario`, `GetRecordByCodeAsync`, `QueryExpressionBuilder`, `AddExecutorAlias`-in-CrewChief) are worse than line drift, because a reader greps, finds nothing, and concludes the feature is absent; (b) **fabricated surface** — `profisee-dq-rules` invented 7 categories of expression syntax, `testauto-test-data-generation` invented a paged distribution model with pseudocode; (c) **numbers that rot** — stale tallies ("19/22 pass", "98 uses", v1.0.56 vs live 1.0.65) were replaced with mechanism descriptions + re-read instructions rather than fresh numbers; (d) **stale code comments outliving the code** — several skills were wrong because their author trusted an XML doc or `//` comment rather than the implementation._

_Verification pass 2026-07-26 (Opus 5/1M) | baseline: 6f30e17e (unchanged, tree clean) | mode: 2 — cross-model validation of the 2026-07-25 Grok-4.5 Mode 6 backlog. User directive: "verification of the backlog which was done with a different model." 10 read-only Explore batches dispatched over all 71 Pending items; **8 batches terminated on an account weekly-usage limit → only 12 items verified (batches A + B). 59 items remain UNVERIFIED.** Nothing applied — 0 items moved to Approved. Verdicts recorded in the `## Verification` section below. Yield so far: 8 AGREE, 4 PARTIAL, 0 full DISAGREE — plus 3 findings the original sweep missed and 3 "the proposed fix would itself introduce an error" flags. Resume with the remaining 59 (batches C–J) after the limit resets._

_Last audited: 2026-07-25 | baseline: 6f30e17eee6aa7ac4acfd17ba436291ec333a599 | mode: 6 (full-corpus review against code — Grok 4.5 reviewer, diff-gate ignored by design; 103 speed-merchants-coupled skills reviewed via 13 read-only Explore agents; meta/tooling dropped). Yield: **~55 verified finding-clusters across ~45 skills → ALL in Pending, awaiting review.** Main-session verification gate re-confirmed every high-impact claim by name-based grep/read (matching 3B/3C wizard flip, FormatDurationMs clock, MaxStepOutputChars 100000, FirstRunBanner always-InstallAll, resetsamples gone, CLI→ScenarioEnqueueService/default queue, SelfManaged per-server, CollectionUpdateJob unwired, ConnEx gateway+flat DTO, JsonResponse OK/Created/NoContent, profisee-dq-rules grammar/MCP rewrite, ValidationService ScenarioConfigurationValidator-only + ShadowMode, secrets console bootstrap + LocalMachine DPAPI, Hangfire≠hasMinimumConfig). Highest-value: matching skills still document pre-wizard 3B=LookupOnly / 3C=LookupThenCreate while live wizard is 3B=LookupThenCreate / 3C=CreateOnly (samples lag — repo informational); CrewChief duration/caps/templates/installer drift from this week's churn; profisee-dq-rules invents non-grammar operators. New baseline = 6f30e17e._

_Prior: 2026-07-25 (AM) | baseline: ccb159ad78c5678b4306b8b3ae797494e5b53727 | mode: 1 (diff scan fb56e571..ccb159ad, 4 commits / 64 files, all CrewChief). Yield: 1 new + 5 ext (3 correctness) — all bulk-approved + implemented same session (see Implemented 2026-07-25)._

_Prior: 2026-07-23 | baseline: fb56e571358362f3baa82e25e82dd790e70ba175 | mode: 6 (full-corpus review against code — Opus 4.8 reviewer, diff-gate ignored by design; 101 speed-merchants-coupled skills reviewed via 13 read-only Explore agents in ONE Workflow fan-out, ~1.85M subagent tokens; infographic/meta/tooling dropped). Yield: **30 verified findings across 19 skills (18 WRONG, 8 DRIFTED, 4 STALE) → ALL 30 IMPLEMENTED same session + 1 desc follow-up (testauto-enrichment-generators Scrutor mention); 5 parallel apply agents, each re-verifying before edit.** Verification gate: main session re-confirmed EVERY finding first-hand by name-based grep/read before approval — 0 false positives, 0 discarded (unusually clean because each reviewer was required to name-grep before declaring anything STALE). Highest-value: matching-scenarios deep-dive had 3B/3C OperationType REVERSED (3B=LookupOnly, 3C=LookupThenCreate — confirmed by shipped sample configs, top matrix was already right); workflow-execution mis-stated MetricsPersistenceJob (per-child ContinueJobWith on the DEFAULT queue, not a batch continuation on "persistence") + wrong DisplayName; metadata-scenario uniqueness suffix is OPT-IN (UseBaseNamesOnly) with a hardcoded "12345" seed (TransformSeed inert); STALE referents gone from code (http-facades callRestApi*/sync GetGatewayResponse, testauto-project Pages/, scenario-types-attribute ExecuteStrategyScenario). Reverse-staleness: crewchief-adding-a-step-type iisreset alias now FIXED (UtilityOrchestrator.cs:87). The 6-finding CrewChief cluster drifted from THIS week's own churn (console-log Fatal level, SecretsRootResolver, DI/middleware line cites, 2025-line StepEditorCard). Codebase inconsistencies surfaced to user (repo read-only, NOT skill errors): shipped constant Template_Scenario3B="Scenario 3B: Lookup + Create" vs its LookupOnly operation. New baseline = fb56e571._

_Prior: 2026-07-22 (PM) | baseline: 3039aca0fc3be538433bb6007d56bca44fb5f5ea | mode: 1 (diff scan 4825a83a..3039aca0, 8 commits / 45 files — ALL authored first-hand in the same Claude session that ran this audit, so no agent fan-out was needed and verification was largely first-hand; one disk-state anomaly (harness showed pre-session SetApiKeyExecutor content) was resolved by name-based grep confirming HasTarget/DescribeDestination/serverName ARE in the committed tree). Surface: SetApiKey connection-model overhaul (serverName/databaseName/authMode + WindowsImpersonation + DescribeDestination + secret demoted to override), remote-Browse Drive Map translation + self-diagnosing path errors, LiveStepOutput live-tail hub, coordinator CurrentRunStepNames/CurrentStepStartedUtc, single-monitor consolidation (per-page run dialogs DELETED → navigate /activity + auto-follow), RunDisplay.FormatDurationMs tiers, card grid fixed 3-up + per-page 2/3/4 column picker, Configure default-switch profile widened (+10 DefaultEnabled + template literals), ConfigureExecutor 10K cap removed, LiveStepOutputTests [DoNotParallelize] gotcha. Yield: **7 ext (3 with correctness fixes: step-executors SetApiKey section, reference-data "no literals" claim, web-ui auto-fill grid claim)**. New baseline = 3039aca0._

_Prior: 2026-07-22 | baseline: 4825a83ad0f80ce67e9a062d974890c28d9adacf | mode: 1 (diff scan 0931603b..4825a83a, 39 commits / 148 files, all CrewChief: remote-credential overhaul + Configuration.exe hardening + Configure wizard + two-tier config reference sets + transfer family + card UI). 3-agent read-only fan-out (Engine+Tests · Web · Data+Cli+installer), each handed the crewchief-* inventory + the 12 pending items as overlap-suppressors → ~30 raw findings consolidated to **9 ext candidates (3 with correctness/reverse-staleness fixes) + 3 delta-notes on pending items**. Verification gate passed on every non-first-hand claim (ConfigurationDefaults→template/values split confirmed in ReferenceDataSets.cs; 3 per-type seeders confirmed DELETED → ReferenceDefaultsSeeder; WindowsImpersonation LOGON32_LOGON_NEW_CREDENTIALS confirmed; StepBundle/StepTransferService/ReferenceTransferService confirmed; Store.Rename/UpdateStepReferences confirmed; several findings first-hand — same-day session work: ComposeArgumentString(resolveValue), DetectConfigurationFailure, remoteAuthentication/RemoteAuthParser/CredSSP, RemoteRunRequest.WorkingDirectory/CC_REMOTE_WORKDIR, Install split-then-resolve). HIGHEST PRIORITY: crewchief-remote-box-prep and crewchief-reference-data carried ACTIVE INVERTED claims (old single credentialSecretName model; quote-then-resolve compose; configuration-defaults set + 3 seeders described as live). **ALL 9 IMPLEMENTED same session** (user "Do all 9"; 8 parallel apply agents, each re-verifying before edit — see the 2026-07-22 Implemented record for the apply-time corrections). No new skills → no linker change. New baseline = 4825a83a._

_Prior: 2026-07-20 (rerun) | baseline: 0931603b9ba478f8b8bd7d807aff7e288e4eab64 | mode: 1 (diff scan 1d8b33cb..0931603b, 2 commits / 31 files: the **credentialed / run-as remote Windows ops** feature LANDING — memory project_crewchief_credentialed_remote_ops recorded it as "uncommitted" on the prior baseline, so the last audit couldn't see it; these commits commit it + a refinement "compatible with windows and linux… windows server or just impersonate user"). 3-agent read-only fan-out (engine-core credential feature · secrets+web UI · docs+tests behavioral-contract), each handed the crewchief-\* inventory + the 3 adjacent Pending items as overlap-suppressors → **5 ext + 1 memory reconcile, ALL IMPLEMENTED same session** (user directive "approve all new ones"). Two mechanisms: (a) CORRECTNESS — the credentialed feature INVERTED crewchief-remote-box-prep's central "two transports / ServiceControl-AppPool-IisReset need NO credential, run as ambient identity" model (all 6 steps now accept optional credentialSecretName; 3 routing modes local/credentialed-remote/legacy-RPC); (b) GAPS — RemoteWindowsOps op-script layer, resolver {{$config}}/leaf normalization, LocalSecretsConfigurationProvider.Load() reload-rebuild-Data, credentialed RemoteLab test. Verification-gate catches: my hypothesized "three-MODE credential (windows/linux/server/impersonate)" does NOT exist in code (real = three-PATH routing); and BOTH sub-agents cited a nonexistent `CrewChief.Engine.Tests` project — real paths are `CrewChief.Tests.Unit` / `CrewChief.Tests.Integration` (glob-verified, corrected before any citation was written, incl. one already propagated into remote-box-prep Sources). Implemented: crewchief-remote-box-prep (major rewrite, SUBSUMES pending ext-crewchief-remote-box-prep-sdk-note-obsolete), crewchief-web-ui, crewchief-secrets, crewchief-testing, crewchief-executor-pattern + memory project_crewchief_remote_boxprep_transport. **12 pre-existing Pending items from the 1d8b33cb pass remain unreviewed** (this rerun did not touch them). No new skills → no linker change. New baseline = 0931603b._

_Prior: 2026-07-20 | baseline: 1d8b33cb421114438c37a71c6a024d72ba4be6b2 | mode: 1 (diff scan fcbcaaaf..1d8b33cb, 17 commits / 113 files: CrewChief refinements + NEW Inno Setup installers (CrewChief + TestAuto sibling pair) + doc updates; no TestAuto SOURCE changes). 5-agent read-only subsystem fan-out (secrets/bootstrap · backup/seeding · DB-ops/executors · web/CLI/filter · installers), each handed the 17 crewchief-* skill inventory as coverage filter → **13 candidates: 2 new + 11 ext**. Two mechanisms: (a) GAPS — features that landed AFTER the 2026-07-19 authoring pass had ZERO coverage (backup/restore, smart-seed date-gated manifest, Inno Setup installers, Windows-Service hosting, SecretsRootResolver, multi-facet page filtering); (b) REVERSE-STALENESS — three 07-19 gotchas documented as OPEN bugs are now FIXED in code → remove stale bug-warnings (ConnEx client-name "ConnectClient"→HttpClientNames.ConnEx now matches; IisReset alias added UtilityOrchestrator.cs:87; "PowerShell-SDK-pending" IRemoteCommandRunner XML rewritten). Verification gate CONFIRMED every staleness claim against live code (agents ran name-based greps). Informational (repo read-only): secrets.local.json stragglers remain in repo doc-comments/exception strings (ApiKeyEncryptor.cs, ParameterResolver.cs, NotificationSettings.cs) + doc 31_OpsSecretsAndNotifications.md — surfaced to user, not auto-fixed. All 13 in Pending awaiting review._

_Prior: 2026-07-19 | baseline: fcbcaaaff7429266268a9d7cd9e5ff0a42cc2f4f | mode: 1 (diff scan 74888cb7..fcbcaaaf, 107 commits / 419 files: the ENTIRE diff is the NEW standalone **CrewChief** solution inside the repo — 6 projects Cli/Data/Engine/Web + 2 test, 77,324 insertions, files-only persistence, zero TestAuto refs, copied from MultiStepUtility). 5-agent read-only subsystem fan-out (Engine / Data-Secrets / Web / Cli-infra / Tests-remote) → 51 raw findings consolidated into **17 crewchief-\* candidates** (family had ZERO prior coverage). Verification gate CONFIRMED against live code: dual `CreateStepForType` factories (Steps.razor.cs:279 + WorkloadEditor.razor.cs:378, both fall through to `CommandLineStep`); two divergent alias tables (StepTypeRegistry deser aliases vs UtilityOrchestrator._executorsByType dispatch — short aliases "iisreset"/"email" deserialize but throw "No executor found" at dispatch, while install/configure/etc. have both); SecretsBootstrapMiddleware WIRED at Program.cs:308 (contrast TestAuto's dormant one — no conflict, different assembly); DefaultRemoteCommandRunner wired real at EngineServiceCollectionExtensions.cs:57-58 (not the NotWired placeholder). Repo-doc staleness (read-only → informational): DeveloperPack ADR-008/B2 cite stale factory line ranges (217-237/373-393 vs real 279-301/378-400). User scope choice: FULL — whole subsystem. All 17 in Pending awaiting review._

_Prior: 2026-07-13 | baseline: 74888cb7ce7b37817a424e6ccfb8f55dc81e4219 | mode: 1 (diff scan 00241476..74888cb7, 10 commits / 89 files: .NET 10 upgrade + Blazor Web App migration + list-page N+1 parallelization + in-app docs refresh) | yield: 1 new + 7 ext + 1 hyg — ALL 9 IMPLEMENTED same session (applied 2026-07-14). Verified-no-change: secrets-bootstrap-middleware claim (UseSecretsBootstrapRedirect still never called from Program.cs). Verification-gate catch during apply: the dotnet-testing reference net8.0 snippet is the PLATFORM template (Profisee.Platform.Testing.{Service}.Unit — platform repos are net8/net6), NOT stale → left unchanged; only the speed-merchants-side half of ext-small-fixes-net10-tfm applied._

_Prior: 2026-07-12 | baseline: 00241476f39b059bdfc94b305bdfae0e3564a5ff (unchanged) | mode: 6 (Opus 4.8/1M reviewer — model-upgrade re-review of unchanged corpus) | yield: 21 verified findings across 21 skills → ALL 21 IMPLEMENTED same session (6 parallel apply agents) + 2 consistency patches (ui-patterns "nested"→"companion" desc, testdata-enrichment-pipeline DBCheckpointManager→DbCheckpointManager type refs); 5 skills fully clean. Highest-value: SM-4 superseded metric-wiring section (mirrored stale AddingNewDetailTypes.md doc), REC-1 SynonymHelper subsection wrong + surfaced a latent repo bug (loader Contains("SynonymList.") never matches "SynonymLists." manifest names → synonyms never load; surfaced to user as informational, repo read-only). 0 reviewer false positives survived the gate. Mode 6 ignores diff-gate by design; the reviewer improved, so the review changed._

_Prior: 2026-07-11 | baseline: 00241476f39b059bdfc94b305bdfae0e3564a5ff | mode: 6 (FIRST full-corpus review against code — new mode added this session; 79 skills, 16 review agents + 9 apply agents) | yield: 100 verified findings in 34 skills → ALL implemented same session (33 skills corrected + dotnet-secret-provider RETIRED/deleted); 28 skills fully clean. Systemic roots: hangfire skill was written from an unimplemented design doc (now bannered); 2026-07-10 audit's TextTruncationHelper "41 call sites" claim was false (helper is unit-test-only). 0 reviewer false positives survived the gate; apply agents caught + corrected 2 reviewer overstatements (#26 Seq startup lines, #55 SelfManaged consumers)._

_Prior: 2026-07-10 | baseline: 00241476 | mode: 1 (FULL repo re-scan, 7-agent subsystem fan-out) | yield: 2 new + 5 ext + 1 desc IMPLEMENTED same session; 1 excluded (Inconclusive convention — conflicts with atomic-tests rule)._

_Prior: 2026-07-01 | baseline: e085c6ba824cff514131de671a6ef55935d20a44 | mode: 1 | yield: 1 ext (connex runtime JSON-escape gate, score 9) + 1 hyg (utilities-module stale ResolveSpecialParameterValues signature) — from 838dad3e..e085c6ba diff (1 commit: escapeForJson gate on ParameterResolver, ConnEx-only)._

_Prior: 2026-06-30 | baseline: 838dad3e305d31e0f91440bc47da70446139d56d | mode: 1 | yield: 1 new (external-json-case-insensitive-reads, score 10), 2 ext (metadata harvest-noise strip 7, multistep passfail-detail 6) — from d3d9b740..838dad3e diff (7 commits: codebase-wide JSON case-sensitivity + key-constants sweep, Connect export testing, entity/model import fixes)._

_Prior: 2026-06-26 | baseline: d3d9b740 | mode: 1 | yield: 0 new — from 99743062..d3d9b740 diff (1 commit, UI-only). All durable knowledge already covered._

_Prior: 2026-06-25 | baseline: 99743062 | mode: 1 | yield: 9 implemented (3 new, 2 ext, 3 desc-stale, 1 hyg) + 1 deferred — from c029c3bf..99743062 diff (30 commits: 4K-ceiling chunked config store, workflow transfer, file-reference retirement, metadata-import rework). All stale claims verified against live code before edit._

---

## Approved (awaiting implementation)

_None — all 71 approved items were IMPLEMENTED on 2026-07-27. Per-item outcomes are in the `## Implemented` section; the full item bodies are retained below under `## Implemented 2026-07-27 — item detail` for provenance._

---

## Verification (2026-07-26 cross-model pass, Opus 5/1M vs Grok-4.5 findings)

Verdicts on Pending items, produced by read-only agents that re-derived each claim from live code at baseline `6f30e17e`. Method: each item's Description decomposed into atomic sub-claims; both halves judged separately — (a) does the skill actually SAY this, (b) does the code actually BEHAVE this way — with a mandatory repo-wide bare-name re-grep before any "unused/gone/unreachable" verdict. **These verdicts are NOT approvals.** Items stay Pending until the user approves them.

**Coverage: 12 of 71 verified. Batches C–J (59 items) never ran — the account hit a weekly usage limit mid-flight.** Unverified items are listed in `## Pending` unannotated; treat the Grok-4.5 claims in them as UNCONFIRMED.

### Batch A — matching family (5 items)

**GROUND TRUTH established for 3B/3C `OperationType`** (this mapping has now been flipped in opposite directions by two consecutive audits, so it was re-derived from every source):

| Source | 3B | 3C |
|---|---|---|
| Wizard `ApplyScenarioTemplate` `UnifiedMatchingScenarioEditor.razor.cs:231,255` | `LookupThenCreate` | `CreateOnly` |
| Wizard inverse map `WizardState.cs:624-637` + show-flags `:258-262` | `LookupThenCreate` | `CreateOnly` |
| Executor XML docs `MatchingOperationExecutor.cs:136,221` | `LookupThenCreate` | `CreateOnly` |
| `ContinuousStrategy.cs:4` doc | — | `CreateOnly` |
| **Shipped samples** `Samples/TestCases/Small/*.json:28` | **`LookupOnly`** | **`LookupThenCreate`** |

Wizard + 2 code-doc sources agree; only the sample JSONs dissent — and the samples ARE consumed (nested-key resolution at `MatchingScenarioConfigBuilder.cs:268-277`). So the divergence is real and must be DOCUMENTED, not silently resolved. `MatchingStrategyFactory.Create:21-30` routes on `IsBatchLoadMode`/`WaitForMatching` only — never on 3B/3C OperationType — so strategy selection is unaffected by which mapping is adopted.

- `ext-testauto-matching-scenarios-wizard-ops` — **PARTIAL** (6/7 sub-claims true). TRUE: 3B/3C matrix `SKILL.md:44-45`, deep-dive `:606`/`:622`, Lubc guard is now a triple-guard (`UnifiedMatchingScenarioEditor.razor.cs:728` vs skill `:146`) plus an undocumented 3B write block `:700-709`, `WebModuleRegistrar` path wrong (only `TestAuto.Web/AutoRegistration/`, not `TestAuto.AutoRegistration/`), S1 RecordSource. FALSE: the "ContinuousStrategy PostLoop" sub-claim — this skill is ALREADY correct at `:765`; that sub-claim belongs to the strategy-pattern item.
- `ext-testauto-matching-strategy-pattern-ops` — **PARTIAL**. TRUE: PostLoop-all-no-op (every implementer read: `BatchLoadStrategy.cs:175`, `PerRecordStrategy.cs:125`, `ContinuousStrategy` declares none — skill `:147` wrongly claims Continuous "persist tracked records"), S2=`BatchLoad` (wizard AND samples agree, skill `:32` disagrees with both), 3B mapping, 4 missing `required` members of `MatchingIterationContext` (`:32,33,45,48`). FALSE: "3C CreateOnly/Continuous" mis-attributes strategy selection to OperationType.
- `ext-testauto-matching-source-data-ops` — **PARTIAL**. TRUE: 3B OperationType `SKILL.md:96`, 3C mix (wizard = 100% new / Create100, skill says 85/15). FALSE: the skill states NO OperationType for 3C — nothing to correct; and 3B `RecordSource: NewValuesOnly` `:97` is ALREADY correct — do not change.
- `ext-testauto-matching-metrics-collector-guard` — **AGREE**. Overwrite genuinely reachable: guard warns and leaves zeros (`MatchingMetricsCollector.cs:157-162`) but `PopulateDerivedDurations()` at `:177` sits OUTSIDE the if/else and unconditionally reassigns negatives (`MetricDetailMatching.cs:132,142-149`). Skill `:153` promises zeros are preserved — false. Bonus: skill lists 6 of the 14 fields that method writes.
- `ext-matching-api-status-poller-token` — **AGREE**. Token IS requested per poll (`MatchingApiStatusPoller.cs:92-93`) but `OAuthTokenProvider.cs:54-55` short-circuits on cache until 5 min before expiry (`:94`), so with 30 s polls only poll #1 hits the network. Skill's "fresh … on every poll" `:61` is wrong. Sources block omits `OAuthTokenProvider.cs`.

### Batch B — CrewChief core / executors (7 items)

- `ext-crewchief-workload-and-runs-duration` — **AGREE**. `FormatDurationMs` (`RunDisplay.cs:57-72`) has exactly TWO clock branches `mm:ss.fff` / `h:mm:ss.fff`; skill `:74`'s `"742 ms"` / `"4 s"` / `"1m 23s"` / `"2h 5m 9s"` tiers and its "rounding once at the seconds level" are all fiction (rounding is at ms). Second finding NOT in the backlog claim: skill `:72` attributes the planned-steps surface to **`BuildPlannedStepNames`, an identifier with ZERO hits repo-wide** — the real builder is `BuildPlannedSteps` returning `PlannedStepInfo(Name, Type)` (`IWorkloadRunCoordinator.cs:46,90`; `WorkloadRunCoordinator.cs:216`).
- `desc-crewchief-workload-and-runs` — **AGREE**. "tiers" does appear at `SKILL.md:4` and is wrong.
- `ext-crewchief-web-ui-caps-types` — **AGREE** (4/4). `MaxStepOutputChars` is **100000** in all 4 appsettings + all 3 code fallbacks (`Web/Program.cs:260`, `Cli/Program.cs:106`, `StepEditorCard.razor.cs:2080`); skill `:76` says 20000. `AllTypes` key is `"CURL"` (`UtilityStepTypeInfo.cs:166-169`), not `CurlStep` — and this matters: `Steps.razor.cs:681` matches `"CURL"` only, so the skill's key would hit the CommandLineStep fallback. StepEditorCard is 2089 lines (skill says ~2025); 7 cites drifted. `MoveParameterToTop/Bottom` (`:686,:692`) + global mirrors undocumented.
- `ext-crewchief-step-executors-unknown-type` — **AGREE**, and it resolves a standing contradiction with an EARLIER audit. Two distinct paths: **deserialization THROWS** (`UtilityStepConverter.cs:38-41` `JsonSerializationException`; `UtilityStepBase.cs:107-110` `NotSupportedException`; `StepTypeRegistry.TryResolve:143-153` has no default registration) while the **Web "Add Step" factory FALLS BACK** (`Steps.razor.cs:698`, `WorkloadEditor.razor.cs:539` → `_ => new CommandLineStep()`). Skill `:47`/`:29`/`:17` attribute the fallback to deserialization — wrong. ⚠️ The corrected text MUST retain the UI-factory fallback as a live footgun, or the fix trades a false statement for a lost true one.
- `ext-crewchief-architecture-19-steps` — **AGREE**. Independent count of `StepTypeRegistry.cs:54-72` = **19**; README `:71` also says 19. Skill `:49-51` says "16 per the README" AND invents a reconciliation ("DeveloperPack counts 19 because it also lists Email, IisReset, DatabaseOperations separately") — those three ARE registry entries `:65,:71,:72`. Both the number and the explanation are wrong.
- `ext-crewchief-adding-orchestration-cites` — **PARTIAL**. TRUE: `CreateStepForType` cites off by **+396** (`Steps.razor.cs` 279→675-699) and **+138** (`WorkloadEditor.razor.cs` 378→516-540); orchestrator dispatch 236→246-248, `ContainsKey` 466→481. ⚠️ ALREADY EXACT — do not "fix": `StepTypeRegistry.cs:71-72` aliases, `UtilityOrchestrator.cs:87` `AddExecutorAlias`, `EmailExecutor.cs:121`. The substantive "no `email` short alias in the executor-alias block `:61-87`" claim is still true.
- `ext-crewchief-orchestration-cites` — **AGREE** (drift +1…+17 across ~20 cites; file now 828 lines). ⚠️ ALREADY EXACT — do not touch: `line 177` (`LiveStepOutput.Clear()`), `lines 346-347`, `lines 36-48` (two serializers), `IProcessRunner.cs:97,105`. A blanket renumbering pass would corrupt these.

### Cross-cutting findings the original sweep did NOT flag

1. **`3A` routes to `ContinuousStrategy`, not `PerRecordStrategy`.** `MatchingStrategyFactory.cs:23-29` branches on `IsBatchLoadMode` then `!WaitForMatching`; the wizard sets `WaitForMatching=false` for 3A (`UnifiedMatchingScenarioEditor.razor.cs:215`), so a wizard-built 3A config gets `ContinuousStrategy`. `testauto-matching-strategy-pattern:128-130` claims 3A → `PerRecordStrategy`. Higher-consequence than several flagged items.
2. **`ContinuousMatching` is a declared-but-dead parm.** Defined `MatchingConstants.cs:270`, set by samples, but ZERO consumer reads in `TestAuto.Matching`. `testauto-matching-scenarios` contradicts itself: `:177` lists it as a CustomParm, `:665` says it is not one. Both statements are partly wrong.
3. **Zero-hit identifiers are a distinct defect class** worse than line drift (an agent greps, finds nothing, concludes the feature is absent). Confirmed instances: `BuildPlannedStepNames`, `TestAuto.AutoRegistration/WebModuleRegistrar.cs`.

### "The proposed fix would itself introduce an error" flags

- `ext-testauto-matching-scenarios-wizard-ops`: a blanket rewrite toward the wizard would falsify the Sample Configs block (`SKILL.md:418-482`), whose snippets mirror real on-disk files — and those files are **nested** under `TimingParms`/`MatchingFlow`/`NewRecordDistribution`, while the skill shows them flat. Keep the divergence documented; do not flatten the snippets.
- `ext-testauto-matching-strategy-pattern-ops`: the caveat at `SKILL.md:39-42` ("executor XML comments describe 3B=LookupThenCreate / 3C=CreateOnly — trust the shipped configs") is FACTUALLY ACCURATE about what those comments say. It must be rewritten, not deleted or inverted — deleting loses the only record that two mappings coexist; inverting falsely implies the samples are unused.
- `ext-crewchief-step-executors-unknown-type` and both cite-drift items: see ⚠️ notes above.

---

## Implemented 2026-07-27 — item detail (all 71 APPLIED; see `## Implemented` for per-item outcomes)

_Retained for provenance. Every item below was approved and applied on 2026-07-27. Line numbers inside these item bodies are as-recorded at the 6f30e17e baseline and were NOT used verbatim — each apply agent re-derived cites at HEAD 4c367fe6._

### ext-testauto-matching-scenarios-wizard-ops — testauto-matching-scenarios
- **Kind**: ext
- **Target**: testauto-matching-scenarios
- **Score**: 10
- **Description**: Correctness — align 3B/3C OperationType matrix + deep-dive with live wizard (3B=LookupThenCreate, 3C=CreateOnly); fix Lubc triple-guard, ContinuousStrategy PostLoop, ContinuousMatching parm, WebModuleRegistrar path, S1 RecordSource.
- **Sources**: `TestAuto.Web/Components/Controls/UnifiedMatchingScenarioEditor.razor.cs`, `TestAuto.Matching/Strategies/ContinuousStrategy.cs`, `TestAuto.Web/AutoRegistration/WebModuleRegistrar.cs`
- **Added**: 2026-07-25
- **Notes**: correctness fix. Samples still lag wizard — document wizard as SoT. Prior Mode 6 had inverted this toward samples; code moved again.

### ext-testauto-matching-strategy-pattern-ops — testauto-matching-strategy-pattern
- **Kind**: ext
- **Target**: testauto-matching-strategy-pattern
- **Score**: 10
- **Description**: Correctness — rewrite OperationType×strategy table for wizard (3B LookupThenCreate, 3C CreateOnly/Continuous, S2 BatchLoad); PostLoop all no-op; add MatchingIterationContext missing props.
- **Sources**: `UnifiedMatchingScenarioEditor.razor.cs`, `MatchingStrategyFactory.cs`, `ContinuousStrategy.cs`, `MatchingIterationContext.cs`
- **Added**: 2026-07-25
- **Notes**: correctness fix

### ext-testauto-matching-source-data-ops — testauto-matching-source-data
- **Kind**: ext
- **Target**: testauto-matching-source-data
- **Score**: 9
- **Description**: Correctness — 3B/3C OperationType + mix claims vs wizard (3C CreateOnly 100% new).
- **Sources**: `UnifiedMatchingScenarioEditor.razor.cs`
- **Added**: 2026-07-25
- **Notes**: correctness fix

### ext-profisee-dq-rules-grammar-mcp — profisee-dq-rules
- **Kind**: ext
- **Target**: profisee-dq-rules
- **Score**: 10
- **Description**: Correctness — rewrite expression language + MCP payload to live grammar (`=`/`<>`, `= NULL`, `"…"` strings, `[Attr].[Name]`) and `save_data_quality_rules` schema (`request.rules`, `what_expression`, `assignment_execution_mode`).
- **Sources**: MCP `get_profisee_expression_grammar`, `save_data_quality_rules` schema
- **Added**: 2026-07-25
- **Notes**: correctness fix; also needs desc rewrite (IsNotNull/gt triggers)

### desc-profisee-dq-rules — profisee-dq-rules
- **Kind**: desc
- **Target**: profisee-dq-rules
- **Description**: Drop invented triggers (IsNotNull, gt/eq); use grammar/MCP-accurate triggers.
- **Sources**: skill frontmatter + grammar
- **Added**: 2026-07-25
- **Notes**: pair with ext-profisee-dq-rules-grammar-mcp

### ext-crewchief-workload-and-runs-duration — crewchief-workload-and-runs
- **Kind**: ext
- **Target**: crewchief-workload-and-runs
- **Score**: 10
- **Description**: Correctness — FormatDurationMs is clock `mm:ss.fff`/`h:mm:ss.fff` (not tiered text); BuildPlannedSteps + CurrentRunPlannedSteps surface.
- **Sources**: `CrewChief.Web/Components/Pages/RunDisplay.cs`, `WorkloadRunCoordinator.cs`, `IWorkloadRunCoordinator.cs`
- **Added**: 2026-07-25
- **Notes**: correctness fix; also update description "tiers" wording

### desc-crewchief-workload-and-runs — crewchief-workload-and-runs
- **Kind**: desc
- **Target**: crewchief-workload-and-runs
- **Description**: Replace "FormatDurationMs tiers" with clock-style duration wording.
- **Sources**: `RunDisplay.cs`
- **Added**: 2026-07-25
- **Notes**: pair with ext above

### ext-crewchief-default-templates-firstrun — crewchief-default-templates
- **Kind**: ext
- **Target**: crewchief-default-templates
- **Score**: 10
- **Description**: Correctness — FirstRunBanner always InstallAll (no checkbox); remove resetsamples; GetSampleStatuses unions sample+reference; document InstallSelected + secrets samples.
- **Sources**: `FirstRunBanner.razor`, `TemplateInstaller.cs`, `CrewChief.iss`, `SampleContentSeeder.cs`
- **Added**: 2026-07-25
- **Notes**: correctness fix

### ext-inno-setup-installer-resetsamples — inno-setup-installer
- **Kind**: ext
- **Target**: inno-setup-installer
- **Score**: 9
- **Description**: Correctness — remove resetsamples task; bump Version cite to 1.0.60.
- **Sources**: `CrewChief.iss`, `Directory.Build.props`
- **Added**: 2026-07-25
- **Notes**: correctness fix

### ext-crewchief-web-ui-caps-types — crewchief-web-ui
- **Kind**: ext
- **Target**: crewchief-web-ui
- **Score**: 9
- **Description**: Correctness — MaxStepOutputChars default 100000; AllTypes key CURL not CurlStep; refresh StepEditorCard line cites + MoveParameterToTop/Bottom.
- **Sources**: `appsettings.json`, `UtilityStepTypeInfo.cs`, `StepEditorCard.razor(.cs)`
- **Added**: 2026-07-25
- **Notes**: correctness fix

### ext-crewchief-step-executors-unknown-type — crewchief-step-executors
- **Kind**: ext
- **Target**: crewchief-step-executors
- **Score**: 9
- **Description**: Correctness — unknown type throws on deserialize (no CommandLine fallback); MaxStepOutputChars default 100000.
- **Sources**: `UtilityStepConverter.cs`, `UtilityStepBase.cs`, `Program.cs`/`appsettings.json`
- **Added**: 2026-07-25
- **Notes**: correctness fix; Web CreateStepForType `_ => CommandLineStep` is separate

### ext-crewchief-architecture-19-steps — crewchief-architecture
- **Kind**: ext
- **Target**: crewchief-architecture
- **Score**: 8
- **Description**: Correctness — README and registry both 19 step types (drop 16-vs-19 framing).
- **Sources**: `CrewChief/README.md`
- **Added**: 2026-07-25
- **Notes**: correctness fix

### ext-crewchief-adding-orchestration-cites — crewchief-adding-a-step-type
- **Kind**: ext
- **Target**: crewchief-adding-a-step-type
- **Score**: 7
- **Description**: Update CreateStepForType / orchestrator dispatch+validation line cites to live ranges.
- **Sources**: `Steps.razor.cs`, `WorkloadEditor.razor.cs`, `UtilityOrchestrator.cs`
- **Added**: 2026-07-25
- **Notes**: correctness fix (line drift)

### ext-crewchief-orchestration-cites — crewchief-orchestration
- **Kind**: ext
- **Target**: crewchief-orchestration
- **Score**: 7
- **Description**: Update ValidateScenario / success / dispatch line ranges to live.
- **Sources**: `UtilityOrchestrator.cs`
- **Added**: 2026-07-25
- **Notes**: correctness fix (line drift)

### ext-crewchief-logging-startup-dead — crewchief-logging
- **Kind**: ext
- **Target**: crewchief-logging
- **Score**: 6
- **Description**: Correctness — LogTagConstants.Startup is test-only (no production call sites).
- **Sources**: `LogTagConstants.cs`, `LoggingTagTests.cs`
- **Added**: 2026-07-25
- **Notes**: correctness fix

### ext-crewchief-file-persistence-truncation — crewchief-file-persistence
- **Kind**: ext
- **Target**: crewchief-file-persistence
- **Score**: 8
- **Description**: Correctness — run-history truncation is head+tail with omitted-chars marker.
- **Sources**: `RunHistoryFile.cs`
- **Added**: 2026-07-25
- **Notes**: correctness fix

### ext-crewchief-secrets-bootstrap-cite — crewchief-secrets
- **Kind**: ext
- **Target**: crewchief-secrets
- **Score**: 5
- **Description**: Update UseSecretsBootstrapRedirect cite Program.cs:343.
- **Sources**: `CrewChief.Web/Program.cs`
- **Added**: 2026-07-25
- **Notes**: line drift

### ext-crewchief-reference-data-ondemand — crewchief-reference-data
- **Kind**: ext
- **Target**: crewchief-reference-data
- **Score**: 8
- **Description**: Correctness — StepDescriptionSeeder via InstallAll not startup; SampleContentSeeder also installs *.secrets.json.
- **Sources**: `TemplateInstaller.cs`, `SampleContentSeeder.cs`, `StepDescriptionSeeder.cs`
- **Added**: 2026-07-25
- **Notes**: correctness fix

### ext-crewchief-remote-box-prep-msgs — crewchief-remote-box-prep
- **Kind**: ext
- **Target**: crewchief-remote-box-prep
- **Score**: 8
- **Description**: Correctness — remote credential errors name User/Password OR credentialSecretName; expand IsLocalTarget; document ShareMount/CC_SHARE_*.
- **Sources**: `ConfigureExecutor.cs`, `MapShareExecutor.cs`, `DefaultRemoteCommandRunner.cs`
- **Added**: 2026-07-25
- **Notes**: correctness fix

### ext-crewchief-testing-readme-ratio — crewchief-testing
- **Kind**: ext
- **Target**: crewchief-testing
- **Score**: 4
- **Description**: Drop stale 19/22 README pass-ratio claim.
- **Sources**: `CrewChief/README.md`
- **Added**: 2026-07-25
- **Notes**: correctness fix

### ext-crewchief-workload-transfer-cites — crewchief-workload-transfer
- **Kind**: ext
- **Target**: crewchief-workload-transfer
- **Score**: 5
- **Description**: Update Program.cs registration cites; password-field sourcing now SecretValueEditor/ShareCredentialEditor.
- **Sources**: `CrewChief.Web/Program.cs`, `StepEditorCard.razor`
- **Added**: 2026-07-25
- **Notes**: line/UI drift

### ext-testauto-workflow-execution-enqueue — testauto-workflow-execution
- **Kind**: ext
- **Target**: testauto-workflow-execution
- **Score**: 10
- **Description**: Correctness — CLI→ScenarioEnqueueService/default queue; isFromWorkflowExecution log-only; Aggregator DisplayName `{0}`; editor OpenScenarioEditorDialog*; fail-fast on Failed.
- **Sources**: `VerbRunTestOptionsHandler.cs`, `ScenarioEnqueueService.cs`, `ScenarioExecutionService.cs`, `WorkflowOrchestrationService.cs`
- **Added**: 2026-07-25
- **Notes**: correctness fix

### ext-testauto-hangfire-architecture-chain — testauto-hangfire-architecture
- **Kind**: ext
- **Target**: testauto-hangfire-architecture
- **Score**: 9
- **Description**: Correctness — live chain MetricsPersistenceJob→WorkloadExecutionUpdateJob; CollectionUpdateJob unwired; drop Batch→Aggregator→Persistence design goal.
- **Sources**: `BatchJobOrchestrator.cs`, `HangfireServerServiceExtensions.cs`, `CollectionUpdateJob.cs`
- **Added**: 2026-07-25
- **Notes**: correctness fix

### ext-testauto-batch-orchestration-selfmanaged — testauto-batch-orchestration
- **Kind**: ext
- **Target**: testauto-batch-orchestration
- **Score**: 9
- **Description**: Correctness — SelfManaged = one child job per server (same branch as Other), not one job total.
- **Sources**: `BatchJobOrchestrator.cs:176-209`
- **Added**: 2026-07-25
- **Notes**: correctness fix

### ext-testauto-resource-collection-seed — testauto-resource-collection
- **Kind**: ext
- **Target**: testauto-resource-collection
- **Score**: 6
- **Description**: Seeder up to 3 (skip empty/dup); AggregationInterval code fallback 15s vs appsettings 5s.
- **Sources**: `ResourceCollectionService.cs`, `PrometheusClient.cs`, `appsettings.json`
- **Added**: 2026-07-25
- **Notes**: correctness fix

### ext-testauto-bounded-parallel-fanout — testauto-bounded-parallel-fanout
- **Kind**: ext
- **Target**: testauto-bounded-parallel-fanout
- **Score**: 4
- **Description**: Fix SemaphoreSlim line cite; add StepTokenBulkEditPanel evidence.
- **Sources**: `MatchingBulkEditPanel.razor.cs`, `StepTokenBulkEditPanel.razor.cs`
- **Added**: 2026-07-25
- **Notes**: minor

### ext-testauto-connex-service-paths — testauto-connex-service
- **Kind**: ext
- **Target**: testauto-connex-service
- **Score**: 9
- **Description**: Correctness — ConnectRestClient gateway BuildPath; JsonResponse IsSuccess OK/Created/NoContent; SQL tActivityDetails only; flat-format folder mixed.
- **Sources**: `ConnectRestClient.cs`, `JsonResponse.cs`, `ConnectExecutionRepository.cs`
- **Added**: 2026-07-25
- **Notes**: correctness fix

### ext-testauto-connex-provider-templates-flat — testauto-connex-provider-templates
- **Kind**: ext
- **Target**: testauto-connex-provider-templates
- **Score**: 9
- **Description**: Correctness — ConnExStep JSON is flat (no nested ConnExStep object); csproj None Update Scripts\\**\\*; tree gaps.
- **Sources**: `ConnExStep.cs`, `ConnExScenarioFactory.cs`, `TestAuto.Utilities.csproj`
- **Added**: 2026-07-25
- **Notes**: correctness fix

### ext-custom-parm-editor-connex-monitor — custom-parm-editor
- **Kind**: ext
- **Target**: custom-parm-editor
- **Score**: 5
- **Description**: UtilityScenarioEditor architecture includes ConnExStep/MonitorStep.
- **Sources**: `UtilityScenarioEditor.razor`
- **Added**: 2026-07-25
- **Notes**: gap

### ext-bulk-custom-parms-apply-label — bulk-custom-parms-editor-base
- **Kind**: ext
- **Target**: bulk-custom-parms-editor-base
- **Score**: 3
- **Description**: Button label "Apply Compatible" (not "Apply Compatible Only").
- **Sources**: `BulkCustomParmsEditorBase.cs`
- **Added**: 2026-07-25
- **Notes**: minor

### ext-testauto-config-validation-pipeline — testauto-config-validation
- **Kind**: ext
- **Target**: testauto-config-validation
- **Score**: 9
- **Description**: Correctness — ValidateConfigurationAsync runs only ScenarioConfigurationValidator; CrossField unwired; document ShadowMode + missing Job/Load validators + complete field lists.
- **Sources**: `ValidationService.cs`, `ScenarioManagementServiceExtensions.cs`
- **Added**: 2026-07-25
- **Notes**: correctness fix

### ext-testauto-scenario-config-store-chunk — testauto-scenario-config-store
- **Kind**: ext
- **Target**: testauto-scenario-config-store
- **Score**: 7
- **Description**: Document whitespace-boundary-safe chunk split (Profisee trim invariant).
- **Sources**: `ScenarioConfigStore.cs`, `ScenarioConfigStoreTests.cs`
- **Added**: 2026-07-25
- **Notes**: gap

### ext-configuration-compression-decompressfully — configuration-compression-codec
- **Kind**: ext
- **Target**: configuration-compression-codec
- **Score**: 6
- **Description**: Add DecompressFully API entry (store + migration).
- **Sources**: `TemplateStorage.cs`, `ScenarioConfigStore.cs`, `ConfigurationMigrationJob.cs`
- **Added**: 2026-07-25
- **Notes**: gap

### ext-testauto-scenario-catalog-stewardship — testauto-scenario-catalog
- **Kind**: ext
- **Target**: testauto-scenario-catalog
- **Score**: 9
- **Description**: Correctness — stewardship both-limits=0 throws; NewRecordPercent keys; GETPAGE every iteration; add GetRecordsByCodeScenario; fix flowchart.
- **Sources**: `ScenarioBase.cs`, `StewardshipFilterScenario.cs`, `GetRecordsByCodes.cs`
- **Added**: 2026-07-25
- **Notes**: correctness fix

### ext-testauto-stewardship-scenario-pattern — testauto-stewardship-scenario-pattern
- **Kind**: ext
- **Target**: testauto-stewardship-scenario-pattern
- **Score**: 8
- **Description**: Correctness — delete pick = page minus selected (not _usedRecordCodes filter); dual-zero throw.
- **Sources**: `StewardshipFilterScenario.cs`, `ScenarioBase.cs`
- **Added**: 2026-07-25
- **Notes**: correctness fix

### ext-testauto-scenario-display-card — testauto-scenario-display
- **Kind**: ext
- **Target**: testauto-scenario-display
- **Score**: 7
- **Description**: ScenarioListEditor hosts cards; IsActive on library only; drop files pills.
- **Sources**: `ScenarioListEditor.razor`, `Scenarios.razor`
- **Added**: 2026-07-25
- **Notes**: correctness fix

### ext-testauto-scenario-metrics-patterns — testauto-scenario-metrics
- **Kind**: ext
- **Target**: testauto-scenario-metrics
- **Score**: 8
- **Description**: Correctness — DataPattern.Other like SelfManaged; drop LubcMatchingScenario; MetricDetailLubcMatching:MetricRequestBase; RecordApiExecution entity.
- **Sources**: `BatchJobOrchestrator.cs`, `MetricDetailLubcMatching.cs`, `MetricSharedConstants.cs`
- **Added**: 2026-07-25
- **Notes**: correctness fix

### ext-testauto-scenario-types-attribute-examples — testauto-scenario-types-attribute
- **Kind**: ext
- **Target**: testauto-scenario-types-attribute
- **Score**: 8
- **Description**: Correctness — MatchingStrategyPolling live ScenarioTypes; Metadata actions Add/Delete/replace.
- **Sources**: `MatchingStrategyPollingScenario.cs`, `MetadataManagementEditor.razor.cs`
- **Added**: 2026-07-25
- **Notes**: correctness fix

### ext-testauto-multistep-steps-tokens — testauto-multistep-steps
- **Kind**: ext
- **Target**: testauto-multistep-steps
- **Score**: 9
- **Description**: Correctness — prefix-driven token resolve; MaxTimeSeconds??30; ARCHIVEDATA Strategy-only; SQL secret names; drop script-file troubleshooting; UseRestMethod.
- **Sources**: `TextTemplater.cs`, `HttpRequestStep.cs`, `CLUCommandBuilder.cs`, `SqlScriptExecutor.cs`
- **Added**: 2026-07-25
- **Notes**: correctness fix

### ext-testauto-execution-context-icontext — testauto-execution-context
- **Kind**: ext
- **Target**: testauto-execution-context
- **Score**: 5
- **Description**: CdpContext implements Profisee.Platform.Utilities.Cdp.Interface.IContext (full name).
- **Sources**: `CdpContext.cs`
- **Added**: 2026-07-25
- **Notes**: correctness fix

### ext-utility-step-createfromjtoken — utility-step-polymorphic-deserialization
- **Kind**: ext
- **Target**: utility-step-polymorphic-deserialization
- **Score**: 7
- **Description**: Document UtilityStepBase.CreateFromJToken dual path (keep switch synced with converter).
- **Sources**: `UtilityStepBase.cs`, `UtilityScenarioEditor.razor.cs`
- **Added**: 2026-07-25
- **Notes**: gap

### desc-testauto-metric-detail-builder — testauto-metric-detail-builder
- **Kind**: desc
- **Target**: testauto-metric-detail-builder
- **Description**: Separate IMetricFactory vs IMetricDetailFactory triggers (not same API).
- **Sources**: `IMetricFactory.cs`, `IMetricDetailFactory.cs`
- **Added**: 2026-07-25
- **Notes**: description conflation

### ext-testauto-ui-patterns-monaco — testauto-ui-patterns
- **Kind**: ext
- **Target**: testauto-ui-patterns
- **Score**: 7
- **Description**: MonacoJsonEditor is live BlazorMonaco host; ExecutionHistory not PeriodicTimer; SelectedCodes comparer nuance.
- **Sources**: `MonacoJsonEditor.razor.cs`, `ExecutionHistory.razor.cs`, `ExecutionMonitoring.razor.cs`
- **Added**: 2026-07-25
- **Notes**: correctness fix

### ext-testauto-log-tags-begin-timed — testauto-log-tags
- **Kind**: ext
- **Target**: testauto-log-tags
- **Score**: 4
- **Description**: BeginTimedOperationWithTag unused in TestAuto but used in CrewChief tests.
- **Sources**: `LoggerTagExtensions.cs`, `CrewChief LoggingTagTests.cs`
- **Added**: 2026-07-25
- **Notes**: wording

### ext-blazor-code-behind-bases — blazor-code-behind
- **Kind**: ext
- **Target**: blazor-code-behind
- **Score**: 6
- **Description**: OnParametersSetAsync is used; list shared bases; mark dialog OnInitialized timer as anti-pattern.
- **Sources**: `RealTimeValidation.razor.cs`, `MarkdownDocBase.cs`, `BulkCustomParmsEditorBase.cs`
- **Added**: 2026-07-25
- **Notes**: correctness fix

### ext-blazor-icons-whitelist — blazor-icons
- **Kind**: ext
- **Target**: blazor-icons
- **Score**: 5
- **Description**: Add production icons add/menu_open + map targets to whitelist.
- **Sources**: `Icon.razor.cs`, `TemplateSelector.razor`, `HelpLayout.razor`
- **Added**: 2026-07-25
- **Notes**: gap

### ext-testauto-http-facades-attrs — testauto-http-facades
- **Kind**: ext
- **Target**: testauto-http-facades
- **Score**: 5
- **Description**: FindLatestBatchByStrategyNameAsync includes Attributes query; LoggingHandler template has "responded".
- **Sources**: `ConnectRestClient.cs`, `LoggingHandler.cs`
- **Added**: 2026-07-25
- **Notes**: drift

### ext-matching-api-status-poller-token — matching-api-status-poller
- **Kind**: ext
- **Target**: matching-api-status-poller
- **Score**: 4
- **Description**: Token requested each poll but provider may return cached.
- **Sources**: `MatchingApiStatusPoller.cs`, `OAuthTokenProvider.cs`
- **Added**: 2026-07-25
- **Notes**: wording

### ext-testauto-matching-metrics-collector-guard — testauto-matching-metrics-collector
- **Kind**: ext
- **Target**: testauto-matching-metrics-collector
- **Score**: 7
- **Description**: Correctness — negative-duration guard then always PopulateDerivedDurations (can overwrite zeros).
- **Sources**: `MatchingMetricsCollector.cs`
- **Added**: 2026-07-25
- **Notes**: correctness fix

### ext-testauto-record-transformation-mutation — testauto-record-transformation
- **Kind**: ext
- **Target**: testauto-record-transformation
- **Score**: 9
- **Description**: Correctness — UseMutationHelper is live selector; MutationTransformer Tier-1 MutationSettings unreachable; AttributeGroups only VariantGenerator; Faker vs Mutation helper usage.
- **Sources**: `MutationTransformer.cs`, `UpdateContinousRecordsByPageAndBatchScenario.cs`, `VariantGenerator.cs`
- **Added**: 2026-07-25
- **Notes**: correctness fix

### ext-testauto-enrichment-generators-factory — testauto-enrichment-generators
- **Kind**: ext
- **Target**: testauto-enrichment-generators
- **Score**: 8
- **Description**: Correctness — FieldGeneratorFactory case still required; Program.cs filter snippet; note adding_new_generator.md Scrutor stale.
- **Sources**: `FieldGeneratorFactory.cs`, `Program.cs`
- **Added**: 2026-07-25
- **Notes**: correctness fix

### ext-testdata-enrichment-pipeline-pointer — testdata-enrichment-pipeline
- **Kind**: ext
- **Target**: testdata-enrichment-pipeline
- **Score**: 6
- **Description**: Drop wrong "see testauto-enrichment-generators for TestAuto" pointer (that skill is TestData.Enrichment.Core).
- **Sources**: skill frontmatter / When-to-use
- **Added**: 2026-07-25
- **Notes**: correctness fix

### ext-testauto-test-data-generation — testauto-test-data-generation
- **Kind**: ext
- **Target**: testauto-test-data-generation
- **Score**: 8
- **Description**: Correctness — GetRecordsByCodeScenario name; Paged envelope factory; align/remove stale CloneAndMutate rule table.
- **Sources**: `GetRecordsByCodes.cs`, `TestDataFactory.cs`, `MutationHelper.cs`, `RuleIds.cs`
- **Added**: 2026-07-25
- **Notes**: correctness fix

### ext-testauto-lookup-cache-runprofiles — testauto-lookup-cache-pattern
- **Kind**: ext
- **Target**: testauto-lookup-cache-pattern
- **Score**: 5
- **Description**: LoadAllAsync table add GetRunProfiles / GetConnectRunProfiles.
- **Sources**: `ReferenceDataCache.cs`
- **Added**: 2026-07-25
- **Notes**: gap

### hyg-testauto-odata-query-building-source — testauto-odata-query-building
- **Kind**: hyg
- **Target**: testauto-odata-query-building
- **Description**: Sources cite wrong QueryExpressionBuilder.cs — point at Web QueryParameterBuilder.
- **Sources**: skill Sources vs live files
- **Added**: 2026-07-25
- **Notes**: hygiene

### ext-testauto-utilities-module-connex — testauto-utilities-module
- **Kind**: ext
- **Target**: testauto-utilities-module
- **Score**: 7
- **Description**: Add ConnExStep/MonitorStep to tables; eight executors; annotate removed Agents.md source.
- **Sources**: `UtilitiesModuleRegistrar.cs`, `UtilityStepConverter.cs`
- **Added**: 2026-07-25
- **Notes**: correctness fix + hyg citation

### ext-testauto-testing-patterns-api — testauto-testing-patterns
- **Kind**: ext
- **Target**: testauto-testing-patterns
- **Score**: 7
- **Description**: Correctness — GetRecordAsync not GetRecordByCodeAsync; Unit inherits TestBase not all BaseTest.
- **Sources**: `IRestClient.cs`, `Testing.SpeedMerchants.Unit/.../TestBase.cs`
- **Added**: 2026-07-25
- **Notes**: correctness fix

### ext-profisee-rest-api-getall — profisee-rest-api
- **Kind**: ext
- **Target**: profisee-rest-api
- **Score**: 6
- **Description**: Document GetAllRecordsAsync (first-page truncation trap).
- **Sources**: `IRestClient.cs`
- **Added**: 2026-07-25
- **Notes**: gap

### ext-api-response-standardization-adoption — api-response-standardization
- **Kind**: ext
- **Target**: api-response-standardization
- **Score**: 7
- **Description**: Correctness — BaseApiController used by one controller; most still ControllerBase; helpers unused.
- **Sources**: `TestAuto.Web/Controllers/*`
- **Added**: 2026-07-25
- **Notes**: correctness fix

### ext-dotnet-project-structure-di — dotnet-project-structure
- **Kind**: ext
- **Target**: dotnet-project-structure
- **Score**: 6
- **Description**: Soften "never Program.cs" — Web registers ConnEx/Metadata/Secrets; per-module registrars.
- **Sources**: `TestAuto.Web/Program.cs`
- **Added**: 2026-07-25
- **Notes**: correctness fix

### ext-dotnet-service-registration-hangfire — dotnet-service-registration
- **Kind**: ext
- **Target**: dotnet-service-registration
- **Score**: 8
- **Description**: Correctness — Hangfire gated by HangfireDB not hasMinimumConfig; add IReferenceDataCache step.
- **Sources**: `RegisterAllServices.cs`
- **Added**: 2026-07-25
- **Notes**: correctness fix

### ext-dotnet-testing-messagesession — dotnet-testing
- **Kind**: ext
- **Target**: dotnet-testing
- **Score**: 6
- **Description**: messageSession never initialized; add Tests/Logs/; clarify Testing.SpeedMerchants.* project names.
- **Sources**: `PerformanceBaseTestClass.cs`
- **Added**: 2026-07-25
- **Notes**: correctness fix

### ext-dotnet-logging-schema-console — dotnet-logging-schema
- **Kind**: ext
- **Target**: dotnet-logging-schema
- **Score**: 5
- **Description**: Align "no console sink" with Profisee sinks (console, file, SEQ).
- **Sources**: `TestData.Shared/Extensions/LoggingExtensions.cs`
- **Added**: 2026-07-25
- **Notes**: correctness fix

### ext-speedmerchants-db-migration-mcp — speedmerchants-db-migration
- **Kind**: ext
- **Target**: speedmerchants-db-migration
- **Score**: 7
- **Description**: Update MCP server aliases to user-speedmerchants-*-mssql; stop hardcoding admin creds.
- **Sources**: live MCP catalog
- **Added**: 2026-07-25
- **Notes**: correctness fix; skill currently embeds plaintext password — scrub on apply

### ext-testauto-secrets-management-bootstrap — testauto-secrets-management
- **Kind**: ext
- **Target**: testauto-secrets-management
- **Score**: 9
- **Description**: Correctness — primary bootstrap is console RunInteractiveSetupAsync; middleware dormant; DPAPI LocalMachine.
- **Sources**: `TestAuto.Web/Program.cs`, `MasterPasswordManager.cs`
- **Added**: 2026-07-25
- **Notes**: correctness fix

### ext-testauto-local-setup-cache — testauto-local-setup
- **Kind**: ext
- **Target**: testauto-local-setup
- **Score**: 7
- **Description**: Cache off via FeatureFlags/CommandLine not Production JSON; soften WebModuleRegistrar-only DI claim; stale SetupLocal path.
- **Sources**: `appsettings.CommandLine.json`, `Program.cs`
- **Added**: 2026-07-25
- **Notes**: correctness fix

### ext-testauto-project-layout — testauto-project
- **Kind**: ext
- **Target**: testauto-project
- **Score**: 6
- **Description**: Allow small @code; ScenarioEditorContent under Pages/; Hangfire jobs mainly Web/Scenarios.
- **Sources**: `ScenarioCompare.razor`, `ScenarioEditorContent.razor`
- **Added**: 2026-07-25
- **Notes**: correctness fix

### ext-testauto-tech-stack-testing — testauto-tech-stack
- **Kind**: ext
- **Target**: testauto-tech-stack
- **Score**: 7
- **Description**: Correctness — drop Playwright/NSubstitute; MSDOTest+bUnit+Moq.
- **Sources**: repo packages / zero Playwright hits
- **Added**: 2026-07-25
- **Notes**: correctness fix

### ext-testauto-modular-di-metadata — testauto-modular-di
- **Kind**: ext
- **Target**: testauto-modular-di
- **Score**: 6
- **Description**: MetadataModuleRegistrar is empty placeholder; Matching not-in-DI list add IRecordMixManager.
- **Sources**: `MetadataModuleRegistrar.cs`, `MatchingModuleRegistrar.cs`
- **Added**: 2026-07-25
- **Notes**: correctness fix

### ext-testauto-prometheus-config-logs — testauto-prometheus-config
- **Kind**: ext
- **Target**: testauto-prometheus-config
- **Score**: 4
- **Description**: Quote live Serilog templates (no emoji).
- **Sources**: `ResourceCollectionService.cs`
- **Added**: 2026-07-25
- **Notes**: drift

### ext-testauto-debugging-workflow-monitor — testauto-debugging-common-failures
- **Kind**: ext
- **Target**: testauto-debugging-common-failures
- **Score**: 7
- **Description**: Correctness — workflow-monitor every IntervalMinutes (1 min shipped); lead with DI record-mix/pool not MatchingActivityMonitorService ctor.
- **Sources**: `WebModuleRegistrar.cs`, `appsettings.json`
- **Added**: 2026-07-25
- **Notes**: correctness fix

## Pending (awaiting review)

_None — all 33 candidates from the 2026-09-09 (Mode 1) pass were bulk-approved ("Everything, highest score first") and APPLIED the same session. Item detail is retained below under `## Implemented 2026-09-09`._

---

_Historical note from the previous pass:_

_None — the 9 items from the 2026-08-10 (PM) Mode 4 pass were bulk-approved ("All 9") and APPLIED the same session. Per-item outcomes are in `## Implemented`; the full item bodies are retained immediately below for provenance._

---

## Implemented 2026-08-10 (PM) — Mode 4 item detail (all 9 APPLIED)

_9 items from the 2026-08-10 (PM) Mode 4 full-corpus description review. Every claim below was verified first-hand in the main session against live code at `15401a46`; no sub-agent findings were transcribed. `desc` and `hyg` kinds are unscored per the rubric — the scores shown on `desc` items are advisory priority only. **Two items grew during apply** — see the `## Implemented` outcome record for what the apply-time verification changed._

### desc-dotnet-testing — dotnet-testing
- **Kind**: desc
- **Target**: dotnet-testing
- **Score**: 8 (advisory)
- **Description**: SKILL.md is TWO documents in one file and the description advertises only the first ~22%. Lines 10–208 are TestAuto integration-test infrastructure (BaseTest, PerformanceBaseTestClass, RegisterAllServices) — which the description covers. Lines 209–889 are a separate `# Legacy: Three-Tier Testing Framework (General .NET)` standard for PLATFORM repos: tier selection IF/THEN rules, rule precedence, placeholder resolution, per-tier Required Files (`unittest.runsettings` / `automation.runsettings`, `BaseTestConfiguration.cs`, `TestCategories.cs`, `SettingsRetriever.cs`, `{Service}AppFactory.cs`, `Fakes/`), Arrange-Act-Assert, Mocks-vs-Fakes-vs-Spies, `PollingAssert` (not `Task.Delay`), environment variables, and the one-test-project-per-repository rule with its exceptions and enforcement. None of that is reachable from the current triggers, so platform-repo test work never fires this skill.
- **Sources**: skill `dotnet-testing/SKILL.md:10,209,257,298,347,374,504,651,776,795`
- **Added**: 2026-08-10
- **Notes**: Missing triggers, not staleness — the body content is fine. Add three-tier / runsettings / one-test-project-per-repo / PollingAssert / AppFactory triggers. Related: the prior `ext-dotnet-testing-inconclusive-required-prereqs` item stays EXCLUDED; this is unrelated to it.

### desc-crewchief-step-executors — crewchief-step-executors
- **Kind**: desc
- **Target**: crewchief-step-executors
- **Score**: 7 (advisory)
- **Description**: The description's executor list — "(SQL, ConnEx, HTTP/curl, CLU, SetApiKey, DB-ops)" — omits three executors that HAVE dedicated body sections: `CheckPortExecutor`, `TeamsExecutor`, `WebSiteExecutor`. It also omits the `Built-in protections — refusals no flag can override` section (the never-delete guards). CrewChief.Engine declares 22 `IStepExecutor` implementations; these three are among the newest, so an agent authoring or debugging a CheckPort / Teams / WebSite step will not trigger the one skill that documents them.
- **Sources**: `CrewChief/CrewChief.Engine/Executors/CheckPortExecutor.cs:21`, `TeamsExecutor.cs:81`, `WebSiteExecutor.cs:28`; skill body H2s `SQL — SqlScriptExecutor` … `Built-in protections — refusals no flag can override`
- **Added**: 2026-08-10
- **Notes**: Missing triggers. Body already documents all three — description-only fix.

### desc-testauto-multistep-steps — testauto-multistep-steps
- **Kind**: desc
- **Target**: testauto-multistep-steps
- **Score**: 6 (advisory)
- **Description**: The trigger phrase `sqlSource/sqlDestination secret names` names no real key. Repo-wide, `sqlSource` and `sqlDestination` have ZERO hits (case-sensitive) and the only case-insensitive hit is an unrelated CrewChief capability label. The real JSON keys are `sqlSourceConnectionSecretName` and `sqlDestinationConnectionSecretName`.
- **Sources**: `TestAuto.Utilities/Common/DTOs/SqlStep.cs:17-18,26-27` (`[JsonProperty]` names), `TestAuto.Utilities/Services/UtilityOrchestrator.cs:446-454` (required-field validation messages), `TestAuto.Utilities/Executors/SqlScriptExecutor.cs:70-71,102-103`
- **Added**: 2026-08-10
- **Notes**: Truncated trigger term, not fabricated surface — an agent grepping the description's term finds nothing. Check whether the BODY uses the full key names before editing; only the description was audited in this pass.

### desc-testauto-scenario-version-history — testauto-scenario-version-history
- **Kind**: desc
- **Target**: testauto-scenario-version-history
- **Score**: 6 (advisory)
- **Description**: The description omits the single most decision-relevant fact about the subsystem, which the BODY already states correctly at `:148`: `ScenarioVersioningService` is an **in-memory stub** backed by `Dictionary<string, List<ScenarioVersionInfo>>`, process-scoped, with no database persistence. It also lists `CreateVersionRequest` as a trigger; that DTO is declaration-only (zero repo consumers) — the controller takes `[FromBody] ScenarioConfiguration` plus `[FromQuery] versionNotes`, which the body explains at `:101`.
- **Sources**: `TestAuto.Web/Services/ScenarioVersioningService.cs:9,12`, `TestAuto.Web/Controllers/ScenarioVersioningController.cs:106-125`, `TestAuto.Shared/Common/Scenario/CreateVersionRequest.cs:7` (sole occurrence repo-wide); skill `SKILL.md:101,148`
- **Added**: 2026-08-10
- **Notes**: ⚠️ DESCRIPTION ONLY — do NOT "fix" the body. `:101` and `:148` are already accurate; a rewrite there would replace correct prose. Add a persistence/stub trigger so "does scenario versioning persist?" reaches this skill.

### desc-testauto-utilities-module — testauto-utilities-module
- **Kind**: desc
- **Target**: testauto-utilities-module
- **Score**: 5 (advisory)
- **Description**: Two documented, production-live behaviors have no trigger coverage: (a) ConnEx credential masking before logging via `ConnExArtifactMasker.MaskCredentials` (called in production at `ConnExExecutor.cs:380`), and (b) step-output truncation before metrics/logging. Both have their own body sections.
- **Sources**: `TestAuto.Utilities/Helpers/ConnExArtifactMasker.cs:20`, `TestAuto.Utilities/Executors/ConnExExecutor.cs:380`; skill body H2s `ConnEx credential masking before logging (ConnExArtifactMasker)`, `Output truncation before metrics/logging`
- **Added**: 2026-08-10
- **Notes**: Missing triggers. Verified-correct in the same pass and NOT to be changed: the "eight IStepExecutor implementations" count is exactly right (8 in TestAuto.Utilities), and the `ScriptKey/ScriptLocator retired` claim holds.

### ext-testauto-log-tags-logconstants-dead — testauto-log-tags
- **Kind**: ext
- **Target**: testauto-log-tags
- **Score**: 5
- **Description**: Correctness/adoption — `LogConstants` has exactly ONE occurrence repo-wide: its own class declaration. Its 11 prefix constants have zero production call sites. The skill names it FIRST in the description ("log statements with LogConstants or LogTagConstants") and uses it in the primary right/wrong examples (`:29`, `:32`, `:52`, `:57`) and the detection rule (`:48`, `:67`), presenting it as co-equal with `LogTagConstants`, which is the one that is actually used. A reader follows the examples and adopts the dead constant.
- **Sources**: `TestAuto.Shared/Constants/LogConstants.cs` (declaration is the sole repo-wide hit), skill `testauto-log-tags/SKILL.md:5,16,18,29,32,48,52,57,67`
- **Added**: 2026-08-10
- **Notes**: correctness fix (adoption, not existence — the class is real and compiles). Pairs with the already-implemented `ext-crewchief-logging-startup-dead` finding; same defect class. Keep the examples but mark which constant family is live.

### ext-orphaned-integration-test-bases — testauto-testing-patterns, profisee-rest-api
- **Kind**: ext
- **Target**: testauto-testing-patterns + profisee-rest-api
- **Score**: 4
- **Description**: `ControllerTestBase` and `BaseRestClientTest` each have exactly ONE occurrence repo-wide (their own declarations) — zero inheritors. `profisee-rest-api`'s description says "integration tests inheriting BaseRestClientTest or BaseTest" and its body `:17` says an `IRestClient` is resolved "via `BaseRestClientTest`"; `testauto-testing-patterns` `:46-47,:147` presents both as Integration bases to choose between. Both imply existing tests to copy from; there are none.
- **Sources**: `Testing.SpeedMerchants.Integration/Web/Helpers/ControllerTestBase.cs` and `Tests/RESTGateway/Client/BaseRestClientTest.cs` (each the sole repo-wide hit; `rg ': ControllerTestBase'` and `rg ': BaseRestClientTest'` both return nothing); skills `testauto-testing-patterns/SKILL.md:35,46,47,147`, `profisee-rest-api/SKILL.md:6,17,129`
- **Added**: 2026-08-10
- **Notes**: correctness fix (adoption). Annotate as "available but currently no inheritors" — do NOT delete the sections; the bases exist and are legitimate choices for a new test.

### desc-configuration-compression-codec — configuration-compression-codec
- **Kind**: desc
- **Target**: configuration-compression-codec
- **Score**: 3 (advisory)
- **Description**: The trigger "repairing stacked layers via `CountCompressionLayers`" implies a live repair path. `CountCompressionLayers` is declaration-only (`TemplateStorage.cs`) with no callers anywhere — it is a diagnostic helper, not part of any wired repair flow.
- **Sources**: `TestAuto.Shared/Services/TemplateStorage.cs` (declaration is the sole repo-wide hit)
- **Added**: 2026-08-10
- **Notes**: Low value; safe to defer. Reword to "counting/diagnosing stacked layers", or state plainly that the helper has no production callers.

### desc-missing-use-when-clause — handoff, teach
- **Kind**: desc
- **Target**: handoff + teach
- **Score**: 3 (advisory)
- **Description**: Format non-compliance with measurable triggering cost. Of all 150 descriptions, exactly two lack any `Use when` clause: `handoff` ("Compact the current conversation into a handoff document for another agent to pick up.", 86 chars) and `teach` ("Teach the user a new skill or concept, within this workspace.", 61 chars) — also the two shortest in the corpus. With no trigger phrases, invocation depends entirely on the user naming the skill.
- **Sources**: frontmatter of `skills/handoff/SKILL.md`, `skills/teach/SKILL.md`; corpus-wide format scan (148/150 compliant)
- **Added**: 2026-08-10
- **Notes**: Both are process skills with no speed-merchants coupling, so there is nothing to verify against code — this is purely `<noun phrase>. Use when <triggers>.` conformance. Note `teach` and `handoff` overlap with plugin-provided commands (`handoff:save` / `handoff:pickup`); confirm the vault copy is the one being loaded before editing.

---

## Deferred

_None._

---

## Excluded

### ext-dotnet-testing-inconclusive-required-prereqs — dotnet-testing
- **Kind**: ext
- **Target**: dotnet-testing (references/TestingSetupGuide_v1.md:745-747)
- **Score**: 10
- **Description**: Repo-wide Assert.Inconclusive-on-missing-live-prereq convention (69 sites/31 files) contradicting the skill's throw-on-required rule.
- **Sources**: `Testing.SpeedMerchants.Integration` (31 files)
- **Added**: 2026-07-10
- **Notes**: EXCLUDED 2026-07-11 — convention should NOT be enshrined: Inconclusive-on-missing-prereq conflicts with the atomic-tests rule (tests must self-provision, not skip); documenting it would legitimize skips slated for elimination. The skill's existing throw-on-required guidance stands as the aspirational standard.


---

## Implemented

### 2026-08-10 (PM) — Mode 4 deep description review, FULL corpus (150 skills). All 9 candidates approved ("All 9") and applied same session, in the main loop, no apply agents.

Per-item outcomes:

| Item | Target | Outcome |
|---|---|---|
| `desc-dotnet-testing` | dotnet-testing | APPLIED — description now names both standards and adds triggers for tier selection, the per-tier required files (`unittest.runsettings` / `automation.runsettings`, BaseTestConfiguration, TestCategories, SettingsRetriever, `{Service}AppFactory`, `Fakes/`), the one-test-project-per-repository rule, mocks-vs-fakes-vs-spies, and PollingAssert. Body untouched. |
| `desc-crewchief-step-executors` | crewchief-step-executors | APPLIED — CheckPort, Teams, WebSite added to the executor list; triggers added for a port-reachability probe, a Teams webhook, IIS site/application deletion + orphaned pools, and the built-in protections with no override flag. |
| `desc-testauto-multistep-steps` | testauto-multistep-steps | APPLIED — `sqlSource/sqlDestination secret names` → `the sqlSourceConnectionSecretName / sqlDestinationConnectionSecretName pair`. **Body verified already correct before editing** (`:146-147`, `:159` cite `SqlStep.cs:17`/`:26`) and left alone. |
| `desc-testauto-scenario-version-history` | testauto-scenario-version-history | APPLIED — description now leads with "backed today by an in-memory stub, not a database", adds a restart-survival / where-to-add-persistence trigger, and states the real wire shape (configuration FromBody + versionNotes FromQuery; CreateVersionRequest is a grouping DTO the controller does not bind). Body `:101`/`:148` deliberately NOT touched — both were already accurate. |
| `desc-testauto-utilities-module` | testauto-utilities-module | APPLIED — triggers added for ConnEx credential redaction before logging (ConnExArtifactMasker) and step-output truncation before metrics/logging. The "eight IStepExecutor implementations" count was re-verified as exactly right and left unchanged. |
| `ext-testauto-log-tags-logconstants-dead` | testauto-log-tags | APPLIED, **and the finding grew during verification.** The original claim was only "LogConstants is dead". Apply-time checks found the real defect: `LogTagConstants` values are **bare** (`"METADATA_CRUD"`) because the `*WithTag` helpers add the brackets via `PrependTag`, while `LogConstants` values are **pre-bracketed** (`"[METADATA_CRUD]"`). Production has ~2,909 `WithTag(` call sites and **zero** raw `LogTagConstants.X + "…"` concatenations — so TWO of the skill's "All of these are correct" examples were wrong: concatenating a bare tag keeps the structured properties but emits the tag UNBRACKETED, silently defeating the `WHERE Message LIKE '%[TAG]%'` search the convention exists for. Rewrote the example block (correct/wrong split now has two distinct wrong-for-different-reasons cases), added a `## Two constant families — brackets and adoption` table, fixed the misleading When-to-Use bullet, and rewrote the description. Helper signatures were read from `LoggerTagExtensions.cs` before writing (tag first, exception AFTER the tag) rather than guessed. |
| `ext-orphaned-integration-test-bases` | testauto-testing-patterns + profisee-rest-api | APPLIED to both. testauto-testing-patterns: the two table rows now carry "Zero inheritors today" plus a blockquote explaining that neither base has a derivative to copy from and to copy a `BaseTest`/`IntegrationTestBase` derivative instead. profisee-rest-api: description reworded, and the intro paragraph's "Tests resolve `IRestClient` … via `BaseRestClientTest`" claim corrected. Sections kept — the bases are real and legitimate for a new test. |
| `desc-configuration-compression-codec` | configuration-compression-codec | APPLIED — "repairing stacked layers via CountCompressionLayers" → diagnosing a value compressed more than once, with the helper explicitly marked as having no production callers. |
| `desc-missing-use-when-clause` | handoff + teach | APPLIED to both; both now follow `<noun phrase>. Use when <triggers>.` as folded scalars. **Caveat recorded during apply:** `teach` carries `disable-model-invocation: true`, so the model cannot self-invoke it — for that skill the rewrite is house-style conformance and README rendering only, NOT a triggering improvement. That is now stated in its own description. `handoff` has no such flag, so its new triggers do take effect. |

Phase 5 (linker): **no change needed** — zero new skills, so `link-to-ai.ps1` was not edited and no junction was created.
Phase 5b: `Generate-SkillsReadme.ps1` regenerated (`150 skills, 7 agents`), and `-Check` exits **0**.

### 2026-08-10 — Mode 1 full-diff audit (127 commits / 516 files). 7 new skills + ~30 corrections, all applied same session.

Applied in the main session (no apply agents), each claim re-derived by name-based grep/read at HEAD `15401a46` before the edit.

**New skills (7)** — all added to `link-to-ai.ps1`, junctions LINKED, README regenerated, `-Check` exits 0. Corpus 143 → **150**.

- `crewchief-capability-preflight` — 7 `StepCapability` values ↔ 7 probers (1:1, per the enum's own doc); 4-state verdict where **only `Failed` blocks** (`Unknown`/`NotProbed` never do — absence of evidence is not evidence of absence); `PreflightGate` as the ONE hard-block with **no bypass flag anywhere**; `StepBodiesForRestart`/`ForResume` so a skipped step cannot block; badges never probe on the render path (probes move real lockout counters); registration lives in Engine because the CLI cannot reference Web.
- `crewchief-raw-json-editing` — `JsonPane` draft-only commit; the **unknown-key DELTA rule** (baseline-at-open tolerated, newly-introduced rejected) and why it exists (`[JsonExtensionData]` lets `sqlScipt` save clean and run as a success-reporting no-op); the empirically-verified Newtonsoft 13.0.4 fact that `MissingMemberHandling.Error` throws **even when the target declares `[JsonExtensionData]`**; Monaco readiness as a re-running probe.
- `crewchief-connect-import` — 5-step wizard, `IConnectImportEmitter`, `ConnExStepSetBuilder` identity-by-`Selections` (so a renamed token still yields correct `resourceId` refs), `ConversionProfile` replay, and the dry run forcing `ContinueOnError` **as well as** `DryRun`.
- `crewchief-help-docs` — front-matter contract where a **missing `url` silently drops the doc**; `NN_` prefix is cosmetic (order comes only from `order`); bare-filename `LogicalName` ⇒ no two docs may share a filename.
- `testauto-https-hosting` — thumbprint is an **override, not a prerequisite**; hard filters incl. Server-Auth EKU and no-`IncludeArchived`; `localhost` deliberately excluded from preferred hosts; **no dev-cert fallback, HTTP survives**; canonical-host redirect targets the name in the CERTIFICATE, never `WebUI:HostName`.
- `testauto-windows-service-hosting` — the 5 ordered startup musts (CWD, resolver-before-manager, `startup-crash.log` breadcrumb, content root, DataProtection ring); the **one-decider/one-marker** convention; restart-via-detached-PowerShell and the update-feed contract.
- `testauto-production-sync` — 6 phases, DBA graph (A→B = A depends on B; cycles broken alphabetically, never thrown), target-only attribute is **Blocking**, domain compare by resolved NAME, singleton non-persistent state with 200-error cap, `NormalizeBaseUrl` as the single must-differ rule, 207 ≠ success.

**Corrections applied (highest-impact first)**

- `crewchief-orchestration` / `crewchief-file-persistence` / `crewchief-workload-transfer` / `crewchief-workload-and-runs` — **`Ref`/`Overrides` retirement**. Materialize-on-add model, `LegacyWorkloadRefGuard` load refusal, `Validate(wf)` one-arg, TWO serializers → ONE, `WorkloadBundle.ReferencedSteps` removed, `WorkloadBundlePreview` 6→4 members, `WorkloadImportResult` 5→3, `BuildPlannedSteps` no longer does file I/O. **2 description-frontmatter fixes.**
- `crewchief-step-type-model` / `crewchief-step-executors` / `crewchief-web-ui` / `crewchief-remote-box-prep` — 3 new step types (`TeamsStep`/`CheckPortStep`/`WebSiteStep`); `AllTypes` 19→**22**; box-prep family six→**seven** (incl. description frontmatter); `RemoteAuth.Auto` + `RemoteAuthSelector` (opt-in by value, blank still = Kerberos-only); ConnEx `WaitForBatch` 7th op with its `maxWaitMinutes` 720 carve-out; `IisBuiltInAppPools` two-path refusal.
- `crewchief-reference-data` / `crewchief-default-templates` — `DefaultReferenceData/` **deleted** → `SampleContent/reference-data/` (5 dead path cites), `drive-map` no longer shipped, `ShippedContentKinds` as single routing authority (the `null` for `.refkv.json` is the explicit no-double-install mechanism), presence-triggered vs value-gated switches + the `/addToCluster:"FALSE"` trap, shipped-sample catalog wholesale replaced.
- `crewchief-cli` — exit contract 0/1/2/3 → **0/1/2/3/4**; `PreflightFailed = 4` is NOT an alias; `service` verb + `--local-system` rejected elsewhere.
- `crewchief-testing` / `crewchief-adding-a-step-type` — machine-local `{ScratchRoot}\ConnectExports` fixtures that `Assert.Fail` (Unit suite is NOT machine-independent); `[DoNotParallelize]` roster 14+2 with three triggers; composition-root guard family; `Counting*`/`Scripted*` taxonomy; `WebApplicationFactory` eager-config trap; lockout-safe GUID-suffixed test accounts; **two → three census oracles**.
- `crewchief-architecture` / `crewchief-secrets` / `crewchief-logging` — service-mode CWD blast radius (8 executors), DataProtection ring, `AddCrewChief*` composition-root rule; three-state `SecretsAccessProbe` ("I could not look" ≠ "it is not there"); circuit-scoped `ISecretRevealSession` (GRANT ≠ TOGGLE); central `SecretMaskingEnricher` + its two unreachable surfaces; LogTags 11→12.
- `testauto-multistep-steps` (+3 reference files) — the **30 s `MaxTimeSeconds` hardcode is GONE**; now `MaxTimeSeconds ?? TimeoutSeconds` with `HttpStepTimeoutCalculator` outer bound `max(...)+5`. Description frontmatter fixed (it named the now-impossible symptom as a trigger).
- `testauto-matching-metrics-collector` — durations are deliberately **raw and unclamped**; negatives are diagnostic (pre-existing cluster / clock skew); `ValidateDurations()` now returns and flags negatives. "Do not add a clamp."
- `testauto-connex-service` — `GetRunProfileAsync` **removed** (REST via never-fatal `ConnectRunProfileReader`); `GetJobTimingsAsync` took the slot; repository scoped to the instance under test only.
- `testauto-record-transformation` — the "dead path" warning is obsolete, but **not** by the mechanism it predicted: no context *parameter*, a settable `Context` **property** — so an unassigned `Context` is now the cause of a silent `SlightTypo`-only run. Seed source/child-seed design; `MaxAttributeChanges` no longer VariantGenerator-only; Faker path seed permanently unsupported.
- `testauto-hangfire-architecture` — `HangfireAvailability` as single source of truth (never re-derive from the connection string — it crashed the pipeline at build time); degraded registration; interface-based enqueue + the **dead token** rule.
- `inno-setup-installer` — package version is `Major.Minor`, not 4-part; `Plugins\` is stripped **and re-staged** (NOT operator state); both installers now stop the service before `taskkill`; `sc failureflag` is the load-bearing part of recovery.
- `secrets-bootstrap-middleware` — gate is **three** conditions (`RuntimeSecretsStatus.SecretsLoaded`); bypass widened to the whole `/secrets` area.
- `testauto-deployed-machine-diagnostics` / `testauto-ui-patterns` / `api-response-standardization` / `blazor-icons` — four **reverse-staleness** fixes: no dev-cert fallback; `SmartJsonEditor` loader is a real readiness probe; 403 passes its body; `MetricsCard` default is `bar_chart`. Plus `PagingControl` + `LoadData` sorting.
- `testauto-bounded-parallel-fanout` / `testauto-testing-patterns` / `testauto-scenario-display` — `IRestClient` not safe for concurrent use (shared mutable `PathAndQueryBuilder`); Radzen rendered-DOM selectors + throw-on-unused fakes with an ordered `Ledger`; card **actions** use `EventCallback.Factory.Create`, not a `Func` selector.

### 2026-08-10 (second pass — the 18 findings the first pass ranked below its cut)

User directive: "Finish all work that was not done before." The first pass applied ~37 of ~96 consolidated
findings; this pass worked the remainder to zero. **Self-correction: the first-pass report claimed
`testauto-ui-patterns` got "PagingControl + LoadData sorting" — only the `SmartJsonEditor` edit had actually
landed. Applied here.** Every claim re-verified first-hand before edit, as before.

- `crewchief-remote-box-prep` — **`BoxPrepRouting.Decide` five-route table**. Note the fifth member is
  `RunAsUnresolved`, **not** "reject" as the scanning agent phrased it (own grep corrected the name).
  Documented why `LocalRunAs` replaced a WinRM loopback (Windows blocks credentialed auth to itself without
  `DisableLoopbackCheck`/`BackConnectionHostNames`/`LocalAccountTokenFilterPolicy`; a Failed `RemoteWinRm`
  verdict then *hard-blocked* the run, making local Run-As unreachable rather than slow), and why a
  half-filled local Run-As is REJECTED rather than downgraded (silent identity substitution = escalation or
  confusing access-denied). Plus `Enable-CrewChiefRemoteManagement.ps1` + the **WSMAN SPN CredSSP
  diagnostic** (both roles correct and delegation still refuses; WinRM misreports it as a policy problem;
  script deliberately offers no `-Fix` because the remedy is an AD write), and the `/setup-verification`
  **logon-attempt budget** (3 strikes, no time reset; two-step `ArmReset`→`ResetLogonBudget` against
  `_reportCredential`, never a re-resolution of the current form fields).
- `crewchief-workload-and-runs` — workload-level `WorkloadRunAs`: the hand-written **password-free
  `ToString`** (a `record struct`'s generated one would print the password), `IsConfigured` as an
  any-non-blank test so a half-filled pair is inherited *and then rejected loudly* rather than silently
  dropped, `WorkloadStepMaterializer.Materialize` applying **both** inheritance and the global-param merge,
  and the parm-driven shipped-workload pattern.
- `crewchief-step-executors` — CheckPort (non-local target FAILS; unreadable listener table SUCCEEDS as
  "NOT CHECKED" — a guard that cannot see must not manufacture a verdict; and why it is a step not an eighth
  capability, since preflight runs before the workload's Uninstall steps), Teams (Adaptive Card via Power
  Automate Workflows envelope, webhook error = step failure), WebSite (`Site Name/AppName` paths, `remove`
  synonym, orphan-pool cleanup routed through the same built-in refusal list).
- `connex-import-tokenization` — scope banner: TestAuto-only, CrewChief has an independent 12-file port, a
  fix in one does NOT land in the other.
- `crewchief-testing` — bUnit DI: `TryAdd*` throughout so a test's own double wins regardless of call order;
  `ISecretRevealSession` **Scoped** = one per `TestContext` = one production circuit; the test-local
  `TwoToggleHost : ComponentBase` shape for observing shared per-circuit state.
- `inno-setup-installer` — CrewChief service-account page rewritten: **no LocalSystem** (enum is
  `sicKeepCurrent|sicSpecific`; LocalSystem reaches the network as `COMPUTERNAME$`), page anchored after
  `wpSelectTasks` (anchoring before made `WizardIsTaskSelected` read unsettled state and skip itself),
  `CanKeepCurrentAccount` + `ServiceAcctPagePrimed`, `PrepareToInstall` hard-refusal, `RefreshServiceState`
  caching (per-click re-query launched 5 AV-scanned processes), and `GrantSecretsFolderAccess` re-admitting
  `(OI)(CI)M` after the `/inheritance:r` lockdown — without it the service reads access-denied and the app
  offers to re-bootstrap over a healthy store.
- `testauto-connex-service` — full `ConnectRunProfileReader` section (ScenarioMgt REST because the model
  lives where ScenarioMgt lives; never throws; 30 s abandon-on-timeout; `static` so `ValidateOnBuild` cannot
  grab it) + `GetJobTimingsAsync` (`connexjobs.State` ⋈ `JSON_VALUE(Properties,'$.BackgroundJobId')`,
  `PerformanceDuration` preferred because it **excludes queue wait**, best-effort fallback to the batch
  window) + `MetricDetailConnectApiExecution` rebased to `MetricDetailBase` (Extended's non-nullable
  CRUD-only columns returned **207 / error 8609 per column**) and the `Code` format change that fixed the
  8603 collision.
- `testauto-multistep-steps` (+ `references/connex-telemetry.md`) — `HttpResponseBody` (in memory,
  deliberately not persisted: 4000-char ceiling), **semantic-status reconciliation** (transport 400 whose
  body declares 404), warning on whitelisting any `>= 400`, 207-with-per-item-failures fails the step; and
  the ConnEx parser's array-rooted bodies, `errors`-as-object shape carrying CDP codes like 8602, RFC-7807
  fallback only when nothing more specific, `TryGetSemanticStatusCodes`.
- `testauto-scenario-metrics` — the response-code column is **not uniform** (`ResponseCode` vs
  `ConnectApiExecution`'s `HttpResponseCode`); probing one name made a clean 200 invisible and marked a
  successful collection as a failed batch. Plus the zero-rows ⇒ mark `Failed` fail-fast.
- `testauto-http-facades` — gateway pages metadata at ~50 and truncates silently; `GetEntitiesAsync` pages
  at 100 with a seen-set guard and **throws** on non-success (a 401 once masqueraded as "every entity
  missing"); `GetAttributesAsync` PageSize 1000; 404-is-absence vs throw-on-failure; `RawErrorBody` with the
  "on failure `ResponseContent` must be null" rule.
- `testauto-ui-patterns` — `PagingControl` + `AllowPaging="false"` (6 call sites) and the rule that sorting
  must be applied in `LoadData` over the FULL list before `Skip`/`Take`.
- `blazor-code-behind` — `_loadGeneration` token re-checked after **every** await and inside every
  `InvokeAsync`; poll timers must gate `StateHasChanged` on actual change.
- `testauto-log-tags` — `PushScenarioLogContext` mandatory in a wholesale `ProcessBatchAsync` override or
  events reach SEQ with no `WorkloadExecution`; `ConnectConstants.DiagPrefix` marks temporary diagnostics.
- `testauto-debugging-common-failures` — sixth **reverse-staleness** fix: the `Features:` vs `FeatureFlags:`
  log-line caveat is obsolete, the line now names the key correctly (`WebModuleRegistrar.cs:188`).

### 2026-07-27 (follow-up — 7 items surfaced by the same day's apply pass)

Single apply agent, one non-overlapping file set, every claim re-derived by name-based grep at HEAD `4c367fe6` before editing. **7 DID, 0 dropped, 0 no-change.**

- `ext-testauto-matching-source-data-s3b-decision-row` — **DID**. Decision-table S3B `Record Type` "Lookups only" → "Lookup, then create on miss", plus a callout: the 3B arm genuinely writes — `ExecuteLookupThenCreateAsync` skips the create on a match (`TestAuto.Matching/Services/MatchingOperationExecutor.cs:195`) and proceeds to create on a miss (`:203`); only S3A is read-only (`UnifiedMatchingScenarioEditor.razor.cs:212`). Consequence made explicit: a wizard 3B run consumes holdout and can add records, so plan offsets/cleanup.
- `ext-testauto-matching-scenarios-strategy-responsibilities-3a` — **DID, by DELETION** (the preferred fix). The duplicated "Strategy Responsibilities" table is gone; `testauto-matching-strategy-pattern` was confirmed to already carry every fact it held (per-scenario strategy table `:42-46`, file inventory `:262-268`, "PostLoopAsync is a no-op in every implementer" `:195-197`), so nothing unique was lost. Replaced with a cross-link that names the recurring defect — 3A labelled `PerRecordStrategy` when `WaitForMatching=false` (`UnifiedMatchingScenarioEditor.razor.cs:215`) routes it to `ContinuousStrategy` — and an explicit "do not re-add a second table". `testauto-matching-strategy-pattern` was NOT touched. *Adjacent in-scope fix:* the executor dispatch block directly below the deleted table still annotated `LookupThenCreate → (3C)` / `CreateOnly → (2)`; re-derived against `MatchingOperationExecutor.cs:68-83` and relabelled per the wizard/sample split, adding the missing `BatchLoad` arm and the silent `_ => ExecuteCreateOnlyAsync` default (`:82`).
- `ext-crewchief-web-ui-cardviewstate-extraction` — **DID**. Verified: pages do **not** hold their own fields any more — `_cardCols` / `CardColsClass` / `SetCardColsAsync` are thin delegates to a `CardViewState` instance (`Steps.razor.cs:47-51`, `Workloads.razor.cs:59-63`, `WorkloadEditor.razor.cs:300-304`), and `_cardCols` is now an expression-bodied **property**, not an assignable field. Section rewritten around `Components/Pages/CardViewState.cs`: clamp `:83`, `ColsClass` `:63`, static `ColumnOptions` `:66-71` (replacing three per-page copies), dotted storage keys `crewchief.<page>.{viewMode,cardCols}` `:45-46` with legacy dashed-key fallback `:180-187`, idempotent `RestoreAsync` `:93-96` replacing five per-page first-render guards, the `PageSize => Math.Max(1, …)` divide-by-zero guard `:131`, and `SetViewTransient`. Description + Sources updated.
- `hyg-crewchief-reference-data-cites` — **DID**, all four re-derived: `SwitchPrefillValue` → `StepEditorCard.razor.cs:1888` (+ `:1511` tint, `:1918` enable); `ReferenceTransferService` → `CrewChief.Web/Program.cs:302`. The two page cites in the backlog were themselves wrong — live is `Steps.razor.cs:629`/`:642` and `WorkloadEditor.razor.cs:544`/`:556`, both a `ConfigureDefaults()` → `ConfigurationSwitchCatalog.BuildDefaultSwitches` pair (`ConfigurationSwitchCatalog.cs:131`). Per the concurrent-edit warning, `WorkloadEditor.razor.cs` is cited **symbol-anchored** with the line numbers marked as volatile.
- `hyg-testauto-batch-orchestration-getrecordsbycodes` — **DID**. `GetRecordsByCodes` → `GetRecordsByCodeScenario`, with the filename-vs-type trap spelled out (`TestAuto.Records/Scenarios/CRUD/Get/GetRecordsByCodes.cs:31`). Note the sibling `GetRecordByCodeScenario` (no `s`) is a *different, real* class in its own file — the two are one character apart, so the disambiguation was worth more than the one-word fix.
- `ext-testauto-scenario-display-three-page-framing` — **DID**. The card claim was already correct; the *adapter* framing was the stale half. "Three Pages, Three Adapter Patterns" replaced with a two-consumer model (card derives its own values `ScenarioCard.razor.cs:131-141` and needs no adapters; only a page's own grid/badge markup does), plus a per-page "still reaches markup?" column. Verified and documented: `WorkflowScenariosEditor`'s adapters are now **vestigial** — its `.razor` references none of the eleven, because the list is delegated to `ScenarioListEditor` (`WorkflowScenariosEditor.razor:317`); the single survivor is `GetMetricsSummaryTooltip` via the `GridMetricsTemplate` fragment (`:342` → `ScenarioListEditor.razor:213-220`). `description:` rewritten to the two-consumer framing (format preserved).
- `hyg-testauto-scenario-display-tooltip-helper` — **DID**. `GetMetricsSummaryTooltip` added to the tooltip section with its real signature — `public static string` (`ScenarioDisplayHelpers.cs:121`), the **only** non-nullable return in the class — four always-present lines with `—` fallbacks (`:125-128`), three conditional lines (`:132,:135,:138`), `\n`-joined (`:140`), and the workflow-context enrichment wrapper at `WorkflowScenariosEditor.razor.cs:1543`.

**Cross-cutting:** the two-skills-one-table duplication that caused the 3B/3C flip-flop across three audits is now structurally removed, not just corrected — `testauto-matching-scenarios` defers to `testauto-matching-strategy-pattern` for all strategy routing.

### 2026-07-27 (Mode 2 — drained the whole backlog: ALL 71 approved items applied same session by 12 parallel apply agents on non-overlapping skill files, each re-verifying against live code at HEAD 4c367fe6 before every edit)

**Outcome by batch** (item bodies retained under `## Implemented 2026-07-27 — item detail`):

| Batch | Skills | Items | Outcome |
|---|---|---|---|
| Matching family | matching-scenarios, matching-strategy-pattern, matching-source-data, matching-metrics-collector, matching-api-status-poller | 5 | 5 DID · 1 sub-claim dropped · 1 NO-CHANGE (already correct) |
| CrewChief core | workload-and-runs (+desc), step-executors, architecture, adding-a-step-type, orchestration | 6 | 6 DID · 3 claims dropped/amended |
| CrewChief templates/web | default-templates, inno-setup-installer, web-ui, reference-data | 4 | 3 DID · 1 PARTIAL · 1 claim dropped as false |
| CrewChief infra | logging, file-persistence, secrets, remote-box-prep, testing, workload-transfer | 6 | 6 DID · 0 dropped |
| TestAuto orchestration | workflow-execution, hangfire-architecture, batch-orchestration, resource-collection, bounded-parallel-fanout, prometheus-config | 6 | 6 DID · 3 amended |
| ConnEx / utilities | connex-service, connex-provider-templates, custom-parm-editor, bulk-custom-parms, utilities-module, utility-step-deser, multistep-steps | 7 | 7 DID · 1 orchestrator claim INVERTED |
| Config / validation / DI | config-validation, scenario-config-store, compression-codec, execution-context, modular-di, project-structure, service-registration | 7 | 6 DID · 1 PARTIAL (**backlog finding false**) |
| Scenario catalog | scenario-catalog, stewardship-pattern, scenario-display, scenario-metrics, scenario-types-attribute, metric-detail-builder (desc) | 6 | 6 DID · 0 dropped · 15/15 sub-claims held |
| Data-gen / enrichment | record-transformation, enrichment-generators, testdata-enrichment-pipeline, test-data-generation, lookup-cache, profisee-rest-api, odata-query-building | 7 | 7 DID · 6 amended |
| UI / Blazor | ui-patterns, log-tags, blazor-code-behind, blazor-icons, http-facades, api-response-standardization | 6 | 6 DID · 4 claims were UNDERSTATED · (1st run died on API 529; retried clean) |
| Env / setup / security | speedmerchants-db-migration, secrets-management, local-setup, project, tech-stack, dotnet-testing, logging-schema, debugging-common-failures, testing-patterns | 9 | 8 DID · 1 DROPPED (**backlog finding false**) |
| DQ rules | profisee-dq-rules (ext + desc) | 2 | 2 DID · authority was the LIVE MCP grammar endpoint, not the repo |

**⚠️ SECURITY — resolved.** `speedmerchants-db-migration` embedded a **plaintext production password in TWO places** (a `**Credentials**` line and a `$Password` default in a PowerShell `param()` block), not the one the backlog reported. Both removed; a tree-wide scan of `work-ai` for the literal, for `ProfiseeAdmin`, and for the backup-server password returns **zero hits**. Template now takes `[Parameter(Mandatory)] [pscredential]$SqlCredential`, with a danger callout pointing at the real secret sources. The backlog's companion claim — that MCP aliases gained a `user-` prefix — was **false**; the skill's existing names were already correct.

**The 2 false backlog findings (dropped, skill was already right):**
- `ext-dotnet-service-registration-hangfire` — claimed the skill gated Hangfire on `hasMinimumConfig`. It already said `hasHangfireConfig` (`ConnectionStrings:HangfireDB`), matching live code. Not reverted — a "two independent guards, don't conflate them" section was added so the same false report isn't re-filed.
- `ext-dotnet-logging-schema-console` — claimed "no console sink" was wrong. It is **correct**: `Profisee.Platform.Utilities.Logging` 1.0.1.173 references only Async/File/MSSqlServer/Seq, with zero "Console" strings in the DLL. Skill kept and strengthened with the evidence, naming the three repo docs that assert otherwise.

**1 false claim introduced by the ORCHESTRATOR (not the backlog):** I told the ConnEx agent that `ConnectRestClient` builds paths via the shared `PathAndQueryBuilder`, extrapolating from the house rule. Live code says the opposite in a header comment — *"No shared mutable PathAndQueryBuilder — paths are built per-call"*, `BuildPath` is private. Documented as a deliberate exception. **Lesson: the re-verification gate must apply to the instruction-giver too.**

**Guard handling (the ⚠️ lists worked as intended):** of the cites marked "ALREADY EXACT — do not touch", `IProcessRunner.cs:97,105`, the `WorkloadEngine` class remarks, `StepTypeRegistry.cs:54-72`, `EmailExecutor.cs:121` and `IisResetExecutor.cs:71` were verified still exact and left alone; `LiveStepOutput.Clear()` (177→168) and the two-serializers block (36-48→36-45) had drifted and were corrected on evidence. No blanket renumbering occurred. The matching-family guards held: the 3B/3C divergence is now DOCUMENTED as two live sources that disagree (wizard authoritative, samples lagging) with an explicit "do not flip this" warning, instead of being resolved in one direction for the third consecutive audit.

**Highest-value corrections:**
- `profisee-dq-rules` was **fabricated**, not stale — 7 invented syntax categories (`IsNotNull()`, `eq/gt/lt` named comparators, `Upper()/Lower()`, single-quoted strings, `[Entity.Attr]` dot-inside-brackets, `assignment_expression` fields, "display_text required"). Rewritten against the live ANTLR `grammar DQL` + 20 real rules; large missing surface added (`IN`, `IF`, `&`, full string/date/change-tracking sets, `assignment_execution_mode`).
- `testauto-test-data-generation` documented a **paged distribution model that does not exist**, with pseudocode. Live `TestDataFactory` never calls `GetRecords` for `DataPattern.Paged` — it hand-builds blank `PageNumber`/`BatchSize` envelopes.
- `testauto-matching-strategy-pattern` — wizard-built **3A resolves to `ContinuousStrategy`, not `PerRecordStrategy`** (`WaitForMatching=false`).
- `testauto-scenario-types-attribute` — the `MatchingStrategyPollingScenario` example was wrong on **4 of 6** attribute args, inverting `RequiresMetrics()`.
- `crewchief-adding-a-step-type` — `AddExecutorAlias` is GONE from CrewChief (aliases now derived from the registry); the maintenance checklist dropped from 6 sites to **4 hand-maintained + a derived do-not-edit list**. Same method still exists in `TestAuto.Utilities` — cross-references added so the two orchestrators aren't conflated.
- `api-response-standardization` — adoption is **1 of 22 controllers**, and all three response helpers have **zero call sites repo-wide**.
- `testauto-config-validation` — documented `Validation:ShadowMode` (code default **true**, shipped false), which makes `ValidateConfigurationAsync` always return valid.

**Repo-side findings surfaced to the user (scan target is read-only — NOT auto-fixed):** `SmartJsonEditor.TryLoadEnhancedEditorAsync` unconditionally returns false, so Monaco is dead despite its feature flag being on; 5 unmapped Bootstrap icon names still shipping (`bell`, `eye`, `house`, `x`, `database`) render as literal text; `403 => Forbid()` discards the built error body incl. `RequestId`; `WorkflowManagementController.cs` is a 1-byte empty file; `MaxTimeSeconds ?? 30` means an HTTP step with `TimeoutSeconds: 600` still dies at 30s; `MutationTransformer` Tier-1 is structurally unreachable so configured `MutationStrategy` is discarded; `MetricDetailMatching.ValidateDurations()` builds an errors list it never throws or returns; `appsettings.CommandLine.json` declares `Features:` while code reads `FeatureFlags:` (dead override); ServiceProvider ConnEx templates lack a record root key so `DetectResourceType` returns null; stale DeveloperPack docs + a `Program.cs` comment describing a first-run checkbox that no longer exists.

**Phase 5b:** `Generate-SkillsReadme.ps1` regenerated (141 skills, 7 agents); `-Check` exits **0**. No new skills created → no linker change, no junction refresh needed.

### 2026-07-25 (Mode 1 diff scan fb56e571..ccb159ad — user bulk-approved ALL 18 pending, applied same session via 10 parallel apply agents, each verifying against live code before edit; ZERO false positives)
- **Outcome per item (10 agents, 18 items):**
  - `ext-crewchief-web-ui-service-picker-templates-reorder` (mine) — **DID**: ServiceNameEditor 4-mode Pick/Secret/Reference/Text, Templates page + FirstRunBanner, global/step param reorder (RebuildOrderedParameters), DB-ops relocate/wait switches.
  - `new-crewchief-default-templates` (mine) — **CREATED** + linked. On-demand install subsystem (TemplateInstaller/FirstRunGate/Templates/SampleTemplateStatus).
  - `ext-crewchief-reference-data-ondemand-seeding` (mine) — **CORRECTED**: seeders no longer wired at startup; on-demand via ITemplateInstaller.InstallAll; only BackupLocation seed-once remains automatic.
  - `ext-crewchief-step-executors-dbops-rename-relocate` (mine) — **DID**: relocateFiles (FILELISTONLY→WITH MOVE→ALTER MODIFY FILE) + waitIndefinitely + new seam methods + 5-op enumeration.
  - `ext-crewchief-token-replacement-param-in-param` (mine) — **CORRECTED**: param-in-param recursion + cycle detection + $ref-valued params + fail-fast; two-phase resolve-then-write.
  - `ext-crewchief-workload-and-runs-stepstart-prompted` (mine) — **DID**: StartStepAsync promptedParameters added to entry-points.
  - `new-crewchief-backup-restore` — **EXISTS** (skill authored 2026-07-22, was never linked → NOW LINKED). Agent verified BackupService records/methods still match; no overwrite.
  - `new-inno-setup-installer` — **CREATED** + linked. Covers CrewChief + TestAuto sibling-pair installers; all 6 Sources verified on disk.
  - `ext-crewchief-secrets-root-resolver-and-scope` — **CORRECTED (partial NO-OP)**: added IsMachineShared flag note + DataProtectionScope LocalMachine correction + HTTPS-cert dual-source section (resolver precedence already present).
  - `ext-crewchief-step-executors-connex-fix-and-dbops` — **NO-OP**: ConnEx client-name fix + DB-ops authMode/impersonation section already in live skill (applied-but-not-moved from 2026-07-22).
  - `ext-crewchief-web-ui-multifacet-filter-and-grid` — **DID + CORRECTED**: added multi-facet filter + grid.Reload gotcha sections; corrected the backlog claim (Steps has 4 facets incl. Type, Workloads only 3 — no Type facet).
  - `ext-crewchief-cli-backup-verbs-and-secrets` — **CORRECTED**: added backup/restore verbs, removed secrets.local.json config-source claim, SecretsRootResolver.
  - `ext-crewchief-reference-data-smart-seed` — **NO-OP**: smart-seed doctrine already documented (verified SeedGate/SeedManifest/SeedHash/SampleMeta present).
  - `ext-crewchief-architecture-windows-service` — **DID**: new Windows-Service hosting section (UseWindowsService / content-root pinning / machine-shared secrets) + package row.
  - `ext-crewchief-adding-a-step-type-iisreset-alias-fixed` — **NO-OP**: worked example already corrected by a prior pass (iisreset alias FIXED at UtilityOrchestrator.cs:87, email kept as throwing example).
  - `ext-crewchief-file-persistence-recycle-bin` — **DID**: added StepFileStore useRecycleBin soft-delete section + trigger.
  - `ext-crewchief-orchestration-description-stamping` — **DID**: added StepExecutionResult.Description central-stamping chokepoint note.
  - `ext-crewchief-workload-and-runs-secrets-local-removed` — **CORRECTED**: NotificationSettings no longer binds secrets.local.json; creds from /secrets store over appsettings.
- **Linker**: 3 new junctions created (crewchief-default-templates, crewchief-backup-restore [pre-existing skill, first link], inno-setup-installer). RESTART required to pick them up.
- **Follow-up hyg (user-approved same session, "reword as needed") — RESOLVED:** removed the misleading "never edit it" / "do NOT edit — CrewChief is read-only" directive from SIX occurrences across 6 skills (crewchief-token-replacement, -orchestration, -executor-pattern, -adding-a-step-type [x2], -step-type-model). CrewChief is actively developed — the phrasing was an audit scan-target rule wrongly baked into skill overviews. LEFT the defensible provenance phrasing "READ-ONLY copy derived from MultiStepUtility" in crewchief-step-executors (one-way copy, not no-edit).


### 2026-07-23 (Mode 6 full-corpus review against code — 30 findings across 19 skills, ALL applied same session; 5 parallel apply agents on non-overlapping file sets, every claim re-verified against live code before edit, ZERO false positives)

Corpus: 101 speed-merchants-coupled skills reviewed by 13 read-only Explore agents (one Workflow fan-out); 82 clean, 19 corrected. Kinds: 18 WRONG · 8 DRIFTED · 4 STALE (+1 desc follow-up).

**CrewChief (6)** — mostly self-inflicted drift from this week's CrewChief work: `crewchief-cli` (console sink is Fatal, not Warning, when not --verbose) · `crewchief-secrets` (rewrote on-disk-layout → SecretsRootResolver 4-level precedence; bootstrap cite 308→384) · `crewchief-adding-a-step-type` (iisreset alias now FIXED → worked example narrowed to email; IisResetExecutor.cs:41→71) · `crewchief-remote-box-prep` (DI cites 66-67→70 resolver/74 runner) · `crewchief-web-ui` (StepEditorCard ~1790→2025 lines + real wizard ranges).

**TestAuto (24)**: `testauto-matching-scenarios` ×4 (real Template_Scenario1..3C constants; GetStepsForTemplate step sequences; 3B/3C OperationType un-reversed; RecordPoolSource→Scenario3ARecordSource) · `testauto-workflow-execution` ×2 (MetricsPersistenceJob per-child/default-queue; DisplayName "{0} Server {1} Batch {2} of {3} Persist Metrics") · `testauto-metadata-scenario` ×2 (UseBaseNamesOnly opt-in suffix; hardcoded "12345" seed) · `testauto-test-data-generation` ×2 (Activator-based selection, no lookup/DI, requires (IConfiguration,IServiceProvider) ctor; Single honors N — no Take(1)) · `testauto-http-facades` ×2 STALE (removed callRestApi* Legacy Sync section + sync GetGatewayResponse row) · `testauto-scenario-types-attribute` STALE (retired ExecuteStrategyScenario example → live ScenarioBaseConnect/SelfManaged) · `testauto-project` STALE (removed deleted Pages/ dir line) · `testauto-scenario-catalog` ("four" now lists the 4th: UnifiedMatchingPostRunCollectionScenario) · `testauto-multistep-steps` (added RetryEnabled/MaxRetries/RetryDelaySeconds rows + retry-before-ContinueOnError) · `testauto-enrichment-generators` (reflection-scan auto-reg not Scrutor; 3→2 steps; +frontmatter desc) · `testauto-snapshot-capture` (persist failure THROWS, not warn+Failed) · `testauto-cli-command-pattern` (host = TestAuto/Program.cs → TestAuto.exe, 3 verbs incl test-services) · `testauto-record-repository` (CS1929→CS1061) · `testauto-resource-collection` (2 ctor deps incl ILogger) · `testauto-ui-patterns` (ScenarioEditorContent Components/Common→Components/Pages) · `blazor-code-behind` (dual-timer → single _refreshTimer + client-side JS testAutoCountdown) · `matching-api-status-poller` (timeout logged at Warning, not Information).

Apply-time notes: Group A used real live line numbers for crewchief-web-ui wizard ranges rather than the proposed approximates. Group B pulled Scenario2/3A wizard sequences from source (not supplied in the brief) and preserved the real `Template_Scenario3B="Scenario 3B: Lookup + Create"` constant string while correcting all operation-type prose. Batch 13 (utilities/profisee/misc, 13 skills) found nothing. No new skills → no linker change.

### 2026-07-22 PM (Mode 1 diff scan 4825a83a..3039aca0 — all 7 ext applied same session per user "Approve all 7"; 7 parallel apply agents, every claim re-verified against live code before edit, ZERO failed verifications)

Items: ext-crewchief-workload-and-runs-live-visibility (10) · ext-crewchief-step-executors-setapikey-connection-model (9, correctness) · ext-crewchief-web-ui-cards-editors-browse (9, correctness) · ext-crewchief-reference-data-drivemap-and-switch-profile (8, correctness) · ext-crewchief-remote-box-prep-browse-drivemap (7) · ext-crewchief-testing-static-hub-parallelism (7) · ext-crewchief-orchestration-livestepoutput (6). Apply notes: (a) the remote-box-prep agent found the "Remote Browse…" bullet actually lives in crewchief-web-ui, so it correctly wrote the deep mechanics into crewchief-remote-box-prep's RemoteWindowsOps section AND extended web-ui — which duplicated the web-ui agent's own concise addition; the main session deduplicated web-ui's browse bullet down to wiring + [[crewchief-remote-box-prep]] cross-link (deep mechanics live only in remote-box-prep). (b) reference-data agent added a verified nuance: GetSeedDefault backs only the editor prefill (SwitchPrefillValue), never BuildDefaultSwitches — the exact enabled-but-blank trap. (c) workload-and-runs agent kept the 1080px width claim scoped to the Activity step-output dialog vs the compact monitor's 1300px. Descriptions updated on workload-and-runs / web-ui / reference-data / remote-box-prep / step-executors. No new skills → no linker change.

_Apply-time verification-gate catches (corrected before writing): workload-transfer DI lines were 279-282 not ~30-32; Configure wizard markup lives at .razor ~1290-1700 not ~320-560 (razor.cs ~1246-1615); the "stale IsLocalTarget wording" was in a CODE doc comment (ConfigureExecutor.cs:~326-328, repo read-only — informational), the skill was merely thin; secrets keep-stale warning paths = 5 not 4; Activity default page size uses a SECOND key WebUI:Activity:DefaultPageSize (fallback 25); switch catalog re-counted 58→61 (IIS 6→9) + secret switches 6→7 (adds maestroServiceUserPassword); step-bundle import is always-new per step (workload import keeps existing same-named steps). Honest residual documented in remote-box-prep: the six executors' RUNTIME null-credential guard still emits the old "requires 'credentialSecretName'" text while step GetValidationError says "requires Run As credentials" — repo-side message mismatch surfaced to user as informational._

The 9 full card specs (scope record, moved verbatim from Pending):

### ext-crewchief-remote-box-prep-runas-auth-configure — crewchief-remote-box-prep
- **Kind**: ext
- **Target**: crewchief-remote-box-prep (correctness rewrite + new capability sections)
- **Score**: 10
- **Description**: Correctness + gap, HIGHEST priority. (a) INVERTED: two-field Run As (`credentialUserId`+`credentialPassword`, `Resolve(userId,pwd) ?? Resolve(secretName)` fallback) supersedes single `credentialSecretName` (SKILL.md:25,32,35,93,100-105 + old error text quoted verbatim). (b) NEW `remoteAuthentication` on all 6 remote steps + `RemoteAuthParser` (Default/Negotiate/CredSSP, fail-safe) threaded to `RemoteRunRequest.Auth` in every executor — CredSSP = double-hop (Windows-auth SQL on a 3rd box; ANONYMOUS LOGON symptom); machine setup Enable-WSManCredSSP client(CrewChief host, -DelegateComputer FQDN)/server(target); help doc 43_OpsRemoteBoxPrep §5. (c) NEW `RemoteRunRequest.WorkingDirectory` + `CC_REMOTE_WORKDIR` + Start-Process splat; ConfigureExecutor defaults workdir to exe's folder (Configuration.exe derives PhysicalPath from CWD → LoadConfig/writeServiceConfig NRE otherwise). (d) INVERTED: `ComposeArgumentString(Func resolveValue)` — quote decision sees RESOLVED values (webSiteName "Default Web Site" regression); compose twice, unresolved for InputText (SKILL.md:102 describes quote-then-resolve). (e) Install split-then-resolve (`SplitArguments` BEFORE per-arg `ApplyTokens`); `IProductInstallRunner.InstallAsync` takes `IReadOnlyList<string>`. (f) Remote installed-product inventory (`IInstalledProductInventory`, `BuildInstalledProductsScript`/`ParseInstalledProducts`/`BuildResolveConfigurationExeScript`) — Uninstall name→code over WSMan now WIRED (old "requires productCodes… not yet wired" guard removed). (g) Configure validation now requires `licenseFile` switch.
- **Sources**: `IRemoteCredentialResolver.cs:36,93`, `ConfigureExecutor.cs:141-146,180,213,243,263,339`, `InstallExecutor.cs:135-140,212`, `UninstallExecutor.cs:253,273-345`, `IisResetExecutor.cs:128`, `ServiceControlExecutor.cs:152`, `AppPoolExecutor.cs:161,208`, `IRemoteCommandRunner.cs:32,99`, `DefaultRemoteCommandRunner.cs:157,350,370`, `ConfigureStep.cs:94,112,165-172`, `IProductInstallRunner.cs:68,119`, `IInstalledProductInventory.cs`, `RemoteWindowsOps.cs` (3 new builders)
- **Added**: 2026-07-22
- **Notes**: ~15 files. Cross-link memory reference_configuration_exe_failure_modes + Documentation/43_OpsRemoteBoxPrep.md §5 (CredSSP what/why/how). Several claims first-hand (authored 2026-07-22 session).

### ext-crewchief-step-executors-detect-impersonation — crewchief-step-executors
- **Kind**: ext
- **Target**: crewchief-step-executors (Configure failure detection + impersonation + IsLocalTarget)
- **Score**: 9
- **Description**: (a) `ConfigureExecutor.DetectConfigurationFailure` — Configuration.exe ALWAYS exits 0; static output scanner fails the step on `Missing parameter <x>` or exception dump (`StackTrace =`, surfaces `Message =` line); applied local + remote. (b) NEW `WindowsImpersonation.RunAsAsync<T>` — P/Invoke LogonUser `LOGON32_LOGON_NEW_CREDENTIALS`/WINNT50 + `WindowsIdentity.RunImpersonatedAsync` (flows across awaits) so outbound Windows-auth SQL authenticates as a chosen account (DOMAIN\user / UPN / bare); consumed by DatabaseOperations Windows-auth-with-credential path. (c) `IsLocalTarget` rewritten FQDN/short-label-aware (cached `LocalIdentities` exact+short sets, leading-label match both directions) — a token resolving to the host's FQDN is now local (SKILL.md:33 describes only the old blank/./localhost/MachineName rule).
- **Sources**: `ConfigureExecutor.cs:339,180,263`, `WindowsImpersonation.cs:24,38,46`, `MapShareExecutor.cs:249-296`, `IsLocalTargetTests.cs`, `ConfigureExecutorTests.cs`
- **Added**: 2026-07-22
- **Notes**: Memory reference_configuration_exe_failure_modes documents the Configuration.exe side. WindowsImpersonation is CrewChief's NON-CredSSP double-hop answer for direct-from-CrewChief SQL (DB-ops); CredSSP (remote-box-prep item) is the WinRM-path answer — document the distinction.

### fix-crewchief-reference-data-two-tier-template — crewchief-reference-data
- **Kind**: ext
- **Target**: crewchief-reference-data (correctness fix + seeder + transfer)
- **Score**: 9
- **Description**: Correctness, HIGH priority (Notes: correctness fix). (a) INVERTED: `configuration-defaults` set NO LONGER EXISTS (SKILL.md:24,48,54,79 + crewchief-web-ui:153 describe it as live). Replaced by two-tier: `configuration-template` (placeholder map switch→{{token}}, never literals — structural → `{{$ref:configuration-values:…}}`, credentials → `{{$config:UserCredentials:…}}`; includeInReplacements:false) + `configuration-values` (actual editable values, replaceable). `SwitchPrefillValue` reads ConfigurationTemplate (StepEditorCard.razor.cs:1573). (b) INVERTED: `ConfigurationDefaultsSeeder`/`DriveMapSeeder`/`ServerNamesSeeder` DELETED (verified on disk) → single `ReferenceDefaultsSeeder` installing embedded `DefaultReferenceData/*.refkv.json` via 3-way additive merge (`ComputeKeysToAdd` vs `SeedRecord.ShippedEntryKeys` — adds only new-in-this-release keys, never re-adds operator-deleted); manifest key `reference-kv/<type>`. (c) NEW `ReferenceTransferService`/`ReferenceBundle` (schemaVersion 1) — selective export/import, additive, on-wire shape mirrors on-disk body, invalid-kebab names skipped not fatal.
- **Sources**: `ReferenceDataSets.cs:29-42`, `ReferenceDefaultsSeeder.cs:1-183`, `Seeding/SeedRecord.cs:13-22`, `Web/Program.cs:~40-86`, `DefaultReferenceData/*.refkv.json`, `ReferenceTransferService.cs:20,55,95`, `StepEditorCard.razor.cs:1573`, `Steps.razor.cs:623`, `WorkloadEditor.razor.cs:497`
- **Added**: 2026-07-22
- **Notes**: SUBSUMES part of pending ext-crewchief-reference-data-smart-seed (its SampleContentSeeder correction stands; the doctrine table needs the merged reality). Two-tier model matches memory project_crewchief_configure_switches.

### ext-crewchief-web-ui-configure-wizard-pickers — crewchief-web-ui
- **Kind**: ext
- **Target**: crewchief-web-ui (Configure wizard + remote pickers)
- **Score**: 8
- **Description**: (a) Configure editor = multi-page WIZARD: `ConfigSwitchPageLayout` (SQL / Web&IIS / Auth / Integrations pages composed from (Group,SubGroup) parts), `ConfigureEditorTabs` (Settings/Target&RunAs/License/…/Advanced/Review), `ConfigSwitchPage`/`ConfigSection`/`ConfigEditorTab` records, `cc-wizard-*` CSS. (b) Review page: `BuildConfigurePreview(reveal)` copy-paste PowerShell command resolving {{$config}}/{{$ref}} design-time, secrets masked unless reveal; `ConfigureReviewGroups`/`ConfigureReviewValue`; stat tiles. (c) Authentication picker (Default (Kerberos)/Negotiate/CredSSP) in the Run As of all 6 remote editors. (d) Installed-Profisee-version picker: `IInstalledProductInventory` → `ResolveConfigurationExeAsync` autofills exe path; `ResolveTargetMachine`/`ResolveRunAsCredential` design-time helpers. (e) Remote Browse…: `IRemoteFileBrowser` + `BuildFileBrowseScript` (mapped drives via Get-SmbMapping + HKEY_USERS Network + nethood .lnk — WinRM network logon can't see session drives); `IServerFileBrowser.EnumerateRoots` folds HKCU\Network persistent mappings (service-mode mapped drives); `FileBrowserDialog` Machine/Credential params.
- **Sources**: `StepEditorCard.razor.cs:150-296,1155-1330,1391-1584`, `StepEditorCard.razor:178-863` (6 auth pickers), `StepEditorCard.razor.css` (cc-wizard-*), `IRemoteFileBrowser.cs`, `IServerFileBrowser.cs:84-140`, `RemoteWindowsOps.cs` (BuildFileBrowseScript)
- **Added**: 2026-07-22
- **Notes**: Wizard mirrors the matching-editor wizard convention (memory project_crewchief_configure_switches). Cross-link remote-box-prep item for the engine side.

### ext-crewchief-web-ui-shared-components — crewchief-web-ui
- **Kind**: ext
- **Target**: crewchief-web-ui (SegmentedToggle + card grid)
- **Score**: 8
- **Description**: (a) NEW generic `SegmentedToggle`/`SegmentedOption<T>` pill selector (`cc-segbar`/`cc-seg`, accent classes cc-seg-literal/secret/ref, Material icons, tooltips) — REPLACED RadzenSelectBar in SecretValueEditor + ServerNameEditor 3-mode editors; the app-wide value-source/mode selector convention. (b) NEW `StepCard`/`WorkloadCard` components (kebab overflow menu; Selected/ShowSelect; OnRun/OnEdit/OnCopy/OnRename/OnExport/OnDelete callbacks) + `cc-card-grid` card view on Steps/Workloads alongside the retained RadzenDataGrid (view toggle).
- **Sources**: `SegmentedToggle.razor` + `.razor.css`, `SegmentedOption.cs`, `SecretValueEditor.razor:20-34`, `StepCard.razor.cs`, `WorkloadCard.razor.cs`, `Steps.razor:64-67`, `Workloads.razor:64`
- **Added**: 2026-07-22
- **Notes**: Delta to pending ext-crewchief-web-ui-multifacet-filter-and-grid (grid item predates the card migration). Matches memory project_crewchief_ui_conventions_2026-07.

### ext-crewchief-workload-transfer-step-bundles — crewchief-workload-transfer
- **Kind**: ext
- **Target**: crewchief-workload-transfer (step + library-export siblings)
- **Score**: 8
- **Description**: (a) NEW step-library transfer: `StepBundle` (`.step-bundle.json`, schemaVersion "1.0") via `IStepTransferService` — build/parse/preview/import, all-or-nothing export, always-new import naming `BuildImportName` (-imported/-imported-N), polymorphic StepFile.Step round-trip through UtilityStepConverter, step-scoped `FindPlaintextSecrets` scanner (sibling of the workload one at workload-transfer SKILL.md:39). (b) NEW `ExportStepsToLibraryDialog` + `IStepLibraryExporter` — promotes a workload's INLINE steps into the library: ref entries skipped, kebab suggestions label→description→type Slugify/MakeUnique de-duped across library+batch, ExportInline new-only (never overwrites), source workload never mutated. (c) DI: IStepTransferService/IReferenceTransferService/IStepLibraryExporter registered in Web Program.cs.
- **Sources**: `StepTransferService.cs:18,119,145,214,167`, `IStepTransferService.cs:11`, `StepBundle.cs:12`, `StepLibraryExporter.cs:42,83,148`, `ExportStepsToLibraryDialog.razor`, `Web/Program.cs:30-32`
- **Added**: 2026-07-22
- **Notes**: ReferenceBundle covered in fix-crewchief-reference-data-two-tier-template. ExportStepsToLibraryDialog matches memory project_crewchief_ui_conventions_2026-07.

### ext-crewchief-workload-and-runs-label-activity — crewchief-workload-and-runs
- **Kind**: ext
- **Target**: crewchief-workload-and-runs (per-instance label + Activity page)
- **Score**: 7
- **Description**: (a) NEW optional `label` on `WorkloadStepEntry` — per-instance display rename shown in run/Activity views WITHOUT touching the shared library step; mapped by WorkloadDefinitionMapper; `WorkloadEngine` overrides resolved step.Description with it (engine side: WorkloadDefinition.cs:58, WorkloadEngine.cs:155-156 — cross-note crewchief-orchestration, adjacent to pending description-stamping item but distinct: entry-level rename vs result stamping). (b) Activity page: config-driven client paging (`WebUI:Activity:PageSizeOptions` fallback 10/25/50/100, ClampPage/PagedRuns surviving the 1s live-refresh ticker), case-insensitive run-name filter atop status filter, `FailureBanner` (first failed step / cancellation reason), `ActiveRun` live-progress card.
- **Sources**: `WorkloadStepEntry.cs:43`, `WorkloadDefinitionMapper.cs:53`, `WorkloadDefinition.cs:58`, `WorkloadEngine.cs:155-156`, `Activity.razor.cs:26-160`, `Activity.razor.css`
- **Added**: 2026-07-22

### ext-crewchief-file-persistence-rename — crewchief-file-persistence
- **Kind**: ext
- **Target**: crewchief-file-persistence (Rename + reference rewrite)
- **Score**: 6
- **Description**: NEW `Rename(oldName,newName)` on IStepFileStore + IWorkloadFileStore: kebab-validates both names, keeps embedded `.Name` in sync, atomic tmp+Move+Delete, refuses if target exists. Paired `WorkloadFileStore.UpdateStepReferences(old,new)` rewrites every workload entry whose Ref matches and re-saves (returns count) — "rename a library step and make workloads follow".
- **Sources**: `StepFileStore.cs:137`, `WorkloadFileStore.cs:128,158`, `IStepFileStore.cs:38`, `IWorkloadFileStore.cs:55`
- **Added**: 2026-07-22

### ext-crewchief-secrets-reloadnow — crewchief-secrets
- **Kind**: ext
- **Target**: crewchief-secrets (reload signaling)
- **Score**: 6
- **Description**: NEW `LocalSecretsConfigurationSource.ReloadNow()`/`ReloadAndSignal()` — re-decrypts the store and fires the change token DIRECTLY because a source added to the minimal-hosting ConfigurationManager after build is not reliably re-run by root.Reload(); /secrets Reload/Replace buttons call it so editors see fresh secrets without restart. Plus Serilog warnings on every keep-stale path (store missing / master unresolved / 0 sections / decrypt failure) — previously silent.
- **Sources**: `SecretConfigurationSources.cs:88,102,120-165`
- **Added**: 2026-07-22


### 2026-07-20 (Mode 1 rerun — credentialed remote-ops feature; diff 1d8b33cb..0931603b; all 5 ext + memory applied same session per "approve all new")

_The 1d8b33cb..0931603b diff (2 commits / 31 files) committed the credentialed / run-as remote Windows ops feature that memory had tracked as uncommitted. 3-agent read-only fan-out; every staleness/path claim re-verified against live code by my own grep before edit (caught + corrected the sub-agents' nonexistent `CrewChief.Engine.Tests` project path). No new skills → no linker/junction change._

- **ext-crewchief-remote-box-prep-credentialed-ops** (8, correctness) → crewchief-remote-box-prep: replaced the "Two remote transports" section with **"Three routing modes"** (local / credentialed-remote / legacy-RPC-fallback; per-step matrix) — all six steps now accept optional `credentialSecretName`; added the **RemoteWindowsOps op-script layer** section (pure `-EncodedCommand` builders, `{ok,previous,final,timedOut}` JSON contract, 600s default / +60s transport margin, `ConvertTo-Json` single-object tolerance); rewrote the resolver section (input normalization: `{{$config:...}}` unwrap incl. inner whitespace, `:User`/`:Password` leaf → parent, `ApplyTokens` before lookup; null-result routing differs installer-fails vs service-family-legacy-fallback); updated the three service-family step bullets to dual-mode; corrected the now-obsolete stale-doc note (code XML fixed) + NotWired quoted string — **SUBSUMES** pending `ext-crewchief-remote-box-prep-sdk-note-obsolete`; frontmatter triggers + Sources (RemoteWindowsOps.cs + the 3 test files, real paths). Reconciled memory [[project_crewchief_remote_boxprep_transport]].
- **ext-crewchief-web-ui-credential-picker** (7, correctness) → crewchief-web-ui: live-enumeration bullet now reflects `GetServicesAsync`/`GetAppPoolNamesAsync` taking a `RemoteCredential?` + card resolving a design-time credential; added `ResolveCredentialRef`/`AnyRefRegex` (distinct from `ResolveConfigRef`); noted the Run-As fields use the *unrestricted* 3-mode SecretValueEditor (Install/Uninstall/Configure dropped `SecretOnly`).
- **ext-crewchief-secrets-reload-rebuild** (6) → crewchief-secrets: added the `LocalSecretsConfigurationProvider.Load()` rebuild-`Data`-on-success-path fact (drops keys removed since last load; early-return/catch leaves live `Data` intact) to the config-source wiring section. Matches the "Reload additive-Data bug fixed" note in memory project_crewchief_credentialed_remote_ops.
- **ext-crewchief-testing-credentialed-remotelab** (5) → crewchief-testing: added `RemoteCredentialSecretName`/`CREWCHIEF_REMOTE_TEST_CRED_SECRET` prereq row + `CredentialedRemoteOpsIntegrationTests` (fallback chain, Spooler Stop→Start self-provision roundtrip, unlocked-box-else-Inconclusive); Sources updated (real project paths).
- **ext-crewchief-executor-pattern-ctor-chain** (4) → crewchief-executor-pattern: added the three-constructor testability-seam chain (IConfiguration DI ctor news up runner+resolver; legacy 3-arg ctor injects an inert resolver → legacy path; all-seams-explicit ctor for fakes).

### 2026-07-19 (Mode 1 — CrewChief FULL skill family: all 17 authored, verified & linked same session)

_The entire 74888cb7..fcbcaaaf diff (107 commits / 419 files) was the NEW standalone CrewChief solution (6 projects, files-only, zero TestAuto refs). 5-agent read-only fan-out surfaced 51 findings, consolidated to 17 crewchief-* skills; user approved ALL ("Full"); 6 parallel authoring agents wrote them (each re-verifying claims vs live source); linked to AI + Cursor (137 skills total). Verification-gate corrections applied while authoring:_

- The two CreateStepForType factories are currently IN SYNC → documented as a HAZARD, not live drift. The real live drift: the orchestrator alias table lacks "iisreset"/"email" short aliases, so they deserialize but throw "No executor found" at dispatch.
- DpapiPassphraseProtector throws off-Windows (env fallback is at the resolver layer, NOT in the protector); no class literally named PassphraseProtector.
- **LATENT BUG surfaced to user (unfixed):** ConnExExecutor requests HttpClient "ConnectClient" but DI registers "ConnEx" → falls back to the default unconfigured client pipeline.
- Box-prep GetValidationError delegation is partial (Install/Uninstall/Configure only; ServiceControl/AppPool validate inline; IisReset has no orchestrator case). Two remote transports: WSMan-credentialed (Install/Uninstall/Configure) vs server-identity ServiceController/ServerManager/iisreset (ServiceControl/AppPool/IisReset).
- LogTagConstants: 13 live tags, 26 dead copied-in (Connect is LIVE — corrected from brief). Config switch catalog = 58 entries. UnreadableInline is WorkloadEditor editor-state not a model field; transfer result types share no base; SynchronousProgress/SafeAppend/SafeUpdate are RunCommand-local; ConnEx real endpoints = GatewayPaths (v1/Connect/Configurations|Strategies|ServiceProviders); driver transport is -EncodedCommand (stale XML doc says stdin).
- Crypto verified from source: Encryption Secrets AES-256-GCM + PBKDF2-SHA256 300k iters (min 100k); Local Secrets AES-256-CBC + Brotli, fixed salt TestAutoSecrets.v1 (TestAuto v2 byte-compatible), PBKDF2 10k; lockout 3 attempts / 15-min doubling, fail-closed. SecretsBootstrapMiddleware WIRED (Program.cs:308).
- The 17: crewchief-architecture, -step-type-model, -adding-a-step-type, -executor-pattern, -step-executors, -remote-box-prep, -secrets, -reference-data, -web-ui, -workload-and-runs, -orchestration, -token-replacement, -file-persistence, -cli, -testing, -workload-transfer, -logging. The approved per-skill specs are retained verbatim below as the scope record.



### 2026-07-14 (Mode 1 diff scan 00241476..74888cb7 — all 9 applied same session)

_All items verified against live code before edit. New skill testauto-bounded-parallel-fanout created + linker/junctions (AI + Cursor). Deviation: dotnet-testing references/TestingSetupGuide_v1.md:364 net8.0 NOT changed — it documents the platform (net8) template, not speed-merchants; verification gate caught the over-broad candidate._

### new-testauto-bounded-parallel-fanout — testauto-bounded-parallel-fanout
- **Kind**: new
- **Target**: testauto-bounded-parallel-fanout (create)
- **Score**: 10
- **Description**: The SemaphoreSlim(10)+Task.WhenAll bounded fan-out convention for 1+N gateway calls (list pages, controllers, bulk editors) incl. the tuple-then-populate rule for plain-Dictionary caches ("Dictionary is not safe for concurrent writes" — populate single-threaded AFTER WhenAll) and order preservation.
- **Sources**: `TestAuto.Web/Components/Pages/Workflows.razor.cs:228`, `WorkflowExecutionEditor.razor.cs:264-280`, `WorkflowExecution.razor.cs:159-175`, `WorkflowBuilder.razor.cs:143-164`, `Scenarios.razor.cs:178-198`, `Controllers/ExecutionControlController.cs:291-306`, `Components/Common/BulkCustomParmsEditorBase.cs:378-426`, `Components/Controls/MatchingBulkEditPanel.razor.cs:101`
- **Added**: 2026-07-13
- **Notes**: 10+ files; cross-link memory project_list_page_nplus1_parallelization + [[bulk-custom-parms-editor-base]].

### ext-testauto-tech-stack-net10-webapp — testauto-tech-stack
- **Kind**: ext
- **Target**: testauto-tech-stack
- **Score**: 10
- **Description**: Framework row (line 27) ".NET 8, Blazor Server" → ".NET 10, Blazor Web App (Interactive Server render mode)". Correctness fix.
- **Sources**: all 24 csproj (net10.0), `TestAuto.Web/Program.cs` (AddRazorComponents), `PipelineExtensions.cs` (MapRazorComponents)
- **Added**: 2026-07-13

### ext-testauto-project-webapp-structure — testauto-project
- **Kind**: ext
- **Target**: testauto-project
- **Score**: 9
- **Description**: Fix 4 stale "Blazor Server" refs (lines 17, 245, 265, 299) → Blazor Web App (Interactive Server); document new hosting files (Components/App.razor = root HTML document, Components/Routes.razor = router, blazor.web.js) and that TestAuto.Web/Pages/ no longer exists.
- **Sources**: `TestAuto.Web/Components/App.razor`, `Components/Routes.razor`, `Program.cs`, `ServiceExtensions/PipelineExtensions.cs`
- **Added**: 2026-07-13

### ext-testauto-record-transformation-synonymhelper-fixed — testauto-record-transformation
- **Kind**: ext
- **Target**: testauto-record-transformation
- **Score**: 8
- **Description**: CORRECTNESS FIX — SynonymHelper subsection still documents the loader-filter no-op bug as live; the bug is FIXED (filter `.Contains(".SynonymLists.")`, category = filename stem) AND the constructor now parses the Profisee Matching synonym-file EXPORT schema ($..Synonyms recursive descent, legacy + current layouts, Identifier.Name/Name + non-empty Term) with per-file try/catch (one bad file = skipped, warning logged). VariantGenerator rule 5 is now functional (Address 576 terms, Country 57, DateOfBirth 27, StreetAddress 21, Email 20, City 11).
- **Sources**: `TestAuto.Shared/Helpers/SynonymHelper.cs`, `TestAuto.Shared/SynonymLists/*.json` (6 files)
- **Added**: 2026-07-13

### ext-testauto-ui-patterns-webapp-grids — testauto-ui-patterns
- **Kind**: ext
- **Target**: testauto-ui-patterns
- **Score**: 7
- **Description**: Scope line (15) "Blazor Server + Radzen" → "Blazor Web App (Interactive Server) + Radzen"; add polled-RadzenDataGrid pattern (grid @ref + Reload() from PeriodicTimer tick, RowRender for row-class, server-side-paging grids keep AllowPaging off) + [PersistentState] on user-view state (ExecutionMonitoring 10 props, 0-sentinel for config-default fallback).
- **Sources**: `TestAuto.Web/Components/Pages/ExecutionMonitoring.razor(.cs)`, `ExecutionHistory.razor(.cs)`, `ExecutionDashboard.razor`
- **Added**: 2026-07-13

### ext-testauto-deployed-machine-diagnostics-net10 — testauto-deployed-machine-diagnostics
- **Kind**: ext
- **Target**: testauto-deployed-machine-diagnostics
- **Score**: 6
- **Description**: ".NET 8" ×3 (lines 60, 62, 127) → ".NET 10"; script's $targetFramework now net10.0.
- **Sources**: `TestAuto.Web/RunTimeSetup/Diagnose-DeployedMachine.ps1`
- **Added**: 2026-07-13

### ext-blazor-code-behind-rendermode — blazor-code-behind
- **Kind**: ext
- **Target**: blazor-code-behind
- **Score**: 5
- **Description**: Line 176 "Under `ServerPrerendered` hosting" → the Web App equivalent (InteractiveServer render mode with prerendering); the two-render-pass fact itself is unchanged.
- **Sources**: `TestAuto.Web/Components/App.razor` (@rendermode InteractiveServer)
- **Added**: 2026-07-13

### ext-small-fixes-net10-tfm — testauto-testing-patterns, dotnet-testing
- **Kind**: ext
- **Target**: testauto-testing-patterns (SKILL.md:83) + dotnet-testing (references/TestingSetupGuide_v1.md:364)
- **Score**: 3
- **Description**: Two one-liners: runsettings snippet `<TargetFrameworks>net8.0</TargetFrameworks>` → net10.0; reference guide `<TargetFramework>net8.0</TargetFramework>` → net10.0.
- **Sources**: `speed-merchants.runsettings`, any csproj
- **Added**: 2026-07-13

### hyg-testauto-help-docs-csproj-lines — testauto-help-docs
- **Kind**: hyg
- **Target**: testauto-help-docs
- **Description**: csproj MD2Razor wiring block line refs drifted by −1 (skill says 101–122; now 100–121) after a PackageReference removal above the block. Two cite sites (§3 header + Sources).
- **Sources**: `TestAuto.Web/TestAuto.Web.csproj:100-121`
- **Added**: 2026-07-13

### 2026-07-12 (Mode 6 — Opus 4.8/1M model-upgrade re-review of the UNCHANGED corpus; baseline 00241476 unchanged; 79 skills, 14 review agents + 6 apply agents; ALL 21 applied same session)

_Mode 6 sweep 2026-07-12: baseline unchanged since the 2026-07-11 Mode 6 pass — the REVIEWER changed (Fable→Opus 4.8/1M), which is the whole rationale for Mode 6 ignoring the diff-gate. 21 verified findings across 21 skills; 5 skills fully clean; 0 reviewer false positives survived my grep/read gate. No-action: profisee-dq-rules dangling citation already annotated (deleted 2026-05-16); speedmerchants-db-migration MCP-alias mismatch = env note, not a skill error. Full evidence: scratchpad mode6-findings.md. Two consistency patches beyond the 21: ui-patterns frontmatter "nested"→"companion"; testdata-enrichment-pipeline frontmatter+table DBCheckpointManager→DbCheckpointManager (type refs)._

- **ext-mode6b-scenario-metrics** (8) → testauto-scenario-metrics: replaced the superseded per-type-switch "Wiring a New Detail Type" 11-step table + "Code Checklist" (~L292-395) with attribute-driven reality — 2 real steps (MetricDetailX:MetricDetailBase + [MetricColumn] in owning domain project; reference as 2nd typeof of [ScenarioTypes]); factories resolve via ScenarioTypeRegistry reflection (MetricDetailFactory.cs:53-63, MetricBatchSummaryFactory.cs:52-93); MetricDetailBuilderFactory/MetricDetailStepBuilder don't exist (stale AddingNewDetailTypes.md doc only)→GenericMetricDetailBuilder<T>. NOTE: ## Sources still cites AddingNewDetailTypes.md (stale repo doc) — left, flagged.
- **ext-mode6b-record-transformation** (8) → testauto-record-transformation: rewrote the (2026-07-11-added) SynonymHelper subsection — real folder SynonymLists\<Category>.json (Address/City/Country/DateOfBirth/Email/StreetAddress, no FirstName), full-dotted manifest key; ADDED a ⚠ warning that the loader filter `Contains("SynonymList.")` never matches manifest segment "SynonymLists." → zero lists load → ApplySynonyms permanent no-op → VariantGenerator rule 5 no-ops. Surfaced the latent repo bug to user as INFORMATIONAL (read-only repo).
- **ext-mode6b-matching-scenarios** (7) → testauto-matching-scenarios: fixed 3 of 4 "Cache Entities for 3A" names (TestAutoMatchStatus→TestAutoMatchingStatus, TestAutoMatchingAttributeReference→TestAutoMatchingStrategyAttributesReference, TestAutoMatchingAttribute→TestAutoMatchingAttributes; row 4 correct). Wrong names existed only in a doc.
- **ext-mode6b-test-data-generation** (7) → testauto-test-data-generation: re-scoped the CloneAndMutate rule table to the standalone TestData.CloneAndMutate console tool (NOT CloneAndMutateScenario, which uses VariantGenerator.ApplyRule 0/1/2-noop/3-SwapChars/4-SlightTypo/5-synonym/6+-noop); cross-links testauto-record-transformation.
- **ext-mode6b-record-repository** (6) → testauto-record-repository: dropped false "only repository pair in solution"; added TestAuto.Matching (IRecordPoolRepository, per-scenario not DI-reg) + TestAuto.Connect (IConnectExecutionRepository) pairs; WebUiRepository = only DI-registered/WebUIDataFacade-backed.
- **ext-mode6b-hangfire-architecture** (6) → testauto-hangfire-architecture: MetricsPersistenceJob has no [Queue] + ContinueJobWith no EnqueuedState → runs on `default` (not `persistence`); persistence slot on FollowOnServer vestigial. aggregation/workload/resource genuinely used.
- **ext-mode6b-execution-context** (6) → testauto-execution-context: CdpContext marked "defined but not wired / no live consumers"; removed the AddScoped<IContext,CdpContext> snippet + Hangfire-usage assertion (grep = decl+ctor only). Property facts kept.
- **ext-mode6b-cli-command-pattern** (6) → testauto-cli-command-pattern: client verb modes = json/environment/display/database; --prompt reframed as interactive selector (not a mode); corrected "--database mode" (no such CLI flag; VerbClientOptionsHandler.cs:95-105, ClientCommand.cs:34-76).
- **ext-mode6b-ui-patterns** (6) → testauto-ui-patterns: replaced fabricated EditRestClientDialog/EditRestClientResult example with real EditSectionDialog + COMPANION (not nested) EditSectionResult (Components/Controls/EditSectionDialog.razor.cs:87,145,163); frontmatter "nested"→"companion".
- **ext-mode6b-project** (6) → testauto-project: Components/ subfolders → Common/Controls/Dashboard/Dialogs/Help/Layout/Pages (dropped phantom Forms/Grids/Shared); ScenarioConfiguration namespace → TestAuto.Shared.Scenarios.Configuration.Scenario.
- **ext-mode6b-workflow-execution** (6) → testauto-workflow-execution: "Card vs Grid View" rewritten as delegation to shared ScenarioListEditor.razor.cs:98 + ScenarioListState.cs:48-52 (paged prop PagedFiltered, not PagedCardItems; IsGridView/LoadViewPreference/PagedCardItems 0 hits in page); QuickEdit Section 3 gained RecordsPerBatch.
- **ext-mode6b-scenario-types-attribute** (5) → testauto-scenario-types-attribute: ITestDataGenerator (0 hits)→ITestData (generators derive DataRecordBase:ITestData); param name testDataType kept.
- **ext-mode6b-config-validation** (5) → testauto-config-validation: added CrossFieldValidator prod-low-concurrency row (prod env AND MaxConcurrentBatchesPerHangfireScenarioServer < 3 → Warning; cs:120-132).
- **ext-mode6b-testing-patterns** (5) → testauto-testing-patterns: BaseTest snippet TestInitialize()→Setup(), optional:false→true, added integration overlay+secrets-file layers + Logger prop; line refs ~41/~45→~53-56/~57 (incl. Sources line).
- **ext-mode6b-dotnet-testing** (5) → dotnet-testing: BaseTest Setup step 2 → 4-layer config precedence (appsettings.json → appsettings.integration.json → IntegrationSecretsLoader secrets file → env vars).
- **ext-mode6b-dotnet-domain-values** (4) → dotnet-domain-values: AttributeNames.cs is file-scoped `namespace TestAuto.Shared.Constants;` (not "no wrapping namespace"); 3 classes named.
- **ext-mode6b-result-pattern** (4) → result-pattern: MasterPasswordManager fail-string corrected (MinPasswordLength const + "...Current length: {n}"); IValidationService completed to 5 members (added GetValidationRulesAsync/GetValidationSuggestionsAsync, verified return types).
- **ext-mode6b-scenario-config-inspector** (4) → scenario-config-inspector: description+section now state plainly CHUNKREF reassembly is NOT implemented in inspect-config.ps1 (BROTLI/GZIP/raw only; verified current script), reassembly steps relabeled "what an extension would need to do".
- **ext-mode6b-custom-parm-editor** (3) → custom-parm-editor: ConnectPostRunConstants line ref 198-216→224-236 (values correct).
- **ext-mode6b-testdata-enrichment-pipeline** (3) → testdata-enrichment-pipeline: type name DBCheckpointManager→DbCheckpointManager (heading + frontmatter + Project Family table; file name DBCheckpointManager.cs kept).

### 2026-07-11 (Mode 6 — full corpus review vs code; all 34 items below APPLIED same session by 9 parallel apply agents; dotnet-secret-provider deleted + linker/README/inbound-refs cleaned)

_Mode 6 sweep 2026-07-11 (baseline 00241476, 79 skills reviewed, 16-agent fan-out): 100 verified findings consolidated into 34 per-skill correction items. All STALE/nonexistent-referent claims gate-verified by name-based grep; positive values spot-checked by direct read. Full evidence: session scratchpad mode6-findings.md (findings #1-#100)._

### ext-mode6-workflow-execution — testauto-workflow-execution
- **Kind**: ext | **Score**: 9 | **Added**: 2026-07-11
- **Description**: 9 correctness fixes: isFromWorkflowExecution default true (not false); ExecuteSingleScenarioAsync→WorkflowOrchestrationService.ExecuteSingleScenarioDetailAsync; monitor every N min (WorkflowMonitor:IntervalMinutes, default 5) not 10s; ScenarioBatchJobOrchestrator→BatchJobOrchestrator; dispatcher enqueues on "default" queue not scn-; remove stale Filter Cache section (0 hits); persistence via IScenarioConfigStore not TemplateStorage; MaxRunningScenarioCount is a metric not the dispatch cap (cap = serverCount arg); drop shifted line numbers. (#82-90)

### ext-mode6-hangfire-architecture — testauto-hangfire-architecture
- **Kind**: ext | **Score**: 9 | **Added**: 2026-07-11
- **Description**: 5 fixes: AddHangfireServices→AddHangfireServers/AddHangfireRecurringJobs split; remove Hangfire.Pro [Semaphore] (0 hits, concurrency = serverCount/DisableConcurrentExecution/UseThrottling); Dispatch = 4-param signature; HangfireInitializer only ForceHangfireSchema (no per-scenario recurring dispatcher); queue topology default/aggregation + scn- for counting only. (#96-100)

### ext-mode6-workflow-export — testauto-workflow-export
- **Kind**: ext | **Score**: 8 | **Added**: 2026-07-11
- **Description**: 5 fixes: remove ScenarioDataMaxChars constant (0 hits); >4000 = chunked via PersistAsync not skip-with-warning (only ScenarioDataDisplay truncated); decompress via _store.LoadAsync; scenarios mode re-persists via PersistAsync under new owner code; ScenarioDataDisplay = ResolveRawAsync truncated 4000. (#91-95)

### ext-mode6-metadata-scenario — testauto-metadata-scenario
- **Kind**: ext | **Score**: 8 | **Added**: 2026-07-11
- **Description**: 4 fixes: failures aggregated not fatal (attr creation skipped only if any entity failed); MaxRetries default 1 no cap (not 5/50); Limits table fabricated — real constraints = >=1 entity, name<=40, >=0 numerics, both-limits-zero throws; entity Delete action ignored (always delete-then-create; only attributes branch on action). (#65-68)

### ext-mode6-multistep-steps — testauto-multistep-steps
- **Kind**: ext | **Score**: 8 | **Added**: 2026-07-11
- **Description**: 5 fixes: PowerShellExecutor→PowerShellScriptExecutor; remove CaptureResponseBody row (0 hits); Monitor top table = Message required + ActivityType via Parameters (not ActivityName/Description); SqlExecutor→SqlScriptExecutor; delete "Body File Path for Large Payloads" subsection + HTTP 415 row (contradicts inline-only). (#74-78)

### ext-mode6-scenario-metrics — testauto-scenario-metrics
- **Kind**: ext | **Score**: 8 | **Added**: 2026-07-11
- **Description**: 6 fixes: builders do NOT enforce [MetricColumn] completeness (Build() => _detail); delete NoOpScenario row (0 hits, DefaultNoOpGenerator consumers = post-run/metadata scenarios); GetRecordsByPageAndBatchScenario→PagedRecords; fix 6 Key-Files paths (no Attributes/ folder, TestDataFactory in TestAuto.Scenarios, DataPattern enum inside ScenarioTypesAttribute.cs); add SelfManaged to DataPattern; RestSubjectArea = 8 members (add Data/ScenarioMgt/Monitor). (#51-56)

### ext-mode6-secret-provider-retire — dotnet-secret-provider
- **Kind**: ext | **Score**: 8 | **Added**: 2026-07-11
- **Description**: RETIRE-OR-REWRITE DECISION: core class SecretManagementConfigurationProvider + AddWindowsSecretManagement + SecretConstants/SecretsVaultName + AddSecretManagementServices all 0 hits (gate-verified). Live secrets = DB-backed TestAutoSecrets (RegisterAllServices.LoadEntitySecrets + SecretStorageHelper), covered by testauto-secrets-management. Options: (a) delete skill folder + linker entry, (b) rewrite as thin pointer to testauto-secrets-management. (#8-10)

### ext-mode6-config-validation — testauto-config-validation
- **Kind**: ext | **Score**: 7 | **Added**: 2026-07-11
- **Description**: 3 fixes: ValidateAsync→ValidateConfigurationAsync; redraw validator hierarchy (ScenarioConfigurationValidator composes 7 section validators directly; BaseValidator only under WorkloadConfigurationValidator; CrossFieldValidator wired separately); RecordsPerBatch→NumberOfGeneratedTestRecordsPerBatch. (#1-3)

### ext-mode6-test-data-generation — testauto-test-data-generation
- **Kind**: ext | **Score**: 7 | **Added**: 2026-07-11
- **Description**: Rebuild scenario→TestDataType mapping table from live [ScenarioTypes] attrs (7 wrong rows incl. deleted Continuous/LubcMatchingScenario); fix ITestData example to Initialize(ScenarioConfiguration) + List<Record> GetRecords(int,int). (#48-49)

### ext-mode6-scenario-types-attribute — testauto-scenario-types-attribute
- **Kind**: ext | **Score**: 7 | **Added**: 2026-07-11
- **Description**: 3 fixes: MetricDetailConnectExecutionApi→MetricDetailConnectApiExecution; remove nonexistent Metadata RestSubjectArea row (metadata uses Profisee) + complete real members; add ConnectStrategyPolling/ConnectPostRunCollection to CustomParmsEditorType table. (#70-72)

### ext-mode6-connex-provider-templates — testauto-connex-provider-templates
- **Kind**: ext | **Score**: 7 | **Added**: 2026-07-11
- **Description**: Flatten ALL step examples — no nested "ConnExStep":{} wrapper (fields flat on step per ConnExStep.cs + serializer.Populate + shipped sample); csproj copy = existing None Update="Scripts\**\*" Always rule (don't instruct Content Include). (#40-41)

### ext-mode6-project — testauto-project
- **Kind**: ext | **Score**: 7 | **Added**: 2026-07-11
- **Description**: 4 fixes: remove ValidationLogRepository.cs from Repositories listing; DynamicServerManager → TestAuto.Scenarios.BatchProcessing; fix TestAuto.Shared.Rest row (IRestClient in .Interfaces, RestApiKey is a property not a type); TestAuto.Web direct deps = Commands/Matching/Metrics/Shared/Shared.Security/Shared.Http/DependencyInjection (Scenarios transitive). (#28-31)

### ext-mode6-logging-schema — dotnet-logging-schema
- **Kind**: ext | **Score**: 7 | **Added**: 2026-07-11
- **Description**: 4 fixes: Serilog block DOES exist in appsettings (MinimumLevel + overrides, honored via ReadFrom.Configuration); MinimumLogLevel default = Warning not Information; no Console sink (console via *AndConsole helpers); LoggingServiceExtensions ≠ LoggingExtensions (TestAuto adds EnableHttpRequestLogging override + startup Seq logging). (#23-26)

### ext-mode6-matching-scenarios — testauto-matching-scenarios
- **Kind**: ext | **Score**: 6 | **Added**: 2026-07-11
- **Description**: 3 fixes: ShowScenario3A => IsLookupOnly (clause removed); RecordMix = List<(Record,string RecordType)> (RecordMixItem doesn't exist); fix ASCII source-system block (20=Dynamics, 30=JDE, 40=SalesForce; RetailClient=SS 1/2/3). (#33-35)

### ext-mode6-matching-strategy-pattern — testauto-matching-strategy-pattern
- **Kind**: ext | **Score**: 6 | **Added**: 2026-07-11
- **Description**: 2 fixes: RecordSource modes = ExistingMatchedOnly/NewValuesOnly/Mixed (+per-SS distribution), no ChangedOnly/Cloned; 3B=LookupOnly, 3C=LookupThenCreate per shipped configs (note executor-comment discrepancy). (#36-37)

### ext-mode6-utilities-module — testauto-utilities-module
- **Kind**: ext | **Score**: 6 | **Added**: 2026-07-11
- **Description**: 2 fixes: TextTruncationHelper has 0 production usages (executors use private TruncateForMetrics(text,max)) — CORRECTS SECTION ADDED BY 2026-07-10 AUDIT; ScriptDiscoveryService lives in Helpers/ not Services/. (#79-80)

### ext-mode6-local-setup — testauto-local-setup
- **Kind**: ext | **Score**: 6 | **Added**: 2026-07-11
- **Description**: 2 fixes: RegisterAllServices has no startHangfireServer param; config key = FeatureFlags:PreloadReferenceDataCache not Features:. (#12-13)

### ext-mode6-secrets-management — testauto-secrets-management
- **Kind**: ext | **Score**: 6 | **Added**: 2026-07-11
- **Description**: Pre-compression guard = 16000 chars (MaxPlaintextLength, old 8000 cap removed; 4000 post-encryption check authoritative). (#11)

### ext-mode6-blazor-icons — blazor-icons
- **Kind**: ext | **Score**: 6 | **Added**: 2026-07-11
- **Description**: Replace LegacyToMaterial table with the real 21 entries (drop phantom diagram-3/box-arrow-up-right/trash/pie-chart — 0 hits; those names would render as literal text); also purge the 4 phantom names from the frontmatter description. (#15)

### ext-mode6-ui-patterns — testauto-ui-patterns
- **Kind**: ext | **Score**: 6 | **Added**: 2026-07-11
- **Description**: 3 fixes: remove Template_Scenario4 row (0 hits, replaced by UnifiedMatchingPostRunCollectionScenario); ScenarioDetailItem → Components/Common/ScenarioDetailItem.cs; WorkflowStepInfo → Components/Controls/StepLinkingEditor.razor.cs. (#16-18)

### ext-mode6-record-repository — testauto-record-repository
- **Kind**: ext | **Score**: 6 | **Added**: 2026-07-11
- **Description**: 2 fixes: WebEntityRepository→WebUiRepository (table + DI snippet, registered in WebModuleRegistrar.cs:40); remove 3 fictitious repository rows (IMatchingRepository/IMetricsRepository/IRecordsRepository — all 0 hits). (#45-46)

### ext-mode6-log-tags — testauto-log-tags
- **Kind**: ext | **Score**: 5 | **Added**: 2026-07-11
- **Description**: 2 example fixes: LogConstants.Phase3 (no such member) → real member; LogTagConstants.Jobs → BatchOrchestrator. (#21-22)

### ext-mode6-http-facades — testauto-http-facades
- **Kind**: ext | **Score**: 5 | **Added**: 2026-07-11
- **Description**: 2 fixes: ApiKeyHandler logs Debug not Warning; {status,error} JObject only from non-generic overload (generic returns null content on non-2xx). (#42-43)

### ext-mode6-scenario-catalog — testauto-scenario-catalog
- **Kind**: ext | **Score**: 5 | **Added**: 2026-07-11
- **Description**: 2 fixes: metadata Action matching is case-INsensitive (ToLowerInvariant vs lowercase constants); remove GenerateTestRecords() row (0 hits; real = ProcessBatchAsync/ProcessBatchRecordAsync). (#63-64)

### ext-mode6-debugging-common-failures — testauto-debugging-common-failures
- **Kind**: ext | **Score**: 5 | **Added**: 2026-07-11
- **Description**: 2 fixes: RecordPoolRepository ctor = (connStr, RecordPoolConfiguration, ILogger) 3-arg; MatchingModuleRegistrar comment lines now 35-48, no IMatchingActivityMonitorService mention. (#61-62)

### ext-mode6-metadata-model-import — testauto-metadata-model-import
- **Kind**: ext | **Score**: 5 | **Added**: 2026-07-11
- **Description**: Interface section: GenerateInsertScript returns commented placeholder when records empty, never empty string (skill's §4 already correct). (#73)

### ext-mode6-batch-orchestration — testauto-batch-orchestration
- **Kind**: ext | **Score**: 5 | **Added**: 2026-07-11
- **Description**: 2 fixes: DataPattern.Other is legacy option behaving like Paged, NOT enum default (default(0)=Single; orchestrator falls back to Paged); replace deleted ExecuteStrategyScenario example. (#38-39)

### ext-mode6-custom-parm-editor — custom-parm-editor
- **Kind**: ext | **Score**: 5 | **Added**: 2026-07-11
- **Description**: 2 fixes: routing = HttpRequestStep→HttpRequestStepEditorCard (CurlStepEditorCard renamed away); drop/update UnifiedMatchingScenarioEditor line counts (256/.razor, 1178/.razor.cs). (#4-5)

### ext-mode6-metric-detail-builder — testauto-metric-detail-builder
- **Kind**: ext | **Score**: 5 | **Added**: 2026-07-11
- **Description**: Reword 2 pitfalls: detail type = 2nd typeof arg of [ScenarioTypes], not a [MetricDetailType("...")] attribute (0 hits) / DetailTypeName is a runtime string property. (#57)

### ext-mode6-testing-patterns — testauto-testing-patterns
- **Kind**: ext | **Score**: 5 | **Added**: 2026-07-11
- **Description**: Remove startHangfireServer:false from both RegisterAllServices examples (param doesn't exist; BaseTest.cs:57 form). (#60)

### ext-mode6-odata-query-building — testauto-odata-query-building
- **Kind**: ext | **Score**: 4 | **Added**: 2026-07-11
- **Description**: AddQueryParams(dict)→WithQueryParameters(dict) (+AddQueryParameter(key,value)). (#44)

### ext-mode6-small-fixes-a — testauto-custom-parm-defaults, dotnet-service-registration, testauto-tech-stack
- **Kind**: ext | **Score**: 4 | **Added**: 2026-07-11
- **Description**: Three one-liners: split ScenarioBaseCrud row (consumes RecordsCustomParms, not RecordsConstants) (#6); split reg-step-10 row (SecurityUtility unconditional, only MachineSecretService guarded) (#27); tech-stack Secrets row → TestAutoSecrets DB-backed store (#7).

### ext-mode6-small-fixes-b — testauto-stewardship-scenario-pattern, testauto-enrichment-generators, testauto-lookup-cache-pattern, matching-api-status-poller
- **Kind**: ext | **Score**: 4 | **Added**: 2026-07-11
- **Description**: Four one-liners: sample JSON "DomainAttibutes"→"DomainAttributes" (#69); SSNFieldGenerator/DOBFieldGenerator→SsnFieldGenerator/DobFieldGenerator (#50); GetScenarioCodeAsync/GetExecutionStatusCodeAsync are concrete-only, not on ILookupCacheService (#47); poller invoked from MatchingStrategyPollingScenario.ProcessBatchAsync not WaitForStrategyToCompleteAsync (#32).

### ext-mode6-small-fixes-c — testauto-help-docs, testauto-scenario-version-history, testauto-snapshot-capture, testauto-resource-collection, testauto-cli-command-pattern, testauto-deployed-machine-diagnostics
- **Kind**: ext | **Score**: 4 | **Added**: 2026-07-11
- **Description**: Six one-liners: testauto-help-docs.js→help-docs.js (#19); versioning registration → WebModuleRegistrar.cs:93 (#20); snapshot ref attr = UnifiedMatchingApiExecutionRunProfile (constant VALUE) (#58); seed success = recordsFailed==0 not recordsCreated==3 (#59); remove --outputFile from client options (#81); diagnostics sections renumber + add Firewall/Seq (#14).

### 2026-07-11 (out-of-band — user authorized fixing the scan's informational repo items)

- **UtilityStepTypeInfo.cs doc-comment**: removed the phantom "Utility Command Test page" consumer claim (sole consumer verified = `UtilityScenarioEditor`); closes the informational note carried since the 2026-07-01 session.
- **TestAuto.Samples orphaned trap files**: deleted `TestCases\Creates\CreateTestDataTest.json` + `TestCases\Metadata\MetadataManagementAddPData.json` (schema consumed by nothing; documented NRE trap) and the now-empty directory tree; updated `CreateTestDataTest.cs` history comment to past tense and removed the `TestAuto.Samples/` directory lines from `CompleteReference.md` (x2) + `00_SolutionInventory.md`. User stages/commits. NOT touched (adjacent, pre-existing): unconsumed duplicate `TestAuto.Metadata\Samples\TestCases\MetadataManagementAddPData.json`; `[Ignore]`d `RestUrlManagementTests.TestRestWithRealConfig` helper path to already-missing `TestAuto.Samples\TestCases\Gets\GetRecordByCodeTest.json`; stale `AttributeDrivenMetricsGuide.md:299` ref to `TestAuto.Samples/TestCases/Matching/LubcMatching.json`.

### 2026-07-11 (Mode 1 — FULL repo re-scan, 7-agent subsystem fan-out, baseline 00241476)

- **new-testauto-custom-parm-defaults** (9) → created `testauto-custom-parm-defaults`: the [CustomParm]/CustomParmDictionaryHelper.BuildDictionary defaults mechanism (key = attr.Key ?? prop name, overrides win), the per-domain parameter classes table (ConnectCustomParms, RecordsConstants, MatchingConstants, MetadataScenarioConstants), the three property idioms (identity/key-map/*Default), and the self-referential `=> nameof(X)` default trap → rule: REQUIRED params are plain const + RAW CustomParms read (ConnectCustomParms NOTE block + ConnectStrategyPollingScenario.ApplyConfiguration). Linker + junctions added (AI + Cursor).
- **new-testauto-scenario-reorder** (7) → created `testauto-scenario-reorder`: ScenarioReorder.Apply<T> semantics (multi-select single-block move preserving relative order, pinned front anchors, 1-based ToPosition clamped to the movable region, caller renumbers ExecutionOrder + marks dirty), who-pins-what table (execution editor pins completed/running; template editor isPinned:null), never-reimplement rule. Linker + junctions added (AI + Cursor).
- **ext-testauto-utilities-module-text-truncation** (8) → testauto-utilities-module: new "Output truncation before metrics/logging" section — the TextTruncationHelper ladder (metrics=4000/logging=1000/display=500/min=100), head+tail-preserving marker format, CombineAndTruncate/WouldBeTruncated, rule that all executors (six today, 41 call sites) and any new executor/metric field must bound output. Frontmatter trigger + source added.
- **ext-testauto-record-transformation-variantgenerator-rules** (7) → testauto-record-transformation: CORRECTNESS FIX — added warning that the Tier-1 rule table is MutationTransformer-ONLY, new "VariantGenerator — the ACTIVE path for CloneAndMutateScenario" section with the two-column rule-vocabulary table (2=no-op, 4=SlightTypo, 5=synonym; 6+=no-op), deterministic per-variant seed (Code*31+idx), MaxAttributeChanges cap, group-blank constraint (AttributeGroups constrains blanking here, not correlation), and the SynonymHelper subsection (embedded SynonymList.<Category>.json, filename-stem key, first-occurrence case-insensitive swap, 50ms regex timeout, how to add a category). Frontmatter triggers + 3 sources added.
- **ext-testauto-scenario-config-store-save-idempotency** (7) → testauto-scenario-config-store: new "Consumer Save-Path Convention" section — pre-assign Guid.NewGuid() as owner Code at add/copy time (chunks + record create key off it → idempotent retry), 8603-already-exists-for-our-code = success (adopt rows, clear IsNew, self-heal), fail-soft per row + empty-Code chunk guard. Frontmatter trigger + WorkflowScenariosEditor source added; cross-linked memory project_workflow_copy_duplicate_save_bug.
- **ext-testauto-connex-service-strategy-name-filter** (6) → testauto-connex-service: FindLatestBatchByStrategyNameAsync row now carries the UNVERIFIED JsonBatchStrategyNameField="Name" caveat — wrong attr → silent null in both consumers → "no batch found for strategy"; debug path = verify against $metadata then change ConnectConstants.cs:27-31.
- **ext-workflow-skills-workload-ui-label** (6) → testauto-workflow-execution, testauto-workflow-transfer, testauto-workflow-export, testauto-project: added the "UI terminology (2026-07)" note under each H1 — UI labels say "Workloads" but ALL code identifiers/routes/entities/config keys remain Workflow*/WorkloadExecution* (verified UI-text-only via rename-commit diff).
- **desc-testauto-workflow-execution-auto-save** → testauto-workflow-execution: rewrote the stale "(no auto-save, unlike WorkflowScenariosEditor)" bullet — commit 00241476 added `await SaveAllChangesAsync()` after the InMemoryEditorResult apply, so the execution editor now auto-saves in-dialog edits (verified both sides by direct read).

### 2026-07-01 (out-of-band — user directed implementation of long-parked deferral)

- **ext-utility-step-type-info** (3) → testauto-utilities-module: promoted from Deferred at user request ("just implement it"). Added checklist step 9 (UI picker metadata) to "Adding a new step type" + a dedicated "Add-Step picker visual metadata — `UtilityStepTypeInfo`" subsection: the 5 static lookups (`GetIcon`/`GetDisplayName`/`GetDescription`/`GetAccentColor`/`GetBgColor`), keyed by `IReferenceDataCache.GetUtilityTypes()`, the alias folding that must mirror `AddExecutorAlias`, and the silent fallback (play_circle/grey/raw-name) that makes registering metadata a real step not an error. Sole consumer verified = `UtilityScenarioEditor` (not a separate file). Frontmatter trigger + 2 Sources added, cross-linked [[blazor-icons]]. **Informational (not fixed — read-only repo):** the class doc-comment `UtilityStepTypeInfo.cs:6-7` still claims a "Utility Command Test page" consumer that does not exist; the skill documents the accurate single consumer instead.

### 2026-07-01 (Mode 1 — baseline 838dad3e..e085c6ba diff scan)

- **ext-connex-import-tokenization-runtime-json-escape** (9) → connex-import-tokenization: rewrote the "Escaping (important)" section into **two escape points in time** — (1) import time escapes LITERAL values (`ArtifactTokenizer.Escape`); (2) run time escapes config/secret/template-RESOLVED values, which are only `{{$config:...}}` tokens at import so `ArtifactTokenizer.Escape` never sees them. `UtilityOrchestrator` now calls `ResolveSpecialParameterValues(mergedParams, escapeForJson: step is ConnExStep)` and `ParameterResolver.EscapeForJsonStringLiteral` (kept identical to `ArtifactTokenizer.Escape`) escapes the resolved value; ConnEx-only (SQL/PS/Curl/CLU consume raw); literal params skipped → no double-escape. Fixed the stale single-arg signature at :209, added test source + escapeForJson annotations to Sources, cross-linked memory `project_connex_runasuser_json_escape`. Verified `ConnExStep` + `ArtifactTokenizer` exist in live code; 4 new regression tests confirm behavior.
- **hyg-utilities-module-resolvespecialparams-signature** → testauto-utilities-module: updated the stale `ResolveSpecialParameterValues(IDictionary<string,string>)` signature (:125) → `(…, bool escapeForJson = false)` with an escapeForJson/no-double-escape note, and the run-time orchestrator call (:136) → `ResolveSpecialParameterValues(mergedParams, escapeForJson: step is ConnExStep)` with the ConnEx-vs-SQL/PS/Curl rationale; cross-linked `[[connex-import-tokenization]]` for the full why.

### 2026-06-30 (Mode 1 — baseline d3d9b740..838dad3e diff scan)

- **new-external-json-case-insensitive-reads** (10) → created `external-json-case-insensitive-reads`: the standing convention for reading EXTERNAL JSON case-insensitively — `JTokenCaseInsensitiveExtensions` (`GetValueCI`/`ValueCI<T>`/`SelectTokenCI`), `GatewayJsonKeys` shared constants + private nested `…Keys` classes for subsystem keys, the "never raw indexer/SelectToken, keys as constants" rule, before/after examples (MonitorActivityCollector, EntityJsonConverter, CreatedRecordsResponseExtensions), anti-pattern table. Replaces the ~26-file `Value<T>("code") ?? Value<T>("Code")` fallback. Linker + junctions added (AI + Cursor). Coverage probe: 0 corpus hits; `json-formatting-conventions` is format-only.
- **ext-metadata-model-import-harvest-noise-strip** (7) → testauto-metadata-model-import: rewrote the `ProjectRecordsForCreate` description (now drops `$`-fields, `ReadOnlyRecordFields` read-only/computed fields, nested objects/arrays, and JSON nulls; detects code case-insensitively — the capitalized `"Code"` match silently produced empty `[]` → 400), documented recursive `HarvestNoiseFields` strip, added both constants to the `MetadataImportConstants` table, cross-linked the new skill. Verified against the live `ModelMetadataHarvester` diff.
- **ext-multistep-steps-passfail-error-detail** (6) → testauto-multistep-steps: extended the `AutoWrapPassFailCode` note — CATCH now captures `ERROR_MESSAGE()` and surfaces it two ways (severity-10 `RAISERROR … WITH NOWAIT` → InfoMessage/Serilog live; second SELECT column → `StepExecutionResult.PassFailErrorDetail` appended to `ErrorMessage`). Verified against the live `SqlScriptExecutor` diff.

### 2026-06-26 (Mode 1 — baseline 99743062..d3d9b740 diff scan)

- **0 candidates.** Single commit `d3d9b740` "Fix old messages" (2 files, net −22 lines) removed the stale 4000-char / "will switch to file mode" warning UI from `HttpRequestStepEditorCard.razor(.cs)`. This is the UI tail of the already-implemented chunked config store (CHUNKREF, large bodies chunk instead of throwing) + file-reference retirement ("file mode" retired). Below the 3+-file reusable threshold → no new/ext skill. Coverage probe: no skill references `HttpRequestStepEditorCard`; all "4000"/`BodyFilePath`/"file mode" mentions across 9 skills (`testauto-multistep-steps`, `testauto-scenario-config-store`, `testauto-config-store-migration`, `testauto-utilities-module`, `testauto-scenario-display`, etc.) already accurately describe the retirement — no stale `desc`/`hyg` fix needed.

### 2026-06-25 (Mode 1 — baseline c029c3bf..99743062 diff scan)

- **new-scenario-config-store** (10) → created `testauto-scenario-config-store`: `IScenarioConfigStore` chunked persistence (inline ≤3900 / CHUNKREF chunks), the no-data-loss write order, dangling-chunk throw, ConfigOwnerType, DI. Linker + junctions added.
- **new-workflow-transfer** (10) → created `testauto-workflow-transfer`: `WorkflowTransferService`/`WorkflowBundle` cross-machine export/import, all-or-nothing export, always-new import + config re-binding, 207 handling, transfer-vs-export table. Linker + junctions added.
- **new-config-store-migration** (9) → created `testauto-config-store-migration` (kept standalone, not folded): `ConfigurationMigrationJob` Convert→Audit deploy gate, idempotency guard (`HasRemainingBodyFilePath`), bodyFilePath inlining + `TryRecoverUnderScriptRoot`, RepairResult counters, audit chunk-integrity pre-check. Linker + junctions added.
- **desc-multistep-steps-file-reference-retirement** → testauto-multistep-steps: removed/rewrote all `ScriptKey`/`BodyFilePath`/`ScriptPath` sites (frontmatter, props tables, "ScriptKey vs Inline" section, SQL/PS/HTTP examples + key notes) to inline-only; **kept** `ScriptContent`/`SqlScript`/`Body`/`Command` (verified live in DTOs — `ScriptContent` is NOT stale). Verified retirement via DTO read + repo grep.
- **desc-metadata-model-import-artifact-storage** → testauto-metadata-model-import: deleted §7 (IMetadataArtifactStorage), rewrote §5 body-sizing to `_store.PersistAsync` (verified in ModelImportScenarioFactory.EmitOneAsync), updated overview/cross-links/sources.
- **ext-configuration-compression-codec-chunking** (7) → configuration-compression-codec: added "Relationship to the Chunked Config Store (CHUNKREF)" section + frontmatter trigger; codec is now the legacy read-path while new scenario-config writes chunk.
- **ext-scenario-config-inspector-chunks** (6) → scenario-config-inspector: added "Chunked configs (CHUNKREF)" reassembly section (parse → query by GroupKey → order by Seq → concat) + dangling-chunk caveat + frontmatter trigger.
- **desc-scenario-display-file-step-methods** → testauto-scenario-display: removed `GetFileStepCount`/`GetFilesTooltip`/`GetFileStepsBadgeStyle` (0 repo hits) from derived-props list + 3 tables; added file-step-display-removed note.
- **hyg-utilities-module-scriptlocator-citation** → testauto-utilities-module: was bigger than a dangling citation — rewrote the whole "Scripts and ScriptKey" section (ScriptLocator/IScriptLocator deleted, runtime ScriptKey resolution retired, steps inline-only) while preserving still-valid `ScriptDirectoryOptions.ResolveRelativePath` (used by migration recovery); fixed frontmatter/when-to-use/tables/sources. Scope expanded per the item's own "annotate or correct" note + verification gate.
- _Also_: added back-reference in testauto-workflow-export → testauto-workflow-transfer (sub-finding of new-workflow-transfer).

### 2026-06-21 (Mode 1 — baseline 01e15a9..c029c3bf diff scan)

- **ext-testauto-testing-patterns-read-after-write-retry** (8) → testauto-testing-patterns: new "Read-after-write retry (commit-visibility latency)" section documenting `TestRetry.PollUntilNotNullAsync` + frontmatter trigger + Sources. Src: TestRetry.cs, BaseTest.cs.
- **ext-testauto-testing-patterns-cross-assembly-runsettings** (7) → testauto-testing-patterns: new "Cross-assembly contention (VS Run All)" subsection with the MaxCpuCount=1 solution-wide runsettings recipe + frontmatter trigger + Sources. Src: speed-merchants.runsettings.
- **ext-dotnet-domain-values-empty-domain-guard** (6) → dotnet-domain-values: new "Gotcha: an attribute key can be present with an EMPTY value list" subsection + populated-attributes filter example. Src: CloneAndMutateRecords.cs, StewardshipFilterRecords.cs.
- **ext-testauto-metric-detail-builder-no-shadow** (6) → testauto-metric-detail-builder: added Named Pitfalls row for shadowing a [MetricColumn]-mapped base property. Src: UtilityStepDetail.cs.
- **hyg-connex-import-tokenization-dangling-spec** → connex-import-tokenization: annotated the SKILL.md:254 citation to the deleted design spec (source removed 2026-06-21; skill now canonical).
- **desc-testauto-multistep-steps-createnowindow** (2) → testauto-multistep-steps: VERIFIED against CommandLineExecutor.cs (UseShellExecute=false always; UseShell only wraps in cmd/pwsh/sh). Skill line 1166 was genuinely inaccurate ("when UseShell: false") — corrected to "regardless of the UseShell setting." Turned from a defer/exclude candidate into a confirmed correctness fix.

_Earlier history: log cleared 2026-06-20 during backlog cleanup. Across 2026-05-19 → 2026-06-20 the audit implemented 90+ items spanning the TestAuto skill corpus. Recover detail from Obsidian file-version history if needed._

## Implemented 2026-09-09 — Mode 1 item detail (all 33 APPLIED)

_Applied in one session. **8 corrections first, then 6 new skills, then 10 extensions, then 12 description expansions on the extended skills** — corrections before additions, because four of them were actively misleading and one documented a path-traversal guard that no longer held._

**Structural decisions taken by Gene during the pass:** the two TestData products share TWO skills with per-product tables rather than four separate ones (the structural-vs-procedural contrast in how each keeps a connection string out of its artefacts is itself the content); and nested workloads got a NEW skill rather than an extension.

**Two stale-path breakages found and fixed, both pre-existing and both invisible until exercised:**
1. All eleven configured input paths in the `skill-audit-with-update` skill pointed at the retired `{AIWorkRoot}` root. The consequence was not cosmetic: reading the backlog through the dead path returned *absent*, i.e. the session read as a FIRST RUN, and a Mode 1 pass would have rebuilt the backlog from scratch and re-proposed candidates settled a month earlier.
2. `link-to-ai.ps1`'s `$sourceBase` pointed at the same dead root, so the linker reported **MISSING source folder** for every entry and **322 drift issues** — it had been unable to see the corpus at all. The 153 existing junctions resolve to `Q:` and were therefore not created by the linker in its current state.

**Verification notes worth keeping — twice the orchestrator's own grep was the faulty party, not an agent:** `HangfireUnavailableFallbacks` returned 0 hits because the FILE carries that name while the CLASS inside is `HangfireUnavailable`; and an `awk` enum range truncated at a doc comment and undercounted `StepCapability` as 7 when it holds 9. Both are the filename-vs-classname trap. **One agent claim was corrected:** the installer web-port subsystem is NOT identical across the two installers — TestAuto patches `appsettings.json` itself because the shipped file arrives fresh every upgrade, while CrewChief writes the `appsettings.Production.json` overlay it creates once. Written up as "identical", that would have sent an agent to patch a file the other installer never reads.

**Convergence:** four candidates were proposed twice under different names and were merged (`crewchief-library-folders`, the AdoBuild family, the token filter chain, nested workloads). `inno-setup-installer` was hit independently by three agents on the same finding — it said "sibling pair" where four installers and four build scripts exist.

### Corrections applied (8)

| Skill | Was | Now |
|---|---|---|
| `crewchief-file-persistence` | "The kebab check IS the guard" | TWO checks, with `FolderPath.ResolveUnder`'s root-containment assert named as load-bearing |
| `crewchief-file-persistence` | flat `<dataFolder>/<kind>/<name>` | optional nested folder segment, `SearchOption.AllDirectories` |
| `crewchief-file-persistence` | blanket `NullValueHandling.Ignore` rule | notes-field exception stated |
| `crewchief-capability-preflight` | "eight capabilities" (description AND heading) | **nine**, with a full `AdoBuild` row |
| `inno-setup-installer` | "sibling-pair … CrewChief and TestAuto" | four named products; title fixed |
| `inno-setup-installer` | Sources gloss "shortcuts-only, once-only appsettings" | service-default + always-refreshed, with why it mattered |
| `crewchief-web-ui` | "Three-mode value editors" | five-mode (six for `ServiceNameEditor`) |
| `crewchief-web-ui` | ref parsing "inline in each editor (local `RefRegex`)" | centralised `TokenShapes`; `RefRegex` is now zero hits |
| `crewchief-workload-and-runs` | asserted `IsUnreadable` is NOT on `WorkloadFile` | it IS; both meanings kept apart |
| `testauto-project` | inventory omitted the TestData.Generation projects | both added |

_Each correction carries a dated note saying what it previously claimed — deliberate, because an agent that read the old text and cached it needs to see the contradiction rather than a silent rewrite._

### New skills created (6)

`testdata-generation-and-mutation-engine` · `testdata-generation-and-mutation-shape-authoring` · `crewchief-library-folders` · `crewchief-platform-build-steps` · `crewchief-nested-workloads` · `testauto-crewchief-export`

### Skills extended (10)

`crewchief-token-replacement` (filter chains + clock + TokenShapes) · `crewchief-web-ui` (classifier, runtime readout, list-filter delegation) · `crewchief-connect-import` (reset emitters) · `inno-setup-installer` (four products + the OPPOSITE port write seams) · `testauto-hangfire-architecture` (the unavailable-fallback contract) · `crewchief-secrets` (`SecretsHostContext`) · `crewchief-file-persistence` (broken-file stub doctrine) · `testauto-help-docs` (per-host layout table, four hosts) · `testauto-connex-service` (page key-range spec) · plus the notes-field line above.

### Item detail

### new-testdata-mutation-shape-authoring — testdata-mutation-shape-authoring
- **Kind**: new
- **Target**: testdata-mutation-shape-authoring
- **Score**: 10
- **Description**: The mutation-shape JSON contract — a CLOSED set of 26 field kinds and 20 mutation rules, fixed bulk-copy column ordinals, the derived 3-letter child DISC, the `MUT:{Entity}|{table}` checkpoint key capped at 100 chars, un-ruled fields copying verbatim, and width traps (Gender+Typo overflows nvarchar(1) only at RUN time).
- **Sources**: `TestData.Mutation.Engine/Model/MutationShape.cs`, `Model/MutationShapeValidator.cs`, `Engine/Fields/PersonFieldPack.cs:6`, `Engine/Mutation/MutationRuleCatalog.cs:22-45`, `Engine/Sql/MutationSchemaBuilder.cs`, `Cli/Samples/RetailClientFlat.local.json`, `Web/Documentation/20_ShapeReference.md`
- **Added**: 2026-09-09
- **Notes**: Should defer to the in-repo `TestData.Mutation/Claude/CLAUDE.md` and the shipped /help docs rather than transcribing the key tables, or the two drift. Coverage probe: `MutationShape`/`FieldKind`/`must-merge`/`MutationLab` → 0 hits corpus-wide.

### new-testdata-mutation-determinism — testdata-mutation-determinism-contract
- **Kind**: new
- **Target**: testdata-mutation-determinism-contract
- **Score**: 10
- **Description**: Every generated value derives from (RandomSeed, code, column ordinal) through SplitMix64 — never `Random.Shared`, `Guid.NewGuid` or the clock. Three traps: SplitMix64 is a MUTABLE STRUCT so multi-draw generators must lift it to a local or re-draw the same state; eight "coherent" kinds read one per-row PersonIdentity so adding a field cannot shift a person; MutationPass skips NULL cells BELOW `Pick` so the selection draw is still spent and the stream stays a function of the shape, not the data.
- **Sources**: `Engine/Generation/SplitMix64.cs:3-6,31-40`, `Engine/Fields/FieldGenContext.cs:5-28`, `Engine/Fields/PersonIdentity.cs`, `Engine/Generation/MutationPass.cs`, `Engine/Mutation/MutationRuleCatalog.cs:9-14`, `Tests/Generation/FamilyCoherenceTests.cs`
- **Added**: 2026-09-09
- **Notes**: `SplitMix64`/`PersonIdentity`/`RandomSeed` → 0 hits. Generic "deterministic" hits 19 skills, none about seed derivation.

### new-testdata-mutation-run-orchestration — testdata-mutation-run-orchestration
- **Kind**: new
- **Target**: testdata-mutation-run-orchestration
- **Score**: 10
- **Description**: A 10-phase enum state machine reaching SQL through exactly three narrow seams (IBulkWriter / ICheckpointClient / ISchemaGate) so phase progression, chunk partitioning, per-chunk table order and the resume column guard are testable with no SQL Server. Resume semantics nobody guesses: rerunning IS the resume; a chunk checkpoints only after every table is written; a resume is REFUSED if a live table's column ordinals drifted; checkpoints are rows in shared `dbo.tGenerationChunk`/`tGenerationPhase` co-tenanted with the sibling tool and kept apart only by the `MUT:` prefix; a cancelled run is Stopped (exit 2), never Failed.
- **Sources**: `Engine/Generation/IBulkWriter.cs:10-18,60-79`, `Engine/Generation/MutationPhases.cs:3-26`, `Engine/Sql/ChunkCheckpointStore.cs:28-46`, `Engine/Generation/MutationOrchestrator.cs`, `Engine/Sql/MutationVerifier.cs`, `Tests/Generation/MutationOrchestratorTests.cs`
- **Added**: 2026-09-09
- **Notes**: `ChunkCheckpoint`/`tGenerationChunk`/`IBulkWriter`/`test-mode` → 0 hits. "resume" hits 13 skills, all a different mechanism.

### new-tdg-determinism-and-chunked-resume — tdg-determinism-and-chunked-resume
- **Kind**: new
- **Target**: tdg-determinism-and-chunked-resume
- **Score**: 10
- **Description**: TestData.Generation's two load-bearing invariants — values are a pure function of (RandomSeed, code, columnOrdinal) via SplitMix64.RowSeed→ColumnSeed with no clock ever feeding a value; and work is chunked on half-open code ranges that tile end-to-end, where EntityName IS the run identity so rerunning the same file *is* the resume and there is no resume flag. Deleting the shape file does not clear checkpoints. `SyntheticDataReader` implements only the 8 IDataReader members SqlBulkCopy calls and throws NotSupportedException on the rest deliberately.
- **Sources**: `TestData.Generation.Engine/Generation/SplitMix64.cs:31-39`, `Engine/Model/ChunkMap.cs:1-14`, `Engine/Sql/ChunkCheckpointStore.cs:1-40`, `Engine/Generation/SyntheticDataReader.cs:6-40`, `Engine/Generation/GenerationOrchestrator.cs:338-401`, `Tests/ChunkMapTests.cs`
- **Added**: 2026-09-09
- **Notes**: Sibling of the two TestData.Mutation determinism/orchestration candidates — decide whether the two products share one skill pair or get their own. `SplitMix64`/`tGenerationChunk`/`IDataReader` → 0 hits.

### new-tdg-shape-contract-and-validation — tdg-shape-contract-and-validation
- **Kind**: new
- **Target**: tdg-shape-contract-and-validation
- **Score**: 10
- **Description**: The shape-JSON → EntityPlan → DDL contract and its closed-enum refusal model. Fixed column ordinal order is the contract between SchemaBuilder's DDL and the bulk-copy reader; the optional IDENTITY Id sits outside it. TypeRules keys and generator names are closed sets sourced from GeneratorRegistry's own constants so validator and registry cannot drift. `Naming.ColumnNames` length must EQUAL its Shape count; a resolved `entity_column` lookup name is ≤50 chars; Code/Name/Dba are system-fixed nvarchar(250) because a Dba value IS an entity Code.
- **Sources**: `Engine/Model/ShapeValidator.cs:13-70`, `Engine/Model/EntityPlan.cs`, `Engine/Generation/GeneratorRegistry.cs`, `Engine/Naming/NamingSettings.cs`, `Engine/Sql/SchemaBuilder.cs`, `Tests/TestShapes.cs:5-58`
- **Added**: 2026-09-09
- **Notes**: The one `ShapeValidator` corpus hit is TestAuto's unrelated `ScenarioDataShapeValidator` — not coverage. Author as a pointer to the in-repo brief + shipped /help, not a transcription.

### new-tdg-deploy-package — tdg-deploy-package
- **Kind**: new
- **Target**: tdg-deploy-package
- **Score**: 10
- **Description**: How a generated SQL table becomes a Profisee model. Every gateway wire fact (endpoints, x-api-key, content type, batch sizes, attributeType/dataType enum codes, and the *capitalised* Record Code/Name keys that create accepts but GET returns lowercase) lives only in DeployConstants, and the two PS1 scripts are copied out of embedded resources VERBATIM with model.json as the contract — so a gateway question is a one-constant edit plus re-emit. DeployModelBuilder does bidirectional plan-vs-live-SQL drift detection and throws DeployModelDriftException → exit 1, with the IDENTITY Id exempt. Two mappings are knowingly lossy and ceilings are enforced at mapping time, not 120 attributes into a live deploy.
- **Sources**: `Engine/Deploy/DeployConstants.cs:1-111`, `Engine/Deploy/DeployManifestWriter.cs:5-15`, `Engine/Deploy/DeployModelBuilder.cs:88-131`, `Engine/Deploy/ProfiseeAttributeMapper.cs:6-22,72-95`, `Engine/Deploy/ISchemaReader.cs:6`
- **Added**: 2026-09-09
- **Notes**: Alternative target if you would rather not add a skill: extend `profisee-rest-api`, which has 0 hits for the v1/Entities+v1/Attributes batch and enum-code specifics used here. INFORMATIONAL: `DeployConstants.cs:38-41` cites `{ScratchRoot}\deploy-wire-check.md` as the provenance for the wire facts — machine-local, so unverifiable from a clean checkout.

### new-crewchief-library-folders — crewchief-library-folders
- **Kind**: new
- **Target**: crewchief-library-folders
- **Score**: 10
- **Description**: **MERGED — proposed independently by two agents.** The step/workload libraries are no longer flat. Three rules an agent will get wrong: names stay GLOBALLY unique, so two files claiming one name are resolved by LibraryFolderIndex's shadow verdict (shallowest wins, ties Ordinal, losers still returned carrying the winner's path so a duplicate is badged not hidden); empty folders cannot exist in a file-derived index, so LibraryFolderCatalog persists an additive-only vocabulary at `folders/<library>.json` with explicit-ancestor and union-with-disk rules ("never authoritative for absence"); and Steps and Workloads have DELIBERATELY SEPARATE folder lists exposed as IStepFolderService / IWorkloadFolderService markers you must inject instead of ILibraryFolderService.
- **Sources**: `CrewChief.Data/Stores/FolderPath.cs:8-18,150`, `Stores/LibraryFolderIndex.cs:17,29-78`, `Stores/LibraryFolderCatalog.cs:11-42,263-284`, `Services/LibraryFolderService.cs:47-197`, `CrewChief.Web/Components/Controls/FolderTree.razor`, `Components/Pages/FolderFilter.cs:28-46`
- **Added**: 2026-09-09
- **Notes**: Pairs with `hyg-crewchief-file-persistence-path-guard` — that skill's flat path and "kebab check IS the guard" rows are the stale half of this change. Corroborated by the existing memory note `project_crewchief_separate_folder_lists`.

### new-crewchief-platform-build-steps — crewchief-platform-build-steps
- **Kind**: new
- **Target**: crewchief-platform-build-steps
- **Score**: 10
- **Description**: **MERGED — proposed by two agents as `crewchief-platform-build-steps` and `crewchief-ado-build-pipeline`.** A four-stage step family (AdoBuildDownload → BuildUnzip → BuildVerify → BuildPublish) whose entire contract is a MARKER FILE, because CrewChief has no step-output-to-step-input piping: stage 1 writes `latest-download.json`, every later stage takes ONLY the download directory and reads build identity back, so a build finishing mid-workload cannot switch what is extracted. A fresh download must RESET unzippedUtc/verified or a new zip inherits the old build's verified flag and publishes unchecked; a corrupt marker reads as "nothing known", never "we have it". Publish is robocopy /MIR gated solely on verified:true. AdoBuildClient pins api-version 7.1, Basic auth over base64(":<PAT>"), and an INFINITE HttpClient timeout deliberately (the 100s default aborts every real ~423 MB download) with the step's timeoutSeconds as the only clock.
- **Sources**: `CrewChief.Engine/Services/BuildDownloadMarker.cs:8-24,98-186`, `Services/AdoBuildClient.cs:14-41`, `Executors/{AdoBuildDownload,BuildUnzip,BuildVerify,BuildPublish}Executor.cs`, `Steps/AdoBuildDownloadStep.cs`, `Capabilities/Probers/AdoBuildProber.cs`, `Web/Documentation/53_-56_StepGuide*.md`
- **Added**: 2026-09-09
- **Notes**: Ties to `desc-crewchief-capability-preflight` — AdoBuild is the ninth capability that skill still calls "eight".

### ext-crewchief-token-replacement — crewchief-token-replacement
- **Kind**: ext
- **Target**: crewchief-token-replacement (new `references/filters.md`)
- **Score**: 10
- **Description**: **MERGED — proposed by two agents.** Tokens now carry a PIPE FILTER CHAIN and CLOCK SOURCES — `{{$now|addDays:7|date:yyyy-MM-dd}}`. 24 named filters with declared arity (arity decides comma-splitting; `date` args are verbatim), values staying DateTimeOffset-typed across stages, a static ValidateChain that runs with no params/config/clock so the editor blocks a bad filter at SAVE time, a purity requirement because resolution evaluates every token TWICE, IRunClock's freeze scope as the only sanctioned clock read, backslash escaping owned solely by TokenFilters.EscapeArgument, and TokenShapes as the single owner of the `{{...}}` regex (it exists because an audit found 3 copies of the token regex, 5 of `$config`, and 7 mutually incompatible `$ref` parsers).
- **Sources**: `CrewChief.Engine/Services/TokenFilters.cs:9-65,232,680-772`, `Services/TokenShapes.cs:8-20,77,131,289`, `Services/TokenComposition.cs:9-45,315-377`, `Services/RunClock.cs`, `Web/Components/Controls/DateMathFilters.cs:6-18`, `Tests.Unit/Engine/TokenFilterTests.cs`
- **Added**: 2026-09-09
- **Notes**: Corpus: `TokenFilters`/`TokenComposition` → 0; `TokenShapes` → 1 passing mention only. The skill owns the token grammar, so this is a gap inside its own subject.

### ext-crewchief-web-ui-value-editors — crewchief-web-ui
- **Kind**: ext
- **Target**: crewchief-web-ui ("Three-mode value editors" section)
- **Score**: 10
- **Description**: The value editors are now FIVE-mode (Literal/Parameter/Secret/Reference/Builder) driven by one shared classifier, plus three surfaces the skill has no notion of: ValueSourceClassifier (the single ordered value→source decision, deliberately one copy so the tab choice and the parameter-grid row colours can never disagree), ValueBuilder + ValueSourceTabs (compose segments + filter chains), and a read-only runtime readout (ValuePreviewService → ValuePreviewCell / RuntimeValueChip) that masks secrets, uses a CSS-only popover so it survives a reconnecting circuit, and copies exactly what is displayed.
- **Sources**: `CrewChief.Web/Components/Controls/ValueSourceClassifier.cs:29-60`, `Controls/SecretValueEditor.razor:207-217`, `Controls/ServerNameEditor.razor:167`, `Controls/ServiceNameEditor.razor:202`, `Services/ValuePreviewService.cs:12-45`, `Controls/RuntimeValueChip.razor:5-30` (17 files reference the family)
- **Added**: 2026-09-09
- **Notes**: Verified: `ValueSourceClassifier` 8 code files / 0 corpus. Pairs with `desc-crewchief-web-ui` and `hyg-crewchief-web-ui-refregex`.

### ext-crewchief-connect-import-reset — crewchief-connect-import
- **Kind**: ext
- **Target**: crewchief-connect-import
- **Score**: 10
- **Description**: The skill stops at IConnectImportEmitter. A whole reset-workload family was added: IEntityResetEmitter + IDatastoreResetEmitter with per-datastore "shapes" resolved through DatastoreResetEmitterRegistry by substring-matching `Configuration.$type` (short type name, because Newtonsoft `$type` carries assembly identity); emitters are pure and return failure results rather than throwing; an unknown datastore is an explicit Unsupported+reason; shapes are EXPLICIT inputs from a separate model export because the strategy artifact carries mapping expressions only; naming is `<base>-reset-entities` / `-reset-datastore` / `-full-run`.
- **Sources**: `CrewChief.Web/Services/ConnectImport/IDatastoreResetEmitter.cs:6-63`, `ConnectImport/DatastoreResetEmitterRegistry.cs:6-22,60-83`, `ConnectImport/IResetWorkloadEmitter.cs:6-60`, `ConnectImport/ResetShapeBuilder.cs`, `Tests.Unit/Web/DatastoreResetEmitterTests.cs`
- **Added**: 2026-09-09
- **Notes**: `IDatastoreResetEmitter`/`ResetShapeBuilder`/`ResetWorkloadEmitter` → 0 hits corpus-wide.

### new-testauto-crewchief-export — testauto-crewchief-export
- **Kind**: new
- **Target**: testauto-crewchief-export
- **Score**: 10
- **Description**: TestAuto.Web can emit a CrewChief-importable `<name>.workload-bundle.json` from a MultiStepUtility workflow. Three doctrines an agent cannot infer: TestAuto.Web must NEVER reference a CrewChief assembly — the bundle/step-type types are hand-written mirrors whose wire shape is pinned only by literal shape tests, so compiler drift is impossible to catch; a fixed rule catalogue R1–R7 with a two-state severity model (Incompatible = scenario disabled / step silently dropped, no operator override; Warning = proceed) and MonitorStep as a permanent never-to-be-filled exclusion; and parameter hoisting where a key is global-safe iff it has exactly one distinct value across the CURRENT selection, keys matched OrdinalIgnoreCase but values Ordinal, with ParameterClassification a pure recompute so deselecting a definer IS conflict resolution.
- **Sources**: `TestAuto.Web/Services/CrewChiefExport/CrewChiefWorkloadBundle.cs:12-28`, `CrewChiefExport/CrewChiefStepTypes.cs:32-68`, `CrewChiefExport/ExportPreflight.cs:39-70,106-113`, `CrewChiefExport/ExportAnalysis.cs:266-273,334-374`, `Components/Controls/CrewChiefExportWizard.razor.cs`, 5 test files under `Testing.SpeedMerchants.Unit/Tests/Web/Services/CrewChiefExport/`
- **Added**: 2026-09-09
- **Notes**: Verified 3–4 code files per identifier, 0 corpus hits. `crewchief-workload-transfer` documents `WorkloadBundle` on the RECEIVING side only and knows nothing of the mirror rule, R1–R7 or hoisting — cross-link the two rather than folding in.

### ext-inno-setup-installer-four-products — inno-setup-installer
- **Kind**: ext
- **Target**: inno-setup-installer
- **Score**: 10
- **Description**: **MERGED — hit independently by three agents, and the orchestrator corrected one claim.** There are FOUR installers and four build scripts, not a sibling pair: CrewChief.iss, TestAuto.iss, TestDataGeneration.iss, DataGenerationAndMutation.iss (verified by `find`). Adds: an operator-chosen HTTP web port that is chosen once then LOCKED (fresh install = wizard field + `/PORT=`; existing install = disabled field showing the current port and `/PORT=` ignored with a log line); **the write seams are deliberately OPPOSITE — TestAuto patches `appsettings.json` ITSELF post-[Files]/pre-service-start via ApplyWebPortToAppSettings because the shipped file arrives fresh every upgrade, while CrewChief writes `appsettings.Production.json`, the overlay created ONCE and never overwritten**; `--urls`/`ASPNETCORE_URLS` cannot help because Program.cs configures Kestrel from `WebUI:HttpPort`; `[INI]`/`[Run]` cannot call a function so the port reaches them only via scripted constants, and Inno has no forward declarations so those must be declared below ChosenPort; the cross-tool port allocation table (5030/5031, 8080/8443, 5045/5046, 5047/5048 — 5040 avoided because svchost binds it); first-install-only port read back on upgrade via `sc qc`/ParsePortFromBinPath; samples shipped `onlyifdoesntexist uninsneveruninstall`; HTTPS deliberately NOT configurable.
- **Sources**: `installer/TestAuto.iss:21-34,56-61,435-660`, `CrewChief/installer/CrewChief.iss:27-35,64-70,333-504`, `TestData.Generation/Installer/TestDataGeneration.iss:1-60`, `TestData.Mutation/Installer/DataGenerationAndMutation.iss:1-60`, all four `New-*Installer.ps1`
- **Added**: 2026-09-09
- **Notes**: **One agent reported the port subsystem as "identical" across both installers — that is WRONG and the difference is the load-bearing part.** Verified: `ApplyWebPortToAppSettings` appears 6× in TestAuto.iss and 0× in CrewChief.iss. Written up as "identical" this would send an agent to patch the wrong file.

### new-testdata-mutation-sql-error-scrubbing — testdata-mutation-sql-error-scrubbing
- **Kind**: new
- **Target**: testdata-mutation-sql-error-scrubbing (or a section inside the orchestration skill)
- **Score**: 9
- **Description**: The shape file carries a clear-text connection string, so EVERY SqlException message reaching a log, a UI toast or a rethrown exception must pass through DatabaseOps.ScrubSecrets first. Companion rules: error text is phrased ABOUT the connection string, never built from it; and master/model/msdb/tempdb/ModelSource are hard-protected from drop with no override. A new SQL call site added without the scrub leaks a password and nothing fails a test.
- **Sources**: `Engine/Sql/DatabaseOps.cs:148-157`, `Engine/Generation/IBulkWriter.cs`, `Generation/BulkTableWriter.cs`, `Import/SqlTableCatalogReader.cs`, `Web/Components/Dialogs/ConnectionWizardDialog.razor.cs` (36 call sites across 16 files)
- **Added**: 2026-09-09
- **Notes**: `ScrubSecrets` → 0 hits. Overlaps `new-tdg-connection-credential-hygiene` — the two products solve the same problem differently (structural vs procedural); consider one shared skill.

### new-testdata-mutation-web-host — testdata-mutation-web-host
- **Kind**: new
- **Target**: testdata-mutation-web-host
- **Score**: 9
- **Description**: The Blazor host owns at most ONE run and everything is a singleton for a specific reason: a circuit dies on browser reconnect, and a circuit-scoped owner would kill a 500M-row run with it. Pages hold no run state — they read MutationRunService.Snapshot and subscribe to Changed, which fires on arbitrary threads so a component MUST marshal via InvokeAsync. IsRunning is derived from the Task, not the phase, so a run that died pre-terminal cannot wedge the UI. Operator state is files-only JSON beside the binaries, capped, with write failures logged and SWALLOWED, and ConnectionProfile structurally cannot hold a password.
- **Sources**: `Web/Services/MutationRunService.cs:6-12,33-38,41-53`, `Web/Services/RunHistoryStore.cs:14-19`, `Web/Services/ConnectionProfileStore.cs:5-24`, `Web/Program.cs:79-84,101-162`
- **Added**: 2026-09-09
- **Notes**: `RunHistoryStore`/`ConnectionProfile`/`reconnect` → 0 hits in any product skill.

### ext-testauto-hangfire-architecture — testauto-hangfire-architecture
- **Kind**: ext
- **Target**: testauto-hangfire-architecture (cross-link testauto-windows-service-hosting)
- **Score**: 9
- **Description**: When `HangfireAvailability.Enabled` is false, ITestAutoBackgroundJobClient / ITestAutoMonitoringApi stay registered but bind to null-object stand-ins with a deliberately ASYMMETRIC contract: queries return EMPTY so a monitoring page renders "no jobs", commands THROW naming the recorded reason, because silently accepting an enqueue that will never run is the worse failure. This exists because the real adapters take Hangfire's own types registered only inside the skipped AddHangfireCore, so five injecting services failed at ACTIVATION and surfaced as a dead Blazor page rather than a disabled feature. `JobDetails` returns an empty (never null) History because callers enumerate without a null check.
- **Sources**: `TestAuto.DependencyInjection/ServiceExtensions/HangfireUnavailableFallbacks.cs:6-31,37-80`, `TestAuto.Web/AutoRegistration/WebModuleRegistrar.cs:134-149`, `ServiceExtensions/MetricsServiceExtensions.cs:76-78`, `ServiceExtensions/RegisterAllServices.cs:162-163`
- **Added**: 2026-09-09
- **Notes**: The MARKER convention is already covered by `testauto-windows-service-hosting:50`; what is absent is the FALSE branch. NB the file is `HangfireUnavailableFallbacks.cs` but the class inside is `HangfireUnavailable` — an identifier grep for the filename returns 0 and misleads.

### ext-crewchief-workload-and-runs-nested — crewchief-workload-and-runs
- **Kind**: ext
- **Target**: crewchief-workload-and-runs (one agent proposed a new `crewchief-nested-workloads` instead — **decide which**)
- **Score**: 9
- **Description**: **MERGED from two agents.** RunWorkloadStep runs a workload inside a workload, resolving the child BY NAME at execution time via IWorkloadResolver (rename-tolerant; NullWorkloadResolver is the no-nesting default). Two counter-intuitive mechanics: parameter layering is parent < child < child-step with each merge applied EXACTLY ONCE by a different layer — the parent<step merge already happened in UtilityOrchestrator before any executor runs, so the executor's own Parameters ARE the parent globals, and duplicating the merge is the natural mistake; and the executor takes `Func<IWorkloadEngine>` purely to break the DI cycle orchestrator → executor → engine → orchestrator, so "simplifying" that factory breaks container construction. Plus a depth-first cycle detector that stops at unresolvable grandchildren rather than reporting them as this step's failure, and a transfer-time warning that a transferred workload does not carry its children.
- **Sources**: `CrewChief.Engine/Executors/RunWorkloadExecutor.cs:20-41,90-196`, `Steps/RunWorkloadStep.cs:3-19`, `Orchestration/{IWorkloadResolver,NullWorkloadResolver}.cs`, `CrewChief.Data/Services/WorkloadResolver.cs`, `Tests.Unit/Data/RunWorkloadTransferWarningTests.cs`, `Web/Documentation/51_StepGuideRunWorkload.md`
- **Added**: 2026-09-09
- **Notes**: `RunWorkloadStep`/`WorkloadResolver`/"nested workload" → 0 hits corpus-wide. INFORMATIONAL: `IWorkloadResolver.cs:10-16` and `RunWorkloadExecutor.cs:39-40` both still say the composition-root wiring is "out of scope for this iteration" — it is wired now.

### ext-crewchief-secrets-host-context — crewchief-secrets
- **Kind**: ext
- **Target**: crewchief-secrets
- **Score**: 9
- **Description**: The Web composition root for secrets is a named bundle, not per-type DI: SecretsHostContext carries the process-wide singletons (SealedKeyManager, ILocalSecretStore, ILockoutGuard, the deleter) plus TWO ProtectedTextFile instances DI cannot tell apart by type — and they are the SAME objects wired into the startup IConfiguration sources, which is why a UI change is visible after IConfigurationRoot.Reload(). Any new secrets page or test must go through it rather than resolving pieces individually.
- **Sources**: `CrewChief.Web/Services/Secrets/SecretsHostContext.cs:6-50`, `CrewChief.Web/Program.cs`, `Components/Pages/{SecretsBootstrap,SecretsManagement}.razor.cs`, `Tests.Unit/Web/SecretsCompositionRootTests.cs` (10 files)
- **Added**: 2026-09-09
- **Notes**: `SecretsHostContext`/`LocalSecretStoreDeleter` → 0 hits; the skill covers ProtectedTextFile but has no composition-root section.

### new-tdg-run-state-and-reporting — tdg-run-state-and-reporting
- **Kind**: new
- **Target**: tdg-run-state-and-reporting
- **Score**: 8
- **Description**: One shared thread-safe progress object serves both hosts, and shared WORDING is the convention that prevents CLI/Web divergence: GenerationPhases string constants whose values are literally the narrow UI tile text, RunSnapshot.FinalSummaryText as the one sentence both surfaces print, Interlocked counters with a single Snapshot() read path, and two deliberate measurement guards — a 30s RecentRateWindow because throughput degrades as the table grows, and a 1ms MinimumRateInterval floor on the DENOMINATOR so a short run cannot report "1,000,000,000 rows/s". `--emit-report` writes from a single `finally` so a report exists for every terminal outcome and can never alter the exit code.
- **Sources**: `Engine/Model/GenerationRunState.cs:6-38,57-90`, `Engine/Reporting/RunReportWriter.cs:11-40`, `Cli/Program.cs:16-46,624-639`, `Web/Services/GenerationRunService.cs`
- **Added**: 2026-09-09
- **Notes**: `RunSnapshot`/`FinalSummaryText`/`GenerationPhases` → 0 hits.

### new-tdg-connection-credential-hygiene — tdg-connection-credential-hygiene
- **Kind**: new
- **Target**: tdg-connection-credential-hygiene
- **Score**: 8
- **Description**: A STRUCTURAL (not procedural) approach to keeping SQL passwords out of persisted and shared artefacts: ConnectionProfile has no public constructor — Sanitize(name, parts) is the single construction path and the deserialiser ctor is private, so a saved profile cannot hold a password by construction; ConnectionStringParts.BuildRedacted() routes through DatabaseOps.ScrubSecrets for anything logged; and the run-report model has no field a connection string could occupy at all, because reports get emailed.
- **Sources**: `Engine/Model/ConnectionProfile.cs:28,76,162-209`, `Engine/Sql/ConnectionStringParts.cs:229`, `Engine/Reporting/RunReportWriter.cs:33-40`, `Web/Services/ConnectionProfileStore.cs:18-50`, `Tests/ConnectionProfileTests.cs:98`
- **Added**: 2026-09-09
- **Notes**: Overlaps `new-testdata-mutation-sql-error-scrubbing`; the structural-vs-procedural contrast between the two sibling products is itself the interesting content.

### ext-crewchief-file-persistence-broken-stub — crewchief-file-persistence
- **Kind**: ext
- **Target**: crewchief-file-persistence
- **Score**: 8
- **Description**: The broken-file stub doctrine. GetAll NEVER throws for a bad file — an unparseable workload comes back as an inert stub carrying Name + LoadError + Folder and zero steps, so one bad file cannot take down the Workloads list, `crewchief list`, Home counts or AllTags, yet stays visible. The stub is inert by contract: Save REFUSES it (writing would truncate the real file), the run coordinator refuses to run it, ValidateCommand must special-case it (zero steps would otherwise reconcile Green as "No steps"), and ReferenceRenameService skips-and-reports it. Any new caller that judges or writes a workload must check IsUnreadable first. The same reasoning governs the shadowed-copy verdict.
- **Sources**: `CrewChief.Data/Models/WorkloadFile.cs:57-61,79-84`, `Stores/WorkloadFileStore.cs:59-73,175-180`, `IWorkloadFileStore.cs:12-18`, `CrewChief.Cli/Commands/ValidateCommand.cs:134-138`, `Services/ReferenceRenameService.cs:15-48`
- **Added**: 2026-09-09
- **Notes**: Pairs with `hyg-crewchief-workload-and-runs-isunreadable` — the only corpus hit for `IsUnreadable` is a WRONG one.

### ext-testauto-help-docs-multi-host — testauto-help-docs
- **Kind**: ext
- **Target**: testauto-help-docs (and/or crewchief-help-docs)
- **Score**: 8
- **Description**: The MD2Razor mechanics ARE covered, but the skill is hard-scoped to TestAuto.Web and states `$layout` "must be `TestAuto.Web.Components.Help.HelpLayout`". There are now THREE hosts of the same pipeline (TestAuto, CrewChief, TestData.Mutation — and TDG is a fourth corpus), each needing its own layout class, base class and per-app JS namespace (`tdgHelp.enhance` vs `ccHelp`). An agent following the skill verbatim in the wrong project writes a doc that will not render. Cheapest fix: a per-host table.
- **Sources**: `TestData.Mutation.Web/TestData.Mutation.Web.csproj:24-58`, `Web/Documentation/20_ShapeReference.md:8`, `Web/Services/Docs/DocsCatalog.cs:19-31`, `Web/Components/Help/MarkdownDocBase.cs`, `Web/wwwroot/js/tdm-help-docs.js`
- **Added**: 2026-09-09
- **Notes**: Verified: `testauto-help-docs:67` pins the TestAuto class; `TestData.Mutation` → 0 hits in either help-docs skill. Scope the rule, do not delete it — TestAuto's own docs still use the TestAuto value.

### ext-crewchief-web-ui-list-filtering — crewchief-web-ui
- **Kind**: ext
- **Target**: crewchief-web-ui (`references/list-filtering.md`)
- **Score**: 8
- **Description**: The per-page filter statics documented there are now thin delegates. The convention: page-level public statics stay (they are the tested seams) but bodies delegate to shared generic helpers — ListFilters (ByTags/ByText/ByValues/ByReconciliation), FolderFilter (null=all, ""=root, path=folder AND descendants, with the folder+"/" suffix check so 'matching-archive' is not a child of 'matching'), and TagAssignment (add-only Ordinal union that must return a NEW list or a bound RadzenDropDown's selection goes stale).
- **Sources**: `CrewChief.Web/Components/Pages/ListFilters.cs:15-40`, `Pages/FolderFilter.cs:8-27`, `Pages/TagAssignment.cs:7-58`, `Pages/Steps.razor.cs:366,408,450-488`
- **Added**: 2026-09-09
- **Notes**: `ListFilters`/`FolderFilter`/`TagAssignment` → 0 hits. The existing reference documents only the page statics, which do still exist.

### ext-testauto-connex-service-pagespec — testauto-connex-service
- **Kind**: ext
- **Target**: testauto-connex-service
- **Score**: 7
- **Description**: ConnectJobPageSpecParser parses `connex.tJob.ExtensionData` into a key-range spec feeding the PageKeyRange metric column. Three judgements an agent would otherwise re-litigate: start bound inclusive / end exclusive, and 7 of 1000 observed pages had start >= end, matched nothing and still reported Succeeded — detecting that is the type's whole reason to exist; IsInverted is deliberately false for non-numeric bounds ("unknown is not the same as valid" — read it as *confirmed bad*, never *confirmed good*); and the FINAL page of an import legitimately carries a null end, so a missing END is a valid open-ended spec while only a missing START is unusable.
- **Sources**: `TestAuto.Connect/Services/ConnectJobPageSpec.cs:10-130`, `Scenarios/ConnectPostRunCollectionScenario.cs:615`, `Services/IConnectExecutionRepository.cs:132`, `Testing.SpeedMerchants.Unit/Tests/Connect/ConnectJobPageSpecTests.cs`
- **Added**: 2026-09-09
- **Notes**: `ConnectJobPageSpec` → 0 hits; the skill's Metric Collector section covers the surrounding scenario in depth but not page-spec parsing. `GetValueCI` is already covered by `external-json-case-insensitive-reads` — do not re-document.

### ext-crewchief-file-persistence-notes-fields — crewchief-file-persistence
- **Kind**: ext
- **Target**: crewchief-file-persistence
- **Score**: 6
- **Description**: The notes fields (`WorkloadFile.GlobalParametersNotes`, `CredentialNotes`, `UtilityStepBase.Notes`) deliberately OMIT `NullValueHandling.Ignore` so the empty key is discoverable in hand-edited JSON — which directly contradicts the blanket rule stated at `crewchief-file-persistence/SKILL.md:98`.
- **Sources**: `CrewChief.Data/Models/WorkloadFile.cs`, `CrewChief.Engine/Steps/UtilityStepBase.cs`
- **Added**: 2026-09-09
- **Notes**: One line in that skill rather than its own section. `NotesField*` → 0 hits.

### desc-inno-setup-installer — inno-setup-installer
- **Kind**: desc
- **Target**: inno-setup-installer
- **Description**: Description line 4 and title line 11 both say "sibling-pair … for CrewChief and TestAuto". Verified FOUR installers and four build scripts exist; `TestDataGeneration`/`DataGenerationAndMutation` → 0 hits in the skill. Rewrite to name four products so an agent does not miss two real installers.
- **Sources**: `find` over the scan target → 4 `*.iss`, 4 `New-*Installer.ps1`
- **Added**: 2026-09-09
- **Notes**: Do together with `ext-inno-setup-installer-four-products`.

### desc-crewchief-capability-preflight — crewchief-capability-preflight
- **Kind**: desc
- **Target**: crewchief-capability-preflight
- **Description**: Description line 4 and heading line 32 both say "eight step capabilities". Verified NINE enum members: LocalAdmin, RemoteRunAs, LocalLogon, RemoteWinRm, SqlAuth, ShareFirstHop, ShareSecondHop, ConnExParameters, **AdoBuild**. Update both the count and the capability list/section.
- **Sources**: `CrewChief.Engine/Capabilities/CapabilityModel.cs:80` (enum), `Capabilities/Probers/AdoBuildProber.cs`, `CapabilitySubsystemRegistration.cs`
- **Added**: 2026-09-09
- **Notes**: A hand-written count that drifted — same class of defect as a census oracle. Do together with `new-crewchief-platform-build-steps`.

### desc-crewchief-web-ui — crewchief-web-ui
- **Kind**: desc
- **Target**: crewchief-web-ui
- **Description**: Description/body call these "three-mode `SecretValueEditor` / `ServerNameEditor`, the 4-mode …" and the section heading is "Three-mode value editors". Verified actual: SecretValueEditor `{ Literal, Parameter, Secret, Reference, Builder }` (five), ServerNameEditor five, ServiceNameEditor six (`Pick` first). The skill's "Secret/Reference/Text" mode naming also no longer matches.
- **Sources**: `Controls/SecretValueEditor.razor:207`, `Controls/ServerNameEditor.razor:167`, `Controls/ServiceNameEditor.razor:202`
- **Added**: 2026-09-09
- **Notes**: Do together with `ext-crewchief-web-ui-value-editors`.

### hyg-crewchief-file-persistence-path-guard — crewchief-file-persistence
- **Kind**: hyg
- **Target**: crewchief-file-persistence
- **Description**: **Security-relevant staleness.** Line 27 gives a flat `<dataFolder>/<kind>/<name>.<kind>.json` path; line 30 says "The kebab check IS the guard — `Get`/`Delete` validate before any `Path.Combine`, so `../escape` can never form a path". `FolderPath.cs:11-17` says the opposite in as many words: *"Until folders existed, the kebab-case check on a step/workload NAME was the stores' entire path-traversal guard … Once a folder joins the path that is no longer sufficient"*, and `ResolveUnder` adds a root-containment assert described as *"the one that holds even if the grammar is later relaxed — do not drop it."* The skill currently tells an agent the guard is something it is not.
- **Sources**: `CrewChief.Data/Stores/FolderPath.cs:11-17,61-80`, `Stores/StepFileStore.cs:398`, `Stores/WorkloadFileStore.cs`
- **Added**: 2026-09-09
- **Notes**: Highest-priority correction in this backlog on consequence, not score.

### hyg-crewchief-workload-and-runs-isunreadable — crewchief-workload-and-runs
- **Kind**: hyg
- **Target**: crewchief-workload-and-runs
- **Description**: Line 65 asserts `UnreadableInline` / `IsUnreadable` "is NOT a property on `WorkloadFile`/`WorkloadStepEntry`/`WorkloadDefinition`". Verified `WorkloadFile.cs:61` → `public bool IsUnreadable => !string.IsNullOrEmpty(LoadError);`. **Both now exist** — `WorkloadEditor.razor.cs:88` has the editor-state one too — so the editor half of the claim still holds and only the "NOT on WorkloadFile" half is wrong. An agent trusting it skips the required check before saving or running a broken stub.
- **Sources**: `CrewChief.Data/Models/WorkloadFile.cs:57,61`, `Stores/WorkloadFileStore.cs:175`, `CrewChief.Cli/Commands/ValidateCommand.cs:136`, `CrewChief.Web/Components/Pages/WorkloadEditor.razor.cs:88`
- **Added**: 2026-09-09
- **Notes**: An asserted NEGATIVE that became false — the hardest kind to notice. Do with `ext-crewchief-file-persistence-broken-stub`.

### hyg-crewchief-web-ui-refregex — crewchief-web-ui
- **Kind**: hyg
- **Target**: crewchief-web-ui
- **Description**: The skill claims the `{{$ref:...}}` form is "parsed/built **inline in each editor** (local `RefRegex` + `BuildRef`), not in SecretValueRef". Verified `RefRegex` → **0 hits anywhere in the scan target**; `BuildRef` now resolves to `TokenShapes.BuildRef` / `TryParseWholeRef`, consumed by ValueSourceClassifier and TokenComposition. The shapes were centralised.
- **Sources**: `CrewChief.Engine/Services/TokenShapes.cs:289`, `Web/Components/Controls/ValueSourceClassifier.cs`
- **Added**: 2026-09-09
- **Notes**: Do with `ext-crewchief-token-replacement` and `desc-crewchief-web-ui`.

### hyg-inno-setup-installer-sources-gloss — inno-setup-installer
- **Kind**: hyg
- **Target**: inno-setup-installer
- **Description**: Line 156's Sources gloss reads "`installer/TestAuto.iss` — TestAuto Inno Setup script (shortcuts-only, once-only appsettings, firewall)". Both parentheticals are wrong and the skill's own matrix rows 22/24 already contradict them. Verified: `Name: service` at `TestAuto.iss:98` (service mode is the default task); `onlyifdoesntexist` count in TestAuto.iss = **0**, and `:107` states "appsettings.json included … always refreshed".
- **Sources**: `installer/TestAuto.iss:98,107`
- **Added**: 2026-09-09
- **Notes**: Now matters more than cosmetically: an agent trusting "once-only" would conclude the installer cannot own the port write, which is exactly backwards — ApplyWebPortToAppSettings exists *because* the file is overwritten every upgrade.

### hyg-testauto-project-inventory — testauto-project
- **Kind**: hyg
- **Target**: testauto-project
- **Description**: Line 249 says "All application projects in `speed-merchants.sln`"; the table at 270-273 lists four `TestData.*` projects but omits the TestData.Generation ones. Verified `grep -c "TestData.Generation" speed-merchants.sln` → 4, so they ARE in that solution. Incompleteness, not a false claim.
- **Sources**: `speed-merchants.sln`
- **Added**: 2026-09-09
- **Notes**: Low consequence; batch with the other inventory-style fixes.
