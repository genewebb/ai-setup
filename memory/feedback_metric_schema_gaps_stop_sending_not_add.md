---
name: feedback-metric-schema-gaps-stop-sending-not-add
description: "TestAuto \"[METRICS] model schema gaps\" 8609 errors = stop sending the columns in code; never add attributes to the metrics model"
metadata:
  node_type: memory
  type: feedback
  originSessionId: 21272085-869a-453c-8763-8bb1bdd7874c
  modified: 2026-10-16T14:56:34.992Z
---

When TestAuto logs "[METRICS] Entity 'X' has model schema gaps ... 8609/8617", fix it by NOT sending the missing columns: redeclare the base property with `new` and no `[MetricColumn]` on the entity's detail class (forward get/set to base). Do NOT add attributes to the Profisee metrics model.

**Why:** Gene, 2026-10-16 (RecordApiExecution + RecordInteractiveApiExecution, SMVMTR2 7.0.38): "we do not want to add to the metrics just fix that they are not sent as they do not exist".

**How to apply:** Read the entity's real attributes (speedMcpRemote get_attributes_by_entity), diff against what BaseMetricDetailPersistenceHandler.MapDetailToRecord emits (TimeSpan props also emit `<col>_Ms`). Fixed example: TestAuto.Records/Metrics/MetricDetailRecordApi.cs + test Testing.SpeedMerchants.Unit/Tests/Records/MetricDetailRecordApiPersistenceTests.cs. Same pattern as Connect / UnifiedMatching detail classes.
