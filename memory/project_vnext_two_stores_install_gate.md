---
name: vnext-two-stores-install-gate
description: "vNext has TWO SQL stores — the mandatory local warehouse (compose container on TestServer) and the optional named central repo (R27); the installer must VERIFY the local one, never create it"
metadata: 
  node_type: memory
  type: project
  originSessionId: 25a6f180-ace3-4c16-9718-60b837d6c54c
  modified: 2026-09-08T01:58:37.810Z
---

**Gene, 2026-09-07 21:56, distinguishing them:** "one container will have a sql instance that those use.
Now that is separate than the central repository that we can just not allow them to run or push metrics
until it is setup properly." Correct — they are two different stores with two different rules.

**1. The local warehouse — MANDATORY.** The SQL Server 2022 container `warehouse` in `compose.yaml`
(host port 14400, database `SpeedmerchantsWarehouse`). Both `Speedy:Warehouse:ConnectionString` and
`Speedy:Transport:ConnectionString` point at it, and `serve` fills both option slots from whichever is
set (`AgentRunner.cs:1158-1164`). Every run drains here ALWAYS. Schema comes from `speedy migrate`
(`CliRunner.cs:531`) — the agent never migrates. Per R28 the TestServer's control plane is "compose, no
installer", so **the warehouse belongs to the TestServer and the agent installer must never set it up**:
a shared resource migrated by each of a dozen agent boxes is a race, not a convenience. What the installer
owes is the other half — collect the address, open the connection, confirm the schema is present, and
refuse on the wizard page rather than letting the service fail at start.

**2. The central repository — OPTIONAL, and the refusal Gene wants ALREADY EXISTS.** R27/§5e: a run
declares `PublicationIntent` = `LocalOnly` (the default) or `Central(<name>)` once, on
`dbo.LoadWorkloadRun.DeclaredPublication`, insert-if-absent so it is immutable after launch. **An
unconfigured central is refused BY NAME before a run id is minted** — landed 2026-09-07 in row 47.H,
criterion 70. Centrals are configured as `Speedy:Publication:Centrals:<name>` (row 48.A, queued) and get
their own migration (row 48.F). Local always drains first; central is a publish step afterwards, never a
different drain target.

**Why the distinction matters:** the two need refusals at different moments. The central is opt-in per
run, so refusing at LAUNCH is right and is built. The local warehouse is not optional — without it there
is nothing to run at all — so refusing at launch is too late; it has to be refused at INSTALL. That is the
gap found closing row 59.7 (2026-09-07 21:20).

**How to apply.** Rows 59.4/59.6 must add a warehouse page: address, a real Test that opens the connection
and checks the schema, refuse Next on failure. It stores a password (the container authenticates as a SQL
login, not Windows auth — see [[feedback_install_dir_holds_all_artifacts]] for where it lands and
[[vnext-installer-purpose]] for why the installer exists). Windows auth applies to the DatabaseServer
under test, NOT to the warehouse container. Two open items nobody has written down: the container runs as
`sa` on a dev-only password, which is wrong for a real fleet; and the TestServer needs inbound 14400 and
5672 reachable, which no row currently owns.
