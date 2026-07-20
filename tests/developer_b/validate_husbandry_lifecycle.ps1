$ErrorActionPreference = 'Stop'

$root = Resolve-Path "$PSScriptRoot\..\.."
$scenePath = Join-Path $root 'scenes\ui\service_hub.tscn'
$gameplayHubPath = Join-Path $root 'src\ui\service_hub.gd'
$husbandryHubPath = Join-Path $root 'src\ui\husbandry_progression_service_hub.gd'
$ranchHubPath = Join-Path $root 'src\ui\ranch_progression_service_hub.gd'
$participantPath = Join-Path $root 'src\husbandry\husbandry_runtime_participant.gd'
$ranchParticipantPath = Join-Path $root 'src\husbandry\ranch_runtime_participant.gd'
$migrationPath = Join-Path $root 'src\husbandry\husbandry_state_migration.gd'
$notificationPath = Join-Path $root 'src\husbandry\husbandry_notification_policy.gd'
$servicePath = Join-Path $root 'src\husbandry\animal_husbandry_service.gd'
$interactionPath = Join-Path $root 'src\husbandry\husbandry_interaction_adapter.gd'
$runAllPath = Join-Path $root 'tests\run_all.ps1'
$workflowPath = Join-Path $root '.github\workflows\husbandry-tests.yml'

$sceneText = Get-Content -Raw -Encoding UTF8 $scenePath
$gameplayHubText = Get-Content -Raw -Encoding UTF8 $gameplayHubPath
$husbandryHubText = Get-Content -Raw -Encoding UTF8 $husbandryHubPath
$ranchHubText = Get-Content -Raw -Encoding UTF8 $ranchHubPath
$participantText = Get-Content -Raw -Encoding UTF8 $participantPath
$ranchParticipantText = Get-Content -Raw -Encoding UTF8 $ranchParticipantPath
$migrationText = Get-Content -Raw -Encoding UTF8 $migrationPath
$notificationText = Get-Content -Raw -Encoding UTF8 $notificationPath
$serviceText = Get-Content -Raw -Encoding UTF8 $servicePath
$interactionText = Get-Content -Raw -Encoding UTF8 $interactionPath
$runAllText = Get-Content -Raw -Encoding UTF8 $runAllPath
$workflowText = Get-Content -Raw -Encoding UTF8 $workflowPath

if ($sceneText -notmatch 'exploration_progression_service_hub\.gd') {
  throw 'Production service_hub scene must retain the current exploration entry point'
}
if ($gameplayHubText -notmatch 'service_hub_feature_coordinator\.gd') {
  throw 'Gameplay hub must own the shared feature lifecycle coordinator'
}
if ($husbandryHubText -notmatch 'extends\s+"res://src/ui/repair_progression_service_hub\.gd"') {
  throw 'Husbandry hub must retain the compatible repair inheritance entry point'
}
if ($husbandryHubText -match 'service_hub_feature_coordinator\.gd') {
  throw 'Husbandry hub must reuse the Gameplay lifecycle coordinator'
}
if ($husbandryHubText -notmatch 'husbandry_runtime_participant\.gd' -or $husbandryHubText -notmatch 'HUSBANDRY_RUNTIME_FEATURE') {
  throw 'Husbandry hub must register the husbandry runtime participant'
}
foreach ($field in @('husbandry_service','husbandry_interaction','husbandry_runtime_participant')) {
  if ($husbandryHubText -notmatch "var\s+$field\s*:\s*Node") {
    throw "Husbandry hub removed public lifecycle field: $field"
  }
}
foreach ($legacyOwner in @('HusbandryServiceScript','HusbandryInteractionScript','FeatureCoordinatorScript','_connect_husbandry_feedback','_on_baby_born','_on_animal_grew')) {
  if ($husbandryHubText -match $legacyOwner) {
    throw "Husbandry inheritance layer still owns runtime responsibility: $legacyOwner"
  }
}
foreach ($legacyLifecycle in @('_begin_world','attach_game','activate_gameplay','save_current','handle_world_start_failed','return_to_menu','_exit_tree','_register_feature_participant')) {
  if ($husbandryHubText -match "func\s+$legacyLifecycle\s*\(") {
    throw "Husbandry hub must remain a thin participant registration layer: $legacyLifecycle"
  }
}
if ($husbandryHubText -notmatch 'func\s+get_character_snapshot\s*\(') {
  throw 'Husbandry hub must preserve the production character diagnostics extension point'
}

if ($ranchHubText -notmatch 'extends\s+"res://src/ui/husbandry_progression_service_hub\.gd"') {
  throw 'Ranch hub must retain the husbandry inheritance entry point'
}
if ($ranchHubText -match 'FeatureCoordinatorScript' -or $ranchHubText -match 'func\s+save_current\s*\(') {
  throw 'Ranch hub must remain a thin participant registration layer'
}
if ($ranchParticipantText -notmatch 'return\s+\[&"husbandry_runtime"\]') {
  throw 'Ranch runtime must explicitly depend on husbandry runtime'
}

foreach ($method in @('get_dependencies','install','normalize_world_state','begin_world','attach_game','activate','save_into','snapshot_into','clear','shutdown','get_lifecycle_snapshot')) {
  if ($participantText -notmatch "func\s+$method\s*\(") {
    throw "Husbandry runtime participant is missing method: $method"
  }
}
foreach ($servicePath in @('animal_husbandry_service\.gd','husbandry_interaction_adapter\.gd')) {
  if ($participantText -notmatch $servicePath) {
    throw "Husbandry participant must own service: $servicePath"
  }
}
if ($participantText -notmatch 'payload\["husbandry"\]' -or $participantText -notmatch 'snapshot\["husbandry"\]') {
  throw 'Husbandry participant must preserve save and diagnostic fields'
}
if ($participantText -notmatch 'bind_entity_interaction_service", null') {
  throw 'Husbandry participant must explicitly unbind the old player'
}
if ($participantText -notmatch 'MAX_PENDING_LIFECYCLE_EVENTS\s*:=\s*64') {
  throw 'Husbandry lifecycle event batching must remain bounded'
}
if ($participantText -notmatch 'call_deferred\("_flush_lifecycle_batch"\)') {
  throw 'Synchronous husbandry lifecycle events must be batched at frame end'
}
if ($participantText -notmatch 'lifecycle_audio_count' -or $participantText -notmatch 'dropped_lifecycle_events') {
  throw 'Husbandry batching diagnostics must expose sound and overflow budgets'
}

if ($migrationText -notmatch 'class_name\s+HusbandryStateMigration' -or $migrationText -notmatch 'normalize_world_state') {
  throw 'Husbandry state migration must be an independent domain helper'
}
if ($migrationText -notmatch 'MAX_TIMER_SECONDS\s*:=\s*86400\.0' -or $migrationText -notmatch 'supports_species') {
  throw 'Husbandry migration must bound timers and reject unknown species'
}
if ($notificationText -notmatch 'MAX_VISIBLE_TYPES\s*:=\s*3' -or $notificationText -notmatch 'newborn_count' -or $notificationText -notmatch 'grown_count') {
  throw 'Husbandry notification policy must bound visible types and preserve event totals'
}
if ($serviceText -notmatch 'func\s+shutdown\s*\(' -or $serviceText -notmatch '_disconnect_live_creature_signals') {
  throw 'Husbandry service must explicitly disconnect live creature callbacks'
}
if ($interactionText -notmatch 'func\s+shutdown\s*\(' -or $interactionText -notmatch 'service\s*=\s*null') {
  throw 'Husbandry interaction adapter must expose explicit shutdown'
}

foreach ($testPath in @('husbandry_runtime_lifecycle_regression\.gd','husbandry_runtime_lifecycle_desktop_acceptance\.gd')) {
  if ($runAllText -notmatch $testPath -and $workflowText -notmatch $testPath) {
    throw "Husbandry lifecycle acceptance is not wired into a permanent gate: $testPath"
  }
}

Write-Host 'PASS husbandry_lifecycle root=gameplay participant=husbandry_runtime dependency=ranch->husbandry batch_limit=64 visible_types=3'
