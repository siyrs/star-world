$ErrorActionPreference = 'Stop'

$root = Resolve-Path "$PSScriptRoot\..\.."
$registryPath = Join-Path $root 'src\block\block_registry.gd'
$connectionPath = Join-Path $root 'src\block\block_connection_policy.gd'
$geometryPath = Join-Path $root 'src\block\block_shape_geometry.gd'
$chunkPath = Join-Path $root 'src\chunk\voxel_chunk.gd'
$previewPath = Join-Path $root 'src\interaction\placement_preview_policy.gd'
$playerPath = Join-Path $root 'src\player\precision_interaction_player.gd'
$worldPath = Join-Path $root 'src\world\voxel_world.gd'
$regressionPath = Join-Path $root 'tests\qa\connected_block_shapes_regression.gd'
$desktopPath = Join-Path $root 'tests\qa\connected_block_shapes_desktop_acceptance.gd'
$workflowPath = Join-Path $root '.github\workflows\connected-block-shapes-tests.yml'
$runAllPath = Join-Path $root 'tests\run_all.ps1'

foreach ($path in @(
  $registryPath,$connectionPath,$geometryPath,$chunkPath,$previewPath,$playerPath,
  $worldPath,$regressionPath,$desktopPath,$workflowPath,$runAllPath
)) {
  if (-not (Test-Path -LiteralPath $path)) { throw "Missing connected-shape contract file: $path" }
}

$registry = Get-Content -Raw -Encoding UTF8 $registryPath
$connection = Get-Content -Raw -Encoding UTF8 $connectionPath
$geometry = Get-Content -Raw -Encoding UTF8 $geometryPath
$chunk = Get-Content -Raw -Encoding UTF8 $chunkPath
$preview = Get-Content -Raw -Encoding UTF8 $previewPath
$player = Get-Content -Raw -Encoding UTF8 $playerPath
$world = Get-Content -Raw -Encoding UTF8 $worldPath
$regression = Get-Content -Raw -Encoding UTF8 $regressionPath
$desktop = Get-Content -Raw -Encoding UTF8 $desktopPath
$workflow = Get-Content -Raw -Encoding UTF8 $workflowPath
$runAll = Get-Content -Raw -Encoding UTF8 $runAllPath

if ($registry -notmatch '"oak_fence"\s*:\s*\{[^\r\n]*"shape"\s*:\s*"fence"[^\r\n]*"connection_family"\s*:\s*"oak_fence"') {
  throw 'Oak fence must use the connected fence shape family'
}
foreach ($paneId in @('glass_pane','glass_pane_ns')) {
  if ($registry -notmatch ('"' + $paneId + '"\s*:\s*\{[^\r\n]*"shape"\s*:\s*"pane"[^\r\n]*"connection_family"\s*:\s*"glass_pane"')) {
    throw "Pane variant is missing the shared connection family: $paneId"
  }
}
if ($registry -match 'glass_pane_(east|west|north|south|ne|nw|se|sw|cross)' -or $registry -match 'oak_fence_(east|west|north|south|cross)') {
  throw 'Connected shapes must not persist one block ID per neighbor mask'
}

foreach ($constant in @('EAST\s*:=\s*1','WEST\s*:=\s*2','SOUTH\s*:=\s*4','NORTH\s*:=\s*8','ALL\s*:=\s*EAST\s*\|\s*WEST\s*\|\s*SOUTH\s*\|\s*NORTH')) {
  if ($connection -notmatch $constant) { throw "Connection policy is missing stable mask contract: $constant" }
}
foreach ($method in @('supports','family_id','can_connect','resolve_mask','fallback_mask','read_neighbors','connected_face','mask_names')) {
  if ($connection -notmatch "static\s+func\s+$method\s*\(") { throw "Connection policy is missing method: $method" }
}
if ($connection -notmatch 'shape",\s*"cube"\)\)\s*==\s*"cube"') {
  throw 'Connected shapes must only attach to same-family blocks or full cube anchors'
}

foreach ($shapeMethod in @('_pane_boxes','_fence_boxes','_face_fully_covered_by_neighbor_box')) {
  if ($geometry -notmatch "static\s+func\s+$shapeMethod\s*\(") { throw "Shape geometry is missing connected helper: $shapeMethod" }
}
if ($geometry -notmatch 'cross_fence|') { }
if ($geometry -notmatch 'return\s+shape\s+not\s+in\s+\[[^\]]*"pane"[^\]]*"fence"') {
  throw 'Panes and fences must remain in the shared partial geometry pipeline'
}
if ($geometry -notmatch 'requested_mask\s*&\s*ConnectionPolicyScript\.ALL') {
  throw 'Connection masks must be clamped to four horizontal directions'
}

if ($chunk -notmatch 'block_connection_policy\.gd' -or $chunk -notmatch '_resolve_connection_mask') {
  throw 'VoxelChunk must derive connected geometry from live neighbor blocks'
}
if ($chunk -notmatch 'ConnectionPolicyScript\.connected_face') {
  throw 'VoxelChunk must suppress connected boundary faces for visual and collision meshes'
}
if ($chunk -match 'block_overrides\[[^\]]+\]\s*=\s*.*connection') {
  throw 'Connection masks are transient derived state and must not enter world overrides'
}
if ($world -notmatch '_rebuild_affected_chunks' -or $world -notmatch 'chunk\.rebuild_mesh\(\)') {
  throw 'World block changes must rebuild local and cross-chunk connected neighbors'
}

foreach ($field in @('target_connection_mask','placement_connection_mask','target_neighbor_ids','placement_neighbor_ids')) {
  if (($preview + "`n" + $player) -notmatch $field) { throw "Preview pipeline is missing connected-shape field: $field" }
}
if ($preview -notmatch 'world_boxes\([\s\S]{0,160}placement_mask') {
  throw 'Placement overlap must use the same resolved connection mask as the preview'
}

foreach ($phrase in @(
  'one-sided pane uses a post and one arm',
  'four-way fence uses one post and eight bounded rails',
  'rebuild removes stale connected faces after neighbor removal'
)) {
  if ($regression -notmatch [regex]::Escape($phrase)) { throw "Connected-shape regression is missing assertion: $phrase" }
}
foreach ($phrase in @(
  'real right click places the first glass pane',
  'preview expands toward the existing pane',
  'removing the neighbor rebuilds the surviving pane',
  'full reload restores connected silhouettes without persisted masks'
)) {
  if ($desktop -notmatch [regex]::Escape($phrase)) { throw "Connected-shape desktop acceptance is missing assertion: $phrase" }
}
if ($workflow -notmatch 'connected_block_shapes_regression\.gd' -or $workflow -notmatch 'connected_block_shapes_desktop_acceptance\.gd') {
  throw 'Connected-shape workflow must run both domain and real desktop acceptance'
}
if ($runAll -notmatch 'validate_connected_block_shapes\.ps1' -or $runAll -notmatch 'connected_block_shapes_regression\.gd') {
  throw 'Full regression entry point must permanently include connected-shape validation'
}

Write-Host 'PASS connected_block_shapes families=2 directions=4 pane_boxes<=5 fence_boxes<=9 masks=persisted:no preview=shared chunk_rebuild=live'
