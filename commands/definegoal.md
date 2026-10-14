---
description: Prepare a requirements-based implementation goal and full handoff without starting it or replacing Claude's built-in /goal command.
argument-hint: "[requirements area, feature ID, or release-record path]"
---

# /definegoal — prepare the implementation handoff

Load the `requirements-implementation-goal` skill and follow it. Its canonical source is:

`{AIWorkRoot}\skills\requirements-implementation-goal\SKILL.md`

Use the configured skill alias when available, or read that source through the available filesystem/Obsidian connection. The skill owns the preparation method and template; this command is a thin entry point.

Requested area or release: `$ARGUMENTS`

Use the current conversation's requirements, selected area, decisions and permissions. If the argument is empty, infer the area from that context; ask only when it is genuinely ambiguous. If a supplied path cannot be read, identify the missing input rather than inventing its contents.

Prepare the release/readiness record and either one complete prompt/command or a justified staged sequence under the skill’s decomposition rules. Each stage gets its own full prompt file and copy/paste command for the existing native `/goal`; a staged sequence ends with complete integration verification. The generated goal must load the complete prompt before implementation starts. Apply the skill’s 4,000-character command limit and exact length check, report the count, and keep the full handoff in the referenced file. Keep unapproved or incomplete definitions visibly blocked.

Invoking `/definegoal` authorizes preparation only. It does not run `/goal`, replace an active goal, implement code, dispatch agents or change client settings. Do not create or modify a command named `goal`; the native `/goal` remains the execution mechanism. Keep the user's model/reasoning choice separate.
