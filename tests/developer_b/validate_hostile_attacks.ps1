$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = Resolve-Path "$PSScriptRoot\..\.."
$attackPath = Join-Path $root 'data\hostile_attacks.json'
$creaturePath = Join-Path $root 'data\creatures.json'
$factoryPath = Join-Path $root 'src\entity\creature_factory.gd'
$registryPath = Join-Path $root 'src\entity\hostile_attack_registry.gd'
$baseCreaturePath = Join-Path $root 'src\entity\base_creature.gd'
$meleeCreaturePath = Join-Path $root 'src\entity\hostile_melee_creature.gd'
$marksmanPath = Join-Path $root 'src\entity\abyss_marksman.gd'
$projectilePath = Join-Path $root 'src\combat\projectile_runtime_service.gd'
$hubPath = Join-Path $root 'src\ui\character_progression_service_hub.gd'
$zombiePath = Join-Path $root 'src\entity\zombie.gd'
$playerPath = Join-Path $root 'src\player\character_progression_player.gd'
$focusPath = Join-Path $root 'src\interaction\player_focus_resolver.gd'
$promptPath = Join-Path $root 'src\experience\interaction_prompt_resolver.gd'
$runAllPath = Join-Path $root 'tests\run_all.ps1'

foreach ($path in @($attackPath,$creaturePath,$factoryPath,$registryPath,$baseCreaturePath,$meleeCreaturePath,$marksmanPath,$projectilePath,$hubPath,$zombiePath,$playerPath,$focusPath,$promptPath,$runAllPath)) {
  if (-not (Test-Path -LiteralPath $path)) { throw "Missing hostile attack contract file: $path" }
}

$attackData = Get-Content -Raw -Encoding UTF8 $attackPath | ConvertFrom-Json
$creatureData = Get-Content -Raw -Encoding UTF8 $creaturePath | ConvertFrom-Json
if ([int]$attackData.schema_version -ne 2) { throw "Hostile attack schema must be 2, got $($attackData.schema_version)" }

$knownCreatures = @{}
foreach ($property in $creatureData.creatures.PSObject.Properties) {
  $knownCreatures[[string]$property.Name] = $property.Value
}

$playerSource = Get-Content -Raw -Encoding UTF8 $playerPath
$damageCooldownMatch = [regex]::Match($playerSource, 'REPEATED_HOSTILE_DAMAGE_COOLDOWN\s*:=\s*([0-9.]+)')
if (-not $damageCooldownMatch.Success) { throw 'Unable to parse the player hostile-damage cooldown' }
$playerDamageCooldown = [double]$damageCooldownMatch.Groups[1].Value
$sourceCapacityMatch = [regex]::Match($playerSource, 'MAX_HOSTILE_DAMAGE_COOLDOWN_SOURCES\s*:=\s*([0-9]+)')
if (-not $sourceCapacityMatch.Success -or [int]$sourceCapacityMatch.Groups[1].Value -gt 64) { throw 'Per-attacker hostile cooldown capacity is missing or unbounded' }

$profiles = @($attackData.profiles)
if ($profiles.Count -ne 3) { throw "Expected exactly three hostile attack profiles, got $($profiles.Count)" }
$seen = @{}
foreach ($profile in $profiles) {
  $speciesId = [string]$profile.species_id
  $sourceId = [string]$profile.source_id
  if ([string]::IsNullOrWhiteSpace($speciesId) -or [string]::IsNullOrWhiteSpace($sourceId)) { throw 'Hostile attack profile has empty species/source identity' }
  if ($seen.ContainsKey($speciesId)) { throw "Duplicate hostile attack profile: $speciesId" }
  if (-not $knownCreatures.ContainsKey($speciesId)) { throw "Hostile attack profile references unknown creature: $speciesId" }
  if ([double]$knownCreatures[$speciesId].damage -le 0) { throw "Hostile attack profile references non-damaging creature: $speciesId" }
  $seen[$speciesId] = $true

  $attackKind = [string]$profile.attack_kind
  $deliveryKind = [string]$profile.delivery_kind
  if ($attackKind -notin @('melee','ranged')) { throw "Invalid attack kind for $speciesId" }
  if ($deliveryKind -notin @('direct','projectile')) { throw "Invalid delivery kind for $speciesId" }
  if (($attackKind -eq 'melee' -and $deliveryKind -ne 'direct') -or ($attackKind -eq 'ranged' -and $deliveryKind -ne 'projectile')) { throw "Attack kind/delivery mismatch for $speciesId" }

  $attackRange = [double]$profile.attack_range
  $minimumRange = [double]$profile.minimum_range
  $preferredRange = [double]$profile.preferred_range
  $detectionRange = [double]$profile.detection_range
  $windup = [double]$profile.windup_seconds
  $cooldown = [double]$profile.cooldown_seconds
  $cancelMultiplier = [double]$profile.cancel_range_multiplier
  $cancelRecovery = [double]$profile.cancel_recovery_seconds
  $leashMultiplier = [double]$profile.target_leash_multiplier
  $telegraphMultiplier = [double]$profile.telegraph_radius_multiplier
  $maxRange = if ($attackKind -eq 'melee') { 6.0 } else { 32.0 }
  if ($attackRange -lt 0.25 -or $attackRange -gt $maxRange) { throw "Invalid attack range for $speciesId" }
  if ($minimumRange -lt 0 -or $minimumRange -ge $attackRange) { throw "Invalid minimum range for $speciesId" }
  if ($preferredRange -lt $minimumRange -or $preferredRange -gt $attackRange) { throw "Invalid preferred range for $speciesId" }
  if ($detectionRange -le $attackRange -or $detectionRange -gt 64.0) { throw "Detection range must exceed attack range for $speciesId" }
  if ($windup -lt 0.1 -or $windup -gt 3.0) { throw "Invalid attack windup for $speciesId" }
  if ($cooldown -lt $playerDamageCooldown -or $cooldown -gt 30.0) { throw "Attack cooldown must not be shorter than the player's hostile-damage cooldown: $speciesId hostile=$cooldown player=$playerDamageCooldown" }
  if ($cancelMultiplier -lt 1.0 -or $cancelMultiplier -gt 3.0) { throw "Invalid cancel range multiplier for $speciesId" }
  if ($cancelRecovery -lt 0.0 -or $cancelRecovery -gt $cooldown) { throw "Invalid cancel recovery for $speciesId" }
  if ($leashMultiplier -lt 1.0 -or $leashMultiplier -gt 3.0) { throw "Invalid target leash for $speciesId" }
  if ($telegraphMultiplier -lt 0.5 -or $telegraphMultiplier -gt 2.0) { throw "Invalid telegraph radius for $speciesId" }

  if ($attackKind -eq 'ranged') {
    if (-not [bool]$profile.requires_line_of_sight) { throw "Ranged hostile must require line of sight: $speciesId" }
    if ([double]$profile.projectile_speed -le 0 -or [double]$profile.projectile_speed -gt 64) { throw "Invalid projectile speed for $speciesId" }
    if ([double]$profile.projectile_max_distance -lt $attackRange -or [double]$profile.projectile_max_distance -gt 64) { throw "Invalid projectile distance for $speciesId" }
    if ([double]$profile.projectile_lifetime_seconds -le 0 -or [double]$profile.projectile_lifetime_seconds -gt 8) { throw "Invalid projectile lifetime for $speciesId" }
    if ([int]$profile.cover_probe_count -lt 1 -or [int]$profile.cover_probe_count -gt 8) { throw "Invalid cover probe budget for $speciesId" }
  }
}
foreach ($required in @('zombie','abyss_brute','abyss_marksman')) {
  if (-not $seen.ContainsKey($required)) { throw "Missing hostile attack profile: $required" }
}

$zombieDamage = [int]$knownCreatures['zombie'].damage
$zombieSource = Get-Content -Raw -Encoding UTF8 $zombiePath
if ($zombieSource -notmatch ('"damage"\s*:\s*' + [regex]::Escape([string]$zombieDamage))) { throw "Zombie fallback damage does not match creatures.json: expected $zombieDamage" }
if ($zombieSource -notmatch 'hostile_melee_creature\.gd') { throw 'Zombie must use the shared hostile melee adapter' }

$registrySource = Get-Content -Raw -Encoding UTF8 $registryPath
foreach ($required in @('var staged','SUPPORTED_SCHEMA_VERSIONS','MAX_COVER_PROBES','_normalize_profile','_profiles = staged')) {
  if ($registrySource -notmatch [regex]::Escape($required)) { throw "Hostile registry is missing atomic/ranged contract: $required" }
}
if ($registrySource -match '_profiles\[species_id\]\s*=\s*normalized') { throw 'Hostile registry must not expose partial profiles before validation completes' }

$factorySource = Get-Content -Raw -Encoding UTF8 $factoryPath
if ($factorySource -notmatch 'abyss_marksman\.gd') { throw 'CreatureFactory must register the abyss marksman' }
if ($factorySource -notmatch 'profile\["hostile_attack"\]') { throw 'CreatureFactory must inject hostile attack profiles before creation' }

$baseSource = Get-Content -Raw -Encoding UTF8 $baseCreaturePath
foreach ($required in @('func _begin_attack_windup','func _advance_attack_windup','func _cancel_attack_windup','func get_hostile_attack_snapshot','AttackTelegraph')) {
  if ($baseSource -notmatch [regex]::Escape($required)) { throw "BaseCreature is missing hostile attack contract: $required" }
}
if ($baseSource -match 'HOSTILE_ATTACK_INTERVAL') { throw 'Hostile attack timing must not remain hard-coded in BaseCreature' }

$meleeSource = Get-Content -Raw -Encoding UTF8 $meleeCreaturePath
if ($meleeSource -notmatch 'take_hostile_damage' -or $meleeSource -notmatch 'get_instance_id') { throw 'Shared melee adapter must submit source-scoped hostile damage' }
$marksmanSource = Get-Content -Raw -Encoding UTF8 $marksmanPath
foreach ($required in @('HostileRangedTacticsPolicy','bind_projectile_runtime','requires_line_of_sight','cover_probe_count','spawn_projectile','AimTelegraph','damage_flow')) {
  if ($marksmanSource -notmatch [regex]::Escape($required)) { throw "Abyss marksman is missing ranged encounter contract: $required" }
}
if ($marksmanSource -match 'Timer\.new|Thread\.new|get_nodes_in_group|take_damage\(') { throw 'Marksman must not create per-shot schedulers, world scans or bypass CombatService' }

$projectileSource = Get-Content -Raw -Encoding UTF8 $projectilePath
foreach ($required in @('MAX_PROJECTILE_SPEED','MAX_PROJECTILE_DISTANCE','MAX_PROJECTILE_LIFETIME','owner_kind','visual_kind','invalid_rejection_count')) {
  if ($projectileSource -notmatch [regex]::Escape($required)) { throw "Shared projectile runtime is missing final bounds: $required" }
}
$hubSource = Get-Content -Raw -Encoding UTF8 $hubPath
foreach ($required in @('HOSTILE_PROJECTILE_CAPACITY := 24','HostileProjectileRuntime','creature_spawned','bind_projectile_runtime','hostile_projectiles')) {
  if ($hubSource -notmatch [regex]::Escape($required)) { throw "Character hub is missing shared hostile projectile composition: $required" }
}
if ($hubSource -match 'current_state\["hostile_projectiles"\]') { throw 'Hostile projectiles must remain transient' }

foreach ($required in @('take_hostile_damage','MAX_HOSTILE_DAMAGE_COOLDOWN_SOURCES','_hostile_damage_cooldowns','attacker_cooldown','get_hostile_damage_snapshot')) {
  if ($playerSource -notmatch [regex]::Escape($required)) { throw "Player hostile damage authority is missing: $required" }
}
$focusSource = Get-Content -Raw -Encoding UTF8 $focusPath
if ($focusSource -notmatch 'get_hostile_attack_snapshot') { throw 'Entity focus must expose the hostile attack snapshot' }
$promptSource = Get-Content -Raw -Encoding UTF8 $promptPath
if ($promptSource -notmatch 'attack_state\s*==\s*"windup"') { throw 'Interaction prompt must explain the windup state' }
if ($promptSource -notmatch '离开红色预警圈可躲避') { throw 'Interaction prompt must explain melee dodge response' }

$runAllSource = Get-Content -Raw -Encoding UTF8 $runAllPath
if ($runAllSource -notmatch 'validate_hostile_attacks\.ps1') { throw 'Full test entry must run the hostile attack validator' }
if ($runAllSource -notmatch 'hostile_attack_windup_regression\.gd') { throw 'Full test entry must run the hostile attack regression' }

Write-Host "PASS hostile_attacks=$($profiles.Count) ranged=1 player_damage_cooldown=$playerDamageCooldown source_capacity=$($sourceCapacityMatch.Groups[1].Value)"
