$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = Resolve-Path "$PSScriptRoot\..\.."
$paths = [ordered]@{
  Data = Join-Path $root 'data\encounter_rewards.json'
  Encounters = Join-Path $root 'data\hostile_encounters.json'
  Items = Join-Path $root 'data\items.json'
  Ranged = Join-Path $root 'data\ranged_combat.json'
  Firearms = Join-Path $root 'data\firearms.json'
  Registry = Join-Path $root 'src\entity\encounter_reward_registry.gd'
  Service = Join-Path $root 'src\entity\encounter_reward_service.gd'
  Lifecycle = Join-Path $root 'src\entity\lifecycle_bound_encounter_reward_service.gd'
  Overlay = Join-Path $root 'src\ui\encounter_reward_overlay.gd'
  Scene = Join-Path $root 'scenes\ui\service_hub.tscn'
  Headless = Join-Path $root 'tests\qa\encounter_reward_economy_regression.gd'
  Desktop = Join-Path $root 'tests\qa\encounter_reward_economy_desktop_acceptance.gd'
  Workflow = Join-Path $root '.github\workflows\bounded-encounter-reward-economy-tests.yml'
  RunAll = Join-Path $root 'tests\run_all.ps1'
  Contract = Join-Path $root 'docs\BOUNDED_ENCOUNTER_REWARD_ECONOMY.md'
  Testing = Join-Path $root 'docs\BOUNDED_ENCOUNTER_REWARD_ECONOMY_TESTING.md'
  Audit = Join-Path $root 'docs\ARCHITECTURE_AUDIT_2026-07-30_ITERATION_56.md'
  Roadmap = Join-Path $root 'docs\PRODUCT_ROADMAP_ITERATION_56.md'
}
foreach ($entry in $paths.GetEnumerator()) {
  if (-not (Test-Path -LiteralPath $entry.Value)) {
    throw "Encounter reward economy file is missing: $($entry.Key) $($entry.Value)"
  }
}
$text = @{}
foreach ($entry in $paths.GetEnumerator()) {
  if ($entry.Key -notin @('Data','Encounters','Items','Ranged','Firearms')) {
    $text[$entry.Key] = Get-Content -Raw -Encoding UTF8 $entry.Value
  }
}

$data = Get-Content -Raw -Encoding UTF8 $paths.Data | ConvertFrom-Json
if ([int]$data.schema_version -ne 1) { throw 'Encounter reward schema must begin at version 1' }
$profiles = @($data.profiles)
if ($profiles.Count -ne 3) { throw "Encounter reward release must contain exactly 3 profiles; actual=$($profiles.Count)" }
$encounterData = Get-Content -Raw -Encoding UTF8 $paths.Encounters | ConvertFrom-Json
$encounterIds = @{}
foreach ($profile in @($encounterData.profiles)) { $encounterIds[[string]$profile.id] = $true }
$itemIds = @{}
foreach ($itemPath in @($paths.Items, $paths.Ranged, $paths.Firearms)) {
  $itemData = Get-Content -Raw -Encoding UTF8 $itemPath | ConvertFrom-Json
  foreach ($item in @($itemData.items)) {
    $itemId = [string]$item.id
    if (-not [string]::IsNullOrWhiteSpace($itemId)) { $itemIds[$itemId] = $true }
  }
}
$profileIds = @{}
foreach ($profile in $profiles) {
  $id = [string]$profile.encounter_profile_id
  if ([string]::IsNullOrWhiteSpace($id) -or $profileIds.ContainsKey($id)) { throw "Duplicate/empty encounter reward profile: $id" }
  if (-not $encounterIds.ContainsKey($id)) { throw "Encounter reward references unknown encounter profile: $id" }
  $profileIds[$id] = $true
  $totalQuantity = 0
  $rewardTypes = @{}
  foreach ($field in @('base_rewards','efficient_bonus')) {
    $property = $profile.PSObject.Properties[$field]
    if ($null -eq $property -or $property.Value -isnot [PSCustomObject]) { throw "Encounter reward $field must be an object: $id" }
    foreach ($rewardProperty in $property.Value.PSObject.Properties) {
      $itemId = [string]$rewardProperty.Name
      $quantity = [int]$rewardProperty.Value
      if (-not $itemIds.ContainsKey($itemId)) { throw "Encounter reward references unknown item: $id/$itemId" }
      if ($quantity -lt 1 -or $quantity -gt 8) { throw "Encounter reward quantity must be 1..8: $id/$itemId/$quantity" }
      $rewardTypes[$itemId] = $true
      $totalQuantity += $quantity
    }
  }
  if ($rewardTypes.Count -gt 4) { throw "Encounter reward exceeds four item types: $id" }
  if ($totalQuantity -gt 16) { throw "Encounter reward exceeds sixteen total items: $id/$totalQuantity" }
  if ([int]$profile.efficient_shot_limit -lt 0 -or [int]$profile.efficient_shot_limit -gt 16) {
    throw "Encounter reward efficiency limit must be 0..16: $id"
  }
}
foreach ($required in @('abyss_assault','abyss_skirmish','continent_night_patrol')) {
  if (-not $profileIds.ContainsKey($required)) { throw "Missing encounter reward profile: $required" }
}

foreach ($token in @(
  'class_name\s+EncounterRewardRegistry','MAX_PROFILES\s*:=\s*16',
  'MAX_REWARD_TYPES\s*:=\s*4','MAX_TOTAL_REWARD_QUANTITY\s*:=\s*16',
  'var\s+staged:\s*Dictionary','_profiles\s*=\s*staged','build_reward','get_validation_errors'
)) {
  if ($text.Registry -notmatch $token) { throw "Atomic reward registry is missing: $token" }
}
if ($text.Registry -match 'extends\s+Node|Timer\.new|Thread\.new|save_world|serialize\s*\(') {
  throw 'Encounter reward registry must remain pure, atomic and non-persistent'
}
foreach ($token in @(
  'class_name\s+EncounterRewardService','MAX_ACTIVE_LEDGERS\s*:=\s*2',
  'MAX_PENDING_REWARDS\s*:=\s*8','MAX_CLAIM_HISTORY\s*:=\s*256',
  'encounter_started','encounter_completed','shot_fired','inventory_changed',
  '_on_member_died','_accepted_target_ids','transact_items','_pending_rewards',
  '_schedule_reward_flush','duplicate_completion','unattributed_shot_count','EncounterRewardOverlay'
)) {
  if ($text.Service -notmatch $token) { throw "Bounded reward service is missing: $token" }
}
if ($text.Service -match 'Timer\.new|Thread\.new|get_nodes_in_group|save_world|serialize\s*\(|current_state\s*\[') {
  throw 'Reward service must use existing signals and inventory authority without scans or a parallel save domain'
}
foreach ($token in @(
  'class_name\s+LifecycleBoundEncounterRewardService',
  'start_world_requested','return_to_menu_requested',
  'clear\("start_world_signal"\)','clear\("return_to_menu_signal"\)',
  '_bound_world_id\s*=\s*""'
)) {
  if ($text.Lifecycle -notmatch $token) { throw "Reward lifecycle adapter is missing: $token" }
}
if ($text.Lifecycle -match 'Timer\.new|Thread\.new|get_nodes_in_group|transact_items|save_world') {
  throw 'Reward lifecycle adapter must only translate explicit world signals into clear boundaries'
}
if (($text.Scene | Select-String -Pattern 'EncounterRewardService' -AllMatches).Matches.Count -ne 1) {
  throw 'Service composition must install exactly one EncounterRewardService'
}
if ($text.Scene -notmatch 'lifecycle_bound_encounter_reward_service\.gd') {
  throw 'Production composition must use the explicit lifecycle-bound reward adapter'
}
if ($text.Scene.IndexOf('HostileEncounterDirector') -gt $text.Scene.IndexOf('EncounterRewardService')) {
  throw 'Reward service must be composed after the encounter director for deterministic lifecycle ordering'
}
foreach ($token in @('EncounterRewardPanel','补给等待领取','净弹药','背包空间不足','reward_granted','reward_pending')) {
  if ($text.Overlay -notmatch [regex]::Escape($token)) { throw "Encounter reward HUD is missing: $token" }
}
foreach ($phrase in @(
  'one invalid reward profile rejects the entire staged registry',
  'last defeated member grants the squad reward before director cleanup',
  'duplicate completion cannot grant the same reward twice',
  'unloaded members are not misclassified as defeated',
  'full inventory queues one bounded pending reward',
  'inventory change automatically retries the pending reward',
  'sixty minute reward production remains linearly bounded'
)) {
  if ($text.Headless -notmatch [regex]::Escape($phrase)) { throw "Encounter reward headless regression is missing: $phrase" }
}
foreach ($phrase in @(
  'last-kill reward waits until the fourth shot is recorded',
  'reward HUD shows the granted supply exact shot cost and net economy',
  'full production inventory keeps the complete reward in one pending record',
  'inventory change automatically retries and grants the pending reward',
  'member unload cannot masquerade as a rewarded squad defeat',
  'reward ledgers claims and pending records do not enter world.json',
  'reloaded world begins with an empty runtime claim history'
)) {
  if ($text.Desktop -notmatch [regex]::Escape($phrase)) { throw "Encounter reward desktop acceptance is missing: $phrase" }
}
foreach ($token in @(
  'uses:\s*\./\.github/workflows/reusable-godot-quality-gate\.yml',
  'validate_bounded_encounter_rewards\.ps1','encounter_reward_economy_regression\.gd',
  'encounter_reward_economy_desktop_acceptance\.gd','encounter-reward-granted\.png',
  'encounter-reward-pending\.png','encounter-reward-report\.json'
)) {
  if ($text.Workflow -notmatch $token) { throw "Encounter reward workflow is missing: $token" }
}
foreach ($token in @('validate_bounded_encounter_rewards\.ps1','encounter_reward_economy_regression\.gd')) {
  if ($text.RunAll -notmatch $token) { throw "Full regression entry is missing reward gate: $token" }
}
foreach ($concept in @('原子','最后一击','待领取','重复 completion','不进入','3600 秒','Windows Release','净弹药')) {
  if (($text.Contract + $text.Testing + $text.Audit + $text.Roadmap) -notmatch [regex]::Escape($concept)) {
    throw "Encounter reward documentation is missing concept: $concept"
  }
}
Write-Host "PASS bounded encounter rewards profiles=$($profiles.Count) rewardTypes<=4 total<=16 ledgers<=2 pending<=8 claims<=256 lifecycle=signals"
