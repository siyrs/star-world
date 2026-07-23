$ErrorActionPreference = 'Stop'

$root = Resolve-Path "$PSScriptRoot\..\.."
$scenePath = Join-Path $root 'scenes\ui\service_hub.tscn'
$gameplayHubPath = Join-Path $root 'src\ui\service_hub.gd'
$toolHubPath = Join-Path $root 'src\ui\tool_progression_service_hub.gd'
$characterHubPath = Join-Path $root 'src\ui\character_progression_service_hub.gd'
$husbandryHubPath = Join-Path $root 'src\ui\husbandry_progression_service_hub.gd'
$ranchHubPath = Join-Path $root 'src\ui\ranch_progression_service_hub.gd'
$runtimeHealthHubPath = Join-Path $root 'src\ui\runtime_health_service_hub.gd'
$explorationHubPath = Join-Path $root 'src\ui\exploration_progression_service_hub.gd'
$coordinatorPath = Join-Path $root 'src\core\service_hub_feature_coordinator.gd'
$machineParticipantPath = Join-Path $root 'src\machine\machine_runtime_participant.gd'
$machineSchedulerPath = Join-Path $root 'src\machine\machine_runtime_scheduler.gd'
$agricultureParticipantPath = Join-Path $root 'src\agriculture\agriculture_runtime_participant.gd'
$husbandryParticipantPath = Join-Path $root 'src\husbandry\husbandry_runtime_participant.gd'
$ranchParticipantPath = Join-Path $root 'src\husbandry\ranch_runtime_participant.gd'
$runtimeParticipantPath = Join-Path $root 'src\exploration\exploration_runtime_participant.gd'
$journalParticipantPath = Join-Path $root 'src\exploration\exploration_journal_reward_participant.gd'
$doorServicePath = Join-Path $root 'src\interaction\block_door_interaction_service.gd'
$runAllPath = Join-Path $root 'tests\run_all.ps1'

foreach ($path in @(
  $scenePath,$gameplayHubPath,$toolHubPath,$characterHubPath,$husbandryHubPath,
  $ranchHubPath,$runtimeHealthHubPath,$explorationHubPath,$coordinatorPath,
  $machineParticipantPath,$machineSchedulerPath,$agricultureParticipantPath,
  $husbandryParticipantPath,$ranchParticipantPath,$runtimeParticipantPath,
  $journalParticipantPath,$doorServicePath,$runAllPath
)) {
  if (-not (Test-Path -LiteralPath $path)) { throw "Lifecycle file is missing: $path" }
}

$sceneText = Get-Content -Raw -Encoding UTF8 $scenePath
$gameplayHubText = Get-Content -Raw -Encoding UTF8 $gameplayHubPath
$toolHubText = Get-Content -Raw -Encoding UTF8 $toolHubPath
$characterHubText = Get-Content -Raw -Encoding UTF8 $characterHubPath
$husbandryHubText = Get-Content -Raw -Encoding UTF8 $husbandryHubPath
$ranchHubText = Get-Content -Raw -Encoding UTF8 $ranchHubPath
$runtimeHealthHubText = Get-Content -Raw -Encoding UTF8 $runtimeHealthHubPath
$explorationHubText = Get-Content -Raw -Encoding UTF8 $explorationHubPath
$coordinatorText = Get-Content -Raw -Encoding UTF8 $coordinatorPath
$machineText = Get-Content -Raw -Encoding UTF8 $machineParticipantPath
$schedulerText = Get-Content -Raw -Encoding UTF8 $machineSchedulerPath
$agricultureText = Get-Content -Raw -Encoding UTF8 $agricultureParticipantPath
$husbandryText = Get-Content -Raw -Encoding UTF8 $husbandryParticipantPath
$ranchText = Get-Content -Raw -Encoding UTF8 $ranchParticipantPath
$runtimeText = Get-Content -Raw -Encoding UTF8 $runtimeParticipantPath
$journalText = Get-Content -Raw -Encoding UTF8 $journalParticipantPath
$doorText = Get-Content -Raw -Encoding UTF8 $doorServicePath
$runAllText = Get-Content -Raw -Encoding UTF8 $runAllPath

if ($sceneText -notmatch 'exploration_progression_service_hub\.gd') {
  throw 'Production service_hub scene must retain the compatible exploration hub entry point'
}
if ($gameplayHubText -notmatch 'service_hub_feature_coordinator\.gd' -or $gameplayHubText -notmatch 'machine_runtime_participant\.gd') {
  throw 'Gameplay composition root must own the shared coordinator and machine runtime participant'
}
if ($husbandryHubText -match 'service_hub_feature_coordinator\.gd') {
  throw 'Husbandry hub must reuse the coordinator inherited from Gameplay'
}
if ($ranchHubText -notmatch 'extends\s+"res://src/ui/husbandry_progression_service_hub\.gd"') {
  throw 'Ranch hub must retain its current public inheritance entry point'
}
if ($runtimeHealthHubText -notmatch 'extends\s+"res://src/ui/ranch_progression_service_hub\.gd"') {
  throw 'Runtime health hub must insert below exploration and above ranch'
}
if ($explorationHubText -notmatch 'extends\s+"res://src/ui/runtime_health_service_hub\.gd"') {
  throw 'Exploration hub must retain its public scene entry while inheriting runtime health'
}
if ($toolHubText -notmatch 'func\s+_exit_tree\s*\([\s\S]{0,700}super\._exit_tree') {
  throw 'Tool hub must propagate deterministic shutdown to the Gameplay composition root'
}
if ($toolHubText -notmatch 'unregister_extension",\s*door_interaction_service' -or $toolHubText -notmatch 'door_interaction_service\.call\("shutdown"\)') {
  throw 'Tool hub must unregister and shut down the door structure service before propagating exit'
}
foreach ($method in @('try_place_block','try_interact','remove_block_structure','clear','shutdown')) {
  if ($doorText -notmatch "func\s+$method\s*\(") { throw "Door structure service is missing deterministic lifecycle method: $method" }
}
$combinedHubs = $gameplayHubText + "`n" + $characterHubText + "`n" + $husbandryHubText + "`n" + $ranchHubText + "`n" + $runtimeHealthHubText + "`n" + $explorationHubText
foreach ($participantPath in @(
  'machine_runtime_participant\.gd',
  'agriculture_runtime_participant\.gd',
  'husbandry_runtime_participant\.gd',
  'ranch_runtime_participant\.gd',
  'exploration_runtime_participant\.gd',
  'exploration_journal_reward_participant\.gd'
)) {
  if ($combinedHubs -notmatch $participantPath) { throw "Production composition must install participant: $participantPath" }
}
foreach ($featureId in @(
  'machine_runtime','agriculture_runtime','husbandry_runtime','ranch_runtime',
  'exploration_runtime','exploration_journal_rewards'
)) {
  if ($combinedHubs -notmatch $featureId) { throw "Production composition is missing feature id: $featureId" }
}
foreach ($legacyField in @('machine_runtime','machine_runtime_participant')) {
  if ($gameplayHubText -notmatch "var\s+$legacyField\s*:\s*Node") { throw "Gameplay hub removed machine runtime field: $legacyField" }
}
foreach ($legacyField in @('stonecutter_service','machine_interaction_router','machine_automation_service','door_interaction_service')) {
  if ($toolHubText -notmatch "var\s+$legacyField\s*:\s*Node") { throw "Tool hub removed compatible runtime field: $legacyField" }
}
foreach ($legacyField in @('agriculture_service','agriculture_interaction','agriculture_runtime_participant')) {
  if ($characterHubText -notmatch "var\s+$legacyField\s*:\s*Node") { throw "Character hub removed compatible agriculture field: $legacyField" }
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
if ($runtimeHealthHubText -notmatch 'var\s+runtime_health_report_service\s*:\s*Node') {
  throw 'Runtime health hub must expose the stable read-only report service port'
}
foreach ($ownedScript in @(
  'FertilizableAgricultureService','AgricultureInteractionAdapterScript',
  'HusbandryServiceScript','HusbandryInteractionScript','AttractionServiceScript',
  'ProductServiceScript','ProspectingServiceScript','DangerServiceScript',
  'ProspectingStateMigrationScript'
)) {
  if ($combinedHubs -match "const\s+$ownedScript") { throw "Inheritance layer still directly owns runtime implementation: $ownedScript" }
}
if ($characterHubText -match 'current_state\["agriculture"\]' -or $characterHubText -match 'agriculture_service\.call\("deserialize"') {
  throw 'Character inheritance must not duplicate agriculture persistence or begin-world ownership'
}
if ($husbandryHubText -match 'FeatureCoordinatorScript' -or $ranchHubText -match 'FeatureCoordinatorScript' -or $runtimeHealthHubText -match 'FeatureCoordinatorScript' -or $explorationHubText -match 'FeatureCoordinatorScript') {
  throw 'Coordinator ownership must remain at the Gameplay composition root'
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

foreach ($participant in @(
  @{Name='Machine'; Text=$machineText},
  @{Name='Agriculture'; Text=$agricultureText},
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

if ($machineText -notmatch 'payload\["machines"\]' -or $machineText -notmatch 'snapshot\["machine_runtime"\]') {
  throw 'Machine participant must own machine persistence and diagnostics'
}
if ($machineText -notmatch 'MAX_PENDING_COMPLETIONS\s*:=\s*128' -or $machineText -notmatch 'call_deferred\("_flush_completion_batch"\)') {
  throw 'Machine completion feedback must remain bounded and frame-batched'
}
if ($schedulerText -notmatch 'MAX_DOMAINS\s*:=\s*16' -or $schedulerText -notmatch 'advance_machine_runtime') {
  throw 'Machine scheduler must retain a bounded shared-domain contract'
}
if ($agricultureText -notmatch 'payload\["agriculture"\]' -or $agricultureText -notmatch 'snapshot\["agriculture"\]') {
  throw 'Agriculture participant must preserve save and diagnostics contracts'
}
if ($agricultureText -notmatch 'MAX_PENDING_MATURITY_EVENTS\s*:=\s*64') {
  throw 'Agriculture maturity feedback must remain bounded'
}
if ($husbandryText -notmatch 'payload\["husbandry"\]' -or $husbandryText -notmatch 'snapshot\["husbandry"\]') {
  throw 'Husbandry participant must preserve save and diagnostics contracts'
}
if ($ranchText -notmatch 'return\s+\[&"husbandry_runtime"\]') {
  throw 'Ranch runtime must declare its husbandry dependency'
}
if ($runtimeText -notmatch 'payload\["exploration"\]' -or $runtimeText -notmatch 'snapshot\["danger"\]') {
  throw 'Exploration runtime participant must preserve save and diagnostics contracts'
}
if ($journalText -notmatch 'return\s+\[&"exploration_runtime"\]') {
  throw 'Journal/reward participant must declare its exploration dependency'
}

foreach ($scriptName in @(
  'machine_base_regression\.gd','agriculture_runtime_lifecycle_regression\.gd',
  'service_hub_feature_lifecycle_regression\.gd','husbandry_runtime_lifecycle_regression\.gd',
  'ranch_runtime_lifecycle_regression\.gd','double_door_regression\.gd'
)) {
  if ($runAllText -notmatch $scriptName) { throw "Full regression entry point must include: $scriptName" }
}

Write-Host 'PASS service_hub_lifecycle participants=6 root=gameplay health=readonly entry=exploration chain=ranch->health->exploration dependencies=ranch->husbandry,journal->exploration history=48 machine_domains=16'
