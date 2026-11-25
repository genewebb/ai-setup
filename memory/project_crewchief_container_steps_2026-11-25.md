---
name: project_crewchief_container_steps_2026-11-25
description: "CrewChief ssh transport + WindowsContainerStep + SqlContainerStep built 11/25 (ba64e0c8); live Logs/WaitHealthy/Verify pass 01:15 (a99164a8); Deploy/Configure not yet live"
metadata:
  node_type: memory
  type: project
  originSessionId: 7986e46e-eb36-4bdb-a0ee-12f91e19b099
  modified: 2026-11-25T05:06:42.519Z
---

Gene 2026-11-24 23:50 (design D25/D26 in planning/Design_CrewChief_ProfiseeContainerTesting.md): CrewChief reaches
both lab VMs with ssh.exe through the Proxmox host (ProxyCommand nc, key sign-in, accept-new host keys); build
transport, then WindowsContainer and SqlContainer steps. Built and committed ba64e0c8 on
bug/isolation_testing_linux/genewebb; unit suite 4728 green (ContainerStepTests).

- Engine/Executors/Ssh (SshEndpoint, SshArguments, DefaultSshCommandRunner), Steps/SshStepBase.
- WindowsContainerStep actions Login/Pull/Run/Configure/WaitHealthy/Logs/Stop/Remove; values as base64 JSON on
  stdin; Configure = docker exec -i with fixed encoded inner script (recipe D24, see [[reference_profisee_container_hostname_binding]]).
- SqlContainerStep Deploy/Verify/Remove; .env mode 600; read-back keys compared in C#; Verify finds the container
  by compose labels, so it works on the harness-made tai-psql project too. tempdb tmpfs not ported.
- Not box-prep (no CredentialSecretName), so box-prep census unchanged; executor census 31.

Live 2026-11-25 01:15 (a99164a8): ContainerStepsIntegrationTests (RemoteLab, CREWCHIEF_SSH_TEST_* env vars) 4/4 pass.
App VM sshd: Administrator key only (administrators_authorized_keys), PasswordAuthentication no; built-in rule is
Private-profile only and the VM networks are Public, so rule TAI-OpenSSH-22 (TCP 22, 172.16.10.0/24). Known hosts:
C:\ProgramData\TestAutoIsolation\ssh\crewchief_known_hosts. Not live yet: SqlContainer Deploy (.env), Configure.

**Why:** app VM not domain-joined and only 443 forwarded, so WinRM design (C4) was dropped.
**How to apply:** live test needs OpenSSH Server enabled on the WS2025 app VM (after any measured run), keys, and
the host as jump. Never run against CorpProxMox01 during a measured run.
