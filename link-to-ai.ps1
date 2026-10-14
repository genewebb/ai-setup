$ErrorActionPreference = 'Stop'

$skills = @(
  'pr-review','task-generator','bug-generator','dotnet-service-registration',
  'profisee-rest-api','dotnet-entity-constants','blazor-code-behind','blazor-icons',
  'dotnet-documentation','dotnet-sql-data-access',
  'dotnet-domain-values','dotnet-testing','dotnet-logging-schema','profisee-logging-library',
  'profisee-entity-lookup','testauto-project','custom-parm-editor',
  'skill-audit-with-update',
  'ai-foundational-rules','solution-architecture-review','json-formatting-conventions',
  'testauto-log-tags','testauto-testing-patterns','profisee-dq-rules','testauto-tech-stack',
  'ado-work-item-standards','dotnet-project-structure','markdown-code-blocks',
  'documentation-location','documentation-folder',
  'requirements-writing','requirements-implementation-goal',
  'ai-repo-management','ai-client-config','permissions-yaml','skill-creator','skill-promotion',
  'testauto-workflow-execution','testauto-workflow-export','skill-multi-turn-completion','testauto-local-setup',
  'testauto-help-docs','testauto-log-viewer','testauto-metadata-model-import',
  'testauto-ui-patterns','testauto-scenario-display','testauto-debugging-common-failures',
  'testauto-multistep-steps','testauto-matching-scenarios','testauto-scenario-metrics',
  'testauto-secrets-management','testauto-enrichment-generators','testauto-hangfire-architecture',
  'testauto-prometheus-config','testauto-resource-collection','testauto-test-data-generation','testauto-scenario-catalog',
  'testauto-matching-source-data',
  'testauto-snapshot-capture',
  'testauto-modular-di','testauto-http-facades','testauto-config-validation',
  'testauto-record-transformation','testauto-odata-query-building','testauto-connex-service',
  'testauto-record-repository',
  'testauto-metadata-scenario','testauto-matching-strategy-pattern',
  'testauto-batch-orchestration','testauto-scenario-types-attribute',
  'testdata-enrichment-pipeline','testauto-metric-detail-builder',
  'testauto-scenario-version-history','testauto-lookup-cache-pattern',
  'testauto-cli-command-pattern','testauto-stewardship-scenario-pattern',
  'testauto-deployed-machine-diagnostics',
  'connex-import-tokenization','testauto-execution-context',
  'configuration-compression-codec','step-reference-resolution',
  'testauto-scenario-config-store','testauto-config-store-migration','testauto-workflow-transfer',
  'matching-api-status-poller','bulk-custom-parms-editor-base',
  'record-mapper-extension-methods','utility-step-polymorphic-deserialization',
  'testauto-utilities-module',
  'api-response-standardization','secrets-bootstrap-middleware',
  'testauto-connex-provider-templates','testauto-matching-metrics-collector',
  'speedmerchants-db-migration','skill-compare-performance-by-versions',
  'result-pattern',
  'external-json-case-insensitive-reads',
  'testauto-custom-parm-defaults','testauto-scenario-reorder','testauto-bounded-parallel-fanout',
  'llm-council',
  'seq-query',
  'scenario-config-inspector',
  'skill-inspect-workflow',
  'speedy-demo',
  'skill-fix-integration-tests',
  'diagnose','grill-me','grill-with-docs','handoff','improve-codebase-architecture',
  'prototype','tdd','teach','to-issues','write-a-skill','zoom-out',
  'find-skills',
  'skill-profile',
  # CrewChief standalone solution (2026-07-19 skill audit — full family)
  'crewchief-architecture','crewchief-step-type-model','crewchief-adding-a-step-type',
  'crewchief-executor-pattern','crewchief-step-executors','crewchief-remote-box-prep',
  'crewchief-secrets','crewchief-reference-data','crewchief-web-ui',
  'crewchief-workload-and-runs','crewchief-orchestration','crewchief-token-replacement',
  'crewchief-file-persistence','crewchief-cli','crewchief-testing',
  'crewchief-workload-transfer','crewchief-logging',
  # 2026-07-25 audit — on-demand templates, backup/restore, installer tooling
  'crewchief-default-templates','crewchief-backup-restore','inno-setup-installer',
  # 2026-08-10 audit — capability preflight, raw-JSON panes, Connect import, in-app help
  'crewchief-capability-preflight','crewchief-raw-json-editing',
  'crewchief-connect-import','crewchief-model-import','crewchief-help-docs',
  # 2026-08-10 audit — TestAuto hosting + Production Sync
  'testauto-https-hosting','testauto-windows-service-hosting','testauto-production-sync',
  # 2026-07-25 — migrated from a native (unlinked) skill in ~\AI\skills
  'atomic-tests',
  # 2026-07-25 — harness mechanisms adapted from ECC (MIT, https://github.com/affaan-m/ECC)
  'config-gc','context-budget','blazor-click-path-audit',
  'inherit-legacy-style','dual-review-convergence',
  # 2026-08-01 — cost-tiered orchestrator-worker loop skill
  'orchestrator-worker-loop',
  # 2026-08-12 — /goal condition interview wizard
  'goal-builder',
  # 2026-09-09 audit (mode 1, baseline 15401a46..c36ddbcf) - two wholly uncovered products,
  # CrewChief folders/build-steps/nesting, and the TestAuto->CrewChief export bridge
  'testdata-generation-and-mutation-engine','testdata-generation-and-mutation-shape-authoring',
  'crewchief-library-folders','crewchief-platform-build-steps','crewchief-nested-workloads',
  'testauto-crewchief-export',
  # 2026-09-09 - migrated from a native (unlinked) folder in ~\AI\skills, found by the drift report
  'elsa-feature-review',
  # 2026-09-09 - vNext (speedmerchants) UI parity campaign: one hub + three test-leg skills for the
  # 53 screens of UoW-9/10/11, each row split .a port / .b bUnit / .c composed-graph / .d Playwright-axe
  'speedy-ui-screen-port','speedy-ui-bunit','speedy-ui-composed-graph','speedy-ui-playwright-axe',
  # 2026-09-11 - THIRD-PARTY (see also the UI/UX Pro Max pack below). Upstream is
  # https://github.com/olsenbrands/fable-foreman (MIT, v0.5.0). Installed globally per its README,
  # then migrated in here so it is linked like everything else rather than sitting NATIVE in
  # ~\AI\skills. Its five foreman-* agents are in $agents below and travel with it.
  # TO UPDATE: re-clone upstream and copy over THIS folder, not the link -- and re-apply the
  # quality-first routing customisation recorded in skills\fable-foreman\LOCAL-CUSTOMISATION.md,
  # because an upstream copy overwrites it.
  'fable-foreman',
  # 2026-09-12 17:1x - MyFable Foreman: the single loop+crew skill for the speedy programme (replaces the
  # orchestrator-worker-loop + fable-foreman STACK for that programme; both stay installed for other repos).
  # 2026-09-17 - renamed to myloop (the skill folder moved with it; the old entry printed MISSING and the
  # new folder printed EXTRA on every drift report until this line caught up)
  'myloop',
  # 2026-09-13 - /mymemory: top-10 RAM consumers rolled up by source (Claude session, IIS install, WSL VM, service)
  'mymemory',
  # 2026-09-14 - THIRD-PARTY: UI/UX Pro Max pack from npm `ui-ux-pro-max-cli` 2.15.0 (MIT; the package
  # records no repository URL). Installed with `uipro init --ai claude` into a scratch folder, then
  # copied in here so it is linked like everything else rather than sitting NATIVE in ~\AI\skills.
  # LOCAL CHANGE: upstream's `design` skill is renamed `uipro-design` (folder, name:, and every
  # skills/design/ script path) because `design` collides with Claude Code's built-in design-canvas skill.
  # TO UPDATE: `npm install -g ui-ux-pro-max-cli`, run `uipro init --ai claude` in an empty scratch
  # folder, re-apply the rename, then copy the seven folders over these (not over the links).
  'ui-ux-pro-max','uipro-design','design-system','ui-styling','brand','banner-design','slides'
)

$agents = @(
  'scenario-designer.md','scenario-custom-metric-coder.md',
  'scenario-config-generator.md','config-validator.md','job-implementer.md','testauto-reviewer.md',
  'silent-failure-hunter.md',
  # 2026-09-11 - the five agents the fable-foreman skill calls BY NAME. The skill does not work
  # without them: installing the skill folder alone gives no delegation and no blind verification.
  'foreman-scout.md','foreman-worker.md','foreman-verifier.md',
  'foreman-codex-wrapper.md','foreman-grok-wrapper.md'
)

# Slash commands — canonical files live in 03 Shared\work-ai\commands. Symlinked into
# both .claude\commands and .cursor\commands so each CLI sees an identical /command.
# File symlinks (mklink without /J) require Developer Mode or admin.
$commands = @(
  'definegoal.md',
  'myworkflow.md',
  'myfable.md'      # 2026-09-12 - MyFable Foreman router
)

$sourceBase = 'Q:\Work\Work\03 Shared\work-ai'  # corrected 2026-09-09: the MyWorkVault root is retired (holds only '99 Documentation'); the corpus lives on the Q: share
$aiBase = Join-Path $env:USERPROFILE 'AI'

foreach ($s in $skills) {
  $target = Join-Path (Join-Path $aiBase 'skills') $s
  $source = Join-Path (Join-Path $sourceBase 'skills') $s
  if (Test-Path $target) {
    Write-Host "EXISTS: skills/$s"
  } else {
    cmd /c mklink /D "$target" "$source" | Out-Null
    if ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $target)) {
      Write-Host "LINKED: skills/$s"
    } else {
      Write-Host "FAILED: skills/$s (mklink exit $LASTEXITCODE) - a junction cannot target a mapped network drive; /D needs admin or Developer Mode" -ForegroundColor Red
    }
  }
}

# Cursor reads skills from ~/.cursor/skills (its native path). Mirror the same per-skill
# junctions pointing directly at the work-ai source so Cursor stays in sync with Claude Code
# and survives a Cursor reinstall. Junctions (mklink /D) need no admin.
# 2026-09-09: the Cursor skills mirror is DISABLED. Every one of its 157 junctions pointed at the
# retired C:\devopslocal\ObsidianVaults root and had been broken since the vault moved to the Q:
# share - i.e. the mirror had not worked for weeks. Gene's call: delete it and stop recreating it.
# To bring it back, restore the loop below and re-run; $sourceBase is correct now.
$mirrorToCursor = $false
$cursorSkills = Join-Path (Join-Path $env:USERPROFILE '.cursor') 'skills'
if ($mirrorToCursor -and -not (Test-Path $cursorSkills)) { New-Item -ItemType Directory -Path $cursorSkills -Force | Out-Null }

if ($mirrorToCursor) {
foreach ($s in $skills) {
  $target = Join-Path $cursorSkills $s
  $source = Join-Path (Join-Path $sourceBase 'skills') $s
  if (Test-Path $target) {
    Write-Host "EXISTS: cursor/skills/$s"
  } else {
    cmd /c mklink /D "$target" "$source"
    Write-Host "LINKED: cursor/skills/$s"
  }
}
} else { Write-Host 'SKIP: cursor skills mirror is disabled ($mirrorToCursor = $false)' }

foreach ($a in $agents) {
  $target = Join-Path (Join-Path $aiBase 'agents') $a
  $source = Join-Path (Join-Path $sourceBase 'agents') $a
  if (Test-Path $target) {
    Write-Host "EXISTS: agents/$a"
  } else {
    cmd /c mklink "$target" "$source"
    Write-Host "LINKED: agents/$a"
  }
}

# Slash commands — mirror into both .claude\commands and .cursor\commands as file symlinks.
$claudeCmdDir = Join-Path (Join-Path $env:USERPROFILE '.claude') 'commands'
$cursorCmdDir = Join-Path (Join-Path $env:USERPROFILE '.cursor') 'commands'
if (-not (Test-Path $claudeCmdDir)) { New-Item -ItemType Directory -Path $claudeCmdDir -Force | Out-Null }
if (-not (Test-Path $cursorCmdDir)) { New-Item -ItemType Directory -Path $cursorCmdDir -Force | Out-Null }

foreach ($c in $commands) {
  $source = Join-Path (Join-Path $sourceBase 'commands') $c
  foreach ($dir in @($claudeCmdDir, $cursorCmdDir)) {
    $target = Join-Path $dir $c
    $label = if ($dir -eq $claudeCmdDir) { "claude/commands/$c" } else { "cursor/commands/$c" }
    if (Test-Path $target) {
      Write-Host "EXISTS: $label"
    } else {
      cmd /c mklink "$target" "$source"
      Write-Host "LINKED: $label"
    }
  }
}

Write-Host "`nDone. Skills: $($skills.Count) (x2: AI + Cursor), Agents: $($agents.Count), Commands: $($commands.Count) (x2: claude + cursor)"

# ---------------------------------------------------------------------------
# Drift report.
#
# The loops above only ever ADD. Anything already sitting in a target tree that
# this script did not put there is invisible to them - which is how four empty
# husks and one unbacked native skill survived for months. Each existing check
# had a scope that excluded them; the gap was between the checks, not in one.
# ---------------------------------------------------------------------------
$issues = 0
$driftRoots = @((Join-Path $aiBase 'skills'))
if ($mirrorToCursor) { $driftRoots += $cursorSkills }
foreach ($target in $driftRoots) {
  if (-not (Test-Path $target)) { continue }
  foreach ($d in (Get-ChildItem $target -Directory -Force)) {
    $item = Get-Item -LiteralPath $d.FullName -Force

    if (-not $item.LinkType) {
      # A real folder here exists ONLY here - no vault copy, no backup.
      # Migrate it (copy to vault, add to $skills, remove native, re-run).
      # Never delete it: that destroys the only copy.
      Write-Host "NATIVE (unbacked, migrate - do not delete): $($d.FullName)" -ForegroundColor Yellow
      $issues++
      continue
    }
    # .Target is a string for a symlink and an array for some link kinds, so take the first element
    # rather than assuming: a StartsWith on an array throws, and the throw would land inside the
    # report that exists to make problems visible.
    $targetPath = @($item.Target)[0]

    if (-not (Test-Path $targetPath)) {
      Write-Host "BROKEN link (target gone): $($d.FullName) -> $targetPath" -ForegroundColor Red
      $issues++
      continue
    }

    # A link whose target is NOT under this vault belongs to a DIFFERENT skills root - today
    # C:\Users\agenewe\.agents\skills, which owns 41 Azure/Profisee skills of which only 'archify' is
    # linked in here. This script neither created it nor can maintain it, and both obvious "fixes"
    # are wrong: adding the name to $skills prints MISSING source folder forever, and deleting the
    # link removes a working skill whose only copy lives in that other root. So it is REPORTED and
    # deliberately NOT counted as an issue.
    $vaultSkills = Join-Path $sourceBase 'skills'
    if (-not $targetPath.StartsWith($vaultSkills, [StringComparison]::OrdinalIgnoreCase)) {
      Write-Host "FOREIGN (links outside this vault, not managed here): $($d.FullName) -> $targetPath" -ForegroundColor DarkGray
      continue
    }

    if ($d.Name -notin $skills) {
      Write-Host "EXTRA (linked but not in `$skills): $($d.FullName)" -ForegroundColor Yellow
      $issues++
    }
  }
}

$orphanEntries = $skills | Where-Object { -not (Test-Path (Join-Path (Join-Path $sourceBase 'skills') $_)) }
foreach ($o in $orphanEntries) {
  Write-Host "MISSING source folder for `$skills entry: $o" -ForegroundColor Red
  $issues++
}

if ($issues -eq 0) { Write-Host "Drift check: clean." -ForegroundColor Green }
else { Write-Host "Drift check: $issues issue(s) above." -ForegroundColor Yellow }

