---
name: reference-speedy-no-generatedocumentationfile
description: "Speedy sets no GenerateDocumentationFile, so a malformed /// XML doc comment raises no warning even with TreatWarningsAsErrors"
metadata: 
  node_type: memory
  type: reference
  originSessionId: 2550a59e-a257-476a-82c3-03144dbd3357
  modified: 2026-09-30T17:09:39.095Z
---

`D:\devops\repos\speedmerchants` sets `GenerateDocumentationFile` in neither `Directory.Build.props` nor any csproj
(verified 2026-09-30). The tree does set `TreatWarningsAsErrors=true`, so a clean build looks like proof that XML doc
comments are well formed — it is not. Without documentation generation the compiler never parses `///` blocks, so an
unclosed `<c>`, a stray `<` or a mismatched `<param>` builds green.

**Why:** a task whose whole change is inside doc comments has no build-level safety net, and a verifier that treats
"0 warnings" as evidence of well-formed markup reports a property it did not measure.

**How to apply:** when a change touches `///` markup, parse the block directly instead of trusting the build — extract
the doc lines, strip the `///` prefixes and load the result as XML in pwsh. That is what proved
`IVersionedCopies.cs`'s `<param name="Kind">` sound on G2.T106. See also
[[reference_documented_security_property_never_tested]].
