$ErrorActionPreference = 'Stop'

$root = Resolve-Path "$PSScriptRoot\..\.."
$attackPath = Join-Path $root 'data\hostile_attacks.json'
$creaturePath = Join-Path $root 'data\creatures.json'
$factoryPath = Join-Path $root 'src\entity\creature_factory.gd'
$baseCreaturePath = Join-Path $root 'src\entity\base_creature.gd'
$zombiePath = Join-Path $root 'src\entity\zombie.gd'
$playerPath = Join-Path $root 'src\player\character_progression_player.gd'
$focusPath = Join-Path $root 'src\interaction\player_focus_resolver.gd'
$promptPath = Join-Path $root 'src\experience\interaction_prompt_resolver.gd'
$runAllPath = Join-Path $root 'tests\run_all.ps1'

$attackData = Get-Content -Raw -Encoding UTF8 $attackPath | ConvertFrom-Json
$creatureData = Get-Content -Raw -Encoding UTF8 $creaturePath | ConvertFrom-Json
if ([int]$attackData.schema_version -ne 1) { throw "Unsupported hostile attack schema: $($attackData.schema_version)" }

$knownCreatures = @{}
foreach ($property in $creatureData.creatures.PSObject.Properties) {
  $knownCreatures[[string]$property.Name] = $property.Value
}

$playerSource = Get-Content -Raw -Encoding UTF8 $playerPath
$damageCooldownMatch = [regex]::Match($playerSource, 'REPEATED_HOSTILE_DAMAGE_COOLDOWN\s*:=\s*([0-9.]+)')
if (-not $damageCooldownMatch.Success) { throw 'Unable to parse the player hostile-damage cooldown' }
$playerDamageCooldown = [double]$damageCooldownMatch.Groups[1].Value

$profiles = @($attackData.profiles)
if ($profiles.Count -lt 1) { throw 'Hostile attack data contains no profiles' }
$seen = @{}
foreach ($profile in $profiles) {
  $speciesId = [string]$profile.species_id
  $sourceId = [string]$profile.source_id
  if ([string]::IsNullOrWhiteSpace($speciesId) -or [string]::IsNullOrWhiteSpace($sourceId)) {
    throw 'Hostile attack profile has empty species/source identity'
  }
  if ($seen.ContainsKey($speciesId)) { throw "Duplicate hostile attack profile: $speciesId" }
  if (-not $knownCreatures.ContainsKey($speciesId)) { throw "Hostile attack profile references unknown creature: $speciesId" }
  if ([double]$knownCreatures[$speciesId].damage -le 0) { throw "Hostile attack profile references non-damaging creature: $speciesId" }
  $seen[$speciesId] = $true

  $attackRange = [double]$profile.attack_range
  $detectionRange = [double]$profile.detection_range
  $windup = [double]$profile.windup_seconds
  $cooldown = [double]$profile.cooldown_seconds
  $cancelMultiplier = [double]$profile.cancel_range_multiplier
  $cancelRecovery = [double]$profile.cancel_recovery_seconds
  $leashMultiplier = [double]$profile.target_leash_multiplier
  $telegraphMultiplier = [double]$profile.telegraph_radius_multiplier
  if ($attackRange -lt 0.25 -or $attackRange -gt 6.0) { throw "Invalid attack range for $speciesId" }
  if ($detectionRange -le $attackRange -or $detectionRange -gt 64.0) { throw "Detection range must exceed attack range for $speciesId" }
  if ($windup -lt 0.1 -or $windup -gt 3.0) { throw "Invalid attack windup for $speciesId" }
  if ($cooldown -lt $playerDamageCooldown -or $cooldown -gt 30.0) {
    throw "Attack cooldown must not be shorter than the player's hostile-damage cooldown: $speciesId hostile=$cooldown player=$playerDamageCooldown"
  }
  if ($cancelMultiplier -lt 1.0 -or $cancelMultiplier -gt 3.0) { throw "Invalid cancel range multiplier for $speciesId" }
  if ($cancelRecovery -lt 0.0 -or $cancelRecovery -gt $cooldown) { throw "Invalid cancel recovery for $speciesId" }
  if ($leashMultiplier -lt 1.0 -or $leashMultiplier -gt 3.0) { throw "Invalid target leash for $speciesId" }
  if ($telegraphMultiplier -lt 0.5 -or $telegraphMultiplier -gt 2.0) { throw "Invalid telegraph radius for $speciesId" }
}
if (-not $seen.ContainsKey('zombie')) { throw 'Production zombie hostile attack profile is missing' }

$zombieDamage = [int]$knownCreatures['zombie'].damage
$zombieSource = Get-Content -Raw -Encoding UTF8 $zombiePath
if ($zombieSource -notmatch ('"damage"\s*:\s*' + [regex]::Escape([string]$zombieDamage))) {
  throw "Zombie fallback damage does not match creatures.json: expected $zombieDamage"
}

$factorySource = Get-Content -Raw -Encoding UTF8 $factoryPath
if ($factorySource -notmatch 'hostile_attack_registry\.gd') { throw 'CreatureFactory must compose the hostile attack registry' }
if ($factorySource -notmatch 'profile\["hostile_attack"\]') { throw 'CreatureFactory must inject the hostile attack profile before creation' }

$baseSource = Get-Content -Raw -Encoding UTF8 $baseCreaturePath
foreach ($required in @('func _begin_attack_windup','func _advance_attack_windup','func _cancel_attack_windup','func get_hostile_attack_snapshot','AttackTelegraph')) {
  if ($baseSource -notmatch [regex]::Escape($required)) { throw "BaseCreature is missing hostile attack contract: $required" }
}
if ($baseSource -match 'HOSTILE_ATTACK_INTERVAL') { throw 'Hostile attack timing must not remain hard-coded in BaseCreature' }
if ($baseSource -match 'take_damage"\s*,\s*attack_damage\s*,\s*"zombie"') { throw 'BaseCreature must not hard-code the zombie damage source' }

$focusSource = Get-Content -Raw -Encoding UTF8 $focusPath
if ($focusSource -notmatch 'get_hostile_attack_snapshot') { throw 'Entity focus must expose the hostile attack snapshot' }
$promptSource = Get-Content -Raw -Encoding UTF8 $promptPath
if ($promptSource -notmatch 'attack_state\s*==\s*"windup"') { throw 'Interaction prompt must explain the windup state' }
if ($promptSource -notmatch '离开红色预警圈可躲避') { throw 'Interaction prompt must explain the real dodge response' }

$runAllSource = Get-Content -Raw -Encoding UTF8 $runAllPath
if ($runAllSource -notmatch 'validate_hostile_attacks\.ps1') { throw 'Full test entry must run the hostile attack validator' }
if ($runAllSource -notmatch 'hostile_attack_windup_regression\.gd') { throw 'Full test entry must run the hostile attack regression' }

Write-Host "PASS hostile attacks=$($profiles.Count) player_damage_cooldown=$playerDamageCooldown zombie_damage=$zombieDamage"
