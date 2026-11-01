---
name: reference_testauto_prod_sql_server
description: PROD TestAuto/speedmerchants metrics DB = Azure SQL wus2-pc-profisee-sqlserver-0 / pc-speedmr-prd-db, reached via speedmerchants-prod-mssql MCP (NOT CORPSQL03)
metadata:
  type: reference
---
PROD speedmerchants (TestAuto metrics, ScenarioMgt model) = Azure SQL `wus2-pc-profisee-sqlserver-0`, database `pc-speedmr-prd-db` (Gene confirmed 2026-10-31). Query it through the `speedmerchants-prod-mssql` MCP (SQL login). sqlcmd -E to CORPSQL03/speedmerchants is refused and is the wrong server.
Connect metrics: data.tConnectApiExecution joined to data.tConnectRunProfile on RunProfile=ID, filter rp.Code. Workflow runs: data.tTestAutoWorkflowExecution (status may still read Running after collection finished).
Related: [[project_connect_test_board_2026-10-30]]
