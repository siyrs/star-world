$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = Resolve-Path "$PSScriptRoot\..\.."
$paths = [ordered]@{
  DirectionPolicy = Join-Path $root 'src\combat\damage_direction_policy.gd'
  Combat = Join-Path $root 'src\combat\combat_service.gd'
  Player = Join-Path $root 'src\player\character_progression_player.gd'
  Camera = Join-Path $root 'src\player\camera_feel_controller.gd'
  Feedback = Join-Path $root 'src\ui\combat_feedback_overlay.gd'
  SettingsPolicy = Join-Path $root 'src\settings\game_settings_policy.gd'
  SettingsPanel = Join-Path $root 'src\ui\settings_panel.gd'
  HardenedSettings = Join-Path $root 'src\ui\hardened_settings_panel.gd'
  Hub = Join-Path $root 'src\ui\service_hub.gd'
  CharacterUi = Join-Path $root 'src\ui\character_game_ui.gd'
  IntensityData = Join-Path $root 'data\encounter_intensity_profiles.json'
  IntensityRegistry = Join-Path $root 'src\entity\encounter_intensity_registry.gd'
  EncounterPolicy = Join-Path $root 'src\entity\hostile_encounter_policy.gd'
  EncounterDirector = Join-Path $root 'src\entity\hostile_encounter_director.gd'
  RewardData = Join-Path $root 'data\encounter_rewards.json'
  RewardRegistry = Join-Path $root 'src\entity\encounter_reward_registry.gd'
  RewardService = Join-Path $root 'src\entity\encounter_reward_service.gd'
  RangedData = Join-Path $root 'data\ranged_combat.json'
  Regression = Join-Path $root 'tests\qa\combat_feedback_intensity_economy_regression.gd'
  LongRun = Join-Path $root 'tests\qa\mixed_combat_long_run_regression.gd'
  Desktop = Join-Path $root 'tests\qa\combat_feedback_intensity_desktop_acceptance.gd'
  Workflow = Join-Path $root '.github\workflows\combat-feedback-intensity-economy-tests.yml'
  RunAll = Join-Path $root 'tests\run_all.ps1'
  Contract = Join-Path $root 'docs\COMBAT_FEEDBACK_INTENSITY_ECONOMY.md'
  Testing = Join-Path $root 'docs\COMBAT_FEEDBACK_INTENSITY_ECONOMY_TESTING.md'
  Audit = Join-Path $root 'docs\ARCHITECTURE_AUDIT_2026-08-06_ITERATION_57.md'
  Roadmap = Join-Path $root 'docs\PRODUCT_ROADMAP_ITERATION_57.md'
  Closure = Join-Path $root 'qa\pr-102-closure-report.md'
}
foreach ($entry in $paths.GetEnumerator()) {
  if (-not (Test-Path -LiteralPath $entry.Value)) {
    throw "Combat feedback/intensity/economy file is missing: $($entry.Key) $($entry.Value)"
  }
}
if (Test-Path -LiteralPath (Join-Path $root '.github\workflows\temporary-next-iteration-snapshot.yml')) {
  throw 'Temporary repository snapshot workflow must not enter the permanent branch'
}

$text = @{}
foreach ($entry in $paths.GetEnumerator()) {
  if ($entry.Key -notin @('IntensityData','RewardData','RangedData')) {
    $text[$entry.Key] = Get-Content -Raw -Encoding UTF8 $entry.Value
  }
}

foreach ($token in @(
  'class_name\s+DamageDirectionPolicy','DIRECTION_FRONT','DIRECTION_RIGHT','DIRECTION_REAR','DIRECTION_LEFT',
  'source_available','atan2','localized_label'
)) {
  if ($text.DirectionPolicy -notmatch $token) { throw "Damage direction policy is missing: $token" }
}
if ($text.DirectionPolicy -match 'extends\s+Node|Timer\.new|Thread\.new|get_nodes_in_group|save_world') {
  throw 'Damage direction policy must remain pure and stateless'
}
foreach ($token in @(
  'incoming_damage_resolved','context:\s*Dictionary','result\[raw_key\]\s*=\s*context\[raw_key\]',
  'take_hostile_damage_with_context','source_position','damage_direction','damage_source_available'
)) {
  if (($text.Combat + $text.Player) -notmatch $token) { throw "Authoritative incoming-damage context is missing: $token" }
}
foreach ($token in @(
  'DIRECTION_PULSE_SECONDS','INCOMING_TEXT_SECONDS','direction_indicator_pool_size','IncomingDamageText',
  'show_damage_direction_pulses','护甲吸收','DamageDirectionPolicy\.DIRECTIONS'
)) {
  if ($text.Feedback -notmatch $token) { throw "Combat feedback HUD is missing: $token" }
}
foreach ($token in @('_build_direction_indicators','DamageDirectionPolicy\.DIRECTIONS','_direction_indicators\[direction\]')) {
  if ($text.Feedback -notmatch $token) { throw "Combat feedback HUD fixed direction pool is missing: $token" }
}
foreach ($token in @(
  'damage_impact_multiplier','set_damage_impact_multiplier','hurt_shake_strength.*damage_impact_multiplier',
  'apply_combat_feedback_settings'
)) {
  if (($text.Camera + $text.Player + $text.Hub + $text.CharacterUi) -notmatch $token) { throw "Camera/HUD settings propagation is missing: $token" }
}
foreach ($token in @(
  'show_damage_direction_pulses','damage_camera_impact','encounter_intensity',
  'ENCOUNTER_INTENSITIES','MIN_DAMAGE_CAMERA_IMPACT','MAX_DAMAGE_CAMERA_IMPACT'
)) {
  if (($text.SettingsPolicy + $text.SettingsPanel + $text.HardenedSettings) -notmatch $token) { throw "Canonical settings contract is missing: $token" }
}

$intensity = Get-Content -Raw -Encoding UTF8 $paths.IntensityData | ConvertFrom-Json
if ([int]$intensity.schema_version -ne 1) { throw 'Encounter intensity schema must be version 1' }
$profiles = @($intensity.profiles)
if ($profiles.Count -ne 3) { throw "Encounter intensity must contain exactly three profiles; actual=$($profiles.Count)" }
$expected = @{
  casual = @(1.35, 0.75)
  standard = @(1.0, 1.0)
  high_risk = @(0.75, 1.25)
}
foreach ($profile in $profiles) {
  $id = [string]$profile.id
  if (-not $expected.ContainsKey($id)) { throw "Unknown encounter intensity profile: $id" }
  if ([double]$profile.cooldown_multiplier -ne [double]$expected[$id][0]) { throw "Unexpected cooldown multiplier: $id" }
  if ([double]$profile.danger_pressure_multiplier -ne [double]$expected[$id][1]) { throw "Unexpected danger pressure multiplier: $id" }
  $extra = @($profile.PSObject.Properties.Name | Where-Object { $_ -notin @('id','display_name','cooldown_multiplier','danger_pressure_multiplier') })
  if ($extra.Count -gt 0) { throw "Intensity profile must not own progression/composition fields: $id/$($extra -join ',')" }
}
foreach ($token in @(
  'class_name\s+EncounterIntensityRegistry','REQUIRED_PROFILE_IDS','MAX_PROFILES\s*:=\s*8',
  'effective_cooldown_seconds','effective_pressure_limit','intensity_profile_id','base_cooldown_seconds'
)) {
  if (($text.IntensityRegistry + $text.EncounterPolicy + $text.EncounterDirector) -notmatch $token) { throw "Encounter intensity implementation is missing: $token" }
}
if ($text.IntensityRegistry -match 'extends\s+Node|Timer\.new|Thread\.new|save_world|serialize\s*\(') {
  throw 'Encounter intensity registry must remain pure local configuration'
}

$rewardData = Get-Content -Raw -Encoding UTF8 $paths.RewardData | ConvertFrom-Json
$allowedRewardItems = @('flint','gunpowder')
$finishedAmmo = @('arrow','light_round','shotgun_shell')
foreach ($profile in @($rewardData.profiles)) {
  foreach ($field in @('base_rewards','efficient_bonus')) {
    foreach ($property in @($profile.$field.PSObject.Properties)) {
      if ([string]$property.Name -notin $allowedRewardItems) {
        throw "Formal encounter reward contains non-crafting input: $($profile.encounter_profile_id)/$field/$($property.Name)"
      }
      if ([string]$property.Name -in $finishedAmmo) {
        throw "Formal encounter reward contains completed ammunition: $($profile.encounter_profile_id)/$($property.Name)"
      }
    }
  }
}
foreach ($token in @(
  'ALLOWED_REWARD_ITEM_IDS','flint','gunpowder','FINISHED_AMMUNITION_IDS',
  '_contains_finished_ammunition','_contains_unsupported_reward_items','finished_ammunition_reward','unsupported_reward_item','_reward_additions'
)) {
  if (($text.RewardRegistry + $text.RewardService) -notmatch $token) { throw "Defensive reward economy contract is missing: $token" }
}
$ranged = Get-Content -Raw -Encoding UTF8 $paths.RangedData | ConvertFrom-Json
$flint = @($ranged.items | Where-Object { [string]$_.id -eq 'flint' })
if ($flint.Count -ne 1 -or [int]$flint[0].max_stack -ne 64) { throw 'Ranged data must define exactly one bounded flint item' }
$arrows = @($ranged.recipes | Where-Object { [string]$_.id -eq 'arrows' })
if ($arrows.Count -ne 1) { throw 'Ranged data must define exactly one arrows recipe' }
if ([int]$arrows[0].ingredients.flint -ne 1 -or $null -ne $arrows[0].ingredients.PSObject.Properties['stone']) {
  throw 'Arrow crafting must consume exactly one flint and no generic stone'
}

foreach ($phrase in @(
  'direction policy classifies','visual direction pulses can be disabled locally',
  'intensity scaling never changes formal enemy composition','runtime transaction filter cannot add completed ammunition',
  'encounter flint can close the real arrow crafting loop'
)) {
  if ($text.Regression -notmatch [regex]::Escape($phrase)) { throw "Primary regression is missing: $phrase" }
}
foreach ($phrase in @(
  'exactly 3,600 seconds','two marksmen four zombies and one brute','pause windows advance no combat state',
  'three JSON save and reload boundaries','never rewards completed ammunition','menu cleanup removes all transient projectiles'
)) {
  if ($text.LongRun -notmatch [regex]::Escape($phrase)) { throw "Mixed combat long-run regression is missing: $phrase" }
}
foreach ($phrase in @(
  'settings exposes exactly three versioned encounter intensities','production settings persist high-risk encounter intensity',
  'accessible incoming-damage text remains visible when pulses are disabled','production HUD shows armour absorption'
)) {
  if ($text.Desktop -notmatch [regex]::Escape($phrase)) { throw "Desktop acceptance is missing: $phrase" }
}
foreach ($token in @(
  'pull_request:','push:','branches:','master','uses:\s*\./\.github/workflows/reusable-godot-quality-gate\.yml',
  'validate_combat_feedback_intensity_economy\.ps1','combat_feedback_intensity_economy_regression\.gd',
  'mixed_combat_long_run_regression\.gd','combat_feedback_intensity_desktop_acceptance\.gd'
)) {
  if ($text.Workflow -notmatch $token) { throw "Permanent quality workflow is missing: $token" }
}
foreach ($token in @(
  'validate_combat_feedback_intensity_economy\.ps1','combat_feedback_intensity_economy_regression\.gd',
  'mixed_combat_long_run_regression\.gd'
)) {
  if ($text.RunAll -notmatch $token) { throw "Full regression entry is missing: $token" }
}
foreach ($concept in @('方向受击','遭遇强度','燧石','成品弹药','3,600 秒','HOLD')) {
  if (($text.Contract + $text.Testing + $text.Audit + $text.Roadmap + $text.Closure) -notmatch [regex]::Escape($concept)) {
    throw "Iteration documentation is missing concept: $concept"
  }
}

Write-Host "PASS combat feedback intensity and economy profiles=$($profiles.Count) rewardProfiles=$(@($rewardData.profiles).Count)"
