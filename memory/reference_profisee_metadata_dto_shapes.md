---
name: profisee-metadata-dto-shapes
description: "Live-verified Profisee gateway metadata DTO shapes and routes (entity fileCategories, attribute Identifier objects, attribute read route) from the 2026-08-19 TDG deploy-script debugging"
metadata: 
  node_type: memory
  type: reference
  originSessionId: d204104c-f778-4885-86a9-0ec54efcd4b0
  modified: 2026-08-19T19:46:43.375Z
---

Live-verified (CORPLTR94, 2026R2, 2026-08-19) while fixing TDG's emitted DeployModel.ps1 — three iterations, each a different gateway DTO/route mismatch:

1. **Entity create (`POST v1/Entities`) fileCategories**: name lives in `identifier.name`, NOT top-level `name`. Working shape: `{ identifier: { id: <guid>, name: "Record Avatar" }, isRecordAvatar: true, extensions: ".jpg, ..." }`. Top-level name → 10028 "File Category name cannot be blank" per entity.
2. **Attribute create (`POST v1/Attributes`)**: `identifier.entityId` is an Identifier OBJECT `{ id, name }` like modelId/domainEntityId — bare guid string → "Error converting value ... to type Identifier".
3. **Attribute READ route**: `GET v1/Entities/{entity}/attributes?pageSize=1000`; `GET v1/Attributes/{entity}` is 404 (v1/Attributes = POST/PATCH only). pageSize explicit or gateway default ~50 silently truncates (AttributeDataFacade.cs:85 does the same).
4. **BaseUrl** must end `/Profisee/rest` — `/Profisee` alone hits the portal and answers 401 even with a valid x-api-key (Swagger lives under /rest, so a key that "works in Swagger" proves nothing about the path).

All four fixes live in the emitted templates `TestData.Generation.Engine\Deploy\DeployModel.ps1` / `RemoveDeployedModel.ps1` (BaseUrl guard). Full P1M deploy (50 DBA entities + 120 attributes + reference data) succeeded end-to-end after these.

Related: [[project_perftestdata_generator]], [[reference_synonymlist_delete_and_baseurl]].
