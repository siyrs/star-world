$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = Resolve-Path "$PSScriptRoot\..\.."
$paths = [ordered]@{
  Creatures = Join-Path $root 'data\creatures.json'
  Ecology = Join-Path $root 'data\creature_ecology.json'
  Attacks = Join-Path $root 'data\hostile_attacks.json'
  Registry = Join-Path $root 'src\entity\hostile_attack_registry.gd'
  Policy = Join-Path $root 'src\entity\hostile_ranged_tactics_policy.gd'
  Marksman = Join-Path $root 'src\entity\abyss_marksman.gd'
  Melee = Join-Path $root 'src\entity\hostile_melee_creature.gd'
  Factory = Join-Path $root 'src\entity\creature_factory.gd'
  Projectile = Join-Path $root 'src\combat\projectile_runtime_service.gd'
  Combat = Join-Path $root 'src\combat\combat_service.gd'
  Player = Join-Path $root 'src\player\character_progression_player.gd'
  Hub = Join-Path $root 'src\ui\character_progression_service_hub.gd'
  FirearmDesktop = Join-Path $root 'tests\qa\firearm_desktop_acceptance.gd'
  Regression = Join-Path $root 'tests\qa\hostile_ranged_encounter_regression.gd'
  Desktop = Join-Path $root 'tests\qa\hostile_ranged_encounter_desktop_acceptance.gd'
  Workflow = Join-Path $root '.github\workflows\bounded-hostile-ranged-encounter-tests.yml'
  RunAll = Join-Path $root 'tests\run_all.ps1'
  Contract = Join-Path $root 'docs\BOUNDED_HOSTILE_RANGED_ENCOUNTERS.md'
  Testing = Join-Path $root 'docs\BOUNDED_HOSTILE_RANGED_ENCOUNTERS_TESTING.md'
  Audit = Join-Path $root 'docs\ARCHITECTURE_AUDIT_2026-07-30_ITERATION_54.md'
  Roadmap = Join-Path $root 'docs\PRODUCT_ROADMAP_ITERATION_54.md'
}
foreach ($entry in $paths.GetEnumerator()) {
  if (-not (Test-Path -LiteralPath $entry.Value)) { throw "Missing hostile ranged contract file: $($entry.Key) $($entry.Value)" }
}
$text = @{}
foreach ($entry in $paths.GetEnumerator()) {
  if ($entry.Key -notin @('Creatures','Ecology','Attacks')) { $text[$entry.Key] = Get-Content -Raw -Encoding UTF8 $entry.Value }
}

$creatures = (Get-Content -Raw -Encoding UTF8 $paths.Creatures | ConvertFrom-Json).creatures
$ecology = Get-Content -Raw -Encoding UTF8 $paths.Ecology | ConvertFrom-Json
$attacks = Get-Content -Raw -Encoding UTF8 $paths.Attacks | ConvertFrom-Json
if ([int]$attacks.schema_version -ne 2) { throw 'Hostile attack schema must be version two' }
$marksmanCreature = $creatures.abyss_marksman
if ($null -eq $marksmanCreature) { throw 'Abyss marksman creature profile is missing' }
if ([int]$marksmanCreature.max_health -lt 8 -or [int]$marksmanCreature.max_health -gt 40) { throw 'Marksman health is outside the bounded encounter range' }
if ([double]$marksmanCreature.speed -le 0 -or [double]$marksmanCreature.speed -gt 5) { throw 'Marksman speed is outside the bounded encounter range' }
if ([int]$marksmanCreature.damage -lt 1 -or [int]$marksmanCreature.damage -gt 8) { throw 'Marksman damage is outside the bounded encounter range' }
if ($null -eq $marksmanCreature.drops.gunpowder) { throw 'Marksman must connect firearm progression through bounded gunpowder drops' }

$profiles = @($attacks.profiles)
if ($profiles.Count -ne 3) { throw "Expected three hostile profiles, got $($profiles.Count)" }
$marksmanAttack = @($profiles | Where-Object { $_.species_id -eq 'abyss_marksman' })[0]
if ($null -eq $marksmanAttack) { throw 'Marksman hostile attack profile is missing' }
if ([string]$marksmanAttack.attack_kind -ne 'ranged' -or [string]$marksmanAttack.delivery_kind -ne 'projectile') { throw 'Marksman must use ranged projectile semantics' }
if (-not [bool]$marksmanAttack.requires_line_of_sight) { throw 'Marksman must require line of sight' }
if ([double]$marksmanAttack.minimum_range -lt 2 -or [double]$marksmanAttack.preferred_range -le [double]$marksmanAttack.minimum_range -or [double]$marksmanAttack.attack_range -le [double]$marksmanAttack.preferred_range) { throw 'Marksman distance bands are inconsistent' }
if ([double]$marksmanAttack.projectile_speed -gt 64 -or [double]$marksmanAttack.projectile_max_distance -gt 64 -or [double]$marksmanAttack.projectile_lifetime_seconds -gt 8) { throw 'Marksman projectile exceeds hard registry budgets' }
if ([int]$marksmanAttack.cover_probe_count -lt 1 -or [int]$marksmanAttack.cover_probe_count -gt 8) { throw 'Marksman cover probes must remain between one and eight' }

$abyss = @($ecology.profiles | Where-Object { $_.id -eq 'abyss_world' })[0]
$marksmanEcology = @($abyss.hostile_species | Where-Object { $_.id -eq 'abyss_marksman' })[0]
if ($null -eq $marksmanEcology -or [int]$marksmanEcology.cap -ne 2) { throw 'Abyss marksman ecology must be present with cap two' }
if ([int]$marksmanEcology.weight -ge [int](@($abyss.hostile_species | Where-Object { $_.id -eq 'zombie' })[0].weight)) { throw 'Marksman must remain rarer than normal zombies' }

foreach ($token in @('var staged','SUPPORTED_SCHEMA_VERSIONS','MAX_RANGED_ATTACK_RANGE','MAX_COVER_PROBES','_profiles = staged')) {
  if ($text.Registry -notmatch [regex]::Escape($token)) { throw "Hostile attack registry is missing: $token" }
}
if ($text.Registry -match '_profiles\[species_id\]\s*=\s*normalized') { throw 'Hostile profile loading must remain atomic' }
if ($text.Registry -match 'extends\s+Node|Timer\.new|Thread\.new') { throw 'Hostile registry must remain pure and synchronous' }

foreach ($token in @('class_name HostileRangedTacticsPolicy','MAX_COVER_PROBES := 8','func can_begin','func cancellation_reason','func motion_kind','func lead_direction','func cover_probe_directions')) {
  if ($text.Policy -notmatch [regex]::Escape($token)) { throw "Hostile ranged policy is missing: $token" }
}
if ($text.Policy -match 'extends\s+Node|FileAccess|Timer\.new|PhysicsRayQueryParameters3D') { throw 'Hostile ranged policy must remain pure and world-independent' }

foreach ($token in @('class_name AbyssMarksmanCreature','bind_projectile_runtime','requires_line_of_sight','LOS_REFRESH_SECONDS','cover_probe_count','cover_probe_ray_count','spawn_projectile','AimTelegraph','damage_flow','owner_kind')) {
  if ($text.Marksman -notmatch [regex]::Escape($token)) { throw "Marksman production behavior is missing: $token" }
}
if ($text.Marksman -match 'Timer\.new|Thread\.new|get_nodes_in_group|resolve_incoming_damage|take_damage\(') { throw 'Marksman must use the shared runtime and CombatService without scans or direct damage' }
if ([regex]::Matches($text.Marksman, 'intersect_ray').Count -gt 4) { throw 'Marksman code owns too many ray query sites' }

foreach ($token in @('class_name HostileMeleeCreature','take_hostile_damage','get_instance_id')) {
  if ($text.Melee -notmatch [regex]::Escape($token)) { throw "Shared melee adapter is missing: $token" }
}
if ($text.Factory -notmatch 'abyss_marksman\.gd' -or $text.Factory -notmatch 'hostile_attack_registry\.gd') { throw 'CreatureFactory must compose marksman and hostile registry' }

foreach ($token in @('MAX_ACTIVE_PROJECTILES := 64','MAX_PROJECTILE_SPEED := 96.0','MAX_PROJECTILE_DISTANCE := 256.0','MAX_PROJECTILE_LIFETIME := 12.0','invalid_rejection_count','owner_kind','visual_kind','func _physics_process')) {
  if ($text.Projectile -notmatch [regex]::Escape($token)) { throw "Shared projectile runtime is missing: $token" }
}
if ([regex]::Matches($text.Projectile, 'func _physics_process').Count -ne 1) { throw 'Shared projectile runtime must own exactly one physics loop' }
if ($text.Projectile -match 'Timer\.new|Thread\.new|get_nodes_in_group|save_world|serialize\s*\(') { throw 'Shared projectile runtime must not create per-projectile scheduling, scans or persistence' }

foreach ($token in @('damage_flow','_resolve_hostile_projectile_hit','take_hostile_damage','damage_source','attacker_id')) {
  if ($text.Combat -notmatch [regex]::Escape($token)) { throw "CombatService hostile projectile authority is missing: $token" }
}
foreach ($token in @('MAX_HOSTILE_DAMAGE_COOLDOWN_SOURCES := 32','_hostile_damage_cooldowns','take_hostile_damage','attacker_cooldown','get_hostile_damage_snapshot','_hostile_cooldown_key')) {
  if ($text.Player -notmatch [regex]::Escape($token)) { throw "Player source-scoped hostile damage is missing: $token" }
}
if ($text.Player -match '_hostile_damage_cooldowns\.size\(\)\s*>\s*MAX_HOSTILE') { throw 'Hostile cooldown capacity must be enforced before insertion' }

foreach ($token in @('HOSTILE_PROJECTILE_CAPACITY := 24','HostileProjectileRuntime','creature_spawned','bind_projectile_runtime','hostile_projectiles','clear", reason')) {
  if ($text.Hub -notmatch [regex]::Escape($token)) { throw "Character hub hostile projectile composition is missing: $token" }
}
if ($text.Hub -notmatch '"setup"\s*,\s*combat_service\s*,\s*HOSTILE_PROJECTILE_CAPACITY') { throw 'Hostile projectile runtime must be configured with the exact bounded capacity' }
if ($text.Hub -match 'current_state\["hostile_projectiles"\]') { throw 'Hostile projectile state must not enter persistence' }

foreach ($token in @('weakref\(target\)','target_id','target_ref\.get_ref','mouse_result')) {
  if ($text.FirearmDesktop -notmatch $token) { throw "Firearm desktop lifecycle regression fix is missing: $token" }
}
if ($text.FirearmDesktop -match 'func\(\)\s*->\s*bool:[\s\S]{0,300}target\.get\("health"\)') { throw 'Firearm desktop wait closure must not dereference a potentially freed target' }

foreach ($phrase in @('different hostile attacker can apply pressure immediately','real world collision blocks marksman line of sight','one hostile projectile applies exactly one target transaction','twenty-fifth hostile projectile is rejected before spawning')) {
  if ($text.Regression -notmatch [regex]::Escape($phrase)) { throw "Hostile ranged regression is missing: $phrase" }
}
foreach ($phrase in @('real marksman aim telegraph is visible','solid cover blocks hostile projectiles','player firearm defeat releases the marksman safely','hostile projectiles do not enter world.json')) {
  if ($text.Desktop -notmatch [regex]::Escape($phrase)) { throw "Hostile ranged desktop acceptance is missing: $phrase" }
}
foreach ($token in @('uses: ./.github/workflows/reusable-godot-quality-gate.yml','validate_bounded_hostile_ranged.ps1','hostile_ranged_encounter_regression.gd','hostile_ranged_encounter_desktop_acceptance.gd','hostile-ranged-aim.png','hostile-ranged-cover.png','hostile-ranged-report.json')) {
  if ($text.Workflow -notmatch [regex]::Escape($token)) { throw "Hostile ranged workflow is missing: $token" }
}
foreach ($token in @('validate_bounded_hostile_ranged.ps1','hostile_ranged_encounter_regression.gd')) {
  if ($text.RunAll -notmatch [regex]::Escape($token)) { throw "Full regression entry is missing: $token" }
}
foreach ($entry in @('Contract','Testing','Audit','Roadmap')) {
  if ([string]::IsNullOrWhiteSpace($text[$entry])) { throw "Hostile ranged documentation is empty: $entry" }
}

Write-Host "PASS bounded hostile ranged profiles=$($profiles.Count) marksman_cap=$($marksmanEcology.cap) cover_probes=$($marksmanAttack.cover_probe_count) hostile_projectile_capacity=24"
