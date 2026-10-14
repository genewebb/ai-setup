---
name: testauto-cli-command-pattern
description: >
  TestAuto CLI entry-point structure, verb definitions, and option-validation
  patterns for the runtest and client commands. Use when building or modifying
  CLI verbs, adding options to RunTestCommand or ClientCommand, debugging
  option-validation errors, implementing the mutually-exclusive option guard
  pattern, generating sample config files via --sample, or tracing how
  VerbRunTestOptionsHandler dispatches to scenario/workload/job/load runners.
---

Repo: speed-merchants (paths below are repo-relative)

# TestAuto CLI Commands

The command *classes* live in `TestAuto.Commands`, but the CLI entry point /
composition root is `TestAuto/Program.cs` — the `TestAuto` console project
(`<OutputType>Exe</OutputType>`, `<AssemblyName>TestAuto</AssemblyName>`), **not**
`TestAuto.Web` (the web host never wires these verbs). `TestAuto/Program.cs:68-83`
registers **three** commands: `RunTestCommand` (`runtest`), `ClientCommand`
(`client`), and a `test-services` command. So: verbs are defined in
`TestAuto.Commands`, hosted by `TestAuto/Program.cs` → `TestAuto.exe`.

---

## Verb: `runtest`

Defined in `RunTestCommand.cs`. Executes test runs from a JSON configuration
file, or generates sample configs, or lists available scenarios.

### Options

| Option | Type | Description |
|---|---|---|
| `--scenario` | bool | Run a single scenario test. |
| `--workload` | bool | Run a workload (collection of scenarios). |
| `--job` | bool | Run a job (collection of workloads). |
| `--load` | bool | Run a load test (collection of jobs). |
| `--filepath` / `-f` | string | Path to the JSON configuration file (required for normal execution). |
| `--sample` | bool | Generate sample config files instead of running tests. |
| `--samplepath` | string | Directory where sample files are written (required with `--sample`). |
| `--list` | bool | Print all registered scenario names and exit. |

### Mutually-Exclusive Validator Pattern

`RunTestCommand` registers a `Command.AddValidator` delegate that enforces
mode-specific rules at parse time — no runtime guard is needed in the handler:

```csharp
Command.AddValidator(result =>
{
    bool sample = result.GetValueForOption(sampleOption);
    bool list   = result.GetValueForOption(listOption);
    int count   = 0;
    if (result.GetValueForOption(scenarioOption)) count++;
    if (result.GetValueForOption(workloadOption)) count++;
    if (result.GetValueForOption(jobOption))      count++;
    if (result.GetValueForOption(loadOption))     count++;

    if (list)
    {
        // --list: no --filepath or --samplepath allowed
    }
    else if (sample)
    {
        // --sample: --samplepath required, --filepath forbidden
    }
    else
    {
        // Normal mode: exactly one of scenario/workload/job/load + --filepath required
        if (count == 0)   result.ErrorMessage = "You must specify one of ...";
        if (count > 1)    result.ErrorMessage = "Options are mutually exclusive ...";
        if (filepath == null) result.ErrorMessage = "Normal execution requires --filepath";
    }
});
```

The validator runs before the handler. If `result.ErrorMessage` is set,
`System.CommandLine` prints the error and shows help automatically — no throw
needed.

### Handler Dispatch — `VerbRunTestOptionsHandler`

`HandleAsync(RunTestOptions)` processes options in priority order:

1. **`--list`** — resolves all `IScenario` registrations from DI, prints names, returns.
2. **`--sample`** — iterates every `IScenario`, calls `GenerateSampleScenarioConfiguration()`, writes `{ScenarioName}_SampleConfig.json` via `SampleConfigWriter.WriteWrappedSampleConfig`. Then generates Workload, Job, and Load sample configs using their respective `*ConfigurationGenerator` services.
3. **`--scenario`** (default path when `--workload`/`--job`/`--load` are all false) — validates via `IConfigurationValidationManager.ValidateScenarioAsync`, then calls `IScenarioEnqueueService.EnqueueScenarioAsync` (Hangfire batch dispatch).
4. **`--workload`** — deserializes `WorkloadConfigurationWrapper`, validates with FluentValidation, calls `IWorkloadExecutionService.ExecuteWorkloadAsync`.
5. **`--job`** — deserializes `JobConfigurationWrapper`, validates, calls `IJobExecutionService.ExecuteJobAsync`.
6. **`--load`** — deserializes `LoadConfigurationWrapper`, validates, calls `ILoadExecutionService.ExecuteLoadAsync`.

### RunTestOptions Model

```csharp
public class RunTestOptions
{
    public bool   Scenario   { get; set; }
    public bool   Workload   { get; set; }
    public bool   Job        { get; set; }
    public bool   Load       { get; set; }
    public string FilePath   { get; set; }
    public string SamplePath { get; set; }
    public bool   Sample     { get; set; }
    public bool   List       { get; set; }
}
```

### SampleConfigWriter

`SampleConfigWriter.WriteWrappedSampleConfig(scenarioName, innerJson, filePath)`
wraps the raw scenario JSON in the standard envelope:

```json
{
  "Name": "MyScenario_v1",
  "ScenarioConfiguration": { ... }
}
```

It parses `innerJson` as a `JObject`, builds the envelope, serializes with
`Formatting.Indented`, and writes asynchronously.

---

## Verb: `client`

Defined in `ClientCommand.cs`. Decrypts and resolves a Profisee client name/ID
from the security store. Exactly one of **four mutually-exclusive modes** must be
selected (`VerbClientOptionsHandler.cs:95-105`); the error message is literally
`"You must specify exactly one of --json, --environment, --display, or --database."`:

| Mode | Aliases | Description |
|---|---|---|
| `--json` | `-j` | Load options from a JSON file. Requires `--fileName`. |
| `--environment` | `-e` | Decrypt client ID and set it as a user environment variable. Requires `--userName`, `--envName`. |
| `--display` | `-d` | Decrypt and print client ID to console. Requires `--userName`. |
| database | *(no CLI flag)* | `DatabaseOption` — calls `SecurityUtility.GetEncryptedClientIdFromDatabase()` with no user argument. See "database mode" below. |

Additional options: `--fileName`, `--userName` / `-u`, `--envName`. (There is no `--outputFile` — the output path is derived from `--fileName`.)

### `--prompt` — interactive selector (NOT one of the exclusive modes)

`--prompt` / `-p` is **not** a mode. It launches an interactive `SelectionPrompt`
(choices Display / Environment / Json / Database) that resolves the user's pick
into one of the four modes above, then sets `Prompt = false`. So it is a front-end
that produces a mode, not a mode itself.

If no mutually-exclusive mode is selected (and `--prompt` is not used), the command
prints `--help` and exits.

The validator is implemented in `VerbClientOptionsHandler.HandleAsync` (not in
`AddValidator`) — it counts the exclusive flags after resolving the interactive
prompt and returns an error if `selectedCount != 1`.

### database mode (no `--database` CLI flag)

`ClientCommand.cs:34-76` registers **no `--database` option**. The `DatabaseOption`
(`DatabaseOption`) mode calls `SecurityUtility.GetEncryptedClientIdFromDatabase()`
with no user argument — useful for automated pipelines where the current runtime
user is the target. It is reachable only via the interactive "Database" choice of
`--prompt`, or by supplying it in a `--json` options file — never as a bare
command-line flag.

---

## Build and Run

Build the CLI from the repo root:

```powershell
dotnet build .\TestAuto\TestAuto.csproj
```

The output executable is `TestAuto.exe`. Run from the `bin\debug` or
`bin\release` directory. Note: `TestAuto.Web.exe` is the web host and does **not**
expose these verbs — build the `TestAuto` console project for the CLI.

---

## Common Usage Examples

<!-- example-paths -->
```powershell
# List all registered scenarios
.\TestAuto.exe runtest --list

# Run a single scenario
.\TestAuto.exe runtest --scenario --filepath "C:\configs\MyScenario.json"

# Run from a UNC share
.\TestAuto.exe runtest --scenario --filepath "\\CORPNAS01\Rnd\PerformanceTesting\Deploy\TestFiles\MyScenario.json"

# Run a workload
.\TestAuto.exe runtest --workload --filepath "C:\configs\Workload_SampleConfig.json"

# Run a job
.\TestAuto.exe runtest --job --filepath "C:\configs\Job_SampleConfig.json"

# Run a load test
.\TestAuto.exe runtest --load --filepath "C:\configs\Load_SampleConfig.json"

# Generate all sample configs into a directory
.\TestAuto.exe runtest --sample --samplepath "C:\configs\samples"

# Decrypt and display client ID interactively
.\TestAuto.exe client --prompt

# Decrypt and display client ID non-interactively
.\TestAuto.exe client --display --userName "gene.webb"

# Set client ID as a user environment variable
.\TestAuto.exe client --environment --userName "gene.webb" --envName "TESTAUTO_CLIENT_ID"
```

---

## Configuration Hierarchy

The four test execution types form a nested hierarchy:

```
Load
 └── Job(s)
      └── Workload(s)
           └── Scenario(s)
```

Each level has a corresponding `*Configuration` / `*ConfigurationWrapper` type,
a `*ConfigurationGenerator` that produces sample JSON, and a
`*ExecutionService` that drives execution. Only `--scenario` goes through
Hangfire enqueue; the others call their execution service directly.

---

## Sources

- `TestAuto.Commands\RunTest\RunTestCommand.cs`
- `TestAuto.Commands\RunTest\RunTestOptions.cs`
- `TestAuto.Commands\RunTest\VerbRunTestOptionsHandler.cs`
- `TestAuto.Commands\RunTest\ConfigWriter.cs`
- `TestAuto.Commands\Client\ClientCommand.cs`
- `TestAuto.Commands\Client\VerbClientOptionsHandler.cs`
- `TestAuto.Commands\Client\VerbClientOptions.cs`
- `TestAuto\Documentation\HowToRunTestsFromCommandLine.md`
