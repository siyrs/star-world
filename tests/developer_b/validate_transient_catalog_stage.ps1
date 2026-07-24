$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = Resolve-Path "$PSScriptRoot\..\.."
$paths = [ordered]@{
  save = Join-Path $root 'src\save\save_service.gd'
  browser = Join-Path $root 'src\ui\save_browser_panel.gd'
  health = Join-Path $root 'src\diagnostics\runtime_health_report_policy.gd'
  invalidation = Join-Path $root 'tests\qa\catalog_stage_invalidation_regression.gd'
  scale = Join-Path $root 'tests\qa\bounded_authoritative_read_regression.gd'
  desktop = Join-Path $root 'tests\qa\bounded_authoritative_read_desktop_acceptance.gd'
  workflow = Join-Path $root '.github\workflows\transient-catalog-stage-tests.yml'
  adjacent_workflow = Join-Path $root '.github\workflows\bounded-authoritative-read-tests.yml'
  contract = Join-Path $root 'docs\TRANSIENT_CATALOG_STAGING.md'
  read_contract = Join-Path $root 'docs\BOUNDED_AUTHORITATIVE_READS.md'
  world_catalog = Join-Path $root 'docs\WORLD_CATALOG.md'
  audit = Join-Path $root 'docs\ARCHITECTURE_AUDIT_2026-07-24_ITERATION_37.md'
  roadmap = Join-Path $root 'docs\PRODUCT_ROADMAP.md'
  run_all = Join-Path $root 'tests\run_all.ps1'
}

$text = @{}
foreach ($name in $paths.Keys) {
  if (-not (Test-Path -LiteralPath $paths[$name])) {
    throw "Missing transient catalog staging file: $($paths[$name])"
  }
  $text[$name] = Get-Content -Raw -Encoding UTF8 $paths[$name]
}

function Assert-Match([string]$Text, [string]$Pattern, [string]$Message) {
  if ($Text -notmatch $Pattern) { throw $Message }
}

function Assert-NoMatch([string]$Text, [string]$Pattern, [string]$Message) {
  if ($Text -match $Pattern) { throw $Message }
}

foreach ($token in @(
  'MAX_STAGED_CATALOG_ENTRIES\s*:=\s*64',
  '_staged_catalog_entries',
  'func\s+_read_staged_catalog_entry\s*\(',
  'func\s+_stage_catalog_entry\s*\(',
  'func\s+_write_catalog_value\s*\(',
  'func\s+_invalidate_staged_catalog_entry\s*\(',
  'func\s+_prune_staged_catalog_entries\s*\(',
  'staged_catalog_entry_count',
  'staged_catalog_peak_count',
  'catalog_stage_capacity',
  'last_stage_hit_count',
  'last_stage_invalidation_count',
  'authoritative_read_count'
)) {
  Assert-Match $text.save $token "SaveService lost transient catalog staging: $token"
}

$capacityMatches = [regex]::Matches(
  $text.save,
  'MAX_STAGED_CATALOG_ENTRIES\s*:=\s*(\d+)'
)
if ($capacityMatches.Count -ne 1 -or [int]$capacityMatches[0].Groups[1].Value -ne 64) {
  throw 'Transient catalog stage capacity must be declared exactly once and remain sixty-four'
}

Assert-Match $text.save 'func\s+list_worlds[\s\S]*?_read_catalog_entry[\s\S]*?_read_staged_catalog_entry[\s\S]*?_read_world_result' 'World listing must prefer sidecar, then transient stage, then a bounded full read'
Assert-Match $text.save 'authoritative_read_budget_used\s*<\s*MAX_AUTHORITATIVE_READS_PER_LIST[\s\S]*?_staged_catalog_entries\.size\(\)\s*<\s*MAX_STAGED_CATALOG_ENTRIES' 'Full reads must stop when neither write capacity nor stage capacity can retain the result'
Assert-Match $text.save 'func\s+_read_staged_catalog_entry[\s\S]*?_file_size[\s\S]*?FileAccess\.get_modified_time[\s\S]*?_invalidate_staged_catalog_entry' 'Staged entries must be invalidated by authoritative size or modification evidence'
Assert-Match $text.save 'if\s+not\s+_write_catalog_entry[\s\S]*?_catalog_write_failure_count\s*\+=\s*1[\s\S]*?_stage_catalog_entry' 'A successful primary save with a failed sidecar write must retain one bounded derived entry'
Assert-Match $text.save 'func\s+delete_world[\s\S]*?_staged_catalog_entries\.erase\(world_id\)' 'Deleting a world must remove its transient catalog entry'
Assert-Match $text.save 'func\s+_write_catalog_value[\s\S]*?_store\.write_dictionary[\s\S]*?_staged_catalog_entries\.erase\(world_id\)' 'Successful sidecar promotion must remove the transient entry'

$stageFunction = [regex]::Match(
  $text.save,
  'func\s+_stage_catalog_entry\s*\([\s\S]*?(?=(?:\r?\n){2,}func\s+)'
)
if (-not $stageFunction.Success) { throw 'Unable to inspect transient catalog stage function' }
Assert-NoMatch $stageFunction.Value 'block_overrides|inventory|crop_counts|species_counts|machines|full_state' 'Transient stage must retain only normalized catalog entries, never full world state'
Assert-Match $stageFunction.Value 'WorldCatalogPolicyScript\.normalize_entry' 'Transient stage must reuse the strict catalog whitelist'
Assert-Match $stageFunction.Value '_staged_catalog_entries\.size\(\)\s*>=\s*MAX_STAGED_CATALOG_ENTRIES' 'Transient stage must reject growth beyond sixty-four entries'

$resetFunction = [regex]::Match(
  $text.save,
  'func\s+reset_catalog_diagnostics\s*\([\s\S]*?(?=(?:\r?\n){2,}func\s+)'
)
if (-not $resetFunction.Success) { throw 'Unable to inspect catalog diagnostic reset' }
Assert-NoMatch $resetFunction.Value '_staged_catalog_entries\.clear\(' 'Resetting diagnostics must not change catalog convergence behavior'

foreach ($token in @('目录待写','暂存目录 %d/%d','暂存命中 %d','catalog_staged','staged_catalog_entry_count','last_stage_hit_count')) {
  Assert-Match $text.browser ([regex]::Escape($token)) "Save browser is missing transient staging UX: $token"
}
foreach ($token in @('暂存目录','暂存命中','staged_catalog_entry_count','catalog_stage_capacity','last_stage_hit_count','last_stage_invalidation_count')) {
  Assert-Match $text.health ([regex]::Escape($token)) "F3 health is missing transient staging evidence: $token"
}

foreach ($phrase in @(
  'first scan stages the sixteen exact entries waiting behind writes',
  'explicit save invalidates only its own staged entry',
  'stale staged metadata is rejected and refreshed from the changed primary',
  'second scan performs one invalidation reread plus eight new reads',
  'health projection never exposes staged metadata or world payloads',
  'steady scan performs no full reads, writes or staged retention'
)) {
  Assert-Match $text.invalidation ([regex]::Escape($phrase)) "Catalog stage invalidation regression is missing assertion: $phrase"
}
foreach ($phrase in @(
  'transient staging eliminates eighty redundant full reads',
  'stage cache peak remains inside the fixed sixty-four entry capacity',
  'F3 projection preserves transient catalog staging evidence'
)) {
  Assert-Match $text.scale ([regex]::Escape($phrase)) "96-world staging regression is missing assertion: $phrase"
}
foreach ($phrase in @(
  'first desktop refresh stages sixteen exact catalog entries',
  'save browser visibly reports the transient catalog stage',
  'F3 visibly reports staged entries and stage hits',
  'desktop convergence parses every authoritative world exactly once'
)) {
  Assert-Match $text.desktop ([regex]::Escape($phrase)) "Catalog staging desktop acceptance is missing assertion: $phrase"
}

foreach ($token in @(
  'uses:\s*\./\.github/workflows/reusable-godot-quality-gate\.yml',
  'validate_transient_catalog_stage\.ps1',
  'catalog_stage_invalidation_regression\.gd',
  'bounded_authoritative_read_regression\.gd',
  'bounded_authoritative_read_desktop_acceptance\.gd',
  'transient-catalog-stage-desktop-health\.png',
  'transient-catalog-stage-desktop\.json'
)) {
  Assert-Match $text.workflow $token "Transient catalog stage workflow is missing: $token"
}
Assert-Match $text.adjacent_workflow 'validate_transient_catalog_stage\.ps1' 'Bounded authoritative-read workflow must retain the staging static contract'
Assert-Match $text.adjacent_workflow 'catalog_stage_invalidation_regression\.gd' 'Bounded authoritative-read workflow must retain stage invalidation coverage'

foreach ($token in @('最多 64','严格白名单','瞬时','176','96','80','跨刷新','不进入存档')) {
  Assert-Match $text.contract ([regex]::Escape($token)) "Transient staging contract is missing: $token"
}
foreach ($token in @('暂存','32','16','重复读取','96')) {
  Assert-Match $text.read_contract ([regex]::Escape($token)) "Authoritative-read contract is missing staging convergence: $token"
}
foreach ($token in @('暂存目录','最多 64','避免重复读取')) {
  Assert-Match $text.world_catalog ([regex]::Escape($token)) "World catalog contract is missing transient staging: $token"
}
foreach ($token in @('176 次','80 次','瞬时目录暂存','真实桌面','Windows Release')) {
  Assert-Match $text.audit ([regex]::Escape($token)) "Architecture audit is missing staging finding or evidence: $token"
}
Assert-Match $text.roadmap '目录暂存[\s\S]{0,80}最多\s*64|最多\s*64[\s\S]{0,80}目录暂存' 'Roadmap must record the bounded transient catalog stage'
Assert-Match $text.run_all 'validate_transient_catalog_stage\.ps1' 'Full suite is missing transient catalog staging validation'
Assert-Match $text.run_all 'catalog_stage_invalidation_regression\.gd' 'Full suite is missing catalog stage invalidation regression'

Write-Host 'PASS transient_catalog_stage capacity=64 whitelist=strict reads=96 legacy=176 saved=80 invalidation=size+mtime save=refresh delete=erase diagnostics=readonly desktop=real release=required'
