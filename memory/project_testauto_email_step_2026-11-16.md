---
name: project-testauto-email-step-2026-11-16
description: "TestAuto multi-step EmailStep (Teams channel mail) ported from CrewChief 11/16: built + 10 tests, uncommitted; PROD TestAutoUtilityType 'Email' row + EmailSettings/Teams secrets pending"
metadata:
  node_type: memory
  type: project
  originSessionId: 9494274d-b969-4d19-92f6-9b27d8b24447
  modified: 2026-11-16T13:57:04.622Z
---

11/16/2026: Gene asked to adopt CrewChief's Teams notify step into TestAuto. Chose CrewChief **EmailStep** (SMTP to Teams channel address) over the webhook TeamsStep, because the tenant closed the webhook (11/10, see TAM TeamsNotifier).

Built in speed-merchants (uncommitted): `EmailStep` DTO, `EmailStepExecutor`, `IEmailSender`/`SmtpEmailSender`, `EmailSettingsConstants` (EmailSettings:* keys + `Teams:ChannelEmail`, token `{{$config:Teams:ChannelEmail}}`), LogTag `EMAIL`, factory/converter/DI/orchestrator alias+validation, `EmailStepEditorCard`, editor add-step default (ContinueOnError=true), NormalizeStepType x3, CrewChief export Supported (+Email, test 18/17), `StepGuide_EmailStep.md` + index. 16 EmailStepExecutorTests (incl. timeout, orchestrator by both type strings) + exporter test; 430 related unit tests pass; Integration project builds. Send bounded by TimeoutSeconds (orchestrator enforces none). No built-in {{ScenarioName}} token; default subject uses {{$config:WebUI:ExecutionMachine}}.

11/16 live test: laptop trusts SMVMTR1 TestAuto self-signed cert 5310F35D… (LocalMachine\Root; Gene chose this over a corp Web Server cert). Added TestAutoUtilityType Email row via ScenarioMgt REST (key file C:\Deploy\Secrets\ProductionApiKey.txt, Gene-provided). Workflow 10000682 "EmailStep smoke test" ran as execution 10000636 / WorkloadExecution 100011457 on SMVMTR1: step Succeeded, SMTP smtp.office365.com:587 accepted the mail in ~2 s, but NOTHING posted in the Teams channel. SMVMTR1 TestAuto log = C:\Deploy\TestAuto\web\LogFiles\SystemLog_NNN.log (not Seq/PROD tSystemLog). Next: check sender mailbox for bounce (NDR) and channel email Advanced settings (allowed senders).

**Why:** run scenarios with Teams notifications. **How to apply:** open items: (1) add `Email` row (Code=Email, FileExtensionTypes=.txt) to TestAutoUtilityType on PROD speedmerchants — Gene approved me doing it, but reading the REST key from secrets was blocked, so Gene adds it or gives me the route; (2) add EmailSettings + Teams sections to each box's TestAutoSecrets profile, restart; (3) real SMTP send to the channel not yet verified. Related: [[reference_scenariomgt_rest_writes_prod_4000_limit]].
