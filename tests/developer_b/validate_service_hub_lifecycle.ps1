$ErrorActionPreference = 'Stop'

$root = Resolve-Path "$PSScriptRoot\..\.."
$scenePath = Join-Path $root 'scenes\ui\service_hub.tscn'
$hubPath = Join-Path $root 'src\ui\exploration_progression_service_hub.gd'
$coordinatorPath = Join-Path $root 'src\core\service_hub_feature_coordinator.gd'
$runtimeParticipantPath = Join-Path $root 'src\exploration\exploration_runtime_participant.gd'
$journalParticipantPath = Join-Path $root 'src\exploration\exploration_journal_reward_participant.gd'
$runAllPath = Join-Path $root 'tests\run_all.ps1'

$sceneText = Get-Content -Raw -Encoding UTF8 $scenePath
$hubText = Get-Content -Raw -Encoding UTF8 $hubPath
$coordinatorText = Get-Content -Raw -Encoding UTF8 $coordinatorPath
$runtimeText = Get-Content -Raw -Encoding UTF8 $runtimeParticipantPath
$journalText = Get-Content -Raw -Encoding UTF8 $journalParticipantPath
$runAllText = Get-Content -Raw -Encoding UTF8 $runAllPath

if ($sceneText -notmatch 'exploration_progression_service_hub\.gd') {
  throw 'Production service_hub scene must retain the compatible exploration hub entry point'
}
if ($hubText -notmatch 'extends\s+"res://src/ui/ranch_progression_service_hub\.gd"') {
  throw 'Exploration hub must retain its current public inheritance entry point during incremental migration'
}
if ($hubText -notmatch 'service_hub_feature_coordinator\.gd') {
  throw 'Exploration hub must compose the feature lifecycle coordinator'
}
foreach ($participantPath in @('exploration_runtime_participant\.gd','exploration_journal_reward_participant\.gd')) {
  if ($hubText -notmatch $participantPath) { throw "Exploration hub must install participant: $participantPath" }
}
foreach ($featureId in @('exploration_runtime','exploration_journal_rewards')) {
  if ($hubText -notmatch $featureId) { throw "Exploration hub is missing feature id: $featureId" }
}
if ($hubText -notmatch 'register_participant') {
  throw 'Exploration hub must register feature participants through the coordinator'
}
foreach ($legacyField in @('prospecting_service','exploration_danger_service','exploration_journal_service','exploration_reward_service')) {
  if ($hubText -notmatch "var\s+$legacyField\s*:\s*Node") {
    throw "Exploration hub removed compatible public field: $legacyField"
  }
}
foreach ($ownedScript in @('ProspectingServiceScript','DangerServiceScript','ProspectingStateMigrationScript')) {
  if ($hubText -match "const\s+$ownedScript") { throw "Exploration Hub still directly owns runtime implementation: $ownedScript" }
}
foreach ($legacyCallback in @('_on_prospecting_completed','_on_prospecting_rejected','_on_exploration_danger_changed','_clear_exploration_runtime')) {
  if ($hubText -match "func\s+$legacyCallback") { throw "Exploration runtime responsibility remains in Hub: $legacyCallback" }
}

foreach ($method in @('register_participant','get_participant_dependencies','begin_world','attach_game','activate','save_into','snapshot_into','clear','shutdown','get_snapshot')) {
  if ($coordinatorText -notmatch "func\s+$method\s*\(") {
    throw "Feature lifecycle coordinator is missing method: $method"
  }
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
if ($coordinatorText -notmatch 'participant_dependencies') {
  throw 'Coordinator diagnostics must expose participant dependencies'
}

foreach ($method in @('get_dependencies','install','begin_world','attach_game','activate','save_into','snapshot_into','clear','shutdown','get_lifecycle_snapshot')) {
  if ($runtimeText -notmatch "func\s+$method\s*\(") {
    throw "Exploration runtime participant is missing method: $method"
  }
}
foreach ($servicePath in @('prospecting_service\.gd','exploration_danger_service\.gd')) {
  if ($runtimeText -notmatch $servicePath) { throw "Runtime participant must own service: $servicePath" }
}
if ($runtimeText -notmatch 'payload\["exploration"\]') {
  throw 'Runtime participant must contribute exploration state to the shared save payload'
}
if ($runtimeText -notmatch 'snapshot\["exploration"\]' -or $runtimeText -notmatch 'snapshot\["danger"\]') {
  throw 'Runtime participant must preserve legacy exploration and danger diagnostics'
}
if ($runtimeText -notmatch 'bind_prospecting_service", null') {
  throw 'Runtime participant must explicitly unbind the old player during cleanup'
}
if ($runtimeText -notmatch 'phase_changed' -or $runtimeText -notmatch 'ecology_changed') {
  throw 'Danger must refresh immediately after phase and ecology changes'
}
if ($runtimeText -notmatch '区域危险已缓解') {
  throw 'Danger recovery must provide player-facing closure'
}
if ($runtimeText -notmatch 'immediate_refresh_count' -or $runtimeText -notmatch 'danger_recovery_count') {
  throw 'Runtime lifecycle diagnostics must expose immediate refresh and recovery counts'
}

foreach ($method in @('get_dependencies','install','begin_world','attach_game','activate','save_into','snapshot_into','clear','shutdown','get_lifecycle_snapshot')) {
  if ($journalText -notmatch "func\s+$method\s*\(") {
    throw "Exploration journal/reward participant is missing method: $method"
  }
}
if ($journalText -notmatch 'return\s+\[&"exploration_runtime"\]') {
  throw 'Journal/reward participant must declare its exploration runtime dependency'
}
if ($journalText -notmatch 'claimable_reward_announced' -or $journalText -notmatch '按 J 查看') {
  throw 'Journal participant must preserve the single player-facing reward notice'
}
if ($journalText -notmatch 'payload\["exploration_rewards"\]') {
  throw 'Journal participant must contribute reward state to the shared save payload'
}

if ($runAllText -notmatch 'service_hub_feature_lifecycle_regression\.gd') {
  throw 'Full regression entry point must include the service hub lifecycle regression'
}

Write-Host 'PASS service_hub_lifecycle participants=2 dependency=journal->runtime history=48 public_fields=4'
