---
name: crewchief-token-replacement
description: >
  The {{...}} token system in CrewChief.Engine — TextTemplater resolution order
  ($config/$env/$ref/params), fail-fast validation, and ParameterResolver's two-hop config/secret
  chain, $ref-valued params, param-in-param composition with cycle detection, and ConnEx-only JSON
  escaping. Use when authoring or debugging CrewChief step tokens, pipe FILTER CHAINS and their arity/escaping rules, the $now/$utcnow/$today clock segments and IRunClock's freeze scope, why a filter chain is refused at save time, TokenShapes as the single owner of the token grammar, why a token stays literal or fails
  a step, circular parameter references, wiring reference data, or how a secret parameter resolves at
  run time.
---

Repo: speed-merchants (paths below are repo-relative)

# CrewChief Token Replacement

CrewChief substitutes `{{...}}` tokens in step content (SQL, PowerShell, command lines, URLs, ConnEx artifacts) and in parameter values. `TextTemplater.ReplaceTokens` does the pattern replacement with a fixed resolution order and fail-fast validation; `ParameterResolver.ResolveSpecialParameterValues` handles the two-hop chain where a parameter value is itself a `{{$config:}}`/`{{$env:}}` reference (as ConnEx imports promote). See [[crewchief-reference-data]] for the `$ref` source, [[crewchief-orchestration]] for where resolution is invoked, [[connex-import-tokenization]] and memory [[project_connex_runasuser_json_escape]] / [[reference_scenario_config_token_prefix]].

## When to Use
- "What token forms does CrewChief support and in what order do they resolve?"
- "Why is `{{$config:...}}` appearing literally in my executed SQL/URL?"
- "Why did my step fail with an unresolved-token error instead of running?"
- "How does a Secret-typed parameter get its value at run time?"
- "Can one parameter reference another (`installed_name = Profisee Server {{version}}`)? What happens on a circular reference?"
- "Why does a ConnEx credential need backslash escaping but SQL doesn't?"

## `TextTemplater` — `{{Key}}` replacement

`CrewChief.Engine/Services/TextTemplater.cs`. Token pattern (line 29-31):

```csharp
private static readonly Regex TokenPattern = new(@"\{\{([^}]+)\}\}",
    RegexOptions.Compiled | RegexOptions.CultureInvariant);
```

**Resolution order** (`ResolveTokenValue`, lines 121-152) — first prefix match wins, then the parameter dict:

| Order | Form | Source | Notes |
|---|---|---|---|
| 1 | `{{$config:Key}}` | `IConfiguration[Key]` | e.g. `{{$config:RestClients:Matching:BaseUrl}}`; colon-separated config path after the prefix |
| 2 | `{{$env:KEY}}` | `Environment.GetEnvironmentVariable(KEY)` | |
| 3 | `{{$ref:type:key}}` | `IReferenceDataResolver.Resolve(type, key)` | resolver is optional (null when host didn't register one); malformed `$ref` → unresolved |
| 4 | `{{Key}}` | parameter dict | **case-insensitive**; a present key with a null value resolves to empty string |

Prefix matching is `OrdinalIgnoreCase`. `$ref:` is parsed by `TryParseRef` (lines 254-266): splits after the prefix on the first `:` into `type`/`key`, rejecting malformed forms.

**Fail-fast validation**: `ReplaceTokens` (lines 81-113) calls `ValidateTokens` first and, if any token is unresolvable, throws `ArgumentException("The following tokens were found in the input but have no matching source: {{a}}, {{b}}...")` listing **all** missing tokens — it does not partially substitute. `FindTokens` returns the distinct token set; `ValidateTokens` returns the unresolvable subset (`CanResolveToken` per token). Note: for `$config`/`$env`/`$ref`, a token is "resolvable" only if the source yields a **non-empty** value; for a plain parameter, the key just has to exist (null/empty is allowed).

Three ctors: `(IConfiguration)`, `(IConfiguration, IReferenceDataResolver?)`, and parameterless (params-only, no `$config`/`$env`/`$ref`). DI wires it as `new TextTemplater(configuration, sp.GetService<IReferenceDataResolver>())` (see `EngineServiceCollectionExtensions.cs:17`).

## `ParameterResolver` — parameter-value resolution (config/secret, $ref, param-in-param)

`CrewChief.Engine/Services/ParameterResolver.cs`. `ResolveSpecialParameterValues(IDictionary<string,string> parameters, bool escapeForJson=false)` resolves parameter VALUES that are themselves templates, in place. It handles four token forms inside a value: `{{$config:...}}`, `{{$env:...}}`, `{{$ref:...}}` (special tokens, resolved via the templater against config/env/reference-data), and `{{OtherParam}}` — a reference to **another parameter in the merged set** (resolved recursively).

Motivation — the two-hop chain: a ConnEx artifact holds `{{DbPassword}}`; the parameter `DbPassword` holds `{{$config:Passwords:...}}`. Executors are single-pass templaters, so the parameter's own `{{$config:...}}` must be resolved **before** the executor substitutes it — otherwise the literal `{{$config:...}}` string lands in the SQL/URL/artifact. The same reasoning extends to param-in-param composition, e.g. `version = 26.2.0`, `installed_name = Profisee Server {{version}}`.

**Param-in-param** (`{{OtherParam}}`): resolved recursively via `ResolveParameter`, **memoized** in a `resolved` side-map, and **definition-order-independent** (a param can reference one defined later). A **cycle** (`a = {{b}}`, `b = {{a}}`) is caught by a `visiting` chain and **throws `CircularParameterReferenceException`** — a **subclass of `UnresolvedParameterTokenException`**, so the orchestrator's existing catch handles it as a normal fail-fast step failure. `{{OtherParam}}` matching is case-insensitive (mirrors `TextTemplater`).

**Fail-fast on unknown tokens**: an unknown `{{token}}` in a value (neither a special prefix nor a sibling param) is collected and, if any remain, **throws `UnresolvedParameterTokenException(ownerKey, unresolvedTokens)`** (backlog bug B) — it does **not** silently leak literal `{{...}}` braces into executed content. A special token whose source yields empty (`ValidateTokens` non-empty) is likewise treated as unresolved. `{{$ref:...}}`-valued params are now resolved this way too (previously they leaked literally). The orchestrator catches the throw and records a step failure that honors `ContinueOnError` (see [[crewchief-orchestration]]).

**Two-phase design** (resolve-into-side-map, then write back):
- **Phase 1** — `foreach key: ResolveParameter(...)` resolves every value into a `resolved` side-map. Any throw (unresolvable or circular) happens **here, before any write-back**, so the caller's `parameters` dictionary is left **fully intact** for error reporting. A value with no `{{` is copied verbatim; otherwise `ResolveValue` runs `TokenPattern.Replace` over it.
- **Phase 2** — write back only values that actually changed (`result != parameters[key]`, Ordinal). Untouched literals are skipped, so ConnEx params already escaped at import time by `ArtifactTokenizer.Escape` are **never double-escaped**. Changed values are escaped **exactly once**, from the **raw** memoized result — even when that raw form was embedded (unescaped) inside another parameter during phase 1. So chained/composed values carry the raw resolved form during composition and JSON-escaping is applied a single time at the end.

**`escapeForJson` is ConnEx-only.** The orchestrator passes `escapeForJson: step is ConnExStep` (`UtilityOrchestrator.cs:214`). ConnEx substitutes resolved values into a **raw JSON artifact**, so a value like `CORP\QAAutomation` must become `CORP\\QAAutomation` or the artifact fails to parse (invalid escape `\Q`). Other step types (SQL/PowerShell/Curl/CLU) consume the raw value and must **not** be escaped. `EscapeForJsonStringLiteral` (lines 174-175) mirrors `ArtifactTokenizer.Escape` exactly; import-time escaping only covered *literal* values, and literal (unchanged) params are skipped in phase 2's write-back, so escaping here can't double-escape (memory [[project_connex_runasuser_json_escape]]).

`ResolveBestEffort(input, parameters)` (lines 178-196): resolves only the tokens it *can*, leaving unresolvable ones untouched — used for display strings, not execution. Never throws (unlike `ResolveSpecialParameterValues`).

## `{{STEP:N}}` is NOT here

Cross-scenario/step-output linking via `{{STEP:N}}` is a **Web-layer TestAuto** mechanism (the [[step-reference-resolution]] `IStepReferenceResolver`), **not present in CrewChief.Engine**. CrewChief's templater only handles `$config`/`$env`/`$ref`/params — do not expect `{{STEP:N}}` to resolve here.

## Quick reference

| Want | Token |
|---|---|
| appsettings / secrets value | `{{$config:Section:Item}}` |
| environment variable | `{{$env:VARNAME}}` |
| reference data | `{{$ref:type:key}}` |
| step/global parameter (case-insensitive) | `{{Key}}` |
| a secret in a scenario/config param | must be `{{$config:...}}` (bare `{{Section:Item}}` won't resolve — memory [[reference_scenario_config_token_prefix]]) |

## Pipe filter chains and clock sources

Tokens are no longer just a lookup. A token body may carry a **filter chain**:

```
{{$now|addDays:7|date:yyyy-MM-dd}}
```

**24 named filters**, each declaring its **arity** - and arity is what decides comma-splitting, so a
filter taking one argument does not split on a comma inside it. `date` arguments are passed **verbatim**.
Values stay **`DateTimeOffset`-typed across stages** rather than round-tripping through strings.

**Clock segments**: `$now`, `$utcnow`, `$today`. `IRunClock`'s freeze scope is the **only sanctioned clock
read** - a filter reading the system clock directly breaks reproducibility within a run.

### Two rules that bite

- **Validation is static and runs with nothing.** `TokenFilters.ValidateChain` takes no params, no config
  and no clock, which is what lets the **editor block a bad chain at SAVE time** rather than at run time.
  A misspelled `|addDay:7` is refused in the editor.
- **Filters must be PURE**, because resolution evaluates every token **TWICE**. A filter with a side
  effect, or one reading a live clock directly, produces two different values in one resolution.

### Escaping

The pipe, comma and backslash inside an argument are backslash-escaped, and
**`TokenFilters.EscapeArgument` is the sole owner** of that grammar. Never hand-build an escaped argument.

## TokenShapes owns the token grammar

`TokenShapes` is the **single** place the token regexes and prefixes live - including `BuildRef` /
`TryParseWholeRef` for the `$ref` form.

It exists because an audit found **3 copies of the token regex, 5 of `$config`, and 7 mutually
incompatible `$ref` parsers** scattered across the editors. Anything that needs to recognise or build a
token goes through `TokenShapes`; see [[crewchief-web-ui]], whose editors were the source of those copies.

## Sources
- `CrewChief\CrewChief.Engine\Services\TextTemplater.cs`
- `CrewChief\CrewChief.Engine\Services\ParameterResolver.cs`
- `CrewChief\CrewChief.Engine\Orchestration\UtilityOrchestrator.cs`  (invocation ~202-204)
- `CrewChief\CrewChief.Engine\EngineServiceCollectionExtensions.cs`  (TextTemplater/ParameterResolver DI ~15-18)
