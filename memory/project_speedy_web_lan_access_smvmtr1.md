---
name: project-speedy-web-lan-access-smvmtr1
description: Speedy dev web on SMVMTR1 reachable from LAN at https://smvmtr1.corp.profisee.com:5310/ via the SpeedyTlsProxy Windows service with the corp machine cert (owner 2026-10-11)
metadata:
  node_type: memory
  type: project
  originSessionId: 28c88d04-48e0-401b-b479-5ac38afd10e0
  modified: 2026-10-11T18:15:02.836Z
---

Owner asked 2026-10-11 to reach the dev stack's web UI from a laptop without importing certificates.
compose.yaml binds 5310 to loopback on purpose (48.RV12); compose is untouched.

- Windows service `SpeedyTlsProxy` (LocalSystem, auto, restart on failure), exe in C:\Deploy\SpeedyTlsProxy, source
  D:\devops\tools\speedy-tls-proxy (YARP 2.3.0, net10.0). Listens 10.0.0.6:5310 with the corp cert from
  LocalMachine\My, picked by SAN SMVMTR1.corp.profisee.com + issuer corp-CORPIT01-CA + Server Auth (never by
  thumbprint, so autoenrollment renewals work; today E803B0F9, valid to 8/4/2027). Forwards to https://127.0.0.1:5310,
  keeps the original Host, sends no X-Forwarded-*.
- Firewall rule "Speedy web 5310 (LAN)", TCP 5310 on 10.0.0.6, Domain profile.
- The container itself serves the self-signed speedy-web-lan.pfx (thumb 5310F35D, SANs incl. 127.0.0.1, in
  LocalMachine\Root) so the proxy can validate the backend strictly.
- `.env.local` ExternalUrl=https://smvmtr1.corp.profisee.com:5310/. Backup .env.local.bak-202610111352.

**Why:** the corp cert key is NOT exportable (template PublishedRDPCertificate), and a Linux container cannot read
the Windows store. TestAuto/CrewChief can use the cert only because they are Windows services. The short name
`smvmtr1` is not in the corp cert's SAN, so only the FQDN URL validates. Changing ExternalUrl puts setup into
SupersededByConfigurationChange; fleets exit 2 until the owner re-confirms at /setup.

**How to apply:** rerunning scripts/e2e/Write-SpeedyStackEnv.ps1 reverts .env.local to localhost and the dev cert,
which also breaks the proxy's backend validation. Owner wants this as an install-setup option: stream-plan item
IN-20261011181452-7666.
