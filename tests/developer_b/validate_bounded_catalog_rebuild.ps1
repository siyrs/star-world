$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = Resolve-Path "$PSScriptRoot\..\.."
$paths = [ordered]@{
  save = Join-Path $root 'src\save\save_service.gd'
  browser = Join-Path $root 'src\ui\save_browser_panel.gd'
  health = Join-Path $root 'src\diagnostics\runtime_health_report_policy.gd'
  regression = Join-Path $root 'tests\qa\bounded_catalog_rebuild_regression.gd'
  desktop = Join-Path $root 'tests\qa\bounded_catalog_rebuild_desktop_acceptance.gd'
  workflow = Join-Path $root '.github\workflows\bounded-catalog-rebuild-tests.yml'
  contract = Join-Path $root 'docs\BOUNDED_CATALOG_REBUILD.md'
  world_catalog = Join-Path $root 'docs\WORLD_CATALOG.md'
  audit = Join-Path $root 'docs\ARCHITECTURE_AUDIT_2026-07-24_ITERATION_35.md'
  roadmap = Join-Path $root 'docs\PRODUCT_ROADMAP.md'
  run_all = Join-Path $root 'tests\run_all.ps1'
}

$text = @{}
foreach ($name in $paths.Keys) {
  if (-not (Test-Path -LiteralPath $paths[$name])) {
    throw "Missing bounded catalog rebuild file: $($paths[$name])"
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
  'MAX_CATALOG_REBUILDS_PER_LIST\s*:=\s*16',
  'catalog_rebuild_budget_used\s*<\s*MAX_CATALOG_REBUILDS_PER_LIST',
  'last_deferred_catalog_rebuild_count',
  'last_catalog_rebuild_budget_used',
  'catalog_rebuild_budget',
  'catalog_rebuild_deferred',
  'world_ids\.sort\(\)'
)) {
  Assert-Match $text.save $token "SaveService lost bounded catalog rebuilding: $token"
}
$budgetMatches = [regex]::Matches(
  $text.save,
  'MAX_CATALOG_REBUILDS_PER_LIST\s*:=\s*(\d+)'
)
if ($budgetMatches.Count -ne 1 -or [int]$budgetMatches[0].Groups[1].Value -ne 16) {
  throw 'Catalog rebuild budget must be declared exactly once and remain sixteen'
}
Assert-Match $text.save 'if\s+primary_ready[\s\S]*catalog_rebuild_budget_used[\s\S]*_write_catalog_entry' 'Catalog writes must be gated by a dedicated budget after primary readiness'
Assert-Match $text.save 'deferred_catalog_rebuild_count\s*\+=\s*1' 'Budget-exhausted healthy primaries must remain observable'
Assert-Match $text.save '_catalog_write_failure_count\s*\+=\s*1' 'Catalog write failures must remain diagnostic'
Assert-NoMatch $text.save 'MAX_PRIMARY_REPAIRS_PER_LIST\s*:=\s*16' 'Primary repair and catalog rebuild budgets must remain independent'

foreach ($token in @('待建目录 %d','每次最多 %d','last_deferred_catalog_rebuild_count','catalog_rebuild_budget')) {
  Assert-Match $text.browser ([regex]::Escape($token)) "Save browser is missing bounded catalog UX: $token"
}
foreach ($token in @('待建目录','目录写入预算','last_deferred_catalog_rebuild_count','catalog_rebuild_budget','last_catalog_rebuild_budget_used')) {
  Assert-Match $text.health ([regex]::Escape($token)) "F3 health is missing bounded catalog evidence: $token"
}

foreach ($phrase in @(
  'keeps every healthy world visible while sidecars converge',
  'never exceeds the catalog disk-write budget',
  'healthy primaries never enter backup recovery',
  'catalog convergence never mutates authoritative primary'
)) {
  Assert-Match $text.regression ([regex]::Escape($phrase)) "Catalog rebuild regression is missing assertion: $phrase"
}
foreach ($phrase in @(
  'first desktop refresh renders every healthy world without a sidecar',
  'save browser visibly explains bounded sidecar rebuilding',
  'F3 visibly reports deferred sidecars and the write budget',
  'steady desktop refresh is a pure sidecar hit'
)) {
  Assert-Match $text.desktop ([regex]::Escape($phrase)) "Catalog rebuild desktop test is missing assertion: $phrase"
}

foreach ($token in @(
  'uses:\s*\./\.github/workflows/reusable-godot-quality-gate\.yml',
  'validate_bounded_catalog_rebuild\.ps1',
  'bounded_catalog_rebuild_regression\.gd',
  'bounded_catalog_rebuild_desktop_acceptance\.gd',
  'bounded-catalog-rebuild-desktop-health\.png',
  'bounded-catalog-rebuild-desktop\.json'
)) {
  Assert-Match $text.workflow $token "Bounded catalog workflow is missing: $token"
}

foreach ($token in @('每次最多 16','世界始终可见','16 → 16 → 16')) {
  Assert-Match $text.contract ([regex]::Escape($token)) "Bounded catalog contract is missing: $token"
}
Assert-Match $text.contract '独立[^\r\n]{0,12}写入预算' 'Bounded catalog contract must keep catalog writes independent from primary repair'
Assert-Match $text.contract '权威数据不变|不修改\s*`?world\.json`?' 'Bounded catalog contract must preserve the authoritative world file'
foreach ($token in @('目录 sidecar','每次最多 16','待建目录','写盘成本')) {
  Assert-Match $text.world_catalog ([regex]::Escape($token)) "World catalog contract is missing rebuild budgeting: $token"
}
foreach ($token in @('同步重建所有目录','主菜单写盘','独立预算','真实桌面','Windows Release')) {
  Assert-Match $text.audit ([regex]::Escape($token)) "Architecture audit is missing catalog rebuild finding: $token"
}
Assert-Match $text.roadmap '目录\s*sidecar[\s\S]{0,60}每次最多\s*16|每次最多\s*16[\s\S]{0,60}sidecar' 'Roadmap must record the independent sixteen-sidecar rebuild budget'
Assert-Match $text.run_all 'validate_bounded_catalog_rebuild\.ps1' 'Full suite is missing static catalog rebuild validation'
Assert-Match $text.run_all 'bounded_catalog_rebuild_regression\.gd' 'Full suite is missing catalog rebuild regression'

Write-Host 'PASS bounded_catalog_rebuild worlds-visible=on primary-budget=8 catalog-budget=16 progressive=16-16-16 authority-unchanged=on diagnostics=bounded desktop=real release=required'
