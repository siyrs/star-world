$ErrorActionPreference = 'Stop'

$root = Resolve-Path "$PSScriptRoot\..\.."
$scenePath = Join-Path $root 'scenes\ui\service_hub.tscn'
$hubPath = Join-Path $root 'src\ui\exploration_progression_service_hub.gd'
$coordinatorPath = Join-Path $root 'src\core\service_hub_feature_coordinator.gd'
$participantPath = Join-Path $root 'src\exploration\exploration_journal_reward_participant.gd'
$runAllPath = Join-Path $root 'tests\run_all.ps1'

$sceneText = Get-Content -Raw -Encoding UTF8 $scenePath
$hubText = Get-Content -Raw -Encoding UTF8 $hubPath
$coordinatorText = Get-Content -Raw -Encoding UTF8 $coordinatorPath
$participantText = Get-Content -Raw -Encoding UTF8 $participantPath
$runAllText = Get-Content -Raw -Encoding UTF8 $runAllPath

if ($sceneText -notmatch 'exploration_progression_service_hub\.gd') {
  throw 'Production service_hub scene must retain the compatible exploration hub entry point'
}
if ($hubText -notmatch 'extends\s+"res://src/ui/ranch_progression_service_hub\.gd"') {
  throw 'Exploration hub must retain its current public inheritance entry point during incremental migration'
}
if ($hubText -notmatch 'ServiceHubFeatureCoordinator' -and $hubText -notmatch 'service_hub_feature_coordinator\.gd') {
  throw 'Exploration hub must compose the feature lifecycle coordinator'
}
if ($hubText -notmatch 'exploration_journal_reward_participant\.gd') {
  throw 'Exploration hub must install the journal/reward lifecycle participant'
}
if ($hubText -notmatch 'register_participant') {
  throw 'Exploration hub must register feature participants through the coordinator'
}
foreach ($legacyField in @('exploration_journal_service','exploration_reward_service')) {
  if ($hubText -notmatch "var\s+$legacyField\s*:\s*Node") {
    throw "Exploration hub removed compatible public field: $legacyField"
  }
}
if ($hubText -match 'const\s+JournalServiceScript' -or $hubText -match 'const\s+RewardServiceScript') {
  throw 'Exploration hub still directly owns journal/reward implementation scripts'
}
if ($hubText -match 'func\s+_on_exploration_reward_claimed' -or $hubText -match 'func\s+_on_exploration_reward_rejected') {
  throw 'Exploration reward feedback must live in the participant, not the inheritance layer'
}

foreach ($method in @('register_participant','begin_world','attach_game','activate','save_into','snapshot_into','clear','shutdown','get_snapshot')) {
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
if ($coordinatorText -notmatch 'duplicate_participant' -or $coordinatorText -notmatch 'participant_contract') {
  throw 'Coordinator must reject duplicate ids and incomplete participant contracts'
}

foreach ($method in @('install','begin_world','attach_game','activate','save_into','snapshot_into','clear','shutdown','get_lifecycle_snapshot')) {
  if ($participantText -notmatch "func\s+$method\s*\(") {
    throw "Exploration lifecycle participant is missing method: $method"
  }
}
if ($participantText -notmatch 'claimable_reward_announced') {
  throw 'Exploration lifecycle participant must expose the single-notice acceptance signal'
}
if ($participantText -notmatch '按 J 查看') {
  throw 'Newly claimable exploration rewards must tell the player how to open the journal'
}
if ($participantText -notmatch '_known_claimable' -or $participantText -notmatch '_sync_claimable_baseline') {
  throw 'Reward availability notices must establish a reload-safe baseline'
}
if ($participantText -notmatch 'payload\["exploration_rewards"\]') {
  throw 'Participant must contribute reward state to the save payload'
}
if ($participantText -notmatch 'snapshot\["exploration_journal"\]' -or $participantText -notmatch 'snapshot\["exploration_rewards"\]') {
  throw 'Participant must preserve legacy diagnostics snapshot fields'
}

if ($runAllText -notmatch 'service_hub_feature_lifecycle_regression\.gd') {
  throw 'Full regression entry point must include the service hub lifecycle regression'
}

Write-Host 'PASS service_hub_lifecycle participant=exploration_journal_rewards history=48 public_fields=2'
