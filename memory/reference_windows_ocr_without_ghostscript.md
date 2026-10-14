---
name: reference_windows_ocr_without_ghostscript
description: OCR scanned PDFs on Windows with tesseract + pypdfium2 and no Ghostscript; winget source is broken on this box (0x8a15000f)
metadata:
  type: reference
---

**winget is broken on this machine.** `0x8a15000f : Data required by the source
is missing` persists after `winget source reset --force` + `winget source update`
(both reported Done). Do not burn turns on it - install from the upstream GitHub
release directly.

Verified-working direct installs (2026-08-25):
- Tesseract: `UB-Mannheim/tesseract` releases, `tesseract-ocr-w64-setup-*.exe`,
  silent with `/S`. Lands in `C:\Program Files\Tesseract-OCR\`. Ships `eng`+`osd` only.
- Ghostscript: `ArtifexSoftware/ghostpdl-downloads`. **`/S` does NOT work** - the
  installer shows a GUI dialog anyway and hangs any unattended `Start-Process -Wait`.
  Detect via `Get-Process | ? MainWindowTitle`.

**Skip Ghostscript entirely.** `ocrmypdf` hard-requires it, but the real pipeline
(rasterize -> OCR -> text) only needs a renderer, and `pypdfium2` (a pdfplumber
dep, so already present alongside markitdown) does it:

```python
pdf[i].render(scale=dpi/72).to_pil().save(png)
subprocess.run([TESS, png, out, "-l", "eng", "--psm", "1"], check=True)
```

Script kept at `C:\devopslocal\powershellscripts\ocr_pdf.py` (args: src dst [dpi]).
Use 300 DPI - Tesseract's models are trained near that density.

Quality check an OCR result before trusting it: alphabetic-character ratio >65%
is healthy. Proper nouns still misread (a 19-page scan rendered "Last Will and
Testament" as "Last Dill and Testament").

Related: [[reference_powershell_native_exe_redirect_encoding]]
