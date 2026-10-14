---
name: crewchief-model-import
description: >
  CrewChief's Profisee model-export to workload-family conversion — the /model-import wizard,
  IModelImportEmitter, ModelImportStepSetBuilder, EntityDependencyGraph cascade selection, and the
  WorkbookRecordReader typed-conversion rule. Use when importing a Profisee model export into CrewChief,
  producing the -teardown / -build / -refdata / -datastore / -full-run family, mapping reference-data
  .xlsx workbooks to entities, debugging a workbook header or cell-conversion error, reasoning about the
  {{EntityName}} token contract or the ProfiseeBaseUrl/ApiKey/ModelId/ModelName/RecordBatchSize globals,
  working on the model-import wizard's selection cascade or its produce/validate steps, or asking why a
  selection, a cycle, a stranded workbook or a 207 was refused.
---

Repo: speed-merchants (paths below are repo-relative)

# CrewChief Model Import

Turns a **Profisee model export** (`{ "Entities": [...], "Attributes": [...] }`) plus optional
reference-data `.xlsx` workbooks into a family of runnable CrewChief workloads that recreate the model's
entities, attributes and records on another gateway.

Sibling of [[crewchief-connect-import]], not a mode of it: that one carries a Connect **integration
strategy** between environments, this one carries the **model** the strategy runs against. The two share
payload shapes (the entity/attribute create bodies and the SQL type map were copied from
`ConnectImport.EntityResetEmitter` / `ResetShapeBuilder`) and nothing else — no code path is shared, so a
fix in one does not land in the other.

## When to Use

- Importing a Profisee model export into CrewChief, or working on `/model-import`.
- Adding or changing a produced workload, its step shapes, or its expected status codes.
- A workbook that "reads 0 records", a header error, or a number that was refused.
- "Why is this entity's checkbox disabled?" / "Why was my selection refused?"
- Reasoning about what is tokenized and what stays literal.

## File map

| File | Role |
|---|---|
| `Services/ModelImport/ModelExport.cs` | The parsed model: `ModelExport`, `ModelEntity`, `ModelAttribute`, `DanglingDomainReference` |
| `Services/ModelImport/ModelExportParser.cs` | JSON → `ModelExport`; every key read case-insensitively; reports ownerless and malformed attributes as a **result**, never a throw |
| `Services/ModelImport/EntityDependencyGraph.cs` | Cascade selection, creation/deletion order, `FindSelectedCycle` |
| `Services/ModelImport/WorkbookRecordReader.cs` | `.xlsx` → gateway-shaped JSON records; the typed-conversion rule |
| `Services/ModelImport/ModelImportConstants.cs` | Endpoints, globals, status codes, formats, name suffixes, `ErrorDetail` path redaction |
| `Services/ModelImport/ModelImportStepSetBuilder.cs` | Pure: selection + records + options → the five step lists |
| `Services/ModelImport/IModelImportEmitter.cs` / `ModelImportEmitter.cs` | Request/result contracts; save, bundle, validate |
| `Components/Pages/ModelImport.razor(.cs)` | The five-step wizard; judgement lives in the services, the page only displays it |
| `Documentation/56_WorkloadModelImport.md` | The in-app help page (`/help/workload-guides/model-import`) |

## The workload family

Five suffixes, produced in this order (`ModelImportEmitter.BuildWorkloads:71-86`):

| Suffix | Produced when | Contents |
|---|---|---|
| -teardown | always | Gateway check, then DELETE per entity in **deletion** order (referrer before what it references) |
| -build | always | Gateway check, then per entity: POST the entity, then one POST carrying all its non-system attributes |
| -refdata | a SELECTED entity has a workbook that read at least one record with no error | Gateway check, then PATCH per batch, entities in **creation** order |
| -datastore | `EmitDatastore` is on | Drop/create one SQL table per entity, then one insert step per entity with rows. No gateway call, so no check |
| -full-run | always | `RunWorkloadStep` per part — teardown, build, refdata |

> [!important] The datastore is built BEFORE the full run, and excluded FROM it
> `BuildFullRun` filters the datastore part out by name (`ModelImportEmitter.cs:288-291`). So the
> *production* order is teardown, build, refdata, datastore, full-run — but the *chain* is teardown,
> build, refdata. A plan that lists full-run before datastore is describing the intent, not the code.

An empty part is never saved (`Add` returns early on `steps.Count == 0`), and an empty **selection** is
refused before the full run is composed — otherwise a zero-step workload would be saved, bundled and
reported as a successful import (`ModelImportEmitter.cs:80-84`).

## The token contract

The single rule worth memorising:

> **An ENTITY name is only ever `{{EntityName}}`. An ATTRIBUTE name is only ever literal.**

Entity tokens land in the URL path, `identifier.name`, an attribute's `identifier.entityId.name` and
`domainEntityId.name`, the datastore table names and every step description
(`ModelImportStepSetBuilder.cs:63-71`). Each selected entity gets a `name → name` global, so an unedited
import behaves as the export describes it and a re-target is one globals edit.

Attribute names stay the export spelling on `identifier.name`, `integrationName`, as a record property
name and as a datastore column name — **even when an attribute is named after an entity**, which a domain
attribute routinely is. Tokenizing those would rename the attribute along with the entity
(`ModelImportStepSetBuilder.cs:73-79`).

### Globals

`ProfiseeBaseUrl`, `ProfiseeApiKey`, `ProfiseeModelId`, `ProfiseeModelName`, `RecordBatchSize`,
`DatastoreConnectionSecret` (only when the datastore is on), plus one per selected entity. The gateway
globals are written **last** so an entity sharing one of their names cannot displace it — and an entity
with one of those names is refused outright, because the token would otherwise resolve to the API key
*inside a URL path* (`ModelImportConstants.cs:147-155`).

The names are deliberately the same ones `ConnectImport.EntityResetConstants` uses, so a Model Import
family and a Connect Import reset workload fill in from one set of values.

## What the builder refuses

`ModelImportStepSetBuilder.Build` returns a `Failure` — **no partial step set, ever**. The operator-facing
list of refusals, with the reason for each, is
`Documentation/56_WorkloadModelImport.md` → *"What the builder refuses"*; it is maintained there so the
help page and this skill cannot drift apart. Read the code at:

| Group | Where |
|---|---|
| Unusable entity NAME — reserved token characters, `[` or `]`, a reserved global, a case-only collision | `ModelImportStepSetBuilder.cs:182` (`FindUnusableEntityName`) |
| A cycle of 2+ selected entities | `ModelImportStepSetBuilder.cs:235` (`FindReferenceCycle`) |
| Records supplied for an entity the selection does not build | `ModelImportStepSetBuilder.cs:263` (`FindStrandedRecords`) |
| `BatchSize < 1`, datastore on with no connection secret | `ModelImportStepSetBuilder.cs:109-113` |

A **self-reference is allowed** and is not a cycle: `AddDependency` drops self edges, because an entity is
created before its own attributes (`EntityDependencyGraph.cs:94`, `:174-177`).

An empty record list for a selected entity is tolerated — only a non-empty list for an *unselected* entity
is stranded (`ModelImportStepSetBuilder.cs:270`).

## Workbook rules

First worksheet only. Row 1 is the header row; every non-empty header must match an attribute name
case-insensitively. Any header problem fails the **whole** workbook, because a mis-spelled column would
otherwise silently drop an attribute from every record (`WorkbookRecordReader.cs:119-121`).

| Rule | Detail |
|---|---|
| Code | Required; a row with an empty Code is skipped silently (trailing blanks) |
| Unknown header | Error naming the column |
| Repeated header | Error — one column per attribute |
| Audit columns | LastChgDTM / LastChgUserName / EnterDTM / EnterUserName ignored **only when the entity has no attribute of that name** — the attribute lookup runs first (`:127-133`) |
| Mapping | File name = entity name, with a dropdown override that is never silently taken back (`ModelImport.razor.cs:581-582`, `:553-559`) |
| One per entity | A second workbook on the same entity is an error naming the first |
| Unopenable | A **result**, not a throw — missing, locked, password-protected, truncated, or an .xls under an .xlsx name (`:72-81`) |

> [!warning] Records and errors can BOTH come back
> A row with one unconvertible cell contributes errors and no record. The page drops every record from a
> workbook with any error (`ModelImport.razor.cs:660`), so a partly-bad sheet never imports half-loaded.

> [!danger] `ClearRead` must move all three fields together
> Records, read errors **and** `ReadAgainstEntityId` are cleared as one act. A branch that dropped the
> records and left the stamp behind made the file read "Read — 0 records" with no error, and the refdata
> workload was produced silently missing that entity — a map → collide → map-back cycle did exactly that
> (`ModelImport.razor.cs:613-629`).

## The conversion rule

Always the **invariant culture**, so a workbook reads the same on every machine
(`WorkbookRecordReader.cs:427-431`).

The per-type table an operator needs — empty cell, Text/Link, domain-bound, Date, DateTime, Number — is
`Documentation/56_WorkloadModelImport.md` → *"How a cell becomes a value"*, and is maintained there so the
two cannot drift. The code is one method: `WorkbookRecordReader.Convert` (`:212`), with the domain check
deliberately **before** the `DataType` switch (`:216`) and the Number rule in `Number` (`:266`).

> [!danger] A Number record value may be a `JValue(BigInteger)` — `Value<decimal>()` and `Value<double>()` THROW on one
> `NumberToken` writes a whole value past `long.MaxValue` as a `BigInteger` token, because a
> `decimal(26,0)` column reaches 26 digits and a long only 19 (`WorkbookRecordReader.cs:345-353`).
> Newtonsoft's `Value<decimal>()` / `Value<double>()` throw on such a token rather than converting, so any
> code that reads a record value back — a preview, a log line, a grid cell — must use the token's TEXT
> (`token.ToString()`) or the underlying value, never a numeric `Value<T>()`. The wizard displays row
> COUNTS and never a value, which is why the page has never hit this; anything that starts showing values
> will.

### Numbers — decimal, never double

The target column is `decimal(26, scale)`, and 26 is ONE budget spent across both sides of the point.

- A **numeric** cell is rounded to the scale, `MidpointRounding.AwayFromZero` — its spare digits are
  binary-float noise, not operator input.
- A **text** cell is taken exactly; more decimals than the scale is an **error** ("an import may not round
  a value away from what was typed"). Digits are counted in the *text*, because parsing is itself what
  would round them away (`:372-403`).
- Either cell: more than `26 − scale` whole digits is an error — checked **after** rounding, since
  rounding 9.5 at scale 0 makes it 10.
- `NumberToken` writes a whole value as a **long** (or `BigInteger` past long's range) and a fractional
  one as a decimal, after `Normalise` strips trailing zeros — so `42.50` and a typed `42.5` reach the
  PATCH body and the INSERT literal as the *same* literal. Newtonsoft would otherwise spell a whole
  decimal `42.0` while the SQL literal said `42` (`:332-353`, `:411-423`).

## Step shapes and status codes

| Step | Codes | Note |
|---|---|---|
| GET `{{ProfiseeBaseUrl}}/v1/Entities` | **200 only** | The gateway check. First step of teardown, build and refdata; `ContinueOnError` is **always false** |
| DELETE `{{ProfiseeBaseUrl}}/v1/Entities/{{Entity}}` | 200, 404 | `ContinueOnError` = `TeardownContinueOnError`, default **true** |
| POST `/v1/Entities`, POST `/v1/Attributes` | 200, 201 | Bodies are arrays even for one element — the gateway 400s a bare object |
| PATCH `/v1/Records/{{Entity}}?recordsAreSameShape=true` | **200, 201 only** | Batched at `RecordBatchSize` (default 500) |

> [!danger] A 404-tolerant teardown cannot tell ABSENT from MIS-ADDRESSED — the gateway check is what makes it loud
> `DeleteCodes` tolerates 404 on purpose: "nothing to drop" is what a clean first run looks like. That makes
> a request which never reached the entity at all indistinguishable from one that found nothing. A base URL
> the gateway does not serve answers 404 with no body, *before authentication*, so every DELETE reports
> Succeeded and the model is untouched — a teardown that is green and did nothing.
>
> The check is the whole defence: it accepts **only 200**, so a wrong address (404) and a wrong or missing
> key (401) both stop the run at its first step. It **lists** entities rather than fetching one by name —
> `GET /v1/Entities/<name>` is itself a 404 for an entity that is legitimately absent, which is the very
> ambiguity being removed — and therefore names no entity and needs no token.
>
> **Never remove it, never give it `ContinueOnError = true`, and never widen its codes.** Each of those puts
> the silent failure straight back. Note the one thing it does NOT do: a list that would be empty stays
> empty, so the check never makes an unwanted workload exist.

> [!note] A base URL ending in `/` is supported, not a misconfiguration
> The secret behind `{{ProfiseeBaseUrl}}` keeps its trailing slash — other consumers expect it, and it is
> the `HttpClient` base-address convention. Every step appends its own `/v1/...`, so the joined URL carries
> `//`, which the gateway 404s. `PowerShellRestExecutor` resolves the URL and runs it through
> `HttpUrlNormalizer.CollapsePathSlashes` **before** the PowerShell command is built (it cannot be repaired
> afterwards — by then it is one quoted fragment of a script), collapsing repeated slashes in the PATH only
> and logging one Warning when it did. Never tell an operator to remove the slash.

> [!danger] 207 is deliberately absent from `RecordCodes`
> The records endpoint answers a **partially applied** batch with 207. For an import that is a failure —
> the workload must stop rather than carry on over dropped records. A rejected value does **not** roll its
> batch back (`ModelImportConstants.cs:112-116`).

`recordsAreSameShape=true` is required, not an optimisation: without it the gateway reads each record's
own shape, which is slower and intolerant of a null-valued property the batch's first record lacks.

Datastore steps use the `DatastoreConnectionSecret` global for **both** source and destination connection,
and write 500 rows per INSERT — bounded by SQL Server's 1000-row VALUES limit, independent of
`RecordBatchSize` (`ModelImportStepSetBuilder.cs:88-92`).

> [!danger] The payload builders and the SQL type map are COPIES — a test is what keeps them honest
> `BuildEntityPayload`, `BuildAttributePayload` and the dataType→SQL map are deliberate copies of
> `ConnectImport.EntityResetEmitter` and `ResetShapeBuilder.MapSqlType` — shapes proven against a live
> gateway — rather than shared code, so a Connect Import change cannot silently alter a model import.
> The thing that stops them drifting APART is
> `CrewChief.Tests.Unit/Web/ModelImport/ModelImportDonorAgreementTests.cs:41`, which builds both sides and
> compares them key by key (`:151` for the entity payload, `:192` for the column types). Editing one side
> alone turns it red on purpose. **Never delete it, relax its comparison, or "fix" it by copying the new
> output into the expectation** — that is the whole mechanism, and without it the two drift in silence.

### Determinism

The builder is pure — no I/O, no clock, no gateway. The record-avatar file category's guid is **derived**
from the entity id via SHA-256 rather than `Guid.NewGuid()` (the donor's behaviour), so re-emitting the
same inputs produces byte-identical steps and a diff means something (`:408-430`).

## Validate — token resolution only

`ModelImportEmitter.Validate` resolves every token against globals, secrets and reference data. It sends
nothing and saves nothing, and **no HTTP client or SQL connection is injected into the emitter at all** —
that is structural, not a matter of care. There is no dry-run of a DELETE against a live model, so this is
the only safe pre-flight (`ModelImportEmitter.cs:17-30`).

A resolvable global whose value is itself a token is followed **one hop**, which is where the real failure
lives: `{{ProfiseeApiKey}}` is always in the globals, so the step text always resolves — what is missing
on an un-bootstrapped box is `$config:RestClients:Profisee:ApiKey`, reported without braces, per step
(`:242-279`).

## Produce

- Destinations: the workload library (`SaveWorkloadsToStore`, default true) and/or a folder of
  `<name>.workload-bundle.json` bundles. Choosing **neither** is refused up front, before anything is
  built: an emit that would produce nothing is an authoring mistake, not a no-op (`:111-115`). The page
  refuses it too, as a Produce-disabled reason.
- An overwrite is confirmed first, by name, listing every workload that would be replaced.
- Two partial-failure shapes, and the result table is built from them
  (`ModelImport.razor.cs:1113-1152`):
  - **Store failure** → only the workloads saved *before* it come back, so the next name in build order is
    the one that failed.
  - **Bundle failure** → the whole family comes back with `BundlePath` set on exactly the bundles that
    landed; the first one without a path failed.

## REQ-017 — no local paths in emitted artefacts

Nothing about a workbook (name, path, extension) reaches a produced workload or bundle: the wizard reads
the rows and the request carries records only. Every operator-facing message names a **file** and never
its folder, via `ModelImportConstants.ErrorDetail`, which strips the caller's path in both its spellings
and then sweeps the text for rooted paths (quoted pass first, so paths with spaces end at their closing
quote) before truncating at 160 chars (`ModelImportConstants.cs:177-256`).

## Selecting entities

The checkbox in the table HEADER is scoped to the rows the filter is showing, never the whole export
(`ModelImport.razor.cs`, `ToggleSelectAllShown` / `SelectAllCounts`). Three things fall out of that and each
one is a test:

- It ticks or unticks only what the operator can see. A select-all that reached the filtered-out rows would
  change a selection nobody looked at.
- It **skips a locked row**, and the check is made inside the loop rather than on a snapshot, because
  ticking one entity can pull the next one in. Skipping it leaves that entity PULLED IN rather than
  promoting it to one the operator chose, which is what keeps the "Why" column and the untick behaviour
  honest.
- It is disabled when nothing shown can be operated: the filter matches no row, or every row it matches is
  pulled in by a selection the filter is hiding.

> [!note] The "some but not all" state is a DOM property, not an attribute
> `indeterminate` cannot be bound in Blazor markup, so the page pushes it after every render through
> `crewchiefIo.setIndeterminate` (`SyncIndeterminateAsync`, the same helper `/templates` uses). It is
> best-effort by design — prerender or a dead circuit still shows a correct checked/unchecked box — so a
> test asserts the public `SelectAllIndeterminate` and the recorded JS call, never the rendered DOM.

## Wizard gates

`CanEnterStep`: step 2 needs a loaded export; steps 3-5 also need **no blocking problem**, so a workbook
or selection error holds the operator on the step that shows it. A dialog that would not open is a
**notice** — listed in the same banner, deliberately outside `HasWizardError`, because a failing file
browser says nothing about whether the import is sound (`ModelImport.razor.cs:169-181`, `:943-959`).

> [!warning] The gating follows the owner-approved MOCKUPS, and they are binding
> While a blocking problem stands, **Next and stepper steps 3-5 are disabled** — the operator is held on
> the step that shows the problem. That is not a judgement call: it is what the approved
> `SelectErrors` mockup draws, and an earlier reading that let the operator walk past it was reversed.
> A dialog failure is the one exception and is a non-blocking **notice**: it is listed in the same banner
> (the banner renders on `WizardErrors`, not on `HasWizardError` — `ModelImport.razor.cs:993`, `:987`) but
> it gates nothing, because locking the wizard would trap the operator behind a browser they cannot open.
> If a mockup and your instinct disagree, the mockup wins or the owner is asked — not both.

> [!warning] The batch-size box is `@oninput` ON PURPOSE, and the plan is NOT rebuilt per keystroke
> This app has **no blur-to-commit inputs**: `@onchange` on a text box is forbidden, because a value typed
> and then Saved without tabbing out would be silently dropped. So the batch-size box commits on every
> keystroke (`ModelImport.razor:390`) — and therefore must not drag a build of the whole workload family
> behind each character. It is validated LOCALLY instead (`BatchSizeError`,
> `ModelImport.razor.cs:731`), and `OnBatchSizeChanged` (`:722`) deliberately does **not** call
> `RefreshPlan`. The plan is rebuilt on a selection change, a workbook change, and on ENTERING steps 4 and
> 5 (`GoToStep`, `:219`; `RefreshPlan`, `:805`), and it never serialises: the byte sizes are measured
> lazily, once per plan, only where the Output step asks (`PlanSize`, `:860`). Adding a `RefreshPlan()` to
> a keystroke handler, or a serialisation to `RefreshPlan`, undoes all of this — and
> `Plan_IsNotRebuiltWhileTheBatchSizeIsTyped_AndIsRebuiltOnceOnEnteringOutput` will say so.

Every public method on the page (`ToggleEntity`, `AddWorkbooks`, `SetTeardownContinueOnError`,
`ProduceAsync`, …) is a **test seam**: this repo is strong-name signed, so `InternalsVisibleTo` is
unavailable, and bUnit cannot drive a disabled element or a Radzen modal. A rendered `disabled` attribute
is a browser courtesy — the refusal underneath it has to be provable without one. See [[crewchief-testing]].

## Sources

- `CrewChief\CrewChief.Web\Services\ModelImport\` (8 files)
- `CrewChief\CrewChief.Web\Components\Pages\ModelImport.razor(.cs)`
- `CrewChief\CrewChief.Web\Documentation\56_WorkloadModelImport.md`
- `CrewChief\CrewChief.Tests.Unit\Web\ModelImport\` (page, emitter, builder, workbook, constants)

## Related

[[crewchief-connect-import]] · [[crewchief-token-replacement]] · [[crewchief-web-ui]] · [[crewchief-testing]] · [[crewchief-help-docs]] · [[profisee-rest-api]] · [[testauto-metadata-model-import]]
