---
name: project-connex-template-tool
description: c:\tmp\connex-template — offline jq templating pipeline for ConnEx artifacts; LocalVault map is canonical; live import still untested
metadata: 
  node_type: memory
  type: project
  originSessionId: dbc61646-fed0-4a03-b373-ef0a2d645382
  modified: 2026-08-08T22:23:27.190Z
---

`c:\tmp\connex-template` — offline "XSLT for JSON" pipeline (tokenize/render/verify) for Profisee Connect export artifacts, alternate to the native CrewChief converter design (vault doc `2026-08-05-connect-export-conversion-design.md`). Usage guide: vault `99 Documentation\CrewChief\2026-08-08-connex-template-usage-guide.md`.

State as of 2026-08-08:
- jq flavour canonical; fixed for Windows Git Bash (native jq.exe cannot open MSYS `/proc/fd` paths — replaced process substitution with `--argjson` in `jq/connex.sh`).
- `jq/map.localvault.json` = recommended map: credential rules point at `value.configuration.value` and a one-time jq reshape adds `name`/`providerType: LocalVault` — matches golden shape read from live workflow 10000158. `jq/map.json` = original bare-credential variant, unproven.
- Filename patterns widened to `^Load[_ ]Staging` (real portal exports have spaces). `.gitignore` fixed (`**/env/*.json` — root-anchored pattern was a secret-leak hole).
- Working SQL pair in `testfiles\`; templates in `tmpl\`, rendered in `out\`; strategy record Id `b6e3988f-7c34-4e75-b3d5-dc88834cab2a` used for Enable/Execute steps (Execute needs expectedStatusCodes 202).
- OPEN: no rendered artifact live-imported yet; testfiles carry nested $type (portal-ish) vs proven gateway shape ($type root+record only) — strip if 400. Python flavour drifted (max_records_per_job vs max_records, bare-credential rules) — scan-helper only.

Later same day — TestAuto-style deployment path (user's preferred direction):
- `jq/map.testauto.json` = TestAuto token names (DbServer, StrategyId, EntityId/EntityName, TargetDatabaseTableName…); dataSource via template rule `{{EntityName}}|{{EntityId}}`; expressionText entity prefixes tokenized by post-pass (attr GUIDs stay literal); numerics/bools NOT tokenized (CrewChief textual substitution would quote them — golden precedent).
- `deploy/deploy-load-staging.workload.json` = generated CrewChief workload: 4 ConnEx steps (Import config, Import strategy, Enable, Execute w/ 202), artifacts EMBEDDED tokenized, globalParameters = defaults captured from original export, creds = {{$config:UserCredentials:*}} placeholders. ResourceId "{{StrategyId}}" safe — ConnExExecutor.cs:344 token-resolves ResourceId.
- capture.jq fixed: template-rules skipped so shared tokens keep clean defaults.
- Roadmap (user's asks): CrewChief discover-tokens button (+ values.captured.json-style defaults sidecar); rule selection by artifact root $type/record key + provider instead of filename regex.

Evening 2026-08-08:
- Workloads page imports only the WorkloadBundle envelope {schemaVersion:"1.0", exportedUtc, workload} — raw workload JSON rejected. deploy file now `deploy-load-staging.workload-bundle.json`, kebab workload name.
- CrewChief Connect Import page (ConnectImport.razor + ConnectImportEmitter, shipped this week) is the PRIMARY route: combines provider+config+strategy exports into ONE workload, 7 steps (Delete×2 teardown, Import×2, Enable, Execute, WaitForBatch — polling EXISTS via ConnEx WaitForBatch op). Added OutputDirectory to emit (writes portable .workload-bundle.json; ConnectImportEmitRequest.OutputDirectory / result BundleFilePath; emitter ctor now takes IWorkloadTransferService; 2915 unit tests green).
- Card-view bulk-select checkbox (.cc-mcard__check, app.css) now always visible (was opacity-0 until hover) per user request.
- In-app cookbook added: CrewChief.Web\Documentation\07_CookbookConnectImport.md (Cookbook category, order 7, /help/cookbook/connect-import) — click-by-click training walkthrough export→tokens→validate→save+bundle→run→second instance; cross-linked from 49_WorkloadConnectImport.md.
- ConnectImport page is now a 5-step WIZARD (Load / Review Tokens / Configure / Output / Finish): _wizardStep state + CanEnterStep gating, stepper buttons (wizard-step-N / wizard-next / wizard-back testids), auto-advance after dialog confirm; step 5 = suggested kebab name from strategy record Name (SuggestWorkloadName, "deploy-<name>"), RadzenSwitch autoload toggle default ON (ConnectImportEmitRequest.SaveWorkloadToStore), Produce Output button. Emitter fails explicitly when autoload off AND no output dir. Docs (07 cookbook + 49) rewritten to wizard flow. 2917 unit tests green.
