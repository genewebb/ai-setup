---
name: project-speedmerchants-dual-runprofile-migrator
description: "OPEN defect - two speedmerchants migrators create dbo.RunProfile with different shapes, silently, order-dependently"
metadata: 
  node_type: memory
  type: project
  originSessionId: e187904d-af49-4c2a-a448-6071056cf6a8
  modified: 2026-08-30T23:30:43.884Z
---

**OPEN as of 2026-08-30.** Found by the K5 executor (vNext UoW-6 iteration 9), correctly left unfixed —
both files were outside its allowed set. **Owed before UoW-7.**

Two migrators in `C:\devops\repos\speedmerchants` create **`dbo.RunProfile`**, with different shapes,
each guarded by `IF OBJECT_ID(N'dbo.RunProfile', N'U') IS NULL`:

| Column | `src/Infrastructure/Warehouse/WarehouseMigrator.cs` | `src/Infrastructure/Runs/RunProfileMigrator.cs` |
| --- | --- | --- |
| `ContentHash` | **absent** | `CHAR(64) NOT NULL` |
| `CapturedUtc` | **absent** | `DATETIME2 NOT NULL` |
| `Machines` | `NVARCHAR(500) NULL` | `NVARCHAR(2000) NOT NULL` (defaulted) |

**Whichever runs first silently wins, and the loser breaks in a different place each way:**

- **Warehouse first** → the RunProfile store's insert fails. Measured verbatim: `Could not migrate the
  run profile tables in 'SpeedmerchantsWarehouse': Column name 'ContentHash' does not exist in the
  target table or view.`
- **Run-store first** → `SqlClientWarehouseSink`'s skeleton insert is literally
  `INSERT INTO dbo.RunProfile (RunId)`, which cannot satisfy two NOT NULL columns that have no
  default — so **every metric drain fails**, breaking the zero-loss guarantee UoW-2 proved.

**Latent today only because compose gives the two stores separate catalogs.** The moment they share
one — which the K5 proof did — one side dies. The `IF OBJECT_ID IS NULL` guard is what makes it silent:
the second migrator reports success having created nothing.

This is the exact defect class vNext exists to eliminate — a component reporting success while what it
claims to have created is wrong. Fix by giving the two tables one owner (or two names), never by
adding a column to whichever side happens to lose.

The K5 proof works around it honestly: it takes its own catalog `SpeedmerchantsRunProfileProof`,
dropped and recreated per run, rather than papering over the collision.

Pairs with [[project_vnext_due_diligence_2026-08-28]] and
[[reference_speedmerchants_vnext_sut_testbed]].
