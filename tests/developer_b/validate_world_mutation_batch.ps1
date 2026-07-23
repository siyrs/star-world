$ErrorActionPreference = 'Stop'

$root = Resolve-Path "$PSScriptRoot\..\.."
$worldPath = Join-Path $root 'src\world\voxel_world.gd'
$batchPath = Join-Path $root 'src\world\batched_voxel_world.gd'
$gamePath = Join-Path $root 'src\core\batched_game.gd'
$scenePath = Join-Path $root 'scenes\game\game.tscn'
$regressionPath = Join-Path $root 'tests\qa\world_mutation_batch_regression.gd'
$desktopPath = Join-Path $root 'tests\qa\world_scale_desktop_acceptance.gd'
$workflowPath = Join-Path $root '.github\workflows\world-scale-tests.yml'
$reusablePath = Join-Path $root '.github\workflows\reusable-godot-quality-gate.yml'
$runAllPath = Join-Path $root 'tests\run_all.ps1'
$contractPath = Join-Path $root 'docs\BOUNDED_WORLD_MUTATION_BATCHING.md'
$auditPath = Join-Path $root 'docs\ARCHITECTURE_AUDIT_2026-07-22_ITERATION_22.md'

foreach ($path in @($worldPath,$batchPath,$gamePath,$scenePath,$regressionPath,$desktopPath,$workflowPath,$reusablePath,$runAllPath,$contractPath,$auditPath)) {
  if (-not (Test-Path -LiteralPath $path)) { throw "Missing world mutation batching contract file: $path" }
}

$world = Get-Content -Raw -Encoding UTF8 $worldPath
$batch = Get-Content -Raw -Encoding UTF8 $batchPath
$game = Get-Content -Raw -Encoding UTF8 $gamePath
$scene = Get-Content -Raw -Encoding UTF8 $scenePath
$regression = Get-Content -Raw -Encoding UTF8 $regressionPath
$desktop = Get-Content -Raw -Encoding UTF8 $desktopPath
$workflow = Get-Content -Raw -Encoding UTF8 $workflowPath
$reusable = Get-Content -Raw -Encoding UTF8 $reusablePath
$runAll = Get-Content -Raw -Encoding UTF8 $runAllPath
$contract = Get-Content -Raw -Encoding UTF8 $contractPath
$audit = Get-Content -Raw -Encoding UTF8 $auditPath

if ($world -notmatch 'func\s+set_block\s*\([\s\S]*?_rebuild_affected_chunks\(block_position\)') { throw 'Base VoxelWorld must keep one overridable rebuild boundary inside set_block' }
if ($batch -notmatch 'extends\s+"res://src/world/voxel_world\.gd"') { throw 'Batched world must preserve the existing VoxelWorld public contract through inheritance' }
foreach ($constant in @('MAX_REBUILD_BATCH_DEPTH\s*:=\s*8','MAX_DIRTY_REBUILD_CHUNKS\s*:=\s*256','MAX_BLOCK_MUTATIONS_PER_BATCH\s*:=\s*4096')) {
  if ($batch -notmatch $constant) { throw "Missing or changed hard budget: $constant" }
}
foreach ($method in @('begin_chunk_rebuild_batch','end_chunk_rebuild_batch','flush_chunk_rebuilds','apply_block_mutations','get_chunk_rebuild_stats','reset_chunk_rebuild_stats','get_streaming_stats','_rebuild_affected_chunks','_affected_chunk_coords')) {
  if ($batch -notmatch "func\s+$method\s*\(") { throw "Batched world is missing method: $method" }
}
if ($batch -notmatch '_dirty_rebuild_chunks\.has\(coord\)' -or $batch -notmatch '_coalesced_rebuild_count\s*\+=\s*1') { throw 'Repeated rebuild requests must deduplicate through the dirty chunk set' }
if ($batch -notmatch '_rebuild_batch_depth\s*==\s*0[\s\S]*?flush_chunk_rebuilds\("immediate_mutation"\)') { throw 'Single mutations must preserve immediate visual and collision correctness' }
if ($batch -notmatch 'pending_coords\.sort_custom') { throw 'Dirty chunk flush order must remain deterministic' }
if ($batch -notmatch '_building_chunks\.get\(coord\)') { throw 'A mutation during an in-progress chunk build must not leave a stale final mesh' }
if ($batch -match 'Timer\.new\(' -or $batch -match 'func\s+_process\s*\(') { throw 'World mutation batching must not create a timer or a second per-frame scheduler' }
if ($batch -match 'func\s+serialize\s*\(' -or $batch -match 'block_overrides\s*\[') { throw 'Rebuild batching must not become a parallel persistence owner' }
if ($batch -notmatch 'result\["rebuild"\]\s*=\s*rebuild') { throw 'Rebuild evidence must extend existing streaming diagnostics' }
if ($batch -notmatch '_reset_rebuild_runtime\(\)[\s\S]*?super\.clear_world\(\)') { throw 'World clear must remove pending rebuild state before inherited cleanup' }

if ($game -notmatch 'extends\s+"res://src/core/game\.gd"' -or $game -notmatch 'batched_voxel_world\.gd') { throw 'Production game composition must use the batched VoxelWorld subclass' }
if ($scene -notmatch 'res://src/core/batched_game\.gd') { throw 'Production GameScene must instantiate batched game composition' }

foreach ($phrase in @('single mutation preserves immediate mesh correctness','one hundred twenty-eight edits deduplicate to one dirty chunk','ten boundary edits collapse twenty requests into two rebuilds','four thousand mutations still rebuild one loaded chunk once','rebuild diagnostics remain transient and never enter world saves')) {
  if ($regression -notmatch [regex]::Escape($phrase)) { throw "World mutation regression is missing assertion: $phrase" }
}
foreach ($phrase in @('scale fixture contains more than three thousand bounded mutations','actual rebuilds never exceed unique dirty chunks','large world save remains below two megabytes','full scale-world reload reaches a bounded playable state','visual evidence uses 1024x576 product resolution')) {
  if ($desktop -notmatch [regex]::Escape($phrase)) { throw "World scale desktop acceptance is missing assertion: $phrase" }
}
if ($desktop -notmatch 'world-scale-desktop\.json' -and $desktop -notmatch 'get_basename\(\)\s*\+\s*"\.json"') { throw 'Desktop scale acceptance must persist a machine-readable benchmark report' }
if ($workflow -notmatch 'uses:\s*\./\.github/workflows/reusable-godot-quality-gate\.yml' -or $workflow -notmatch 'world_mutation_batch_regression\.gd') {
  throw 'World scale caller must declare real domain tests through the reusable gate'
}
if ($reusable -notmatch 'tests\\ci\\Invoke-Godot\.ps1' -or $reusable -notmatch 'tests\\ci\\run_godot_desktop_test\.ps1') {
  throw 'Reusable Godot gate must own awaited domain and desktop execution'
}
if ($workflow -notmatch 'world_scale_desktop_acceptance\.gd' -or $workflow -notmatch 'world-scale-desktop\.json') {
  throw 'World scale caller must retain visualization and benchmark evidence declarations'
}
if ($runAll -notmatch 'validate_world_mutation_batch\.ps1' -or $runAll -notmatch 'world_mutation_batch_regression\.gd') { throw 'Full regression entry point must permanently include world mutation batching' }
if ($contract -notmatch '4,?096' -or $contract -notmatch '256' -or $contract -notmatch 'immediate') { throw 'World mutation contract must document budgets and immediate single-edit semantics' }
if ($audit -notmatch 'set_block' -or $audit -notmatch '16×64×16') { throw 'Architecture audit must record the original full-chunk rebuild problem' }

Write-Host 'PASS world_mutation_batch depth=8 dirty_chunks=256 mutations=4096 single_edit=immediate diagnostics=streaming persistence=none ci=reusable'
