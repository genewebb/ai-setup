---
name: crewchief-cli
description: >
  The CrewChief.Cli command-line surface — hand-rolled verb parser, exit-code contract,
  composition root, and secret/console I/O seams. Use when adding or changing a CLI verb,
  editing CliArgs/UsageText, wiring the CLI's Program.cs DI or two-stage configuration,
  changing exit codes, testing a command via its TextWriter/IConsoleIo seams, or reconciling
  the stale README against the real command set.
---

Repo: speed-merchants (paths below are repo-relative)

# CrewChief CLI (CrewChief.Cli)

CrewChief ships a bespoke `crewchief` CLI alongside the Blazor Web App. It is **files-only**
(no DB), shares the same data folder and run history as the Web UI, and is deliberately built
**without** a CLI-framework package — the whole argument surface is one testable static method.
Every command class is DI-resolved and takes an injectable `TextWriter`/`IConsoleIo` seam so it
runs headless in unit tests and never echoes secrets.

## When to Use
- Adding or modifying a verb, sub-command, or `--flag` (edit `CliArgs.Parse` + `UsageText` + `Program.Dispatch`).
- Changing the exit-code contract or how an outcome maps to an exit code.
- Wiring the CLI composition root (`Program.cs`): DI registrations, layered `IConfiguration`, Serilog sinks, data-folder resolution.
- Writing a test that drives a command headless (via `TextWriter output` or a fake `IConsoleIo`).
- Reconciling the README (its Commands block is stale) against the real verb set.

## Verbs (truth = `CliArgs.UsageText` + `Program.Dispatch`, NOT the README)

| Verb | Shape | Dispatches to |
|---|---|---|
| `run workload <name>` / `run step <name>` | `[--param k=v ...]` | `RunCommand.Execute` |
| `resume <runId>` | `[--param k=v ...]` | `RunCommand.ExecuteResume` |
| `list steps` / `list workloads` | `[--tag <tag>]` | `ListCommand.Execute` |
| `history` / `history show <id>` / `history clear` | `[--last <n>]` | `HistoryCommand.ExecuteList/Show/Clear` |
| `backup` | `[--out <path>] [--parts steps,workloads,reference-data]` | inline in `Program.Dispatch` → `IBackupService.CreateBackup` |
| `restore <zipPath>` | `[--parts steps,workloads,reference-data]` | inline in `Program.Dispatch` → `IBackupService.RestoreBackup` |
| `seal-secret` | `[--out <path>] [--iterations <n>] [--stdin]` | `SealSecretCommand.Execute` |
| `unlock` | — | `UnlockCommand.Execute` |
| `secrets import` | `--in <path> [--profile <name>]` | `SecretsCommand.ExecuteImport` |
| `secrets export` | `[--out <path>]` | `SecretsCommand.ExecuteExport` |
| `secrets status` | — | `SecretsCommand.ExecuteStatus` |
| `service status` / `service set-account` | `[--local-system]` | `ServiceCommand`, behind the `IServiceAccountOps` seam |

**`service` is deliberately unlike every other verb** in two ways worth knowing before you touch the parser:
- It does **not** accept `--data-folder`. It operates on the Windows service registration, not on a data folder, so accepting the flag would imply a scoping that does not exist.
- `--local-system` is **rejected** — not ignored — on any other command (`CliArgs.cs:107-118`). Silently dropping a machine-affecting flag on a command that cannot honour it is exactly the failure mode this refusal exists to prevent.
- `set-account` requires elevation and returns `NotElevated` (2) when the console is not elevated; an OS-level failure after the attempt returns `ServiceOperationFailed` (1).

Global options `--data-folder <path>` and `--verbose` may appear **anywhere** — they are stripped
in a first pass before the positional grammar runs.

## The parser (`CliArgs.cs`)
- `public static CliArgs? Parse(string[] args, out string? error)` — returns one immutable
  `CliArgs` record, or `null` + a human-readable `error` (embedding `UsageText`) on any failure.
  Callers exit `NotFoundOrValidation` (2) when it returns null.
- **Single pass** over `args`: a `switch (token)` strips every known `--flag` (consuming its
  value, erroring on a missing one), and anything else lands in `positionals`.
- `positionals[0]` (lower-cased) selects the verb, then a per-verb `ParseXxx` validates the
  remaining grammar (e.g. `ParseRun` requires `workload|step` + a name; `ParseSecrets` requires a
  known sub and enforces `--in` for import).
- `--param KEY=VALUE` splits on the first `=` (`eq <= 0` is an error); keys are
  case-insensitive (`StringComparer.OrdinalIgnoreCase`). `resume` deliberately carries `--param`
  forward so it overrides the resumed run's stored `GlobalParameters` (matching a normal run's precedence).
- Adding a verb = add a `case` in `Parse`'s switch, a `ParseXxx` (if it has its own grammar), a
  line in `UsageText`, and a `case` in `Program.Dispatch`.

## Exit codes (`CliExitCodes.cs`)

| Const | Value | Meaning |
|---|---|---|
| `Success` | 0 | Run Succeeded, or read-only command finished |
| `RunFailed` | 1 | Step/workload reached terminal Failed |
| `NotFoundOrValidation` | 2 | Not-found, usage error, resume shape-change guard |
| `Cancelled` | 3 | Run cancelled (Ctrl+C) |
| `LockedOut` | = 2 | Secret scope in brute-force lockout (aliased) |
| `NotUnlocked` | = 2 | Box not unlocked / no store (aliased) |
| `NotElevated` | = 2 | `service set-account` refused — console not elevated (aliased) |
| `ServiceOperationFailed` | = 1 | An OS-level operation ran and failed (grant refused, SCM rejected the identity change) (aliased) |
| **`PreflightFailed`** | **4** | **A `run`/`resume`/`step` was hard-blocked by the Capability Advisor preflight — a genuinely NEW code** |

- The contract is **0/1/2/3/4**, not the old fixed 0/1/2/3.
- `LockedOut`, `NotUnlocked` and `NotElevated` all alias `NotFoundOrValidation` (2); `ServiceOperationFailed`
  aliases `RunFailed` (1). Those distinctions live in the console message, not the number — the reasoning
  being that a script already treats 2 as "my invocation was wrong, don't retry", which is the correct
  reaction to all three.
- **`PreflightFailed = 4` is NOT an alias**, and the distinction is load-bearing: `RunFailed` means a step
  executed and failed; `NotFoundOrValidation` means the input was invalid. Neither is true here — the run
  never started, not a single step ran, and **no `runs.json` record is written for it**. Every failing
  verdict's remediation is printed to `IConsoleIo` before the code is returned. There is deliberately **no
  bypass flag anywhere**, on the CLI or the Web UI. See [[crewchief-capability-preflight]].
- `RunCommand.ExitCodeForOutcome`: `"Succeeded"→0`, `"Cancelled"→3`, else `→1`.
- `Program.cs` top-level `catch` maps any escaped exception to `RunFailed` (1) so the CLR never
  surfaces an out-of-contract crash code. Ctrl+C is cooperative: `Console.CancelKeyPress` sets
  `e.Cancel = true` and cancels the token → engine records `Outcome=Cancelled` → exit 3.

## Composition root (`Program.cs`, top-level statements)
- **Two-stage layered `IConfiguration`**: `baseConfiguration` (appsettings.json + env, base path
  `AppContext.BaseDirectory` — there is **no** `secrets.local.json` config source; that source was
  removed) resolves the data folder **first**; then `configuration` layers `AddConfiguration(baseConfiguration)` +
  `EncryptionSecretsUnsealConfigurationSource` (feeds `CrewChief:ApiKeyEncryption:*`, the SetApiKey
  seam) + `LocalSecretsConfigurationSource` (flattens the local store so `{{$config:Section:Item}}`
  resolves at runtime).
- **Data-folder rules**: `--data-folder` is resolved via `Path.GetFullPath` **relative to the
  current directory** (it is a normal CLI argument); the configured `CrewChief:DataFolder` default
  is resolved **relative to the exe dir** (`AppContext.BaseDirectory`, matching how the Web resolves
  it relative to ContentRootPath). Secret files are **never** under `--data-folder`, so CLI and Web
  share the same encrypted files. Their **root is not hard-coded** to `%APPDATA%\CrewChief` — the CLI
  resolves it via `SecretsRootResolver.Resolve(baseConfiguration[SecretsRootResolver.ConfigKey],
  runningAsWindowsService: false)` (`Program.cs:40-41`), so `CrewChief:SecretsFolder` /
  `CREWCHIEF_SECRETS_FOLDER` override the default. The CLI passes `runningAsWindowsService: false`, so
  the machine-shared `%ProgramData%\CrewChief\secrets` default only applies when that env var/config
  key points there (e.g. set machine-wide by the Web Windows-Service installer); otherwise the
  interactive default is per-user `%APPDATA%\CrewChief`. See [[crewchief-secrets]] for the full
  precedence chain.
- **Serilog dual-sink**: console sink `restrictedToMinimumLevel` gated by `--verbose`
  (`Information` if `--verbose`, else **`Fatal`** — `parsed.Verbose ? LogEventLevel.Information :
  LogEventLevel.Fatal`, `Program.cs:77`). Non-verbose the console shows only the command's own
  pass/fail output; all Warning/Error/engine logs are suppressed on the console and go to the log
  file instead. File sink (`logs/crewchief-cli-.log`, daily rolling) is **always** `Information`.
- **Manual `ServiceCollection` DI**: `AddCrewChiefEngine(configuration)` plus the file stores
  (`IStepFileStore` = `new StepFileStore(dataFolder, useRecycleBin: true)`, `IWorkloadFileStore`),
  `IKeyValueReferenceStore`, `IBackupService` (`new BackupService(dataFolder)` — backs the
  `backup`/`restore` verbs), `IRunHistory` (`RunHistoryFile`, sized by `CrewChief:MaxRunHistory`
  / `CrewChief:MaxStepOutputChars`), the secret services, and the command classes.
- **Notifier is ALWAYS registered** (`INotifier → SmtpNotifier`) and internally gates on
  `NotificationSettings.Enabled/Mode` — an absent/disabled `CrewChief:Notifications` section yields
  a no-op notifier, **not** a conditional DI registration.

## Console/secret I/O seam (`IConsoleIo.cs`)
- `IConsoleIo` abstracts terminal interaction so secret commands are testable and secrets are never
  echoed/logged/passed as args. Real impl = `ConsoleIo`.
- `ReadHidden(label)`: no-echo prompt via `Console.ReadKey(intercept: true)` with backspace
  handling; **redirected-stdin fallback** does a plain `ReadLine` (the pipe source controls
  visibility) so it still never echoes.
- `ReadAllStdin()`: `Console.In.ReadToEnd()` — pipes a raw key in without echo.
- `seal-secret` reads the raw key from stdin when `--stdin` **or** `Console.IsInputRedirected`;
  otherwise a no-echo prompt. The key is never accepted as a command-line argument.

## Command classes (`Commands/`)
- Each is a `sealed` DI-resolved class with a `TextWriter? output = null` (or `IConsoleIo`) seam;
  constructors null-guard every dependency.
- `RunCommand` **re-validates** its sub-command in `Execute`'s switch (`_ => Fail(...)`) even though
  `CliArgs` already blocks bad values at parse time — defense in depth. `ListCommand` does the same.
- `RunCommand` mirrors the Web run pages via shared **CrewChief.Data**: `RunRecord` shape (so
  `runs.json` is shared Web↔CLI), `WorkloadDefinitionMapper`, `WorkloadResumePlanner`
  (`CanResume`/`ShapeChanged`/`ComputeStartAtIndex`/`BuildPriorResults`/`GetCompletedIndexes`),
  `WorkloadRunOutcomeMapper.Map` (handles the engine's two cancellation shapes:
  returned `WasCancelled` vs thrown `OperationCanceledException`), and `StepResultRecord`.
  `SynchronousProgress<T>`, `SafeAppend`/`SafeUpdate` (best-effort, swallow+log history-IO
  failures so a runs.json write race can't abort a run's exit code) are **RunCommand-local**, not
  in CrewChief.Data.
- `resume` gate: only a `Kind=="workload"` record from a terminal Failed/Cancelled outcome resumes;
  a Succeeded run falls through to a "nothing to resume" no-op; a shape change → exit 2.
- `HistoryCommand.MaxDisplayChars = 4000` — a display-time re-truncation mirroring the Web History
  page on top of `IRunHistory`'s own write-time truncation.
- Secret commands (`SealSecretCommand`, `UnlockCommand`, `SecretsCommand`) live here but the
  cryptography lives in CrewChief.Data.Secrets — see [[crewchief-secrets]]. `SecretsCommand` enforces
  master≠Encryption-Secrets-passphrase separation and honors the brute-force lockout.

## Cross-links
- [[crewchief-secrets]] — seal-secret / unlock / secrets verb internals (Encryption + Local secrets).
- [[crewchief-workload-and-runs]] — the shared RunRecord / resume / outcome model the CLI reuses.
- [[crewchief-web-ui]] — the Web pages these commands mirror.
- [[crewchief-architecture]] — engine/data/composition-root layering (`AddCrewChiefEngine`).
- [[testauto-cli-command-pattern]] — TestAuto's CLI is **framework-style** (verb options handlers,
  `--sample`); CrewChief is bespoke and single-method. Do not port TestAuto's option-guard pattern here.

## Sources
- `CrewChief\CrewChief.Cli\CliArgs.cs`
- `CrewChief\CrewChief.Cli\Program.cs`
- `CrewChief\CrewChief.Cli\CliExitCodes.cs`
- `CrewChief\CrewChief.Cli\IConsoleIo.cs`
- `CrewChief\CrewChief.Cli\Commands\RunCommand.cs`
- `CrewChief\CrewChief.Cli\Commands\HistoryCommand.cs`
- `CrewChief\CrewChief.Cli\Commands\ListCommand.cs`
- `CrewChief\CrewChief.Cli\Commands\SealSecretCommand.cs`
- `CrewChief\CrewChief.Cli\Commands\UnlockCommand.cs`
- `CrewChief\CrewChief.Cli\Commands\SecretsCommand.cs`
