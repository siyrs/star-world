$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = Resolve-Path "$PSScriptRoot\..\.."
$paths = [ordered]@{
  save = Join-Path $root 'src\save\save_service.gd'
  browser = Join-Path $root 'src\ui\save_browser_panel.gd'
  health = Join-Path $root 'src\diagnostics\runtime_health_report_policy.gd'
  regression = Join-Path $root 'tests\qa\bounded_multi_world_recovery_regression.gd'
  desktop = Join-Path $root 'tests\qa\bounded_multi_world_recovery_desktop_acceptance.gd'
  workflow = Join-Path $root '.github\workflows\bounded-multi-world-recovery-tests.yml'
  contract = Join-Path $root 'docs\BOUNDED_MULTI_WORLD_RECOVERY.md'
  audit = Join-Path $root 'docs\ARCHITECTURE_AUDIT_2026-07-24_ITERATION_34.md'
  roadmap = Join-Path $root 'docs\PRODUCT_ROADMAP.md'
  run_all = Join-Path $root 'tests\run_all.ps1'
}

$text = @{}
foreach ($name in $paths.Keys) {
  if (-not (Test-Path -LiteralPath $paths[$name])) { throw "Missing bounded recovery file: $($paths[$name])" }
  $text[$name] = Get-Content -Raw -Encoding UTF8 $paths[$name]
}

function Assert-Match([string]$Text, [string]$Pattern, [string]$Message) {
  if ($Text -notmatch $Pattern) { throw $Message }
}
function Assert-NoMatch([string]$Text, [string]$Pattern, [string]$Message) {
  if ($Text -match $Pattern) { throw $Message }
}

foreach ($token in @(
  'MAX_PRIMARY_REPAIRS_PER_LIST\s*:=\s*8',
  'repair_budget_used\s*<\s*MAX_PRIMARY_REPAIRS_PER_LIST',
  '_read_world_result\(world_id,\s*false,\s*allow_primary_repair\)',
  'world_ids\.sort\(\)',
  'last_deferred_recovery_count',
  'last_repair_budget_used',
  'primary_repair_budget',
  'recovery_deferred'
)) { Assert-Match $text.save $token "SaveService lost bounded recovery behavior: $token" }

Assert-Match $text.save 'repair_primary:\s*bool\s*=\s*true' 'Explicit world loads must retain immediate primary repair'
Assert-Match $text.save 'read_dictionary_validated\([\s\S]*repair_primary' 'Validated reads must receive the caller repair decision'
Assert-NoMatch $text.save 'MAX_PRIMARY_REPAIRS_PER_LIST\s*:=\s*(?:0|[1-7]|[9-9][0-9]*)' 'Repair budget must remain exactly eight'

foreach ($token in @('待渐进修复 %d','每次最多 %d','last_deferred_recovery_count')) {
  Assert-Match $text.browser ([regex]::Escape($token)) "Save browser is missing progressive recovery evidence: $token"
}
foreach ($token in @('待渐进修复','primary_repair_budget','last_repair_budget_used','last_deferred_recovery_count')) {
  Assert-Match $text.health ([regex]::Escape($token)) "F3 health is missing bounded recovery evidence: $token"
}

foreach ($phrase in @(
  'keeps all valid fallback worlds visible',
  'never exceeds the disk repair budget',
  'all corrupt primaries are eventually repaired exactly once'
)) {
  Assert-Match $text.regression ([regex]::Escape($phrase)) "Recovery regression is missing assertion: $phrase"
}
Assert-Match $text.desktop ([regex]::Escape('steady desktop refresh is a pure sidecar hit')) 'Desktop recovery is missing steady sidecar assertion'

foreach ($token in @(
  'uses:\s*\./\.github/workflows/reusable-godot-quality-gate\.yml',
  'validate_bounded_multi_world_recovery\.ps1',
  'bounded_multi_world_recovery_regression\.gd',
  'bounded_multi_world_recovery_desktop_acceptance\.gd',
  'bounded-multi-world-recovery-desktop\.png',
  'bounded-multi-world-recovery-desktop\.json'
)) { Assert-Match $text.workflow $token "Bounded recovery workflow is missing: $token" }

foreach ($token in @('修复预算','世界始终可见','确定性收敛','完整加载不受预算限制','8 → 8 → 4')) {
  Assert-Match $text.contract ([regex]::Escape($token)) "Bounded recovery contract is missing: $token"
}
foreach ($token in @('同步修复所有损坏世界','主菜单卡顿','渐进恢复','真实桌面','Windows Release')) {
  Assert-Match $text.audit ([regex]::Escape($token)) "Architecture audit is missing: $token"
}
Assert-Match $text.roadmap '每次最多 8 个主文件修复' 'Roadmap must record bounded multi-world recovery'
Assert-Match $text.run_all 'validate_bounded_multi_world_recovery\.ps1' 'Full suite is missing static recovery contract'
Assert-Match $text.run_all 'bounded_multi_world_recovery_regression\.gd' 'Full suite is missing recovery regression'

Write-Host 'PASS bounded_multi_world_recovery worlds-visible=on primary-repairs-per-scan=8 order=stable progressive=8-8-4 explicit-load=immediate diagnostics=bounded desktop=real release=required'
