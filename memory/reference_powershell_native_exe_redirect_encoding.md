---
name: reference_powershell_native_exe_redirect_encoding
description: PS7 ">" redirect of a native exe crosses two encoders (producer locale codepage + Console::OutputEncoding ibm437); fixing one silently yields U+FFFD
metadata:
  type: reference
---

On this machine `[Console]::OutputEncoding` is **ibm437** and CPython picks
**cp1252** for `sys.stdout` when stdout is a pipe (not a console). A
`somepythonexe file > out.md` redirect therefore crosses TWO encoders.

Fixing only one is worse than fixing neither: setting `[Console]::OutputEncoding`
to UTF-8 alone makes the file *validate* as UTF-8 while every non-ASCII char
has already become U+FFFD (`\xef\xbf\xbd`). Verified 2026-08-25: `\xe2\x80\x99`
(U+2019) survived only when BOTH were set.

Working wrapper pattern (save/restore in `finally` so the session is untouched):

```powershell
$prevEnc = [Console]::OutputEncoding
$prevPy  = $env:PYTHONIOENCODING
try {
    [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
    $env:PYTHONIOENCODING = 'utf-8'
    & $exe @args
}
finally {
    [Console]::OutputEncoding = $prevEnc
    $env:PYTHONIOENCODING = $prevPy
}
```

Diagnostics: `[Console]::OutputEncoding.WebName` vs `$OutputEncoding.WebName`
(different things - the latter is stdin-side and is already utf-8, a red herring).
Check the producer with `exe -c "import sys; print(sys.stdout.encoding)" | cat`.
Prefer a tool's own `-o/--output` flag when it has one - that bypasses both layers.

Related: [[project_ds918_nas_deployment]], [[reference_powershell_script_contract_gotchas]]
