$ErrorActionPreference = 'Stop'

$root = Resolve-Path "$PSScriptRoot\..\.."
$gameplayHubPath = Join-Path $root 'src\ui\service_hub.gd'
$husbandryHubPath = Join-Path $root 'src\ui\husbandry_progression_service_hub.gd'
$ranchHubPath = Join-Path $root 'src\ui\ranch_progression_service_hub.gd'
$runtimeHealthHubPath = Join-Path $root 'src\ui\runtime_health_service_hub.gd'
$explorationHubPath = Join-Path $root 'src\ui\exploration_progression_service_hub.gd'
$participantPath = Join-Path $root 'src\husbandry\ranch_runtime_participant.gd'
$policyPath = Join-Path $root 'src\husbandry\ranch_notification_policy.gd'
$attractionPath = Join-Path $root 'src\husbandry\animal_attraction_service.gd'
$productPath = Join-Path $root 'src\husbandry\animal_product_service.gd'
$runAllPath = Join-Path $root 'tests\run_all.ps1'

$gameplayHubText = Get-Content -Raw -Encoding UTF8 $gameplayHubPath
$husbandryHubText = Get-Content -Raw -Encoding UTF8 $husbandryHubPath
$ranchHubText = Get-Content -Raw -Encoding UTF8 $ranchHubPath
$runtimeHealthHubText = Get-Content -Raw -Encoding UTF8 $runtimeHealthHubPath
$explorationHubText = Get-Content -Raw -Encoding UTF8 $explorationHubPath
$participantText = Get-Content -Raw -Encoding UTF8 $participantPath
$policyText = Get-Content -Raw -Encoding UTF8 $policyPath
$attractionText = Get-Content -Raw -Encoding UTF8 $attractionPath
$productText = Get-Content -Raw -Encoding UTF8 $productPath
$runAllText = Get-Content -Raw -Encoding UTF8 $runAllPath

if ($gameplayHubText -notmatch 'service_hub_feature_coordinator\.gd') {
  throw 'Gameplay composition root must own the shared feature lifecycle coordinator'
}
if ($husbandryHubText -match 'service_hub_feature_coordinator\.gd') {
  throw 'Husbandry hub must reuse the Gameplay coordinator'
}
if ($ranchHubText -notmatch 'extends\s+"res://src/ui/husbandry_progression_service_hub\.gd"') {
  throw 'Ranch hub must preserve the husbandry inheritance entry point'
}
if ($ranchHubText -notmatch 'ranch_runtime_participant\.gd' -or $ranchHubText -notmatch 'ranch_runtime') {
  throw 'Ranch hub must register the ranch runtime participant'
}
foreach ($field in @('animal_attraction_service','animal_product_service','ranch_runtime_participant')) {
  if ($ranchHubText -notmatch "var\s+$field\s*:\s*Node") { throw "Ranch hub removed public field: $field" }
}
foreach ($ownedScript in @('FeatureCoordinatorScript','AttractionServiceScript','ProductServiceScript','ProductStateMigrationScript')) {
  if ($ranchHubText -match "const\s+$ownedScript") { throw "Ranch inheritance layer still directly owns runtime implementation: $ownedScript" }
}
foreach ($legacyLifecycle in @('_begin_world','attach_game','activate_gameplay','save_current','handle_world_start_failed','return_to_menu','get_character_snapshot','_exit_tree','_register_feature_participant')) {
  if ($ranchHubText -match "func\s+$legacyLifecycle\s*\(") { throw "Ranch hub must remain a thin registration layer: $legacyLifecycle" }
}

if ($runtimeHealthHubText -notmatch 'extends\s+"res://src/ui/ranch_progression_service_hub\.gd"') {
  throw 'Runtime health layer must inherit ranch without moving ranch ownership'
}
if ($runtimeHealthHubText -match 'service_hub_feature_coordinator\.gd' -or $runtimeHealthHubText -match 'ranch_runtime_participant\.gd') {
  throw 'Runtime health layer must not duplicate ranch lifecycle or coordinator ownership'
}
if ($runtimeHealthHubText -notmatch 'func\s+save_current\s*\(' -or $runtimeHealthHubText -notmatch 'super\.save_current') {
  throw 'Runtime health layer must observe the complete inherited save transaction'
}
if ($explorationHubText -notmatch 'extends\s+"res://src/ui/runtime_health_service_hub\.gd"') {
  throw 'Exploration public entry must preserve ranch through the runtime health layer'
}
if ($explorationHubText -match 'service_hub_feature_coordinator\.gd') {
  throw 'Exploration hub must reuse the coordinator inherited from Gameplay'
}
foreach ($legacyLifecycle in @('_begin_world','attach_game','activate_gameplay','save_current','handle_world_start_failed','return_to_menu','_exit_tree')) {
  if ($explorationHubText -match "func\s+$legacyLifecycle\s*\(") { throw "Exploration hub still duplicates shared lifecycle forwarding: $legacyLifecycle" }
}

foreach ($method in @('get_dependencies','install','normalize_world_state','begin_world','attach_game','activate','save_into','snapshot_into','clear','shutdown','get_lifecycle_snapshot','get_attraction_service','get_product_service')) {
  if ($participantText -notmatch "func\s+$method\s*\(") { throw "Ranch runtime participant is missing method: $method" }
}
if ($participantText -notmatch 'return\s+\[&"husbandry_runtime"\]') {
  throw 'Ranch runtime must explicitly depend on husbandry runtime'
}
foreach ($servicePath in @('animal_attraction_service\.gd','animal_product_service\.gd','animal_product_state_migration\.gd','ranch_notification_policy\.gd')) {
  if ($participantText -notmatch $servicePath) { throw "Ranch runtime participant must own dependency: $servicePath" }
}
if ($participantText -notmatch 'payload\["animal_products"\]') {
  throw 'Ranch participant must contribute animal product state to the shared save payload'
}
if ($participantText -notmatch 'snapshot\["animal_attraction"\]' -or $participantText -notmatch 'snapshot\["animal_products"\]') {
  throw 'Ranch participant must preserve ranch diagnostics fields'
}
if ($participantText -notmatch 'call_deferred\("_flush_product_batch"\)') {
  throw 'Ranch product notifications must coalesce synchronous spawns before publishing'
}
foreach ($signalName in @('following_transition_announced','product_batch_announced')) {
  if ($participantText -notmatch $signalName) { throw "Ranch participant is missing acceptance signal: $signalName" }
}
if ($participantText -notmatch 'attach_player", null') {
  throw 'Ranch participant must explicitly release old player references during cleanup'
}
if ($participantText -notmatch 'set_product_service", null') {
  throw 'Ranch participant shutdown must release the interaction read model'
}
if ($participantText -notmatch 'product_audio_count' -or $participantText -notmatch 'product_batch_count') {
  throw 'Ranch lifecycle diagnostics must expose bounded batch notification evidence'
}

foreach ($method in @('following_transition','product_batch')) {
  if ($policyText -notmatch "static\s+func\s+$method\s*\(") { throw "Ranch notification policy is missing method: $method" }
}
if ($policyText -notmatch 'MAX_PRODUCT_TYPES_IN_MESSAGE\s*:=\s*3') {
  throw 'Ranch product summary must keep a bounded player-facing type list'
}

if ($attractionText -notmatch 'func\s+setup\([^)]*\)\s*->\s*bool' -or $attractionText -notmatch 'func\s+shutdown\s*\(') {
  throw 'Animal attraction service must expose validated setup and deterministic shutdown'
}
if ($productText -notmatch 'func\s+setup\(' -or $productText -notmatch '\)\s*->\s*bool:' -or $productText -notmatch 'func\s+shutdown\s*\(') {
  throw 'Animal product service must expose validated setup and deterministic shutdown'
}
if ($runAllText -notmatch 'ranch_runtime_lifecycle_regression\.gd') {
  throw 'Full regression entry point must include the ranch runtime lifecycle regression'
}

Write-Host 'PASS ranch_lifecycle root=gameplay participant=ranch_runtime dependency=husbandry_runtime chain=ranch->health->exploration health=read-only batch_types=3 public_fields=3'
