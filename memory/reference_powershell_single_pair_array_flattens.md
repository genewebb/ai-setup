---
name: reference-powershell-single-pair-array-flattens
description: PowerShell @( @("a","b") ) flattens to @("a","b"); foreach then yields strings and $p[0]/$p[1] are CHARACTERS — a find/replace table with one pair corrupted a whole file
metadata:
  type: reference
---

2026-09-27: a scripted doc edit used `pairs=@( @(old,new) )` and `foreach($p in $pairs){ $t=$t.Replace($p[0],$p[1]) }`. With ONE pair the outer @() unrolls the inner array, so `$p` is each string and `$p[0]`,`$p[1]` are its first two chars: `Replace('T','h')` then `Replace('s','t')` rewrote every s→t in stream-kit\SKILL.md. The `Contains($p[0])` guard passed because a single char is always present.

**How to apply:** build pair tables with the unary comma — `@( ,@(old,new) )` — or use `[pscustomobject]@{Old=..;New=..}` objects; assert `$p.Count -eq 2` / `$p -is [array]` before replacing. Recovery that worked: find the prior text in session transcripts (`~\.claude\projects\<repo>\*.jsonl`), re-apply the same corruption to the candidate and require byte-exact equality with the damaged file before restoring.

Related: [[reference_obsidian_smb_vault_watcher_blind]]
