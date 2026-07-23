$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = Resolve-Path "$PSScriptRoot\..\.."
$paths = @{
  Policy = Join-Path $root 'src\world\recent_chunk_snapshot_cache.gd'
  Chunk = Join-Path $root 'src\chunk\cached_voxel_chunk.gd'
  World = Join-Path $root 'src\world\cached_batched_voxel_world.gd'
  Game = Join-Path $root 'src\core\batched_game.gd'
  Regression = Join-Path $root 'tests\qa\recent_chunk_snapshot_cache_regression.gd'
  Desktop = Join-Path $root 'tests\qa\recent_chunk_cache_desktop_acceptance.gd'
  Workflow = Join-Path $root '.github\workflows\recent-chunk-cache-tests.yml'
  Reusable = Join-Path $root '.github\workflows\reusable-godot-quality-gate.yml'
  RunAll = Join-Path $root 'tests\run_all.ps1'
  Contract = Join-Path $root 'docs\RECENT_CHUNK_SNAPSHOT_CACHE.md'
  Audit = Join-Path $root 'docs\ARCHITECTURE_AUDIT_2026-07-22_ITERATION_25.md'
}
foreach ($entry in $paths.GetEnumerator()) {
  if (-not (Test-Path -LiteralPath $entry.Value)) { throw "Recent chunk cache file is missing: $($entry.Key) $($entry.Value)" }
}
$text = @{}
foreach ($entry in $paths.GetEnumerator()) { $text[$entry.Key] = Get-Content -Raw -Encoding UTF8 $entry.Value }

if ($text.Policy -notmatch 'MAX_SNAPSHOTS\s*:=\s*64' -or $text.Policy -notmatch 'CHUNK_CELL_COUNT\s*:=\s*16\s*\*\s*64\s*\*\s*16') {
  throw 'Recent chunk cache must retain exactly sixty-four complete 16x64x16 block snapshots'
}
foreach ($method in @('store','take','patch','clear','get_stats')) {
  if ($text.Policy -notmatch "func\s+$method\s*\(") { throw "Recent cache policy is missing: $method" }
}
if ($text.Policy -notmatch '_lru_order\.pop_front\(\)' -or $text.Policy -notmatch '_eviction_count\s*\+=\s*1') {
  throw 'Recent chunk cache must evict the oldest snapshot at capacity'
}
if ($text.Policy -match 'func\s+serialize\s*\(' -or $text.Policy -match 'FileAccess' -or $text.Policy -match 'Timer\.new\(') {
  throw 'Recent chunk cache must remain transient and must not own files or timers'
}
if ($text.Chunk -notmatch 'extends\s+"res://src/chunk/voxel_chunk\.gd"') {
  throw 'Cached chunk must preserve the existing VoxelChunk public contract'
}
foreach ($method in @('begin_initialize_from_snapshot','capture_block_snapshot','can_capture_block_snapshot','was_hydrated_from_snapshot','local_cell_index')) {
  if ($text.Chunk -notmatch "func\s+$method\s*\(" -and $text.Chunk -notmatch "static\s+func\s+$method\s*\(") { throw "Cached chunk is missing: $method" }
}
if ($text.Chunk -notmatch '_begin_mesh_build\(\)' -or $text.Chunk -notmatch '_generation_cells_skipped\s*=\s*TOTAL_CELLS') {
  throw 'Snapshot hydration must skip generation and begin directly at mesh construction'
}
if ($text.World -notmatch 'extends\s+"res://src/world/batched_voxel_world\.gd"') {
  throw 'Cached world must retain bounded mutation batching through inheritance'
}
foreach ($method in @('_begin_next_chunk_build','_load_chunk_synchronously','_unload_chunk','_cancel_build','get_recent_chunk_cache_stats','get_streaming_stats')) {
  if ($text.World -notmatch "func\s+$method\s*\(") { throw "Cached world is missing: $method" }
}
if ($text.World -notmatch '_recent_chunk_cache\.patch' -or $text.World -notmatch '_cache_chunk_snapshot') {
  throw 'Unloaded authoritative edits and unload/cancel paths must update recent snapshots'
}
if ($text.World -notmatch 'result\["recent_chunk_cache"\]') {
  throw 'Recent cache evidence must extend the existing streaming diagnostics'
}
if ($text.World -match 'func\s+serialize\s*\(' -or $text.World -match 'Timer\.new\(' -or $text.World -match 'func\s+_process\s*\(') {
  throw 'Recent cache must not become a persistence owner or a second scheduler'
}
if ($text.Game -notmatch 'cached_batched_voxel_world\.gd') {
  throw 'Production GameScene must compose the cached batched world'
}
foreach ($phrase in @(
  'sixty-five stores retain sixty-four recent snapshots and evict one',
  'warm chunk reload skips sixteen-thousand-three-hundred-eighty-four generation cells',
  'unloaded edits patch the cached block array before the next warm reload',
  'recent chunk snapshots and diagnostics remain transient and never enter world saves'
)) {
  if ($text.Regression -notmatch [regex]::Escape($phrase)) { throw "Recent chunk cache regression is missing assertion: $phrase" }
}
foreach ($phrase in @(
  'hydrates every target chunk from a recent snapshot',
  'cross-chunk glass panes re-derive a non-empty connection mask after repeated reloads',
  'recent chunk cache never exceeds its sixty-four snapshot memory budget',
  'chunk-cache visual evidence uses 1024x576 resolution',
  'new world session starts without stale in-memory chunk snapshots'
)) {
  if ($text.Desktop -notmatch [regex]::Escape($phrase)) { throw "Recent chunk cache desktop acceptance is missing assertion: $phrase" }
}
if ($text.Workflow -notmatch 'uses:\s*\./\.github/workflows/reusable-godot-quality-gate\.yml' -or $text.Workflow -notmatch 'recent_chunk_snapshot_cache_regression\.gd') {
  throw 'Recent chunk cache caller must declare real domain tests through the reusable gate'
}
if ($text.Reusable -notmatch 'tests\\ci\\Invoke-Godot\.ps1' -or $text.Reusable -notmatch 'tests\\ci\\run_godot_desktop_test\.ps1') {
  throw 'Reusable Godot gate must own awaited domain and desktop execution'
}
if ($text.Workflow -notmatch 'recent_chunk_cache_desktop_acceptance\.gd' -or $text.Workflow -notmatch 'recent-chunk-cache-desktop\.json') {
  throw 'Recent chunk cache caller must retain visualization and benchmark evidence declarations'
}
if ($text.RunAll -notmatch 'validate_recent_chunk_cache\.ps1' -or $text.RunAll -notmatch 'recent_chunk_snapshot_cache_regression\.gd') {
  throw 'Full regression entry point must permanently include recent chunk caching'
}
if ($text.Contract -notmatch '64' -or $text.Contract -notmatch '4 MiB' -or $text.Contract -notmatch '不进入存档') {
  throw 'Recent chunk cache contract must document memory and persistence boundaries'
}
if ($text.Audit -notmatch '16,384' -or $text.Audit -notmatch '卸载' -or $text.Audit -notmatch 'LRU') {
  throw 'Architecture audit must record the repeated chunk regeneration problem and bounded solution'
}

Write-Host 'PASS recent_chunk_cache snapshots=64 cells=16384 memory=4MiB patch=1 persistence=none scheduler=shared ci=reusable'
