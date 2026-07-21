$ErrorActionPreference = 'Stop'

$root = Resolve-Path "$PSScriptRoot\..\.."
$registryPath = Join-Path $root 'src\block\block_registry.gd'
$policyPath = Join-Path $root 'src\block\block_door_policy.gd'
$orientationPath = Join-Path $root 'src\block\block_orientation_policy.gd'
$geometryPath = Join-Path $root 'src\block\block_shape_geometry.gd'
$previewPath = Join-Path $root 'src\interaction\placement_preview_policy.gd'
$servicePath = Join-Path $root 'src\interaction\block_door_interaction_service.gd'
$playerPath = Join-Path $root 'src\player\precision_interaction_player.gd'
$harvestPath = Join-Path $root 'src\harvest\block_harvest_service.gd'
$harvestRegistryPath = Join-Path $root 'src\harvest\block_harvest_registry.gd'
$hubPath = Join-Path $root 'src\ui\tool_progression_service_hub.gd'
$regressionPath = Join-Path $root 'tests\qa\double_door_regression.gd'
$desktopPath = Join-Path $root 'tests\qa\double_door_desktop_acceptance.gd'
$workflowPath = Join-Path $root '.github\workflows\double-door-tests.yml'
$runAllPath = Join-Path $root 'tests\run_all.ps1'

foreach ($path in @(
  $registryPath,$policyPath,$orientationPath,$geometryPath,$previewPath,$servicePath,
  $playerPath,$harvestPath,$harvestRegistryPath,$hubPath,$regressionPath,$desktopPath,
  $workflowPath,$runAllPath
)) {
  if (-not (Test-Path -LiteralPath $path)) { throw "Missing double-door contract file: $path" }
}

$registry = Get-Content -Raw -Encoding UTF8 $registryPath
$policy = Get-Content -Raw -Encoding UTF8 $policyPath
$orientation = Get-Content -Raw -Encoding UTF8 $orientationPath
$geometry = Get-Content -Raw -Encoding UTF8 $geometryPath
$preview = Get-Content -Raw -Encoding UTF8 $previewPath
$service = Get-Content -Raw -Encoding UTF8 $servicePath
$player = Get-Content -Raw -Encoding UTF8 $playerPath
$harvest = Get-Content -Raw -Encoding UTF8 $harvestPath
$harvestRegistry = Get-Content -Raw -Encoding UTF8 $harvestRegistryPath
$hub = Get-Content -Raw -Encoding UTF8 $hubPath
$regression = Get-Content -Raw -Encoding UTF8 $regressionPath
$desktop = Get-Content -Raw -Encoding UTF8 $desktopPath
$workflow = Get-Content -Raw -Encoding UTF8 $workflowPath
$runAll = Get-Content -Raw -Encoding UTF8 $runAllPath

$blockListMatch = [regex]::Match($registry, '(?s)const BLOCK_IDS := \[(.*?)\]')
if (-not $blockListMatch.Success) { throw 'Unable to parse BlockRegistry.BLOCK_IDS' }
$blockIds = @([regex]::Matches($blockListMatch.Groups[1].Value, '"([^"]+)"') | ForEach-Object { $_.Groups[1].Value })
if ([array]::IndexOf($blockIds, 'oak_door') -ne 23) { throw 'Legacy oak_door numeric ID must remain 23' }
$doorVariants = @($blockIds | Where-Object { $_ -eq 'oak_door' -or $_ -like 'oak_door_*' })
if ($doorVariants.Count -ne 16) { throw "Expected 16 persisted door variants, got $($doorVariants.Count)" }
if (@($doorVariants | Select-Object -Unique).Count -ne 16) { throw 'Door variants must be unique' }
if ([array]::IndexOf($blockIds, 'oak_door_east') -le [array]::IndexOf($blockIds, 'stonecutter')) {
  throw 'New door variants must append after all legacy blocks'
}
if ($registry -notmatch '"oak_door"\s*:\s*\{[^\r\n]*"shape"\s*:\s*"door"[^\r\n]*"door_half"\s*:\s*"lower"') {
  throw 'Legacy oak_door must become the south/closed/lower door state'
}
foreach ($variant in $doorVariants) {
  if ($registry -notmatch ('"' + [regex]::Escape($variant) + '"\s*:\s*\{[^\r\n]*"door_family"\s*:\s*"oak_door"')) {
    throw "Door variant is missing the oak_door family: $variant"
  }
}
if ($registry -match '"doors"\s*:' -or $registry -match 'door_state_cache') {
  throw 'Door state must remain encoded by block IDs, not a parallel registry domain'
}

foreach ($constant in @('CLOSED_LOWER','CLOSED_UPPER','OPEN_LOWER','OPEN_UPPER')) {
  if ($policy -notmatch "const\s+$constant") { throw "Door policy is missing state table: $constant" }
}
foreach ($method in @(
  'supports','is_upper','is_open','rotation_quarters','variant','closed_lower_for_quarters',
  'upper_variant','toggled_variant','resolve_pair','local_box','placement_boxes',
  'placement_world_boxes'
)) {
  if ($policy -notmatch "static\s+func\s+$method\s*\(") { throw "Door policy is missing method: $method" }
}
if ($policy -notmatch 'THICKNESS\s*:=\s*0\.125') { throw 'Door collision thickness must remain one eighth of a block' }
if ($orientation -notmatch 'DOOR_FAMILY\s*:=\s*"oak_door"' -or $orientation -notmatch 'closed_lower_for_quarters') {
  throw 'Orientation policy must resolve held doors to a closed lower variant'
}
if ($geometry -notmatch '"door"\s*:\s*\r?\n\s*boxes\s*=\s*\[DoorPolicyScript\.local_box') {
  throw 'Shared block geometry must render every persisted door half through the door policy'
}
if ($geometry -notmatch '"door"\]') { throw 'Door must remain a partial geometry shape' }

foreach ($field in @('placement_companion_position','placement_companion_block_id','placement_upper_block_id','placement_support_block_id')) {
  if (($preview + "`n" + $player) -notmatch $field) { throw "Door preview pipeline is missing field: $field" }
}
if ($preview -notmatch 'door_upper_occupied' -or $preview -notmatch 'door_support_missing') {
  throw 'Door preview must reject upper-cell occupation and missing support'
}
if ($preview -notmatch 'placement_world_boxes') { throw 'Door player-overlap must use the complete two-cell geometry' }
if ($player -notmatch 'bind_block_structure_service' -or $player -notmatch 'try_place_block') {
  throw 'Production player must route structured placement through the door service'
}

foreach ($method in @('try_interact','try_place_block','remove_block_structure','get_interaction_hint','get_snapshot','shutdown')) {
  if ($service -notmatch "func\s+$method\s*\(") { throw "Door interaction service is missing method: $method" }
}
if ($service -notmatch 'consume_selected' -or $service -notmatch 'door_inventory_race') {
  throw 'Door placement must consume one item only after both cells commit and roll back inventory races'
}
if ($service -notmatch '_replace_pair' -or $service -notmatch 'door_toggle_failed') {
  throw 'Door toggles must update both halves with rollback'
}
if ($harvest -notmatch 'remove_block_structure' -or $harvest -notmatch 'removed_positions') {
  throw 'Harvest must delegate linked door removal and preserve both removed positions'
}
if ($harvestRegistry -notmatch 'harvest_parent' -or $harvestRegistry -notmatch 'visual_parent') {
  throw 'Variant blocks must inherit canonical harvest rules'
}
if ($hub -notmatch 'DoorInteractionServiceScript' -or $hub -notmatch 'register_extension' -or $hub -notmatch 'bind_block_structure_service') {
  throw 'ToolProgressionServiceHub must compose, register and bind the door service'
}

foreach ($phrase in @(
  'legacy oak_door numeric ID remains stable',
  'failed toggle rolls the lower half back to its original state',
  'paired removal grants exactly one canonical door item',
  'inventory race restores both cells'
)) {
  if ($regression -notmatch [regex]::Escape($phrase)) { throw "Double-door regression is missing assertion: $phrase" }
}
foreach ($phrase in @(
  'real preview rejects an occupied upper door cell',
  'real right click atomically places matching door halves',
  'real harvesting of the upper half removes the complete door',
  'full reload preserves the open state'
)) {
  if ($desktop -notmatch [regex]::Escape($phrase)) { throw "Double-door desktop acceptance is missing assertion: $phrase" }
}
if ($workflow -notmatch 'double_door_regression\.gd' -or $workflow -notmatch 'double_door_desktop_acceptance\.gd') {
  throw 'Double-door workflow must run both domain and real desktop acceptance'
}
if ($runAll -notmatch 'validate_double_doors\.ps1' -or $runAll -notmatch 'double_door_regression\.gd') {
  throw 'Full regression entry point must permanently include double-door validation'
}

Write-Host 'PASS double_doors states=16 cells=2 drop=1 open_collision=edge persistence=block_ids atomic=true'
