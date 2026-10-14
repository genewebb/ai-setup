---
name: testauto-matching-source-data
description: >
  200M-record matching test dataset reference: source systems, codes, offsets, and mutation types. Use when configuring matching scenario record pools, setting offset parameters, debugging unexpected match counts, or understanding how test records are distributed across matching scenarios.
---

Repo: speed-merchants (paths below are repo-relative)

# TestAuto Matching Test Dataset Architecture

The matching performance tests operate against a dataset of approximately 200 million records drawn from two ModelSource tables. About 50 million unique base records live in `ModelSource.dbo.RetailClient` under source system codes 1 (Template Records), 2 (NPPES), and 3 (Generated Records). An additional 150 million mutated records live in `ModelSource.dbo.RetailClientCloned` under source system codes 20 (Dynamics), 30 (JDE), and 40 (SalesForce). The cloned records are produced by the matching mutation tool, which applies realistic data-quality variations to the base records. All six source system codes retain their original codes when loaded into the Profisee model; the matching engine then produces MDM golden records as a seventh source. Each test scenario draws a defined slice of these records using keyset-pagination offsets so that scenarios never overlap and holdout records stay truly unseen.

## Source Systems

### Primary Source Systems — `ModelSource.dbo.RetailClient` (~50M total)

| Name              | Code | Record Count | Purpose                                      |
| ----------------- | ---- | ------------ | -------------------------------------------- |
| Template Records  | `1`  | 3,000,000    | Manually created test records                |
| NPPES             | `2`  | 6,881,257    | National Provider data (healthcare)          |
| Generated Records | `3`  | 40,118,743   | Programmatically generated unique records    |
| **TOTAL**         |      | **~50M**     |                                              |

### Cloned Source Systems — `ModelSource.dbo.RetailClientCloned` (150M total)

| Name       | Code | Base Source  | Record Count | Purpose                        |
| ---------- | ---- | ------------ | ------------ | ------------------------------ |
| Dynamics   | `20` | SS 1, 2, 3   | 50,000,000   | Microsoft Dynamics integration |
| JDE        | `30` | SS 1, 2, 3   | 50,000,000   | JD Edwards integration         |
| SalesForce | `40` | SS 1, 2, 3   | 50,000,000   | Salesforce CRM integration     |
| **TOTAL**  |      |              | **150M**     |                                |

Reference table: `ModelSource.dbo.SourceSystem`

### Profisee Model Source Systems (after load)

In the Profisee model you will see source systems **1, 2, 3, 20, 30, 40, MDM**. Source system codes are preserved 1-to-1 during load; the matching engine creates MDM golden records as the only additional code.

## Mutation Types

The matching mutation tool applies the following variation types to base records when generating the cloned source systems (SS 20, 30, 40):

- **Typos** — intentional misspellings in names and addresses
- **Abbreviations** — e.g., "Street" → "St", "Avenue" → "Ave"
- **Missing Data** — selective removal of field values
- **Format Variations** — alternate phone number and date formats
- **Transpositions** — swapped characters or words
- **Case Changes** — mixed-case variations

These mutations ensure the matching algorithms are exercised against realistic data-quality issues.

## Scenario-Specific Record Distributions

### Scenario 1: Initial Load (Empty Model)

Loads N records into an empty model. All records are **CREATEs** (100% new).

Default configuration (15M total):

| Source System | Code | Records Used | Max Available  |
| ------------- | ---- | ------------ | -------------- |
| Template      | `1`  | 3,000,000    | 3,000,000      |
| NPPES         | `2`  | 3,000,000    | 6,881,257      |
| Generated     | `3`  | 9,000,000    | 40,118,743     |
| Dynamics      | `20` | 0 (optional) | 50,000,000     |
| JDE           | `30` | 0 (optional) | 50,000,000     |
| SalesForce    | `40` | 0 (optional) | 50,000,000     |

Rules: sum of all source system counts must equal `TotalRecords`; no source system count may exceed its available records. Records are pulled in `Code` order (TOP N). Loaded in batches of 50,000.

**Post-Scenario 1 offsets established:**

| Source System | Rows Used     | Next Available Row |
| ------------- | ------------- | ------------------ |
| SS 1          | 1–3,000,000   | 3,000,001 (all used) |
| SS 2          | 1–3,000,000   | 3,000,001          |
| SS 3          | 1–9,000,000   | 9,000,001          |

### Scenario 2: Operational Batch Load (CM ON)

Simulates a nightly batch load against an already-matched model.

- **85%** Changed records — sourced from Dynamics (20), JDE (30), SalesForce (40)
- **15%** New records — sourced from SS 1, 2, 3 starting **after** Scenario 1's offsets

### Scenario 3A: Lookup Stress Test

Maximum lookup throughput test. Uses existing matched records already in Profisee, filtered by `MatchStatus IN (20, 30, 40, 50)` and retrieved via REST API. No new source data is consumed.

### Scenario 3B: Lookup Scoring Test

Tests the scoring engine with fuzzy matching against records the matching engine has **never seen**.

Configuration (offset-based example):

| Parameter             | Value     | Meaning                                     |
| --------------------- | --------- | ------------------------------------------- |
| `OperationType`       | `LookupThenCreate` | Wizard `Template_Scenario3B` (`TestAuto.Web/Components/Controls/UnifiedMatchingScenarioEditor.razor.cs:231`). The shipped sample still says `LookupOnly` (`TestAuto.Matching/Samples/TestCases/Small/UnifiedMatching_Scenario3B_LookupScoring_Small.json:28`) — both are live; see [[testauto-matching-scenarios]] |
| `RecordSource`        | `NewValuesOnly` | Wizard and sample agree (`razor.cs:232`, sample `:29`) |
| `HoldoutSourceSystem` | `3`       | Pulls from Generated Records (SS 3)         |
| `HoldoutStartAfterRow`| `9000000` | Start after Scenario 1's 9M rows from SS 3  |
| `HoldoutRecordCount`  | `1000000` | Number of holdout records to submit         |

Available holdout pool: 40,118,743 − 9,000,000 = **~31M records** from SS 3.

Forces fuzzy scoring on four attributes: `FirstName`, `LastName`, `AddressLine1`, `FullName`.

### Scenario 3C: LUBC (Lookup, Update, Batch, Create)

Full user-simulation cycle. The wizard template is **all creates**:

- **`NewPercent` = 100** — the whole pool is new values
- **`CreatePercent` = 100 / `UpdatePercent` = 0** — no update leg

Source: `ApplyScenarioTemplate` case `Template_Scenario3C`,
`TestAuto.Web/Components/Controls/UnifiedMatchingScenarioEditor.razor.cs:258-262`.

> The old **85% Create / 15% Update** split is what the wizard now applies to **3B**
> (`razor.cs:237-238`). Separately, the shipped 3C samples still carry an 85% Changed / 15% New
> `Mixed` distribution
> (`TestAuto.Matching/Samples/TestCases/Small/UnifiedMatching_Scenario3C_Continuous_Small.json:50-81`)
> — that is a Changed-vs-New source split, not a Create-vs-Update split. Both configurations are
> live; see [[testauto-matching-scenarios]].

## Offset Management

### Why Offsets Matter

Offsets ensure test isolation and reproducibility across scenarios:

- Scenario 1 consumes rows 1–N from each source system.
- Scenario 3B requires "unseen" records; it must start after Scenario 1's rows.
- `RecordMixManager` uses these offsets to select the correct page of records.

### Configuration Pattern

Offsets are set as flat CustomParms on the scenario configuration:

| Parameter                    | Applies To                                    |
| ---------------------------- | --------------------------------------------- |
| `NewRecordStartingOffset`    | Source systems with code < 10 (SS 1, 2, 3)   |
| `ChangedRecordStartingOffset`| Source systems with code >= 10 (SS 20, 30, 40)|

For Scenario 3B, `HoldoutStartAfterRow` is an alias for `NewRecordStartingOffset`.

### Implementation Details

- `RecordMixManager` uses **keyset pagination** — not SQL `OFFSET`/`FETCH`.
- At initialization, `GetStartingCodeForPositionAsync()` runs a one-time query to find the `Code` value at position `partitionStart + offset`.
- All subsequent batch queries use: `WHERE SourceSystem = @SS AND Code > @lastCode ORDER BY Code`
- Validation rules: offsets must be >= 0; `ChangedPercent + NewPercent` must equal 100 for mixed-mode scenarios.

## Decision Table: Source Code by Scenario

| Scenario | Source Codes Used                       | Record Type          | Offset Dependency           |
| -------- | --------------------------------------- | -------------------- | --------------------------- |
| S1       | 1, 2, 3 (optionally 20, 30, 40)         | 100% Creates         | None (starts at row 1)      |
| S2       | 20, 30, 40 (85%) + 1, 2, 3 (15%)       | Mixed (new + changed)| `NewRecordStartingOffset` after S1 |
| S3A      | None (reads from Profisee via REST)     | Lookups only         | None                        |
| S3B      | 3 (holdout slice)                       | Lookup, then create on miss | `HoldoutStartAfterRow` = 9,000,000 |
| S3C      | Wizard: new values only. Samples: 20/30/40 (85%) + 1/2/3 (15%) | Wizard: 100% Create. Samples: 85% Changed / 15% New | Context-dependent |

> **S3B is not lookup-only.** The wizard sets `OperationType = LookupThenCreate` for 3B
> (`TestAuto.Web/Components/Controls/UnifiedMatchingScenarioEditor.razor.cs:231`), and that arm
> genuinely writes: `ExecuteLookupThenCreateAsync` sends the lookup, **skips the create when a match
> is found** (`TestAuto.Matching/Services/MatchingOperationExecutor.cs:195`) and **proceeds to create
> when no match is found** (`:203`). So a wizard-built 3B run consumes its holdout slice and can add
> records to the target entity — plan offsets and cleanup accordingly. Only S3A
> (`OperationType = LookupOnly`, `razor.cs:212`) is read-only.

## Sources

- `TestAuto.Matching\Documentation\SourceSystemsAndTestData.md`
