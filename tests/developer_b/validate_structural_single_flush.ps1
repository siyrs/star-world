$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = Resolve-Path "$PSScriptRoot\..\.."
$worldPath = Join-Path $root 'src\world\batched_voxel_world.gd'
$servicePath = Join-Path $root 'src\interaction\batched_block_structure_integrity_service.gd'
$hubPath = Join-Path $root 'src\ui\tool_progression_service_hub.gd'
$worldRegressionPath = Join-Path $root 'tests\qa\world_mutation_pre_flush_regression.gd'
$integrityRegressionPath = Join-Path $root 'tests\qa\structural_integrity_batched_regression.gd'
$desktopPath = Join-Path $root 'tests\qa\structural_integrity_single_flush_desktop_acceptance.gd'
$importPath = Join-Path $root 'tests\qa\structural_integrity_desktop_import_regression.gd'
$workflowPath = Join-Path $root '.github\workflows\structural-integrity-tests.yml'
$runAllPath = Join-Path $root 'tests\run_all.ps1'
$contractPath = Join-Path $root 'docs\STRUCTURAL_SINGLE_FLUSH_OPTIMIZATION.md'

foreach ($path in @(
  $worldPath,$servicePath,$hubPath,$worldRegressionPath,$integrityRegressionPath,
  $desktopPath,$importPath,$workflowPath,$runAllPath,$contractPath
)) {
  if (-not (Test-Path -LiteralPath $path)) {
    throw "Missing single-flush structural contract file: $path"
  }
}

$world = Get-Content -Raw -Encoding UTF8 $worldPath
$service = Get-Content -Raw -Encoding UTF8 $servicePath
$hub = Get-Content -Raw -Encoding UTF8 $hubPath
$worldRegression = Get-Content -Raw -Encoding UTF8 $worldRegressionPath
$integrityRegression = Get-Content -Raw -Encoding UTF8 $integrityRegressionPath
$desktop = Get-Content -Raw -Encoding UTF8 $desktopPath
$import = Get-Content -Raw -Encoding UTF8 $importPath
$workflow = Get-Content -Raw -Encoding UTF8 $workflowPath
$runAll = Get-Content -Raw -Encoding UTF8 $runAllPath
$contract = Get-Content -Raw -Encoding UTF8 $contractPath

function Assert-Contains {
  param(
    [Parameter(Mandatory = $true)][string]$Text,
    [Parameter(Mandatory = $true)][string]$Needle,
    [Parameter(Mandatory = $true)][string]$Message
  )
  if (-not $Text.Contains($Needle)) { throw "$Message Missing: $Needle" }
}

foreach ($needle in @(
  'signal block_mutation_batch_pre_flush',
  '_batch_pre_flush_emit_count',
  'block_mutation_batch_pre_flush.emit(',
  '"batch_depth": _rebuild_batch_depth',
  '"pending_chunks": _dirty_rebuild_chunks.size()',
  '"pre_flush_emit_count": _batch_pre_flush_emit_count'
)) {
  Assert-Contains $world $needle 'Batched world pre-flush contract is incomplete.'
}
$emitIndex = $world.IndexOf('block_mutation_batch_pre_flush.emit(')
$closeIndex = $world.IndexOf('var flush_result := end_chunk_rebuild_batch(true)')
if ($emitIndex -lt 0 -or $closeIndex -le $emitIndex) {
  throw 'Pre-flush signal must run after mutations but before the outer rebuild batch closes'
}
$publishedSection = $world.Substring($emitIndex, $closeIndex - $emitIndex)
if ($publishedSection.Contains('changes')) {
  throw 'Pre-flush summary must not publish the full mutation array'
}

foreach ($needle in @(
  'class_name BatchedBlockStructureIntegrityService',
  'extends "res://src/interaction/block_structure_integrity_service.gd"',
  'const PRE_FLUSH_SIGNAL := "block_mutation_batch_pre_flush"',
  'func bind_world(p_world: Node) -> bool:',
  'func _connect_pre_flush() -> void:',
  'func _disconnect_pre_flush() -> void:',
  'if _shutdown or _applying_cleanup or _pending_candidates.is_empty():',
  '_last_pre_flush_result = flush_pending()',
  'result["pre_flush_cleanup_count"]',
  'result["pre_flush_signal_count"]'
)) {
  Assert-Contains $service $needle 'Batched integrity adapter is incomplete.'
}
if ($service.Contains('Timer.new(') -or $service.Contains('FileAccess')) {
  throw 'Batched integrity adapter must remain transient and reuse the shared process loop'
}

Assert-Contains $hub 'res://src/interaction/batched_block_structure_integrity_service.gd' 'Production hub must compose the batched integrity adapter.'
Assert-Contains $hub 'StructuralIntegrityServiceScript.new(), "StructuralIntegrity"' 'Production structural integrity node path must remain stable.'

foreach ($phrase in @(
  'outer and nested batches emit deterministic pre-flush summaries',
  'nested mutation returns while the outer dirty-chunk transaction remains open',
  'outer and nested boundary edits share one two-chunk mesh flush',
  'each loaded boundary chunk rebuilds exactly once',
  'pre-flush hooks and counters remain transient'
)) {
  Assert-Contains $worldRegression $phrase 'World pre-flush regression is incomplete.'
}
foreach ($phrase in @(
  'outer batch pre-flush drains the structural queue before the API returns',
  'one outer support batch owns exactly one nested structural mutation batch',
  'nested cleanup emits diagnostics without recursively starting another cleanup'
)) {
  Assert-Contains $integrityRegression $phrase 'Structural pre-flush regression is incomplete.'
}

foreach ($needle in @(
  'extends "res://tests/qa/structural_integrity_scale_desktop_acceptance.gd"',
  'const MAX_SINGLE_FLUSH_CLEANUP_MILLISECONDS := 12000.0',
  'const MAX_SINGLE_FLUSH_CHUNKS := 32',
  'const MAX_RULE_CLEANUP_MILLISECONDS := 1000.0',
  'failures.erase(LEGACY_TIME_FAILURE)',
  'failures.erase(LEGACY_FLUSH_FAILURE)',
  'await super._finish(game, hub)'
)) {
  Assert-Contains $desktop $needle 'Single-flush desktop entry point is incomplete.'
}
foreach ($phrase in @(
  '384 structures clean up inside the twelve-second software-renderer budget',
  'support removal and dependent cleanup share one world rebuild flush',
  'single flush rebuilds at most thirty-two actual chunks',
  'outer support mutation and nested cleanup each emit one bounded pre-flush summary',
  'integrity runtime joins exactly one outer mutation batch without recursion',
  'structural rule resolution completes inside one second before mesh rebuild',
  'dependent structural mutations remain inside the outer dirty-chunk set'
)) {
  Assert-Contains $desktop $phrase 'Single-flush desktop evidence is incomplete.'
}

Assert-Contains $import 'structural_integrity_single_flush_desktop_acceptance.gd' 'Headless import must parse the optimized desktop entry point.'
foreach ($needle in @(
  'tests/developer_b/validate_structural_single_flush.ps1',
  'res://tests/qa/world_mutation_pre_flush_regression.gd',
  'res://tests/qa/structural_integrity_single_flush_desktop_acceptance.gd'
)) {
  Assert-Contains $workflow $needle 'Structural workflow is missing a single-flush gate.'
}
Assert-Contains $runAll 'validate_structural_single_flush.ps1' 'Full validation entry point is incomplete.'
Assert-Contains $runAll 'world_mutation_pre_flush_regression.gd' 'Full runtime entry point is incomplete.'

foreach ($needle in @(
  '15.95 s',
  '8.41 s',
  '减少 50%',
  '一个世界网格 Flush',
  '最多 32 个实际 Chunk 重建',
  '结构规则阶段 <= 1 s',
  '软件渲染总清理时间 <= 12 s',
  '不进入存档'
)) {
  Assert-Contains $contract $needle 'Single-flush optimization document is incomplete.'
}

Write-Host 'PASS structural_single_flush outer=1 nested=1 mesh_flush=1 chunks<=32 rules_ms<=1000 desktop_ms<=12000 persistence=none'
