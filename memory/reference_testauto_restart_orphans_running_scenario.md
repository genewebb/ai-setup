---
name: reference_testauto_restart_orphans_running_scenario
description: Restarting/redeploying TestAuto.Web mid-workflow kills the in-process Hangfire scenario job (e.g. Connect Poll); it is never resumed and the execution stays Running forever
metadata:
  node_type: memory
  type: reference
  originSessionId: 4dd36d8c-694d-4696-be28-10c24d7ba30b
  modified: 2026-11-04T00:20:12.712Z
---

Seen 2026-11-03 on SMVMTR1 (Synapse 1M 8T export, execution 10000321): the Poll job (ConnectStrategyPollingScenario) was queued 14:38:05; a TestAuto.Web restart at 14:38:36 logged "scenarioserver-scn-connectstrategypollingscenario ... stopped non-gracefully". After restart (and two later redeploys) no Poll log line ever appeared; WorkloadExecution stayed Running, WorkflowMonitorJob kept checking it every minute. The Connect batch itself finished fine, but the run's metrics were lost and the run had to be cancelled and redone.

Second effect: the dead job stays "Processing" in Hangfire (#6115, on a server that no longer exists) through later restarts, and TestAuto's ScenarioDispatcher counts it ("desired: 1, running: 1, toEnqueue: 0"), so EVERY later Poll of that scenario type silently never starts. Check /hangfire/jobs/processing. Gene's fix 11/03 19:00: stop service, drop the Hangfire DB, restart; Poll then dispatched normally.

**How to apply:** never redeploy/restart TestAuto while a measured workflow runs (check data.vTestAutoWorkflowExecution for Running first). A run "Running" far past its expected time: compare connex.tBatch ProcessingState on the Profisee DB with the TestAuto scenario status, then grep SystemLog_*.log under C:\Deploy\TestAuto\web\LogFiles for "stopped non-gracefully". Related: [[project_connect_test_board_2026-10-30]], [[project_crewchief_schedules_2026-11-03]].
