---
name: reference_no_venvs_on_nas_d_drive
description: D:\ is SMB-mapped NAS - never put Python venvs or toolchains there; measured 55s vs 4.6s CLI startup
metadata:
  type: reference
---

`D:` is `\SynologyDS918\devopslocal` over SMB (see `net use`). Source repos are
fine there; **installed toolchains are not**.

Measured 2026-08-25 with markitdown[all] (onnxruntime + numpy + pandas +
pypdfium2): cold `--help` took **54.8s** from a venv on `D:`, **4.6s** warm from
a venv on `C:`. Every import is a network read.

Pattern: keep the repo on `D:`, put the venv on local disk
(`C:\Users\<user>\.venvs\<tool>`), and editable-install the NAS source into it:

```
py -3.13 -m venv "$env:USERPROFILE\.venvs\<tool>"
& "$env:USERPROFILE\.venvs\<tool>\Scripts\python.exe" -m pip install -e "D:/repos/<repo>/packages/<pkg>[all]"
```

Elevation note: mapped drives are per-user and invisible to elevated shells, but
pip rewrites the editable `.pth` to the **UNC** path
(`\SynologyDS918\devopslocal\...`) automatically, so the install keeps working
elevated. Do not hand-write `D:\` paths into profiles.

Related: [[project_ds918_nas_deployment]]
