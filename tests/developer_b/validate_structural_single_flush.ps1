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

foreach ($token in @(
  'signal\s+block_mutation_batch_pre_flush',
  '_batch_pre_flush_emit_count',
  'block_mutation_batch_pre_flush\.emit',
  '"batch_depth"\s*:\s*_rebuild_batch_depth',
  '"pending_chunks"\s*:\s*_dirty_rebuild_chunks\.size\(\)',
  '"pre_flush_emit_count"\s*:\s*_batch_pre_flush_emit_count'
)) {
  if ($world -notmatch $token) {
    throw "Batched world is missing pre-flush contract: $token"
  }
}
if ($world -notmatch 'block_mutation_batch_pre_flush\.emit[\s\S]{0,500}end_chunk_rebuild_batch\(true\)') {
  throw 'Pre-flush signal must run after mutations but before the outer rebuild batch closes'
}
if ($world -match 'block_mutation_batch_pre_flush\.emit\([\s\S]{0,300}changes') {
  throw 'Pre-flush summary must not publish the full mutation array'
}

foreach ($token in @(
  'class_name\s+BatchedBlockStructureIntegrityService',
  'extends\s+"res://src/interaction/block_structure_integrity_service\.gd"',
  'PRE_FLUSH_SIGNAL\s*:=\s*"block_mutation_batch_pre_flush"',
  'func\s+bind_world\s*\(',
  'func\s+_connect_pre_flush\s*\(',
  'func\s+_disconnect_pre_flush\s*\(',
  '_shutdown\s+or\s+_applying_cleanup\s+or\s+_pending_candidates\.is_empty\(\)',
  '_last_pre_flush_result\s*=\s*flush_pending\(\)',
  'pre_flush_cleanup_count',
  'pre_flush_signal_count'
)) {
  if ($service -notmatch $token) {
    throw "Batched integrity service is missing single-flush behavior: $token"
  }
}
if ($service -match 'Timer\.new\(' -or $service -match 'FileAccess') {
  throw 'Batched integrity adapter must remain transient and reuse the shared process loop'
}

if ($hub -notmatch 'batched_block_structure_integrity_service\.gd') {
  throw 'Production ToolProgressionServiceHub must compose the batched integrity adapter'
}
if ($hub -notmatch 'StructuralIntegrityServiceScript\.new\(\),\s*"StructuralIntegrity"') {
  throw 'Production structural integrity node path must remain stable'
}

foreach ($phrase in @(
  'outer and nested batches emit deterministic pre-flush summaries',
  'nested mutation returns while the outer dirty-chunk transaction remains open',
  'outer and nested boundary edits share one two-chunk mesh flush',
  'each loaded boundary chunk rebuilds exactly once',
  'pre-flush hooks and counters remain transient'
)) {
  if ($worldRegression -notmatch [regex]::Escape($phrase)) {
    throw "World pre-flush regression is missing assertion: $phrase"
  }
}
foreach ($phrase in @(
  'outer batch pre-flush drains the structural queue before the API returns',
  'one outer support batch owns exactly one nested structural mutation batch',
  'nested cleanup emits diagnostics without recursively starting another cleanup'
)) {
  if ($integrityRegression -notmatch [regex]::Escape($phrase)) {
    throw "Structural pre-flush regression is missing assertion: $phrase"
  }
}

foreach ($token in @(
  'extends\s+"res://tests/qa/structural_integrity_scale_desktop_acceptance\.gd"',
  'MAX_SINGLE_FLUSH_CLEANUP_MILLISECONDS\s*:=\s*12000',
  'MAX_SINGLE_FLUSH_CHUNKS\s*:=\s*32',
  'MAX_RULE_CLEANUP_MILLISECONDS\s*:=\s*1000',
  'failures\.erase\(LEGACY_TIME_FAILURE\)',
  'failures\.erase\(LEGACY_FLUSH_FAILURE\)',
  'flush_count',
  'pre_flush_cleanup_count',
  'batch_active',
  'await\s+super\._finish'
)) {
  if ($desktop -notmatch $token) {
    throw "Single-flush desktop acceptance is missing optimized evidence: $token"
  }
}
foreach ($phrase in @(
  '384 structures clean up inside the twelve-second software-renderer budget',
  'support removal and dependent cleanup share one world rebuild flush',
  'single flush rebuilds at most thirty-two actual chunks',
  'structural rule resolution completes inside one second before mesh rebuild',
  'dependent structural mutations remain inside the outer dirty-chunk set'
)) {
  if ($desktop -notmatch [regex]::Escape($phrase)) {
    throw "Single-flush desktop acceptance is missing assertion: $phrase"
  }
}

if ($import -notmatch 'structural_integrity_single_flush_desktop_acceptance\.gd') {
  throw 'Headless import regression must parse the optimized desktop entry point'
}
foreach ($token in @(
  'validate_structural_single_flush\.ps1',
  'world_mutation_pre_flush_regression\.gd',
  'structural_integrity_single_flush_desktop_acceptance\.gd'
)) {
  if ($workflow -notmatch $token) {
    throw "Structural workflow is missing single-flush gate: $token"
  }
}
if ($runAll -notmatch 'validate_structural_single_flush\.ps1') {
  throw 'Full validation entry point must include the single-flush static contract'
}
if ($runAll -notmatch 'world_mutation_pre_flush_regression\.gd') {
  throw 'Full runtime entry point must include the world pre-flush regression'
}

foreach ($token in @(
  '15\.95',
  '8\.41',
  '50%',
  '一个世界网格 Flush',
  '最多 32 个实际 Chunk 重建',
  '结构规则阶段 <= 1 s',
  '软件渲染总清理时间 <= 12 s',
  '不进入存档'
)) {
  if ($contract -notmatch $token) {
    throw "Single-flush optimization document is missing evidence or boundary: $token"
  }
}

Write-Host 'PASS structural_single_flush outer=1 nested=1 mesh_flush=1 chunks<=32 rules_ms<=1000 desktop_ms<=12000 persistence=none'
