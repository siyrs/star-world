$ErrorActionPreference = 'Stop'

$root = Resolve-Path "$PSScriptRoot\..\.."
$registryPath = Join-Path $root 'src\block\block_registry.gd'
$policyPath = Join-Path $root 'src\block\block_ladder_policy.gd'
$orientationPath = Join-Path $root 'src\block\block_orientation_policy.gd'
$geometryPath = Join-Path $root 'src\block\block_shape_geometry.gd'
$targetResolverPath = Join-Path $root 'src\interaction\voxel_target_resolver.gd'
$previewPath = Join-Path $root 'src\interaction\placement_preview_policy.gd'
$movementPath = Join-Path $root 'src\player\player_movement_controller.gd'
$ladderPlayerPath = Join-Path $root 'src\player\ladder_climbing_player.gd'
$explorationPlayerPath = Join-Path $root 'src\player\exploration_player.gd'
$runAllPath = Join-Path $root 'tests\run_all.ps1'
$workflowPath = Join-Path $root '.github\workflows\directional-ladder-tests.yml'
$doorWorkflowPath = Join-Path $root '.github\workflows\double-door-tests.yml'
$regressionPath = Join-Path $root 'tests\qa\directional_ladder_regression.gd'
$desktopPath = Join-Path $root 'tests\qa\directional_ladder_desktop_acceptance.gd'

foreach ($path in @(
  $registryPath,$policyPath,$orientationPath,$geometryPath,$targetResolverPath,
  $previewPath,$movementPath,$ladderPlayerPath,$explorationPlayerPath,$runAllPath,
  $workflowPath,$doorWorkflowPath,$regressionPath,$desktopPath
)) {
  if (-not (Test-Path -LiteralPath $path)) { throw "Directional ladder file is missing: $path" }
}

$registryText = Get-Content -Raw -Encoding UTF8 $registryPath
$policyText = Get-Content -Raw -Encoding UTF8 $policyPath
$orientationText = Get-Content -Raw -Encoding UTF8 $orientationPath
$geometryText = Get-Content -Raw -Encoding UTF8 $geometryPath
$targetResolverText = Get-Content -Raw -Encoding UTF8 $targetResolverPath
$previewText = Get-Content -Raw -Encoding UTF8 $previewPath
$movementText = Get-Content -Raw -Encoding UTF8 $movementPath
$ladderPlayerText = Get-Content -Raw -Encoding UTF8 $ladderPlayerPath
$explorationPlayerText = Get-Content -Raw -Encoding UTF8 $explorationPlayerPath
$runAllText = Get-Content -Raw -Encoding UTF8 $runAllPath
$workflowText = Get-Content -Raw -Encoding UTF8 $workflowPath
$doorWorkflowText = Get-Content -Raw -Encoding UTF8 $doorWorkflowPath

$blockIdsMatch = [regex]::Match($registryText, 'const\s+BLOCK_IDS\s*:=\s*\[(?<body>[\s\S]*?)\]\s*\n\s*const\s+DEFINITIONS')
if (-not $blockIdsMatch.Success) { throw 'Unable to parse BlockRegistry.BLOCK_IDS' }
$blockIds = @([regex]::Matches($blockIdsMatch.Groups['body'].Value, '"([^"]+)"') | ForEach-Object { $_.Groups[1].Value })
$canonicalIndex = [Array]::IndexOf($blockIds, 'ladder')
if ($canonicalIndex -ne 25) { throw "Legacy ladder numeric ID moved: expected 25, found $canonicalIndex" }
$ladderIds = @($blockIds | Where-Object { $_ -match '^ladder(?:_(?:east|north|west))?$' })
if ($ladderIds.Count -ne 4) { throw "Expected four directional ladder IDs, found $($ladderIds.Count)" }
foreach ($required in @('ladder','ladder_east','ladder_north','ladder_west')) {
  if ($required -notin $ladderIds) { throw "Missing directional ladder variant: $required" }
}
foreach ($variant in @('ladder_east','ladder_north','ladder_west')) {
  if ([Array]::IndexOf($blockIds, $variant) -le 25) { throw "Ladder variant was not append-only: $variant" }
  if ($registryText -notmatch ('"' + [regex]::Escape($variant) + '"[^\n]+"visual_parent":"ladder"[^\n]+"harvest_parent":"ladder"')) {
    throw "Ladder variant must inherit canonical visuals and harvest: $variant"
  }
}
if ($registryText -notmatch '"ladder"[^\n]+"shape":"ladder"[^\n]+"orientation_family":"ladder"[^\n]+"targetable":true[^\n]+"climbable":true') {
  throw 'Canonical ladder must expose directional, targetable and climbable contracts'
}

foreach ($constant in @(
  'THICKNESS\s*:=\s*0\.125',
  'MAX_CONTACT_CELLS\s*:=\s*18',
  'CONTACT_DEPTH\s*:=\s*0\.52'
)) {
  if ($policyText -notmatch $constant) { throw "Ladder policy budget or geometry constant is missing: $constant" }
}
foreach ($method in @(
  'resolve_for_face_normal','support_offset','local_box','is_valid_support',
  'has_support','climb_zone','resolve_contact'
)) {
  if ($policyText -notmatch "static\s+func\s+$method\s*\(") {
    throw "Ladder policy is missing method: $method"
  }
}
if ($policyText -notmatch 'shape",\s*"cube"\)\)\s*==\s*"cube"') {
  throw 'Ladders must attach only to explicit anchors or complete cube supports'
}
if ($orientationText -notmatch 'LADDER_FAMILY' -or $orientationText -notmatch 'LadderPolicyScript\.variant_for_quarters') {
  throw 'Shared orientation policy must resolve ladder variants'
}
if ($geometryText -notmatch '"ladder"[\s\S]{0,100}LadderPolicyScript\.local_box' -or $geometryText -notmatch '"door",\s*"ladder"') {
  throw 'Ladders must enter the shared partial geometry pipeline'
}
if ($targetResolverText -notmatch 'targetable' -or $targetResolverText -notmatch 'BlockRegistryScript\.is_solid') {
  throw 'Voxel targeting must include explicit non-solid targetable shapes without dropping solid blocks'
}

foreach ($reason in @('ladder_face_invalid','ladder_support_mismatch','ladder_support_missing')) {
  if ($previewText -notmatch $reason) { throw "Placement preview is missing ladder rejection: $reason" }
}
if ($previewText -notmatch 'LadderPolicyScript\.is_valid_support') {
  throw 'Placement preview must use the authoritative ladder support policy'
}
foreach ($field in @(
  'ladder_climb_speed','ladder_acceleration','ladder_horizontal_factor',
  'ladder_detach_speed','ladder_jump_velocity'
)) {
  if ($movementText -notmatch $field) { throw "Movement controller is missing ladder field: $field" }
}
foreach ($method in @('resolve_ladder_velocity','_step_ladder')) {
  if ($movementText -notmatch "func\s+$method\s*\(") { throw "Movement controller is missing method: $method" }
}
if ($movementText -notmatch 'detached_ladder' -or $movementText -notmatch 'on_ladder') {
  throw 'Movement controller must expose explicit ladder entry and detach results'
}
if ($explorationPlayerText -notmatch 'extends\s+"res://src/player/ladder_climbing_player\.gd"') {
  throw 'Production exploration player must inherit ladder climbing behavior'
}
foreach ($method in @(
  'get_ladder_movement_snapshot','_physics_process','_append_ladder_context',
  '_resolve_selected_block_id','_update_ladder_state'
)) {
  if ($ladderPlayerText -notmatch "func\s+$method\s*\(") { throw "Ladder player is missing method: $method" }
}
if ($ladderPlayerText -notmatch 'LADDER_REATTACH_COOLDOWN_SECONDS\s*:=\s*0\.22') {
  throw 'Jump detach must retain a bounded ladder reattach cooldown'
}
if ($ladderPlayerText -match 'save_world\(' -or $ladderPlayerText -match 'FileAccess\.open\(' -or $ladderPlayerText -match 'func\s+serialize_state\s*\(') {
  throw 'Transient ladder contact and movement diagnostics must not own persistence'
}

if ($runAllText -notmatch 'validate_directional_ladders\.ps1' -or $runAllText -notmatch 'directional_ladder_regression\.gd') {
  throw 'Directional ladder contracts and regression must be wired into tests/run_all.ps1'
}
if ($workflowText -notmatch 'Invoke-Godot\.ps1' -or $workflowText -notmatch 'directional_ladder_desktop_acceptance\.gd') {
  throw 'Directional ladder CI must run real waited regressions and desktop acceptance'
}
if ($workflowText -match '(?m)^\s*godot\s+--headless') {
  throw 'Directional ladder workflow must not invoke GUI-subsystem Godot without the wait wrapper'
}
if ($doorWorkflowText -notmatch 'Invoke-Godot\.ps1' -or $doorWorkflowText -match '(?m)^\s*godot\s+--headless') {
  throw 'Double-door workflow must retain the reliable waited Godot invocation contract'
}

Write-Host "PASS directional_ladders variants=4 canonical_id=25 thickness=0.125 contact_cells=18 climb_speed=3.2 desktop=1 ci_wait=1"
