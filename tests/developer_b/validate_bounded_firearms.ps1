$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = Resolve-Path "$PSScriptRoot\..\.."
$paths = [ordered]@{
  Data = Join-Path $root 'data\firearms.json'
  RangedData = Join-Path $root 'data\ranged_combat.json'
  ItemsData = Join-Path $root 'data\items.json'
  RecipesData = Join-Path $root 'data\recipes.json'
  Items = Join-Path $root 'src\inventory\item_registry.gd'
  Crafting = Join-Path $root 'src\crafting\crafting_service.gd'
  Registry = Join-Path $root 'src\combat\ranged_weapon_registry.gd'
  Hitscan = Join-Path $root 'src\combat\hitscan_runtime_service.gd'
  Ranged = Join-Path $root 'src\combat\ranged_combat_service.gd'
  Combat = Join-Path $root 'src\combat\combat_service.gd'
  Equipment = Join-Path $root 'src\equipment\equipment_service.gd'
  Actions = Join-Path $root 'src\input\gameplay_input_actions.gd'
  ControllerProfile = Join-Path $root 'src\input\gameplay_controller_profile.gd'
  Input = Join-Path $root 'src\input\gameplay_input_service.gd'
  ControllerPlayer = Join-Path $root 'src\player\controller_exploration_player.gd'
  Player = Join-Path $root 'src\player\character_progression_player.gd'
  VisualPolicy = Join-Path $root 'src\player\held_item_visual_policy.gd'
  MeshFactory = Join-Path $root 'src\player\held_item_mesh_factory.gd'
  ItemView = Join-Path $root 'src\player\first_person_item_view.gd'
  ViewData = Join-Path $root 'data\first_person_viewmodel.json'
  Feedback = Join-Path $root 'src\ui\combat_feedback_overlay.gd'
  Hub = Join-Path $root 'src\ui\character_progression_service_hub.gd'
  RegistryTest = Join-Path $root 'tests\qa\firearm_registry_regression.gd'
  RuntimeTest = Join-Path $root 'tests\qa\firearm_runtime_regression.gd'
  DesktopTest = Join-Path $root 'tests\qa\firearm_desktop_acceptance.gd'
  Workflow = Join-Path $root '.github\workflows\bounded-firearm-combat-tests.yml'
  RunAll = Join-Path $root 'tests\run_all.ps1'
  Contract = Join-Path $root 'docs\BOUNDED_FIREARM_COMBAT.md'
  Testing = Join-Path $root 'docs\BOUNDED_FIREARM_COMBAT_TESTING.md'
  Audit = Join-Path $root 'docs\ARCHITECTURE_AUDIT_2026-07-29_ITERATION_53.md'
  Roadmap = Join-Path $root 'docs\PRODUCT_ROADMAP_ITERATION_53.md'
}
foreach ($entry in $paths.GetEnumerator()) {
  if (-not (Test-Path -LiteralPath $entry.Value)) {
    throw "Bounded firearm file is missing: $($entry.Key) $($entry.Value)"
  }
}
$text = @{}
foreach ($entry in $paths.GetEnumerator()) {
  if ($entry.Key -notin @('Data','RangedData','ItemsData','RecipesData','ViewData')) {
    $text[$entry.Key] = Get-Content -Raw -Encoding UTF8 $entry.Value
  }
}

$firearms = Get-Content -Raw -Encoding UTF8 $paths.Data | ConvertFrom-Json
$items = @($firearms.items)
$recipes = @($firearms.recipes)
$profiles = @($firearms.profiles)
if ([int]$firearms.schema_version -ne 1) { throw 'Firearm schema must begin at version 1' }
if ($items.Count -ne 6 -or $recipes.Count -ne 6 -or $profiles.Count -ne 3) {
  throw "Firearm release must contain 6 items, 6 recipes and 3 profiles; actual=$($items.Count)/$($recipes.Count)/$($profiles.Count)"
}
$baseItemIds = @{}
foreach ($item in @((Get-Content -Raw -Encoding UTF8 $paths.ItemsData | ConvertFrom-Json).items)) { $baseItemIds[[string]$item.id] = $true }
foreach ($item in @((Get-Content -Raw -Encoding UTF8 $paths.RangedData | ConvertFrom-Json).items)) { $baseItemIds[[string]$item.id] = $true }
$firearmItemIds = @{}
foreach ($item in $items) {
  $id = [string]$item.id
  if ([string]::IsNullOrWhiteSpace($id) -or $baseItemIds.ContainsKey($id) -or $firearmItemIds.ContainsKey($id)) {
    throw "Duplicate firearm item id: $id"
  }
  $firearmItemIds[$id] = $true
}
foreach ($required in @('gunpowder','light_round','shotgun_shell','star_pistol','frontier_carbine','scattergun')) {
  if (-not $firearmItemIds.ContainsKey($required)) { throw "Missing firearm item: $required" }
}
foreach ($weaponId in @('star_pistol','frontier_carbine','scattergun')) {
  $weapon = @($items | Where-Object { [string]$_.id -eq $weaponId })[0]
  if ([string]$weapon.category -ne 'weapon' -or [int]$weapon.max_stack -ne 1 -or [int]$weapon.durability -le 0) {
    throw "Firearm must be durable non-stackable weapon: $weaponId"
  }
  if ([string]$weapon.equipment.slot -ne 'main_hand') { throw "Firearm must reuse main_hand: $weaponId" }
  if ([string]$weapon.tool_type -notin @('pistol','carbine','shotgun')) { throw "Invalid firearm tool_type: $weaponId" }
}
$lightRounds = @($items | Where-Object { [string]$_.id -eq 'light_round' })[0]
$shells = @($items | Where-Object { [string]$_.id -eq 'shotgun_shell' })[0]
if ([string]$lightRounds.category -ne 'ammunition' -or [int]$lightRounds.max_stack -ne 64) { throw 'Light rounds must stack to 64' }
if ([string]$shells.category -ne 'ammunition' -or [int]$shells.max_stack -ne 32) { throw 'Shotgun shells must stack to 32' }

$baseRecipeIds = @{}
foreach ($recipe in @((Get-Content -Raw -Encoding UTF8 $paths.RecipesData | ConvertFrom-Json).recipes)) { $baseRecipeIds[[string]$recipe.id] = $true }
foreach ($recipe in @((Get-Content -Raw -Encoding UTF8 $paths.RangedData | ConvertFrom-Json).recipes)) { $baseRecipeIds[[string]$recipe.id] = $true }
$firearmRecipeIds = @{}
foreach ($recipe in $recipes) {
  $id = [string]$recipe.id
  if ($baseRecipeIds.ContainsKey($id) -or $firearmRecipeIds.ContainsKey($id)) { throw "Duplicate firearm recipe: $id" }
  if ([string]$recipe.station -ne 'workbench') { throw "Firearm recipe must use workbench: $id" }
  $firearmRecipeIds[$id] = $true
}
foreach ($required in @('gunpowder_batch','light_rounds','shotgun_shells','star_pistol','frontier_carbine','scattergun')) {
  if (-not $firearmRecipeIds.ContainsKey($required)) { throw "Missing firearm recipe: $required" }
}

$expectedModes = @{ star_pistol='semi'; frontier_carbine='auto'; scattergun='pump' }
$profileIds = @{}
foreach ($profile in $profiles) {
  $id = [string]$profile.id
  if ($profileIds.ContainsKey($id)) { throw "Duplicate firearm profile: $id" }
  $profileIds[$id] = $true
  if ([string]$profile.weapon_item_id -ne $id -or -not $firearmItemIds.ContainsKey($id)) { throw "Invalid firearm profile identity: $id" }
  if ([string]$profile.action_kind -ne 'firearm' -or [string]$profile.delivery_kind -ne 'hitscan') { throw "Firearm must use hitscan action semantics: $id" }
  if ([string]$profile.fire_mode -ne $expectedModes[$id]) { throw "Unexpected fire mode: $id" }
  if ([int]$profile.magazine_capacity -lt 1 -or [int]$profile.magazine_capacity -gt 64) { throw "Magazine exceeds hard budget: $id" }
  if ([double]$profile.reload_seconds -le 0 -or [double]$profile.reload_seconds -gt 8) { throw "Reload exceeds hard budget: $id" }
  if ([double]$profile.fire_interval_seconds -lt 0.06 -or [double]$profile.fire_interval_seconds -gt 3) { throw "Fire interval exceeds hard budget: $id" }
  if ([int]$profile.pellet_count -lt 1 -or [int]$profile.pellet_count -gt 12) { throw "Pellet count exceeds hard budget: $id" }
  if ([double]$profile.spread_degrees -lt 0 -or [double]$profile.spread_degrees -gt 12) { throw "Spread exceeds hard budget: $id" }
  if ([double]$profile.max_distance -le 0 -or [double]$profile.max_distance -gt 128) { throw "Hitscan range exceeds hard budget: $id" }
  if (([double]$profile.damage_per_pellet * [int]$profile.pellet_count) -gt 48) { throw "Raw shot damage exceeds hard budget: $id" }
}
foreach ($required in $expectedModes.Keys) {
  if (-not $profileIds.ContainsKey($required)) { throw "Missing firearm profile: $required" }
}

foreach ($token in @('firearms\.json','DEFAULT_EXTENSION_PATHS','staged_items','_items\s*=\s*staged_items')) {
  if ($text.Items -notmatch $token) { throw "Item registry firearm staging is missing: $token" }
}
foreach ($token in @('firearms\.json','DEFAULT_EXTENSION_PATHS','var\s+staged','_recipes\s*=\s*staged')) {
  if ($text.Crafting -notmatch $token) { throw "Crafting firearm staging is missing: $token" }
}
foreach ($token in @(
  'ALLOWED_ACTION_KINDS','ALLOWED_DELIVERY_KINDS','ALLOWED_FIRE_MODES',
  'MAX_MAGAZINE_CAPACITY\s*:=\s*64','MAX_HITSCAN_DISTANCE\s*:=\s*128\.0',
  'MAX_PELLETS_PER_SHOT\s*:=\s*12','MAX_RAW_DAMAGE_PER_SHOT\s*:=\s*48\.0',
  '_normalize_firearm_profile'
)) {
  if ($text.Registry -notmatch $token) { throw "Firearm profile registry is missing: $token" }
}
if ($text.Registry -match 'extends\s+Node|Timer\.new|save_world|FileAccess\.WRITE') { throw 'Ranged registry must remain pure and read-only' }

foreach ($token in @(
  'class_name\s+HitscanRuntimeService','MAX_RAYS_PER_SHOT\s*:=\s*12',
  'MAX_DISTANCE\s*:=\s*128\.0','PhysicsRayQueryParameters3D\.create','intersect_ray',
  'grouped_hits','pellet_hits','resolve_projectile_hit','shot_resolved\.emit'
)) {
  if ($text.Hitscan -notmatch $token) { throw "Bounded hitscan runtime is missing: $token" }
}
if ($text.Hitscan -match 'Timer\.new|Thread\.new|_process\s*\(|_physics_process\s*\(|queue_free|save_world|serialize\s*\(|take_damage') {
  throw 'Hitscan runtime must be immediate, node-free, non-persistent and CombatService-authoritative'
}

foreach ($token in @(
  'HitscanRuntimeScript','MAGAZINE_METADATA_KEY','func\s+begin_primary\s*\(',
  'func\s+advance_primary\s*\(','func\s+request_reload\s*\(',
  '_complete_reload','transact_items','update_slot_metadata','ammo_transaction_failed',
  'fire_mode','empty_magazine','reload_cancelled','recoil_pitch_degrees'
)) {
  if ($text.Ranged -notmatch $token) { throw "Firearm transaction service is missing: $token" }
}
if ($text.Ranged -match 'Timer\.new|current_state\["firearm"\]|save_world|serialize\s*\(|deserialize\s*\(') {
  throw 'Firearm transient state must not create timers or a parallel save domain'
}
$reloadStart = $text.Ranged.IndexOf('func request_reload')
$reloadCommit = $text.Ranged.IndexOf('func _complete_reload')
$ammoCommit = $text.Ranged.IndexOf('transact_items', $reloadCommit)
if ($reloadStart -lt 0 -or $reloadCommit -lt 0 -or $ammoCommit -lt $reloadCommit) {
  throw 'Reserve ammunition must be committed only when reload completes'
}
foreach ($token in @('item_metadata_changed','MAX_METADATA_KEYS_PER_UPDATE\s*:=\s*16','func\s+update_slot_metadata\s*\(','metadata\.duplicate','equipment_changed\.emit')) {
  if ($text.Equipment -notmatch $token) { throw "Equipment metadata transaction is missing: $token" }
}
if ($text.Hub -match 'current_state\["firearm"\]|current_state\["ranged_combat"\]') { throw 'Hub must reuse inventory/equipment persistence only' }

foreach ($token in @('const\s+RELOAD','KEY_R','is_reload_just_pressed')) {
  if (($text.Actions + $text.Input) -notmatch $token) { throw "Logical reload input is missing: $token" }
}
foreach ($token in @('"reload"','button\s*9')) {
  if (($text.ControllerProfile + (Get-Content -Raw -Encoding UTF8 (Join-Path $root 'data\gameplay_controller_profile.json'))) -notmatch $token) {
    throw "Controller reload profile is missing: $token"
  }
}
foreach ($token in @('is_reload_just_pressed','request_ranged_reload','reload_count')) {
  if ($text.ControllerPlayer -notmatch $token) { throw "Controller player reload routing is missing: $token" }
}
foreach ($productionText in @($text.Ranged,$text.Player,$text.ControllerPlayer)) {
  if ($productionText -match 'JOY_BUTTON_|JOY_AXIS_|InputEventJoypad|KEY_R') { throw 'Physical input constants leaked into firearm production logic' }
}
foreach ($token in @('begin_primary','advance_primary','release_primary','request_ranged_reload','_apply_ranged_recoil','hitscan_id')) {
  if ($text.Player -notmatch $token) { throw "Player firearm integration is missing: $token" }
}

foreach ($token in @('FIREARM_TOOL_TYPES','"firearm"','ranged_fire','ranged_reload')) {
  if ($text.VisualPolicy -notmatch $token) { throw "Firearm visual policy is missing: $token" }
}
foreach ($token in @('_build_firearm','"pistol"','"carbine"','"shotgun"','Magazine','Pump','Barrel')) {
  if ($text.MeshFactory -notmatch $token) { throw "Firearm mesh factory is missing: $token" }
}
foreach ($token in @('equipment_service','MAIN_HAND_SLOT','item_source','"equipment"','firearm_scale')) {
  if ($text.ItemView -notmatch $token) { throw "Equipped firearm viewmodel routing is missing: $token" }
}
$viewData = Get-Content -Raw -Encoding UTF8 $paths.ViewData | ConvertFrom-Json
if ([double]$viewData.firearm_scale -le 0) { throw 'Firearm viewmodel scale must be positive' }

foreach ($token in @('magazine_rounds','magazine_capacity','reserve_ammo_count','reload_ratio','换弹','弹匣')) {
  if ($text.Feedback -notmatch $token) { throw "Firearm HUD is missing: $token" }
}
foreach ($token in @('reload_started','reload_completed','reload_cancelled','星火手枪|枪械')) {
  if ($text.Hub -notmatch $token) { throw "Firearm player feedback is missing: $token" }
}

foreach ($phrase in @(
  'real crafting transaction creates a pistol',
  'magazine rounds survive save and reload',
  'unbounded firearm profile rejects the entire registry'
)) {
  if ($text.RegistryTest -notmatch [regex]::Escape($phrase)) { throw "Firearm registry regression is missing: $phrase" }
}
foreach ($phrase in @(
  'reload start does not pre-deduct reserve ammunition',
  'shotgun pellets aggregate into one target damage transaction',
  'automatic carbine emits shot',
  'firearm runtime creates no per-shot Timer nodes'
)) {
  if ($text.RuntimeTest -notmatch [regex]::Escape($phrase)) { throw "Firearm runtime regression is missing: $phrase" }
}
foreach ($phrase in @(
  'real left-mouse click fires a hitscan pistol shot through CombatService',
  'real keyboard R starts the shared reload transaction',
  'real controller right trigger fires the same pistol path',
  'real controller left shoulder starts the shared reload transaction',
  'magazine rounds survive save and reload'
)) {
  if ($text.DesktopTest -notmatch [regex]::Escape($phrase)) { throw "Firearm desktop acceptance is missing: $phrase" }
}
foreach ($token in @(
  'uses:\s*\./\.github/workflows/reusable-godot-quality-gate\.yml',
  'validate_bounded_firearms\.ps1','firearm_registry_regression\.gd',
  'firearm_runtime_regression\.gd','firearm_desktop_acceptance\.gd',
  'firearm-combat-reload\.png','firearm-combat-hit\.png','firearm-combat-report\.json'
)) {
  if ($text.Workflow -notmatch $token) { throw "Firearm workflow is missing: $token" }
}
foreach ($token in @('validate_bounded_firearms\.ps1','firearm_registry_regression\.gd','firearm_runtime_regression\.gd')) {
  if ($text.RunAll -notmatch $token) { throw "Full regression entry is missing firearm gate: $token" }
}
foreach ($phrase in @('弹匣','原子','12','128','不提前扣','CombatService','主手装备优先')) {
  if (($text.Contract + $text.Testing + $text.Audit + $text.Roadmap) -notmatch [regex]::Escape($phrase)) {
    throw "Firearm documentation is missing concept: $phrase"
  }
}

Write-Host "PASS bounded firearms items=$($items.Count) recipes=$($recipes.Count) profiles=$($profiles.Count) rays=12 range=128"
