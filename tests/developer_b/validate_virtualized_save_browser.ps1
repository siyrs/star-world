$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = Resolve-Path "$PSScriptRoot\..\.."
$paths = [ordered]@{
  browser = Join-Path $root 'src\ui\save_browser_panel.gd'
  regression = Join-Path $root 'tests\qa\save_browser_virtualization_regression.gd'
  desktop = Join-Path $root 'tests\qa\save_browser_virtualization_desktop_acceptance.gd'
  workflow = Join-Path $root '.github\workflows\save-browser-virtualization-tests.yml'
  contract = Join-Path $root 'docs\VIRTUALIZED_SAVE_BROWSER.md'
  audit = Join-Path $root 'docs\ARCHITECTURE_AUDIT_2026-07-25_ITERATION_38.md'
  roadmap = Join-Path $root 'docs\PRODUCT_ROADMAP.md'
  run_all = Join-Path $root 'tests\run_all.ps1'
}

$text = @{}
foreach ($name in $paths.Keys) {
  if (-not (Test-Path -LiteralPath $paths[$name])) {
    throw "Missing virtualized save browser file: $($paths[$name])"
  }
  $text[$name] = Get-Content -Raw -Encoding UTF8 $paths[$name]
}

function Assert-Match([string]$Text, [string]$Pattern, [string]$Message) {
  if ($Text -notmatch $Pattern) { throw $Message }
}

function Assert-NoMatch([string]$Text, [string]$Pattern, [string]$Message) {
  if ($Text -match $Pattern) { throw $Message }
}

function Get-MethodBody([string]$Text, [string]$MethodName) {
  $pattern = '(?ms)^func\s+' + [regex]::Escape($MethodName) + '\s*\([^\n]*\).*?(?=^func\s+|\z)'
  $match = [regex]::Match($Text, $pattern)
  if (-not $match.Success) { throw "Unable to isolate method: $MethodName" }
  return $match.Value
}

foreach ($token in @(
  'MAX_VISIBLE_ROWS\s*:=\s*24',
  'MAX_AUTO_SETTLE_PASSES\s*:=\s*6',
  '_row_slots',
  '_row_world_ids',
  'func\s+get_virtualization_snapshot\s*\(',
  'func\s+get_visible_world_ids\s*\(',
  'func\s+show_page\s*\(',
  'func\s+_build_row_pool\s*\(',
  'func\s+_sync_auto_settle_process\s*\(',
  'func\s+_has_catalog_backlog\s*\(',
  'set_process\(false\)',
  '第 %d / %d 页',
  '自动整理 %d/%d'
)) {
  Assert-Match $text.browser $token "Save browser lost virtualization or progressive-settlement behavior: $token"
}

$refreshBody = Get-MethodBody $text.browser '_perform_refresh'
Assert-NoMatch $refreshBody 'queue_free\(|\.new\(\)' 'Refresh must rebind the fixed row pool instead of allocating or freeing controls'
Assert-Match $refreshBody 'save_service\.list_worlds\(\)' 'Refresh must still use the authoritative bounded world-list contract'

$rowPoolBody = Get-MethodBody $text.browser '_build_row_pool'
Assert-Match $rowPoolBody 'for\s+slot_index\s+in\s+MAX_VISIBLE_ROWS' 'Row pool must be created from the fixed twenty-four-row limit'
Assert-Match $rowPoolBody '_row_create_count\s*\+=\s*1' 'Row creation must remain observable for regression tests'

$processBody = Get-MethodBody $text.browser '_process'
Assert-Match $processBody '_remaining_auto_settle_passes\s*-=' 'Each automatic pass must consume the fixed settlement budget'
Assert-Match $processBody '_perform_refresh\(false\)' 'Automatic settlement must reuse the normal bounded catalog scan'
Assert-NoMatch $text.browser 'Timer\.new\(|await\s+.*create_timer|Thread\.new\(' 'Virtualization and settlement must not add timers or threads'

foreach ($phrase in @(
  'browser creates exactly twenty-four reusable rows',
  'page navigation performs no additional disk or catalog scan',
  'automatic settling converges after four cross-frame passes',
  'automatic settling obeys the fixed six-pass hard cap',
  'repeated refreshes never allocate another world row'
)) {
  Assert-Match $text.regression ([regex]::Escape($phrase)) "Virtualization regression is missing assertion: $phrase"
}

foreach ($phrase in @(
  'real browser creates exactly twenty-four reusable row nodes',
  'visible browser converges the seventy-two-world catalog in four automatic cross-frame passes',
  'three pages expose every real world exactly once',
  'real page navigation performs no catalog or disk scan',
  'steady refresh retains the original fixed row pool'
)) {
  Assert-Match $text.desktop ([regex]::Escape($phrase)) "Virtualization desktop acceptance is missing assertion: $phrase"
}

foreach ($token in @(
  'uses:\s*\./\.github/workflows/reusable-godot-quality-gate\.yml',
  'validate_virtualized_save_browser\.ps1',
  'save_browser_virtualization_regression\.gd',
  'save_browser_virtualization_desktop_acceptance\.gd',
  'save-browser-virtualization-desktop\.png',
  'save-browser-virtualization-desktop\.json'
)) {
  Assert-Match $text.workflow $token "Virtualization workflow is missing: $token"
}

foreach ($token in @('固定 24 行','最多 6','分页','不新增 Timer','72 个世界','Windows Release')) {
  Assert-Match $text.contract ([regex]::Escape($token)) "Virtualization contract is missing: $token"
}
foreach ($token in @('queue_free','节点抖动','手动刷新','固定行池','真实桌面','Windows Release')) {
  Assert-Match $text.audit ([regex]::Escape($token)) "Architecture audit is missing finding or acceptance evidence: $token"
}
Assert-Match $text.roadmap '固定 24 行' 'Roadmap must record the virtualized save browser row pool'
Assert-Match $text.roadmap '自动整理' 'Roadmap must record bounded progressive catalog settlement'
Assert-Match $text.run_all 'validate_virtualized_save_browser\.ps1' 'Full suite is missing the virtualization static contract'
Assert-Match $text.run_all 'save_browser_virtualization_regression\.gd' 'Full suite is missing the virtualization regression'

Write-Host 'PASS virtualized_save_browser rows=24 pages=bounded refresh=rebind auto-settle=6 per-frame=1 timers=0 threads=0 desktop=72-world release=required'
