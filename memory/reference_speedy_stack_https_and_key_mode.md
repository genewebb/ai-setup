---
name: reference_speedy_stack_https_and_key_mode
description: Speedy compose stack after Write-SpeedyStackEnv serves https-only on 5310; setup refuses a 644 installation.key; Complete-SpeedyTestSetup masks refusals with a .Count StrictMode error
metadata:
  node_type: memory
  type: reference
  originSessionId: b51b0f58-2541-4f84-9eb2-a4ae4b05e924
  modified: 2026-10-02T13:11:45.205Z
---

Found on SMVMTR1 2026-10-01 while making dpv2 green.

- Once `scripts\e2e\Write-SpeedyStackEnv.ps1` writes `.env.local` (`ASPNETCORE_URLS=https://+:8080`), port 5310 serves **https only** with the CN=localhost dev cert. An http probe fails with "An error occurred while sending the request"; probe `https://localhost:5310/health` (not 127.0.0.1, the cert name check fails). dpContainers now picks the scheme from `.env.local`.
- Setup completion refuses `PROTECTION_KEY_NOT_RESTRICTED` when `/keys/installation.key` (web-keys volume) is 644. compose.yaml web entrypoint now creates it under umask 077 and chmods 600 on every start.
- `Complete-SpeedyTestSetup` used to throw "The property 'Count' cannot be found" when a refusal listed 0 or 1 unsatisfied keys. A function returning `@()` or `@('one')` unrolls to $null or a plain string, and under StrictMode Latest neither has `.Count` (2+ keys worked). That hid the real refusal. FIXED in f9334a4 (G2.T111), which wraps the call in `@()`. General lesson: under StrictMode, wrap any function result in `@()` before reading `.Count`. To read a refusal body directly: `& (module) { Invoke-SetupCompletion ... }`.
- A crash-looping container reads `running` for about a second after each restart. A state check must compare RestartCount across a settle wait.
- `dpv2` has no `-NoBuild`; only `dpContainers` does.

Related: [[project_speedy_stack_on_smvmtr1_2026-09-28]]
