---
name: reference_profisee_gateway_record_paging_400
description: Profisee REST gateway answers 400 (not an empty page) for a PageNumber past the last — walk-until-empty pagers break on exact multiples
metadata: 
  node_type: memory
  type: reference
  originSessionId: b085d44c-6642-41f4-9aca-4ff12d6dc36e
  modified: 2026-08-16T03:03:00.681Z
---

Verified 2026-08-15 on CORPLTR94 against `v1/Records/PDATA120` with 1000 rows:

- `?PageSize=200&PageNumber=5` → 200 OK, 200 rows, `totalPages: 5`
- `?PageSize=200&PageNumber=6` → **400 Bad Request**
- `?PageSize=200&PageNumber=7` → **400 Bad Request**

So the common "page until a page comes back empty" idiom **throws** whenever the row count divides exactly by the page size — there is no empty page to stop on, only a 400. It looks correct in testing precisely because a partial final page is the usual case; an exact multiple is what breaks it.

Stop by the envelope's `totalPages` (or accumulate against `totalRecords`) and never request a page past the last. Breaking on a short page is still a fine *additional* guard, just not sufficient on its own.

Envelope keys: `pageNumber, pageSize, resultCount, totalPages, previousPage, nextPage, totalRecords, data, errors`.

Other gateway shapes confirmed the same session:
- Records list: `GET v1/Records/{entity}` — **not** `v1/Entities/{entity}/Records` (404).
- Record delete: `DELETE v1/Records/{entity}/{code1,code2,...}` (comma-separated **path** segments) → 200. A JSON body → 400; `?codes=` → 400.
- ConnEx resource delete: `DELETE v1/Connect/{Configurations|Strategies|ServiceProviders}?{ConfigurationUids|IntegrationStrategyUids|ServiceProviderUids}={id}` → 204. Path form → 405. See [[project_crewchief_connex_import_three_bugs]].
