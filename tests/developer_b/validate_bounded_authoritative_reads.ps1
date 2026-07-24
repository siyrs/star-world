$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = Resolve-Path "$PSScriptRoot\..\.."
$paths = [ordered]@{
  save = Join-Path $root 'src\save\save_service.gd'
  browser = Join-Path $root 'src\ui\save_browser_panel.gd'
  health = Join-Path $root 'src\diagnostics\runtime_health_report_policy.gd'
  regression = Join-Path $root 'tests\qa\bounded_authoritative_read_regression.gd'
  desktop = Join-Path $root 'tests\qa\bounded_authoritative_read_desktop_acceptance.gd'
  workflow = Join-Path $root '.github\workflows\bounded-authoritative-read-tests.yml'
  contract = Join-Path $root 'docs\BOUNDED_AUTHORITATIVE_READS.md'
  world_catalog = Join-Path $root 'docs\WORLD_CATALOG.md'
  audit = Join-Path $root 'docs\ARCHITECTURE_AUDIT_2026-07-24_ITERATION_36.md'
  roadmap = Join-Path $root 'docs\PRODUCT_ROADMAP.md'
  run_all = Join-Path $root 'tests\run_all.ps1'
}

$text = @{}
foreach ($name in $paths.Keys) {
  if (-not (Test-Path -LiteralPath $paths[$name])) {
    throw "Missing bounded authoritative-read file: $($paths[$name])"
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
  'MAX_AUTHORITATIVE_READS_PER_LIST\s*:=\s*32',
  'authoritative_read_budget_used\s*<\s*MAX_AUTHORITATIVE_READS_PER_LIST',
  'last_deferred_authoritative_read_count',
  'last_authoritative_read_budget_used',
  'authoritative_read_budget',
  'authoritative_read_deferred',
  '_deferred_world_metadata\s*\(',
  'world_ids\.sort\(\)'
)) {
  Assert-Match $text.save $token "SaveService lost bounded authoritative reads: $token"
}
$budgetMatches = [regex]::Matches(
  $text.save,
  'MAX_AUTHORITATIVE_READS_PER_LIST\s*:=\s*(\d+)'
)
if ($budgetMatches.Count -ne 1 -or [int]$budgetMatches[0].Groups[1].Value -ne 32) {
  throw 'Authoritative read budget must be declared exactly once and remain thirty-two'
}
Assert-Match $text.save 'if\s+not\s+allow_authoritative_read[\s\S]*_deferred_world_metadata[\s\S]*continue' 'Budget exhaustion must return a visible placeholder without parsing the world payload'
Assert-Match $text.save 'authoritative_read_budget_used\s*\+=\s*1[\s\S]*_read_world_result' 'Full reads must consume a slot before authoritative parsing'
Assert-Match $text.save 'catalog_rebuild_deferred\s*"?\]?\s*=\s*true' 'Unread placeholders must remain eligible for sidecar convergence'
Assert-NoMatch $text.save 'MAX_PRIMARY_REPAIRS_PER_LIST\s*:=\s*32|MAX_CATALOG_REBUILDS_PER_LIST\s*:=\s*32' 'Read, repair and write budgets must remain independent'

foreach ($token in @('世界信息待读取','待读世界 %d','每次最多 %d','last_deferred_authoritative_read_count','authoritative_read_budget')) {
  Assert-Match $text.browser ([regex]::Escape($token)) "Save browser is missing bounded read UX: $token"
}
foreach ($token in @('待读世界','权威读取预算','last_deferred_authoritative_read_count','authoritative_read_budget','last_authoritative_read_budget_used')) {
  Assert-Match $text.health ([regex]::Escape($token)) "F3 health is missing authoritative-read evidence: $token"
}

foreach ($phrase in @(
  'keeps all worlds visible before metadata is resolved',
  'never exceeds the authoritative JSON read budget',
  'healthy primaries never enter backup recovery',
  'deferred metadata reads never mutate authoritative primary'
)) {
  Assert-Match $text.regression ([regex]::Escape($phrase)) "Authoritative-read regression is missing assertion: $phrase"
}
foreach ($phrase in @(
  'first desktop refresh renders every world before full metadata resolution',
  'save browser visibly explains deferred authoritative metadata reads',
  'F3 visibly reports deferred worlds and the full-read budget',
  'steady desktop refresh performs zero full reads and zero sidecar writes'
)) {
  Assert-Match $text.desktop ([regex]::Escape($phrase)) "Authoritative-read desktop test is missing assertion: $phrase"
}

foreach ($token in @(
  'uses:\s*\./\.github/workflows/reusable-godot-quality-gate\.yml',
  'validate_bounded_authoritative_reads\.ps1',
  'bounded_authoritative_read_regression\.gd',
  'bounded_authoritative_read_desktop_acceptance\.gd',
  'bounded-authoritative-read-desktop-health\.png',
  'bounded-authoritative-read-desktop\.json'
)) {
  Assert-Match $text.workflow $token "Bounded authoritative-read workflow is missing: $token"
}

foreach ($token in @('每次最多 32','世界始终可见','占位行','权威存档不变')) {
  Assert-Match $text.contract ([regex]::Escape($token)) "Bounded authoritative-read contract is missing: $token"
}
Assert-Match $text.contract '读取预算[\s\S]{0,120}写入预算|写入预算[\s\S]{0,120}读取预算' 'Read and write budgets must be documented independently'
foreach ($token in @('同步解析所有完整存档','主菜单读取成本','独立预算','真实桌面','Windows Release')) {
  Assert-Match $text.audit ([regex]::Escape($token)) "Architecture audit is missing authoritative-read finding: $token"
}
Assert-Match $text.world_catalog '权威读取预算|完整 JSON 读取预算' 'World catalog contract must mention the bounded authoritative read path'
Assert-Match $text.roadmap '完整存档读取[\s\S]{0,60}每次最多\s*32|每次最多\s*32[\s\S]{0,60}完整存档读取' 'Roadmap must record the thirty-two-world read budget'
Assert-Match $text.run_all 'validate_bounded_authoritative_reads\.ps1' 'Full suite is missing static authoritative-read validation'
Assert-Match $text.run_all 'bounded_authoritative_read_regression\.gd' 'Full suite is missing authoritative-read regression'

Write-Host 'PASS bounded_authoritative_reads worlds-visible=on primary-budget=8 read-budget=32 catalog-budget=16 placeholders=bounded convergence=deterministic authority-unchanged=on desktop=real release=required'
