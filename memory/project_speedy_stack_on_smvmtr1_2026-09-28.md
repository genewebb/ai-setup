---
name: project_speedy_stack_on_smvmtr1_2026-09-28
description: Gene wants the whole Speedy compose stack running on SMVMTR1, not SMVMTR2; built and started there 2026-09-28 with a fresh .env SA password
metadata:
  type: project
---

Gene's standing preference as of 2026-09-28: **everything runs on SMVMTR1** (the stream hub), not SMVMTR2. This supersedes the "TR2 = deployed stack" half of [[project_stream_host_smvmtr1_2026-09-28]].

On 2026-09-28 the compose stack was built and started on SMVMTR1 for the first time: `docker compose build` then `docker compose up -d --wait`, both exit 0. Running: warehouse + rabbitmq (healthy), web, coordinator, fleet, throttle; `migrate` and `backup-setup` are one-shot and exit 0 by design. Web answers on http://127.0.0.1:5310.

Before that build the host had no Speedy images, containers or volumes at all — Rancher Desktop and the engine were up, which is why "no containers" was not a crash. `docker ps -a` empty on a working engine means nothing was ever built on the host.

`compose.yaml` requires `SM_SA_PASSWORD` (`:?` form, no default anywhere). A root `.env` was created with a generated password; `/.env` is gitignored. That password is baked into the `warehouse-data` volume at first `up` — editing `.env` afterwards does not change the container.

Caveat for rebuilds: images are built from the working tree, and the stream integrator applies patches to that same tree continuously, so an image is a snapshot of whatever was on disk. Rebuild after a group closes, not mid-integration.

Related: [[project_stream_host_smvmtr1_2026-09-28]], [[reference_rancher_desktop_autostart_is_login_scoped]].
