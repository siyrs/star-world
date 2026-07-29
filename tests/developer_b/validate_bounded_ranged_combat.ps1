$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = Resolve-Path "$PSScriptRoot\..\.."
$paths = [ordered]@{
  Data = Join-Path $root 'data\ranged_combat.json'
  Items = Join-Path $root 'src\inventory\item_registry.gd'
  Crafting = Join-Path $root 'src\crafting\crafting_service.gd'
  Registry = Join-Path $root 'src\combat\ranged_weapon_registry.gd'
  Policy = Join-Path $root 'src\combat\ranged_shot_policy.gd'
  Projectile = Join-Path $root 'src\combat\projectile_runtime_service.gd'
  Ranged = Join-Path $root 'src\combat\ranged_combat_service.gd'
  Combat = Join-Path $root 'src\combat\combat_service.gd'
  Player = Join-Path $root 'src\player\character_progression_player.gd'
  Hub = Join-Path $root 'src\ui\character_progression_service_hub.gd'
  CharacterUi = Join-Path $root 'src\ui\character_game_ui.gd'
  Feedback = Join-Path $root 'src\ui\combat_feedback_overlay.gd'
  RegistryTest = Join-Path $root 'tests\qa\ranged_combat_registry_regression.gd'
  RuntimeTest = Join-Path $root 'tests\qa\ranged_combat_runtime_regression.gd'
  DesktopTest = Join-Path $root 'tests\qa\ranged_combat_desktop_acceptance.gd'
  Workflow = Join-Path $root '.github\workflows\bounded-ranged-combat-tests.yml'
  RunAll = Join-Path $root 'tests\run_all.ps1'
  Contract = Join-Path $root 'docs\BOUNDED_RANGED_COMBAT.md'
  Audit = Join-Path $root 'docs\ARCHITECTURE_AUDIT_2026-07-29_ITERATION_52.md'
  Testing = Join-Path $root 'docs\BOUNDED_RANGED_COMBAT_TESTING.md'
  Roadmap = Join-Path $root 'docs\PRODUCT_ROADMAP_ITERATION_52.md'
}
foreach ($entry in $paths.GetEnumerator()) {
  if (-not (Test-Path -LiteralPath $entry.Value)) { throw "Bounded ranged combat file is missing: $($entry.Key) $($entry.Value)" }
}
$text = @{}
foreach ($entry in $paths.GetEnumerator()) {
  if ($entry.Key -ne 'Data') { $text[$entry.Key] = Get-Content -Raw -Encoding UTF8 $entry.Value }
}

$baseItems = @((Get-Content -Raw -Encoding UTF8 (Join-Path $root 'data\items.json') | ConvertFrom-Json).items)
$baseRecipes = @((Get-Content -Raw -Encoding UTF8 (Join-Path $root 'data\recipes.json') | ConvertFrom-Json).recipes)
$ranged = Get-Content -Raw -Encoding UTF8 $paths.Data | ConvertFrom-Json
$rangedItems = @($ranged.items)
$rangedRecipes = @($ranged.recipes)
$profiles = @($ranged.profiles)
if ([int]$ranged.schema_version -ne 1) { throw 'Ranged combat schema must remain version 1' }
if ($rangedItems.Count -ne 2 -or $rangedRecipes.Count -ne 2 -or $profiles.Count -ne 1) {
  throw 'Bow extension must remain exactly bow, arrow, two recipes and one profile'
}
$baseItemIds = @{}; foreach ($item in $baseItems) { $baseItemIds[[string]$item.id] = $true }
$extensionItemIds = @{}
foreach ($item in $rangedItems) {
  $id = [string]$item.id
  if ([string]::IsNullOrWhiteSpace($id) -or $extensionItemIds.ContainsKey($id) -or $baseItemIds.ContainsKey($id)) { throw "Duplicate ranged item id: $id" }
  $extensionItemIds[$id] = $true
}
foreach ($required in @('bow','arrow')) { if (-not $extensionItemIds.ContainsKey($required)) { throw "Missing ranged item: $required" } }
$bow = @($rangedItems | Where-Object { [string]$_.id -eq 'bow' })[0]
$arrow = @($rangedItems | Where-Object { [string]$_.id -eq 'arrow' })[0]
if ([string]$bow.category -ne 'weapon' -or [string]$bow.tool_type -ne 'bow' -or [int]$bow.max_stack -ne 1 -or [int]$bow.durability -le 0) { throw 'Bow must remain a durable main-hand weapon' }
if ([string]$bow.equipment.slot -ne 'main_hand') { throw 'Bow must reuse main_hand' }
if ([string]$arrow.category -ne 'ammunition' -or [int]$arrow.max_stack -ne 64) { throw 'Arrow must remain bounded ammunition' }
$baseRecipeIds = @{}; foreach ($recipe in $baseRecipes) { $baseRecipeIds[[string]$recipe.id] = $true }
$extensionRecipeIds = @{}
foreach ($recipe in $rangedRecipes) {
  $id = [string]$recipe.id
  if ($extensionRecipeIds.ContainsKey($id) -or $baseRecipeIds.ContainsKey($id)) { throw "Duplicate ranged recipe: $id" }
  if ([string]$recipe.station -ne 'workbench') { throw "Ranged recipe must use workbench: $id" }
  $extensionRecipeIds[$id] = $true
}
foreach ($required in @('bow','arrows')) { if (-not $extensionRecipeIds.ContainsKey($required)) { throw "Missing ranged recipe: $required" } }
$profile = $profiles[0]
if ([string]$profile.id -ne 'bow' -or [string]$profile.weapon_item_id -ne 'bow' -or [string]$profile.ammo_item_id -ne 'arrow') { throw 'Bow profile identity is inconsistent' }
if ([double]$profile.draw_seconds -le 0 -or [double]$profile.draw_seconds -gt 5) { throw 'Invalid draw duration' }
if ([double]$profile.minimum_draw_ratio -lt 0 -or [double]$profile.minimum_draw_ratio -ge 1) { throw 'Invalid minimum draw ratio' }
if ([double]$profile.maximum_damage -lt [double]$profile.minimum_damage) { throw 'Invalid ranged damage interval' }
if ([double]$profile.maximum_speed -gt 96 -or [double]$profile.maximum_speed -lt [double]$profile.minimum_speed) { throw 'Invalid ranged speed interval' }
if ([double]$profile.max_distance -gt 256 -or [double]$profile.max_lifetime_seconds -gt 12) { throw 'Projectile travel budget exceeds limits' }

foreach ($token in @('DEFAULT_EXTENSION_PATHS','ranged_combat\.json','staged_items','_items\s*=\s*staged_items')) {
  if ($text.Items -notmatch $token) { throw "Item registry bow extension contract is missing: $token" }
}
foreach ($token in @('DEFAULT_EXTENSION_PATHS','ranged_combat\.json','var\s+staged','_recipes\s*=\s*staged')) {
  if ($text.Crafting -notmatch $token) { throw "Crafting bow extension contract is missing: $token" }
}
foreach ($token in @(
  'class_name\s+RangedWeaponRegistry','extends\s+RefCounted','MAX_PROJECTILE_SPEED\s*:=\s*96\.0',
  'MAX_PROJECTILE_DISTANCE\s*:=\s*256\.0','MAX_PROJECTILE_LIFETIME\s*:=\s*12\.0',
  'ALLOWED_ACTION_KINDS','_normalize_charge_profile','func\s+get_profile\s*\('
)) {
  if ($text.Registry -notmatch $token) { throw "Generalized ranged registry lost bow contract: $token" }
}
if ($text.Registry -match 'extends\s+Node|Timer\.new|save_world|FileAccess\.WRITE') { throw 'Ranged registry must remain pure and read-only' }
foreach ($token in @('func\s+charge_ratio\s*\(','func\s+evaluate_release\s*\(','undercharged','lerpf','func\s+build_shot\s*\(')) {
  if ($text.Policy -notmatch $token) { throw "Ranged shot policy is missing: $token" }
}
foreach ($token in @(
  'class_name\s+ProjectileRuntimeService','MAX_ACTIVE_PROJECTILES\s*:=\s*64','PROCESS_MODE_PAUSABLE',
  'func\s+_physics_process\s*\(','PhysicsRayQueryParameters3D\.create','intersect_ray',
  'resolve_projectile_hit','func\s+clear\s*\(','capacity_rejection_count'
)) {
  if ($text.Projectile -notmatch $token) { throw "Projectile runtime lost bounded behavior: $token" }
}
if ([regex]::Matches($text.Projectile, 'func\s+_physics_process\s*\(').Count -ne 1) { throw 'Projectile runtime must own exactly one physics loop' }
if ($text.Projectile -match 'Timer\.new|Thread\.new|save_world|world\.serialize|for\s+.*get_nodes_in_group') { throw 'Projectile runtime must not add per-projectile scheduling persistence or scans' }
foreach ($token in @(
  'class_name\s+RangedCombatService','PROCESS_MODE_PAUSABLE','func\s+begin_charge\s*\(',
  'func\s+release_charge\s*\(','func\s+cancel_charge\s*\(','transact_items','spawn_projectile',
  'consume_durability','projectile_capacity','func\s+clear\s*\('
)) {
  if ($text.Ranged -notmatch $token) { throw "Ranged service lost legacy bow transaction: $token" }
}
if ($text.Ranged -match 'Timer\.new|save_world|serialize\s*\(|deserialize\s*\(') { throw 'Ranged transient state must reuse existing persistence' }
$transactionIndex = $text.Ranged.IndexOf('transact_items')
$spawnIndex = $text.Ranged.IndexOf('spawn_projectile')
if ($transactionIndex -lt 0 -or $spawnIndex -lt 0 -or $transactionIndex -gt $spawnIndex) { throw 'Bow must remove arrow immediately before projectile creation' }
foreach ($token in @('func\s+resolve_projectile_hit\s*\(','calculate_raw','attack_kind','player_%s_attack','_target_attributes','_apply_hit','outgoing_attack_resolved\.emit')) {
  if ($text.Combat -notmatch $token) { throw "CombatService lost ranged authority: $token" }
}
foreach ($token in @('var\s+ranged_combat_service','bind_ranged_combat_service','func\s+_start_primary_action\s*\(','func\s+_advance_harvest\s*\(','func\s+_cancel_harvest\s*\(','release_primary','cancel_primary','ranged_fire')) {
  if ($text.Player -notmatch $token) { throw "Player shared ranged input is missing: $token" }
}
foreach ($token in @('RangedCombatServiceScript','setup_character_progression','bind_ranged_combat_service','"ranged_combat"\s*:','clear",\s*reason')) {
  if ($text.Hub -notmatch $token) { throw "Character hub ranged composition is missing: $token" }
}
if ($text.Hub -match 'current_state\["ranged_combat"\]|save_world') { throw 'Character hub must not persist ranged runtime state' }
foreach ($token in @('ranged_combat_service','combat_feedback_overlay\.call\("setup",\s*combat_service,\s*ranged_combat_service')) {
  if ($text.CharacterUi -notmatch $token) { throw "Character UI ranged binding is missing: $token" }
}
foreach ($token in @('RangedChargePanel','ranged_visible','charge_ratio','cooldown_ready_ratio','ammo_count','没有箭矢','蓄力不足')) {
  if ($text.Feedback -notmatch $token) { throw "Ranged feedback UI lost bow behavior: $token" }
}
foreach ($phrase in @('default item registry atomically includes the bow extension','duplicate item IDs reject the entire staged registry','full draw reaches the configured maximum damage')) {
  if ($text.RegistryTest -notmatch [regex]::Escape($phrase)) { throw "Bow registry regression is missing: $phrase" }
}
foreach ($phrase in @('one projectile applies damage exactly once','undercharged release consumes no arrow','runtime stops accepting projectiles at exactly 64','world transition clears every projectile deterministically')) {
  if ($text.RuntimeTest -notmatch [regex]::Escape($phrase)) { throw "Bow runtime regression is missing: $phrase" }
}
foreach ($phrase in @('real left-mouse press starts bow charging','real controller trigger starts the same charge path','arrow count survives save and reload','transient projectiles do not enter world.json')) {
  if ($text.DesktopTest -notmatch [regex]::Escape($phrase)) { throw "Bow desktop acceptance is missing: $phrase" }
}
foreach ($token in @('uses:\s*\./\.github/workflows/reusable-godot-quality-gate\.yml','validate_bounded_ranged_combat\.ps1','ranged_combat_registry_regression\.gd','ranged_combat_runtime_regression\.gd','ranged_combat_desktop_acceptance\.gd')) {
  if ($text.Workflow -notmatch $token) { throw "Ranged workflow is missing: $token" }
}
foreach ($token in @('validate_bounded_ranged_combat\.ps1','ranged_combat_registry_regression\.gd','ranged_combat_runtime_regression\.gd')) {
  if ($text.RunAll -notmatch $token) { throw "Full regression entry is missing: $token" }
}
foreach ($phrase in @('CombatService','64','零消耗','真实')) {
  if (($text.Contract + $text.Audit + $text.Testing + $text.Roadmap) -notmatch [regex]::Escape($phrase)) { throw "Ranged documentation is missing concept: $phrase" }
}

Write-Host "PASS bounded bow extension items=$($rangedItems.Count) recipes=$($rangedRecipes.Count) profiles=$($profiles.Count)"
