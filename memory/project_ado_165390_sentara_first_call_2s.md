---
name: project_ado_165390_sentara_first_call_2s
description: ADO Issue 165390 (Sentara SaaS, case 00044200) first API call after idle ~2 s; customer data falsified the 30 s channel-cache theory, threshold sits between 45 s and 180 s; code facts and next step
metadata:
  type: project
---

ADO Issue 165390, Sentara Healthcare SaaS (2025r4-159459), support case 00044200. Assigned to Gene, Sev 2 High, iteration Skeletor 5, state New, no links.

Facts from code (rest-api repo, local copy 2026-03-27 and ADO master both agree):
- `Gateway.Infrastructure/WCFClient.cs` caches the WCF ChannelFactory in IMemoryCache keyed by token+url with `SlidingExpiration = 30 s`. Never sets `ConnectionPoolSettings`, so net.tcp pool IdleTimeout is the WCF default (2 min).
- API-key to token cache (`ApplicationBuilderExtensions.UseGetTokenFromApiKey`) expires at ExpiresIn minus 30 s; auth default `AccessTokenLifetime` = 3600 s, so token expiry is NOT the 2-minute mechanism unless SaaS overrides it.
- RecordService caches entity and attributes for 5 s; records go to the data service through a static `HttpClient` in `data/Utilities.Data/Client/DataClient.cs` with default pooling.

Customer data (3 rounds, 2026-09-15): 10 s and 45 s idle fast (73-156 ms), cold and 3 min idle slow (2.1-2.3 s), delay entirely server-side. 45 s fast kills the 30 s channel-cache theory. Two backend IPs seen.

**Why:** the next step is not another customer round; pull Gateway Serilog request logs and OpenTelemetry spans from the SaaS tenant for the CSV timestamps to see which hop holds the 2 s.
**How to apply:** interim answer for the customer = heartbeat every 45 s or less with the SAME api key (caches keyed per token). Related: [[project_ado_165390_bisection_ask]] never answered as of 2026-09-22.
