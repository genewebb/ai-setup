---
name: result-pattern
description: >
  Async success/failure wrapper patterns used throughout TestAuto — PasswordValidationResult,
  FluentValidation ValidationResult, and C# value tuples. Use when returning operation
  success/failure without throwing exceptions, checking .IsValid on a returned result,
  choosing between result types for a new service method, or understanding why a method
  returns a tuple vs a result object.
---

# Result Patterns in TestAuto

TestAuto does **not** use a generic `Result<T>` type. Instead it uses three distinct patterns
depending on the domain and usage context. Choosing the right one matters — mixing them adds noise.

## When to Use

- "how do I return success/failure without throwing" — use `PasswordValidationResult` (custom domain) or FluentValidation (config/schema)
- "adding a validation method to a service" — return `Task<ValidationResult>` (FluentValidation) and check `.IsValid`
- "method needs to return a result code plus data" — use a C# value tuple
- "what does `.IsValid` mean on this return type" — check which of the three patterns the method uses

## Pattern 1: PasswordValidationResult (Custom Domain Result)

Defined in `TestAuto.Shared/Interfaces/IMasterPasswordManager.cs`. Used specifically for password
requirement checks.

### Type Definition

```csharp
public class PasswordValidationResult
{
    public bool IsValid { get; private set; }
    public string? ErrorMessage { get; private set; }

    public static PasswordValidationResult Success() =>
        new() { IsValid = true };

    public static PasswordValidationResult Failure(string message) =>
        new() { IsValid = false, ErrorMessage = message };
}
```

### Return Conventions

```csharp
// In the implementation (MasterPasswordManager.cs):
if (string.IsNullOrEmpty(password))
    return PasswordValidationResult.Failure("Password is required");

if (password.Length < MinPasswordLength)   // MinPasswordLength const = 16
    return PasswordValidationResult.Failure(
        $"Password must be at least {MinPasswordLength} characters. Current length: {password.Length}");

return PasswordValidationResult.Success();
```

### Caller Pattern

```csharp
var passwordValidation = passwordManager.ValidatePasswordRequirements(masterPassword ?? "");
if (!passwordValidation.IsValid)
{
    Console.ForegroundColor = ConsoleColor.Red;
    Console.WriteLine($"✗ Password validation failed: {passwordValidation.ErrorMessage}");
    Console.ResetColor();
    return (1, null);
}
```

Source: `TestAuto.Web/Services/SecretSetupCommands.cs`, `TestAuto.Shared.Security/Services/MasterPasswordManager.cs`

---

## Pattern 2: FluentValidation ValidationResult

Used for all configuration and scenario validation. Returns `FluentValidation.Results.ValidationResult`
which carries `.IsValid` and a `.Errors` collection of `ValidationFailure`.

### Interface Contract

```csharp
// IValidationService (TestAuto.Shared/Interfaces/IValidationService.cs) — all five members
public interface IValidationService
{
    Task<ValidationResult> ValidateConfigurationAsync(ScenarioConfiguration configuration);
    Task<ValidationResult> ValidateSectionAsync(string sectionName, object sectionData);
    Task<ValidationResult> ValidateWithRulesAsync(ScenarioConfiguration configuration, IEnumerable<string> ruleNames);
    Task<IEnumerable<ValidationRuleInfo>> GetValidationRulesAsync(string sectionName);
    Task<IEnumerable<ValidationSuggestion>> GetValidationSuggestionsAsync(ValidationResult validationResult);
}

// IConfigurationValidationManager (TestAuto.Shared/Interfaces/IConfigurationValidationManager.cs)
public interface IConfigurationValidationManager
{
    Task<(ScenarioConfiguration Config, ValidationResult Result)> ValidateScenarioAsync(string filePath);
}
```

### Return Conventions

```csharp
// Return valid result:
return new ValidationResult();           // empty = valid

// Return failure:
var fr = new ValidationFailure("File", $"Could not read file: {ex.Message}");
return (null, new ValidationResult(new[] { fr }));

// From a FluentValidation validator:
var result = await _scenarioValidator.ValidateAsync(cfg);
return (cfg, result);
```

### Caller Pattern

```csharp
var result = await _validationService.ValidateConfigurationAsync(config);
if (!result.IsValid)
{
    foreach (var error in result.Errors)
    {
        _logger.LogWarning("Validation failure — {Property}: {Error}",
            error.PropertyName, error.ErrorMessage);
    }
}
```

Source: `TestAuto.Web/Services/ValidationService.cs`, `TestAuto.Shared/Helpers/ConfigurationValidationManager.cs`

---

## Pattern 3: C# Value Tuples

Used when a method needs to return multiple values — commonly an exit/result code plus a payload.

### Common Shapes

```csharp
// Exit code + optional data (SecretSetupCommands.cs)
Task<(int Result, Dictionary<string, string?>? Secrets)>

// Parsed object + validation result (IConfigurationValidationManager.cs)
Task<(ScenarioConfiguration Config, ValidationResult Result)>

// URL + key pair (IMasterPasswordManager.cs)
(string? restUrl, string? apiKey) GetScenarioMgtRestConfig();
```

### Caller Pattern

```csharp
var (exitCode, secrets) = await SecretSetupCommands.RunInteractiveSetupAsync(args);
if (exitCode != 0) return exitCode;
// use secrets...

var (config, validationResult) = await _configManager.ValidateScenarioAsync(filePath);
if (!validationResult.IsValid) { /* handle errors */ }
```

Source: `TestAuto.Web/Services/SecretSetupCommands.cs`, `TestAuto.Shared/Interfaces/IConfigurationValidationManager.cs`

---

## Pattern 4: ConfigurationValidationResult (Startup Validation)

Used exclusively in startup configuration validation (`ConfigurationValidationService`). Similar shape
to `PasswordValidationResult` but also carries a `Warnings` list.

```csharp
public class ConfigurationValidationResult
{
    public bool IsValid { get; set; }
    public List<string> Errors { get; set; } = new();
    public List<string> Warnings { get; set; } = new();
}
```

Converted to `AppStartupStatus` via `new AppStartupStatus(result)` for injection into the Blazor UI.

Source: `TestAuto.Web/Services/ConfigurationValidationService.cs`, `TestAuto.Web/Services/AppStartupStatus.cs`

---

## Choosing the Right Pattern

| Scenario | Pattern |
|---|---|
| Password / credential validation | `PasswordValidationResult` (static `Success()`/`Failure()`) |
| Config / scenario / schema validation | FluentValidation `ValidationResult` |
| Method returning exit code + data | C# value tuple |
| App startup health | `ConfigurationValidationResult` → `AppStartupStatus` |

## Sources

- `TestAuto.Shared/Interfaces/IMasterPasswordManager.cs`
- `TestAuto.Shared.Security/Services/MasterPasswordManager.cs`
- `TestAuto.Shared/Interfaces/IValidationService.cs`
- `TestAuto.Shared/Interfaces/IConfigurationValidationManager.cs`
- `TestAuto.Shared/Helpers/ConfigurationValidationManager.cs`
- `TestAuto.Web/Services/ValidationService.cs`
- `TestAuto.Web/Services/SecretSetupCommands.cs`
- `TestAuto.Web/Services/ConfigurationValidationService.cs`
- `TestAuto.Web/Services/AppStartupStatus.cs`
