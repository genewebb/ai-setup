---
name: crewchief-step-type-model
description: >
  The CrewChief.Engine step-type model — how step types are declared, registered, and polymorphically (de)serialized from JSON. Use when adding or renaming a CrewChief step type, deserializing a workload/step JSON config, debugging an "Unknown step type" error, understanding UtilityStepBase's shared fields or JsonExtensionData round-trip, or working on StepTypeRegistry / UtilityStepConverter.
---

Repo: speed-merchants (paths below are repo-relative)

# CrewChief Step-Type Model

CrewChief is a standalone .NET 10 step/workflow tool (files-only, Newtonsoft/Serilog/Radzen) copied from an internal "MultiStepUtility" scenario with ZERO TestAuto references. Every step is a concrete subclass of `UtilityStepBase` carrying a `type` discriminator. `StepTypeRegistry` is the single source of truth mapping each `type` string (canonical name + aliases) to a CLR type and a parameterless factory; both deserialization entry points (`UtilityStepConverter.ReadJson` and `UtilityStepBase.CreateFromJToken`) consult it, so a new step type is one `Register<T>(...)` line for the *deserialization* side. Unknown JSON fields survive a load→save cycle via a `[JsonExtensionData]` bag.

## When to Use
- "Add a new step type to CrewChief" (deserialization half — see also [[crewchief-adding-a-step-type]] for the full checklist: four dispatch sites, plus the coverage assertions that make the change indivisible)
- "Why does `{{"type":"foo"}}` throw 'Unknown step type'?"
- "How does CrewChief pick which concrete step class to build from JSON?"
- "What common fields does every step have (timeout, retry, continue-on-error)?"
- "Why did an unknown JSON property not get dropped on save?"

## `UtilityStepBase` — the shared base

`CrewChief.Engine/Steps/UtilityStepBase.cs`. Abstract; every step inherits these `[JsonProperty]` members:

| Property | JSON key | Default | Notes |
|---|---|---|---|
| `Type` | `type` | `""` | `Required = Required.Always`; the discriminator |
| `Parameters` | `parameters` | empty `Dictionary<string,string>` **OrdinalIgnoreCase** | token-replacement values; case-insensitive |
| `TimeoutSeconds` | `timeoutSeconds` | `600` | per-attempt timeout |
| `ContinueOnError` | `continueOnError` | `false` | evaluated *after* retries are exhausted |
| `RetryEnabled` | `retryEnabled` | `false` | when true, failed attempt is retried |
| `MaxRetries` | `maxRetries` | `0` | total attempts = `1 + clamp(MaxRetries,0,10)` |
| `RetryDelaySeconds` | `retryDelaySeconds` | `5` | clamped `[0,300]` at execution |
| `WorkingDirectory` | `workingDirectory` | `null` | |
| `Description` | `description` | `null` | logging/label |
| `ExtensionData` | *(catch-all)* | empty | `[JsonExtensionData]` forward-compat bag |

`ExtensionData` (lines 84-85): Newtonsoft populates it with any JSON property that has no declared member on read and flattens the entries back to top-level keys on write, so a step authored under a newer schema survives an older editor's load→save unchanged instead of silently losing fields.

`CreateFromJToken(JToken)` (lines 92-121) is the legacy/direct entry point: reads `type` (case-insensitive), resolves via `StepTypeRegistry.TryResolve`, `JsonConvert.DeserializeObject` into the resolved CLR type, then `Parameters ??= new Dictionary(OrdinalIgnoreCase)` because JSON `"parameters": null` would otherwise NRE downstream getters/executors. Throws `NotSupportedException` on an unknown type.

## `StepTypeRegistry` — single source of truth

`CrewChief.Engine/Steps/StepTypeRegistry.cs`. A `static` class with a static-ctor-built ordered list of `StepTypeRegistration { ClrType, Factory, TypeStrings }`. Each entry's **first** string is the canonical name; the rest are aliases. Lookups are `OrdinalIgnoreCase`.

The registration table (lines 54-72), verbatim canonical + aliases:

```
Register<SqlStep>("sqlstep", "sql")
Register<PowerShellStep>("powershellstep", "powershell", "ps")
Register<CommandLineStep>("commandlinestep", "commandline", "cli", "cmd")
Register<CLUStep>("clustep", "clu")
Register<HttpRequestStep>("httprequeststep", "httprequest", "http")
Register<CurlStep>("curlstep", "curl")
Register<ConnExStep>("connexstep", "connex")
Register<WaitStep>("waitstep", "wait")
Register<MapShareStep>("mapsharestep", "mapshare")
Register<ServiceControlStep>("servicecontrolstep", "servicecontrol", "service")
Register<HealthGateStep>("healthgatestep", "healthgate", "health")
Register<DatabaseOperationsStep>("databaseoperationsstep", "databaseoperations")
Register<AppPoolStep>("apppoolstep", "apppool")
Register<UninstallStep>("uninstallstep", "uninstall")
Register<InstallStep>("installstep", "install")
Register<ConfigureStep>("configurestep", "configure")
Register<SetApiKeyStep>("setapikeystep", "setapikey")
Register<IisResetStep>("iisresetstep", "iisreset")
Register<EmailStep>("emailstep", "email")
Register<TeamsStep>("teamsstep", "teams")
Register<CheckPortStep>("checkportstep", "checkport")
Register<WebSiteStep>("websitestep", "website", "site")
```

Key mechanics:
- `Register<TStep>(params string[] typeStrings) where TStep : UtilityStepBase, new()` builds the registration with `() => new TStep()` as the factory (lines 87-91).
- The static ctor folds every `typeString` into a `Dictionary` via `.Add(...)` — a **duplicate alias throws at type-load** (line 82 comment: "surface it loudly at type-load time"). You cannot ship two registrations claiming the same string.
- `TryResolve(string?, out StepTypeRegistration?)` returns false for null/whitespace or an unknown string (lines 109-118).
- Public surface: `Registrations` (declaration order), `AllTypeStrings` (every accepted key).

**Adding a step type here = one `Register<T>(...)` line.** That covers deserialization only — the executor dispatch table is separate; see the footgun checklist in [[crewchief-adding-a-step-type]].

`WebSiteStep` is the second three-alias registration after `CommandLineStep`/`CurlStep`-style shorthands: `"websitestep"`, `"website"`, **and** `"site"`.

### `CreateStep` vs `CreateStepForAuthoring`
The registry exposes two factories, and picking the wrong one is a real bug:
- **`CreateStep`** — the deserialization path. Produces a bare instance whose properties come from the JSON being read. It must NOT apply authoring defaults, or every load would silently rewrite a saved step.
- **`CreateStepForAuthoring`** — the "user pressed Add Step" path. Same instance, plus authoring-time defaults that a *new* step should carry but a *saved* step must never acquire retroactively. This is where `RemoteAuthentication` gets seeded to `Auto` for the box-prep family, which is why `Auto` is opt-in by value and a blank field on an existing step still parses to `Default` (Kerberos-only).

## `UtilityStepConverter` — the polymorphic JSON converter

`CrewChief.Engine/Steps/UtilityStepConverter.cs`. A `JsonConverter<UtilityStepBase>`.

- `static Serializer` property (lines 18-21): a `JsonSerializer` preloaded with this converter — the canonical way to (de)serialize a step.
- `ReadJson` (lines 23-56): loads a `JObject`, reads `Type`/`type` (case-insensitive), throws `JsonSerializationException("Step must have a 'Type'...")` if blank, `StepTypeRegistry.TryResolve` → `JsonSerializationException($"Unknown step type: {stepType}")` if unknown, builds via `registration.Factory()`, then `serializer.Populate(subReader, step)`. Ends with `step.Parameters ??= new Dictionary(OrdinalIgnoreCase)` (same null-parameters guard as `CreateFromJToken`).
- **`WriteSerializer`** (lines 62-65): a *separate*, private `JsonSerializer` used only by `WriteJson`'s `JObject.FromObject`. It deliberately omits `UtilityStepConverter` (passing the outer serializer would re-enter `WriteJson` and recurse forever) and adds a `StringEnumConverter` so step enums (e.g. `CLUStep`'s `CLUClearOptions`/`CLUReportType`/`CLUTaskType`) persist as readable strings; `ReadJson` tolerates both string and integer enum forms.
- `WriteJson` (lines 67-83): after `FromObject`, it reads `type` **case-insensitively** (`GetValueCI("type")`) and only synthesizes `jsonObject["type"] = value.GetType().Name` when no type key exists or it is blank. A prior case-*sensitive* `ContainsKey("Type")` bug added a *second* `"Type"` key with the CLR type name, so a round-trip rewrote the type and trumped a workload override — hence the case-insensitive read.

### Serializer decision table

| Need | Use |
|---|---|
| Deserialize one step / round-trip | `UtilityStepConverter.Serializer` |
| Direct JToken → step (legacy path) | `UtilityStepBase.CreateFromJToken(token)` |
| Deserialize a workload entry, ignore unknown Overrides keys | `WorkloadEngine.ExecutionSerializer` (see [[crewchief-orchestration]]) |
| Validate a workload entry, reject unknown Overrides keys | `WorkloadEngine.ValidationSerializer` (`MissingMemberHandling.Error`) |

## Difference from the TestAuto cousin

TestAuto's `UtilityStepConverter` (see the [[utility-step-polymorphic-deserialization]] skill) used a **hand-coded switch** over the type string inside `ReadJson`. CrewChief factored that switch out into the dedup **`StepTypeRegistry`** (duplicate-alias-throws) shared by both entry points, and added the `[JsonExtensionData]` forward-compat bag on `UtilityStepBase`. The trap that remains is that the *executor* dispatch table is still a separate hand-maintained list (see [[crewchief-adding-a-step-type]], memory [[project_crewchief_steptype_factory_duplicated]]).

## Sources
- `CrewChief\CrewChief.Engine\Steps\StepTypeRegistry.cs`
- `CrewChief\CrewChief.Engine\Steps\UtilityStepConverter.cs`
- `CrewChief\CrewChief.Engine\Steps\UtilityStepBase.cs`
