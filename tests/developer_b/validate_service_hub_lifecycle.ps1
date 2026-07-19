$ErrorActionPreference = 'Stop'

$root = Resolve-Path "$PSScriptRoot\..\.."
$scenePath = Join-Path $root 'scenes\ui\service_hub.tscn'
$husbandryHubPath = Join-Path $root 'src\ui\husbandry_progression_service_hub.gd'
$ranchHubPath = Join-Path $root 'src\ui\ranch_progression_service_hub.gd'
$explorationHubPath = Join-Path $root 'src\ui\exploration_progression_service_hub.gd'
$coordinatorPath = Join-Path $root 'src\core\service_hub_feature_coordinator.gd'
$husbandryParticipantPath = Join-Path $root 'src\husbandry\husbandry_runtime_participant.gd'
$ranchParticipantPath = Join-Path $root 'src\husbandry\ranch_runtime_participant.gd'
$runtimeParticipantPath = Join-Path $root 'src\exploration\exploration_runtime_participant.gd'
$journalParticipantPath = Join-Path $root 'src\exploration\exploration_journal_reward_participant.gd'
$runAllPath = Join-Path $root 'tests\run_all.ps1'

$sceneText = Get-Content -Raw -Encoding UTF8 $scenePath
$husbandryHubText = Get-Content -Raw -Encoding UTF8 $husbandryHubPath
$ranchHubText = Get-Content -Raw -Encoding UTF8 $ranchHubPath
$explorationHubText = Get-Content -Raw -Encoding UTF8 $explorationHubPath
$coordinatorText = Get-Content -Raw -Encoding UTF8 $coordinatorPath
$husbandryText = Get-Content -Raw -Encoding UTF8 $husbandryParticipantPath
$ranchText = Get-Content -Raw -Encoding UTF8 $ranchParticipantPath
$runtimeText = Get-Content -Raw -Encoding UTF8 $runtimeParticipantPath
$journalText = Get-Content -Raw -Encoding UTF8 $journalParticipantPath
$runAllText = Get-Content -Raw -Encoding UTF8 $runAllPath

if ($sceneText -notmatch 'exploration_progression_service_hub\.gd') {
  throw 'Production service_hub scene must retain the compatible exploration hub entry point'
}
if ($husbandryHubText -notmatch 'service_hub_feature_coordinator\.gd') {
  throw 'Husbandry composition root must install the shared feature lifecycle coordinator'
}
if ($ranchHubText -notmatch 'extends\s+"res://src/ui/husbandry_progression_service_hub\.gd"') {
  throw 'Ranch hub must retain its current public inheritance entry point'
}
if ($explorationHubText -notmatch 'extends\s+"res://src/ui/ranch_progression_service_hub\.gd"') {
  throw 'Exploration hub must retain its current public inheritance entry point'
}
$combinedHubs = $husbandryHubText + "`n" + $ranchHubText + "`n" + $explorationHubText
foreach ($participantPath in @('husbandry_runtime_participant\.gd','ranch_runtime_participant\.gd','exploration_runtime_participant\.gd','exploration_journal_reward_participant\.gd')) {
  if ($combinedHubs -notmatch $participantPath) { throw "Production composition must install participant: $participantPath" }
}
foreach ($featureId in @('husbandry_runtime','ranch_runtime','exploration_runtime','exploration_journal_rewards')) {
  if ($combinedHubs -notmatch $featureId) { throw "Production composition is missing feature id: $featureId" }
}
foreach ($legacyField in @('husbandry_service','husbandry_interaction')) {
  if ($husbandryHubText -notmatch "var\s+$legacyField\s*:\s*Node") { throw "Husbandry hub removed compatible public field: $legacyField" }
}
foreach ($legacyField in @('animal_attraction_service','animal_product_service')) {
  if ($ranchHubText -notmatch "var\s+$legacyField\s*:\s*Node") { throw "Ranch hub removed compatible public field: $legacyField" }
}
foreach ($legacyField in @('prospecting_service','exploration_danger_service','exploration_journal_service','exploration_reward_service')) {
  if ($explorationHubText -notmatch "var\s+$legacyField\s*:\s*Node") { throw "Exploration hub removed compatible public field: $legacyField" }
}
foreach ($ownedScript in @('HusbandryServiceScript','HusbandryInteractionScript','AttractionServiceScript','ProductServiceScript','ProspectingServiceScript','DangerServiceScript','ProspectingStateMigrationScript')) {
  if ($combinedHubs -match "const\s+$ownedScript") { throw "Inheritance layer still directly owns runtime implementation: $ownedScript" }
}
if ($ranchHubText -match 'FeatureCoordinatorScript' -or $explorationHubText -match 'FeatureCoordinatorScript') {
  throw 'Coordinator ownership must remain at the earliest migrated husbandry composition root'
}

foreach ($method in @('register_participant','get_participant_dependencies','normalize_world_state','begin_world','attach_game','activate','save_into','snapshot_into','clear','shutdown','get_snapshot')) {
  if ($coordinatorText -notmatch "func\s+$method\s*\(") { throw "Feature lifecycle coordinator is missing method: $method" }
}
if ($coordinatorText -notmatch 'MAX_PHASE_HISTORY\s*:=\s*48') {
  throw 'Feature lifecycle diagnostic history must remain bounded'
}
if ($coordinatorText -notmatch '_invoke_reverse\("clear"' -or $coordinatorText -notmatch '_invoke_reverse\("shutdown"') {
  throw 'Feature clear and shutdown must run in reverse dependency order'
}
foreach ($reason in @('duplicate_participant','participant_contract','participant_dependency_missing','participant_dependency_cycle')) {
  if ($coordinatorText -notmatch $reason) { throw "Coordinator must expose lifecycle rejection: $reason" }
}
if ($coordinatorText -notmatch 'participant_dependencies' -or $coordinatorText -notmatch '_record_phase\("normalize_world_state"') {
  throw 'Coordinator diagnostics must expose dependencies and ordered normalization'
}

foreach ($participant in @(
  @{Name='Husbandry'; Text=$husbandryText},
  @{Name='Ranch'; Text=$ranchText},
  @{Name='Exploration'; Text=$runtimeText}
)) {
  foreach ($method in @('get_dependencies','install','normalize_world_state','begin_world','attach_game','activate','save_into','snapshot_into','clear','shutdown','get_lifecycle_snapshot')) {
    if ($participant.Text -notmatch "func\s+$method\s*\(") { throw "$($participant.Name) runtime participant is missing method: $method" }
  }
}
foreach ($method in @('get_dependencies','install','begin_world','attach_game','activate','save_into','snapshot_into','clear','shutdown','get_lifecycle_snapshot')) {
  if ($journalText -notmatch "func\s+$method\s*\(") { throw "Exploration journal/reward participant is missing method: $method" }
}

if ($husbandryText -notmatch 'payload\["husbandry"\]' -or $husbandryText -notmatch 'snapshot\["husbandry"\]') {
  throw 'Husbandry participant must preserve save and diagnostics contracts'
}
if ($husbandryText -notmatch 'bind_entity_interaction_service", null') {
  throw 'Husbandry participant must explicitly unbind the old player during cleanup'
}
if ($ranchText -notmatch 'return\s+\[&"husbandry_runtime"\]') {
  throw 'Ranch runtime must declare its husbandry dependency'
}
if ($ranchText -notmatch 'payload\["animal_products"\]' -or $ranchText -notmatch 'snapshot\["animal_attraction"\]' -or $ranchText -notmatch 'snapshot\["animal_products"\]') {
  throw 'Ranch participant must preserve save and diagnostics contracts'
}
if ($runtimeText -notmatch 'payload\["exploration"\]' -or $runtimeText -notmatch 'snapshot\["exploration"\]' -or $runtimeText -notmatch 'snapshot\["danger"\]') {
  throw 'Exploration runtime participant must preserve save and diagnostics contracts'
}
if ($runtimeText -notmatch 'bind_prospecting_service", null') {
  throw 'Exploration runtime participant must explicitly unbind the old player during cleanup'
}
if ($runtimeText -notmatch 'phase_changed' -or $runtimeText -notmatch 'ecology_changed' -or $runtimeText -notmatch '区域危险已缓解') {
  throw 'Exploration runtime must preserve immediate danger and recovery feedback'
}
if ($journalText -notmatch 'return\s+\[&"exploration_runtime"\]') {
  throw 'Journal/reward participant must declare its exploration runtime dependency'
}
if ($journalText -notmatch 'payload\["exploration_rewards"\]' -or $journalText -notmatch 'claimable_reward_announced') {
  throw 'Journal participant must preserve reward persistence and notice contracts'
}

foreach ($scriptName in @('service_hub_feature_lifecycle_regression\.gd','husbandry_runtime_lifecycle_regression\.gd','ranch_runtime_lifecycle_regression\.gd')) {
  if ($runAllText -notmatch $scriptName) { throw "Full regression entry point must include: $scriptName" }
}

Write-Host 'PASS service_hub_lifecycle participants=4 dependencies=ranch->husbandry,journal->exploration normalization=ordered history=48 public_fields=8'
