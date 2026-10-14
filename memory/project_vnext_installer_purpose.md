---
name: vnext-installer-purpose
description: "Why the vNext agent installer and Windows service exist: unattended start/restart on domain Windows boxes and setup for non-technical users — NOT a goal in itself"
metadata: 
  node_type: memory
  type: project
  originSessionId: 25a6f180-ace3-4c16-9718-60b837d6c54c
  modified: 2026-09-07T22:27:57.650Z
---

**Gene, 2026-09-07 16:50: "Just confirm the reason for an install or service is only to facilitate the setup or
restart, we don't want to do it just because but if it can help configure the setup for non users that was the
goal."**

So the installer and the Windows service are JUSTIFIED BY THREE THINGS AND NOTHING ELSE:
1. **Unattended start** — the agent comes up on boot with nobody logged in.
2. **Restart and recovery** — the SCM restarts a crashed or timed-out agent.
3. **Setup a non-expert can complete** — the wizard picks roles, sets the service account and grants its logon
   right, ACLs the secrets folder, and seeds secrets on first run.

**THE AUDIENCE IS SETTLED (Gene, 2026-09-07 18:21):** "An employee which could be a developer, a tester, or a
QA person sets up the machine. Assume they need to double-click and follow screens." So the **wizard is
confirmed** over a PowerShell script, and the ~500 remaining minutes of installer rows are approved work.
Design consequence worth holding on to: these people can read an error message and are not frightened of a
service account, but they must never need a command line, and they do not know the product's internals. Every
screen should say what it is asking for AND WHY, not merely what to type.

**Anything not serving one of those three is gold-plating and should be cut, not built.** Explicitly out:
a self-update feed, a service-restart button, a web UI for the agent. (The donor TestAuto has all three; they
exist there because it is an interactive web app, and [[reuse-donor-installers]] harvests its startup facts,
not its features.)

**Where the service genuinely earns its place, and where it does not.** Docker already gives unattended start
and restart for the containerised fleet — `compose.yaml`'s `fleet` service runs `restart: unless-stopped` and
needs no installer at all. The Windows service is for the boxes containers cannot serve: the domain-joined
Windows machines in the R28 topology, where the agent needs a DOMAIN IDENTITY to do what a Linux container
cannot — Windows auth to SQL, the LocalAdmin capability check (which came back Unknown on Ubuntu in both the
P7 and P9 proofs), and anything touching a real service account. **State this whenever the service's value is
questioned: containers cover the container case; the service covers the domain-Windows case.**

**How to apply.** Every row in the 59.x block must name which of the three reasons it serves. Rows 59.3 (roles
page), 59.4 (credentials and the LSA logon right), 59.5 (reconcile on re-run and uninstall) and 59.6 (secrets
bootstrap and the folder ACL) serve reason 3 directly. Rows 59.2, 59.7 and 59.8 are packaging mechanics —
unavoidable overhead once you ship an installer at all, not value in themselves. Row 59.1 (the `serve` verb
with an SCM lifetime) is the prerequisite for reasons 1 and 2 and buys nothing on its own. Row 59.9 is the
proof. If the audience turns out to be only technical staff, the wizard's value drops sharply and a
PowerShell setup script would serve reasons 1 and 2 at a fraction of the 710 estimated minutes — worth
re-asking before the wizard rows start.
