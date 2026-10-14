---
name: project_crewchief_secret_picker_convenience_only
description: "CrewChief value pickers go on nearly EVERY single-line field, sensitive or not — the line is multi-line bodies, not sensitivity. Corrects the old 'sensitive fields only' reading."
metadata:
  node_type: memory
  type: project
  originSessionId: 9d8fc319-68e4-4547-b000-0c8f949ea498
  modified: 2026-09-01T02:34:40.045Z
---

**Corrected 2026-08-31 after this note caused a wrong scoping call.** The original said the
`SecretValueEditor` picker was wired onto sensitive fields ONLY. That described its 2026-07-16 wiring
and practice has long since overtaken it — reading it as current policy is a mistake.

**What is actually true, verified in `StepEditorCard.razor`:** the picker is on nearly every
single-line value field, sensitive or not — `httpStep.Url`, `cluStep.Url`, `connExStep.BaseUrl`
(URLs), `mapStep.SharePath` (a UNC path), `sqlStep.SqlSource/DestinationConnectionSecretName`
(connection names), alongside the genuinely sensitive `connExStep.ApiKey`, `CredentialUserId`,
`CredentialPassword`.

**The line is MULTI-LINE BODIES, not sensitivity.** No picker on: SQL script, PowerShell
`ScriptContent`, HTTP body, curl command, ConnEx artifact JSON, CLU advanced arguments, command-line
arguments. Tokens still resolve there at run time via `TextTemplater`; those fields just get a plain
`textarea`, because a chip strip over a 15-row script editor helps nobody.

**`SecretValueEditor` is a misnomer** — it is the general-purpose single-line value editor. It does
not know a server name from a database name from a URL, and does not need to: the value is a string,
the sources are the same four (Secret / Reference Data / Text / Builder), the resolution is the same.
`ServerNameEditor` and `ServiceNameEditor` exist for their **enumeration extras** ("load services",
"load app pools"), not because the value is a different kind of thing.

**Still true from the original decision:** the picker is CONVENIENCE, not a restriction, and
**save-time "looks like a raw secret" scanning/blocking was considered and declined**. Plain-text
fields accept a literal typed straight in. Do not propose adding that scanning.

**Gene's stated defect in the control (2026-08-31):** the **text** filter arguments are clunky —
unlabelled `form-control-sm` boxes inside a chip, so on a two-argument filter (`replace` find/with,
`substring` start/length) nothing says which box is which; `date` argument 0 got a preset dropdown and
text filters got no equivalent; and the chip row wraps badly past two or three filters. The Builder
itself he likes. Fix this rather than copy it when porting to speedmerchants.

**How to apply:** when adopting into speedmerchants (vNext UoW-9, see §5d of
`vNextImplementation_v2.md`), build ONE generic value editor applied broadly, with an optional
enumeration hook — do not fork a component per field kind. Relates to
[[project_crewchief_secrets_shipped]], [[project_crewchief_value_builder]],
[[project_crewchief_reference_pickers]], [[reference_scenario_config_token_prefix]].
