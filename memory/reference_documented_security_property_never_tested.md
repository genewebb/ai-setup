---
name: reference_documented_security_property_never_tested
description: "A security property copied from vendor docs into your own notes reads like a measured fact a month later — RabbitMQ's loopback_users belief was recorded twice in speedmerchants and was false through Docker."
metadata: 
  node_type: memory
  type: reference
  originSessionId: aa701f44-5fa5-4edf-ae81-2fc43ee32e4c
  modified: 2026-09-11T14:24:17.119Z
---

Measured 2026-09-11 in `speedmerchants` (row 48.RV12c).

## What happened

`compose.yaml` published RabbitMQ on `0.0.0.0:5672`, `0.0.0.0:15672` (management UI) and
`0.0.0.0:15692`, plus SQL Server on `0.0.0.0:14400`. Two archived planning docs recorded that this was
safe:

- `.loop-archive-uow4/GOAL.md:57` — *"default user is localhost-restricted by RabbitMQ policy"*
- `.loop-archive-uow4/GOAL.md:38` — *"guest/guest works only on localhost — fine here"*

RabbitMQ genuinely does ship `loopback_users = [guest]`. The statement was true of the product and
false of **this deployment**:

```
GET http://127.0.0.1:15672/api/overview      stock account -> 200
GET http://192.168.8.208:15672/api/overview  stock account -> 200   <-- LAN, accepted
```

**Why the rule does not fire through Docker:** a port published on `0.0.0.0` reaches the container
from the **bridge gateway**, not from `127.0.0.1`. A loopback rule cannot recognise a remote client as
remote when every client arrives wearing the gateway's address. Full broker control — create/delete
queues, purge, publish, read — was available to anything that could route to the box, on four LAN
addresses.

## The transferable part

**A security property taken from documentation and written into your own project notes is
indistinguishable from a measured one a month later.** It had survived two archived units and a
census that explicitly named the port. Nobody was careless; the note was simply never a measurement.

The same shape of comfort, elsewhere in the same repo: *"`SM_SA_PASSWORD` has been required since
59.3e, so no default password ships."* True, and **a required password is not a closed port.**

## The habit

When a note asserts a containment property, test it from the outside before relying on it. Two
commands settle it, and neither needs a second machine — connecting to the host's OWN LAN address is
a non-loopback connection as far as the service is concerned:

```powershell
Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -notmatch '^(127\.|169\.254)' }
Test-NetConnection -ComputerName <that address> -Port <port>
# then actually authenticate, because reachable and accepting are different facts
```

Fix was `127.0.0.1:` prefixes on all four mappings plus `docker compose up -d`; both services keep
state in named volumes so nothing was lost, containers reach each other by service name on the compose
network so nothing broke, and three warehouse-dependent criteria re-ran clean afterwards.

Related: [[reference_speedy_azure_central_warehouse]] · [[feedback_verify_no_guessing]] ·
[[reference_gate6_false_reds_ordering_and_libraries]]
