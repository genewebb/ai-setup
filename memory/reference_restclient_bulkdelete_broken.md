---
name: reference-restclient-bulkdelete-broken
description: "IRestClient.BulkDeleteRecordsAsync REMOVED 10/8 (it always 404'd); delete by code = DeleteRecordsAsync + SplitRecordCodesForQuery; gateway DELETE Records/bulk/{entity} wipes the WHOLE entity"
metadata:
  node_type: memory
  type: reference
  originSessionId: 2e872688-f90d-435a-b363-0e499a7c56ac
  modified: 2026-10-08T16:40:39.800Z
---

Until 2026-10-08, speed-merchants `IRestClient.BulkDeleteRecordsAsync` never deleted anything. The facade POSTed to `Records/bulk`, which has no entity and is not a real route, so every call returned 404. It was found when a Run Purge failed 3 of 3 runs with 404. The same bug meant Production Sync deletes never landed, and its loop re-read page 1 until it came back empty, so a failing delete spun forever.

Fixed 10/8 (uncommitted in speed-merchants; Gene approved "fix both + remove"):
- `BulkDeleteRecordsAsync` was removed from `IRestClient`, `RestClient`, `RecordDataFacade` and the fakes.
- `RestClient.DeleteRecordAsync` and `DeleteRecordsAsync` now escape codes with `RestRequestHelper.EscapeRecordCode`. Inside a code, `\` and `,` each get a leading `\`.
- `PathAndQueryBuilder.WithForceDelete` became `WithClearReferencesBeforeDelete` and sends `ClearReferencesBeforeDelete=true`. The old code sent `force`, which the gateway ignores, so clear-references was silently off for every caller.
- `RestRequestHelper.SplitRecordCodesForQuery` splits code lists so the URL-encoded `RecordCodes` value stays at or under 1800 characters.
- The Run Purge store and Production Sync both use the splitter.
- Production Sync now reads every code first and deletes after.

Gateway routes, verified from the local Swagger:
- `DELETE /v1/Records/{entity}?RecordCodes=&ClearReferencesBeforeDelete=` deletes by code.
- `DELETE /v1/Records/bulk/{entity}` deletes **ALL** records of the entity, plus history and DQ issues. Never point code at it.

Swagger says ClearReferencesBeforeDelete needs the Quick Update role and Update/Create/Delete permission on the related entities. This is unverified against the TestAuto API keys. If deletes that pass true start failing, check that permission first.
