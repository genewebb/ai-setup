---
name: reference-pptx-deck-toolchain
description: How to build on-brand Profisee .pptx decks with python-pptx and visually verify them via PowerPoint COM PNG export
metadata: 
  node_type: memory
  type: reference
  originSessionId: dc6a7c67-10a1-4d0e-9d1b-c27f6d6b0308
  modified: 2026-08-05T18:19:16.692Z
---

Branded decks are generated, not hand-built. Toolchain that works on this box:

- **Donor template:** open `51 Profisee\Presentations\Profisee_Performance_Benchmarks_2026R1.pptx`
  with `python-pptx`, then strip its slides (`prs.part.drop_rel(rId)` + remove from
  `prs.slides._sldIdLst`). Layouts/masters/theme survive; orphaned media is dropped on save
  (~15.5 MB output).
- **Theme:** navy `1A3040`, accent1 blue `21A4DF`, accent2 teal `00A694`, accent3 orange `F7941F`,
  accent4 deep `105270`; fonts Montserrat SemiBold / Montserrat. 13.333×7.5in.
- **Useful layout indexes:** 5 = Cover (ph13 title, ph14 sub, ph15 meta — move ph15 to 4.3in or a
  2-line subtitle overlaps it), 19 = Transition-Title-1 (section divider), 8 = Primary-Single-Title
  (title + body ph12), 11 = Primary_Blank (title only — draw your own cards/tables).
- **Notes slides have no body placeholder** in this donor. Inject one with `pptx.oxml.parse_xml`
  (`<p:ph type="body" idx="1"/>`) — `lxml.etree.fromstring` fails (`has_ph_elm` missing) and
  `NotesSlideShapes` has no `add_textbox`.
- **Placeholder paragraphs inherit centred alignment** on some layouts — set `PP_ALIGN.LEFT`
  explicitly on card, code-block and note paragraphs.
- **Visual verification:** PowerPoint is installed; export every slide to PNG and read the images.
  `$pp=New-Object -ComObject PowerPoint.Application; $d=$pp.Presentations.Open($path,$true,$false,$false);
  $d.SaveCopyAs("$out\s",18); $d.Close(); $pp.Quit()` (LibreOffice is NOT installed). Always do this —
  overflow and inherited-alignment bugs are invisible in the XML.

Reusable builder + the three deck scripts live in `51 Profisee\Presentations\` (`deckkit.py`,
`build_short.py`, `build_long.py`, `build_connect.py`; `.py` files are invisible in the Obsidian UI).
`deckkit` also has `stats`/`stat_tiles` (big-number tile band), `hbars` (proportional bars with
direct value labels), `band` (colored lead-statement bar), `blank` (title-only slide).

- **Card bodies must be whole sentences**, not pre-wrapped line fragments — `cards()` word-wraps
  to column width, so hand-split lines re-wrap mid-sentence at other column counts.
- **PowerPoint lock gotcha:** a deck open in the user's PowerPoint blocks `prs.save`
  (PermissionError). The running instance is COM-invisible (`GetActiveObject` → MK_E_UNAVAILABLE,
  likely elevation mismatch) and `New-Object -ComObject PowerPoint.Application` spawns a second
  empty instance instead of attaching. Wait for the lock (poll `open(path,'r+b')`) — don't kill.
- Benchmarks-deck pre-fix backup: `C:\tmp\pptx-backups\Profisee_Performance_Benchmarks_2026R1.pre-fix-2026-08-05.pptx`.

Related: [[project_crewchief_standalone]], [[project_doc_location]]
