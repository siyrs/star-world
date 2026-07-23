$ErrorActionPreference = 'Stop'

$root = Resolve-Path "$PSScriptRoot\..\.."
$participantPath = Join-Path $root 'src\exploration\exploration_runtime_participant.gd'
$batchPolicyPath = Join-Path $root 'src\exploration\danger_refresh_batch_policy.gd'
$dangerServicePath = Join-Path $root 'src\exploration\exploration_danger_service.gd'
$dangerPolicyPath = Join-Path $root 'src\exploration\exploration_danger_policy.gd'
$spawnerPath = Join-Path $root 'src\entity\creature_spawner.gd'
$hudPath = Join-Path $root 'src\ui\hud.gd'
$dangerDataPath = Join-Path $root 'data\exploration_danger.json'
$runAllPath = Join-Path $root 'tests\run_all.ps1'
$workflowPath = Join-Path $root '.github\workflows\multi-hostile-danger-tests.yml'
$desktopBasePath = Join-Path $root 'tests\qa\multi_hostile_danger_desktop_acceptance.gd'
$desktopBatchedPath = Join-Path $root 'tests\qa\multi_hostile_danger_batched_desktop_acceptance.gd'

$participantText = Get-Content -Raw -Encoding UTF8 $participantPath
$batchPolicyText = Get-Content -Raw -Encoding UTF8 $batchPolicyPath
$dangerServiceText = Get-Content -Raw -Encoding UTF8 $dangerServicePath
$dangerPolicyText = Get-Content -Raw -Encoding UTF8 $dangerPolicyPath
$spawnerText = Get-Content -Raw -Encoding UTF8 $spawnerPath
$hudText = Get-Content -Raw -Encoding UTF8 $hudPath
$runAllText = Get-Content -Raw -Encoding UTF8 $runAllPath
$dangerData = Get-Content -Raw -Encoding UTF8 $dangerDataPath | ConvertFrom-Json

foreach ($path in @($workflowPath,$desktopBasePath,$desktopBatchedPath)) {
  if (-not (Test-Path -LiteralPath $path)) { throw "Multi-hostile danger contract file is missing: $path" }
}
$workflowText = Get-Content -Raw -Encoding UTF8 $workflowPath
$desktopBatchedText = Get-Content -Raw -Encoding UTF8 $desktopBatchedPath

if ($batchPolicyText -notmatch 'MAX_VISIBLE_TRIGGERS\s*:=\s*4') {
  throw 'Danger refresh batch policy must bound visible trigger diagnostics to four'
}
foreach ($trigger in @('threat_changed','ecology_changed','phase_changed')) {
  if ($batchPolicyText -notmatch $trigger) { throw "Danger refresh batch policy is missing trigger priority: $trigger" }
}
if ($batchPolicyText -notmatch 'coalesced_event_count' -or $batchPolicyText -notmatch 'dropped_event_count') {
  throw 'Danger refresh batch policy must preserve coalesced and dropped event diagnostics'
}

if ($participantText -notmatch 'MAX_PENDING_DANGER_EVENTS\s*:=\s*64') {
  throw 'Immediate danger event queue must remain hard-capped at 64'
}
if ($participantText -notmatch 'call_deferred\("_flush_danger_refresh_batch"\)') {
  throw 'Immediate danger events must be coalesced at the frame boundary'
}
if ($participantText -notmatch 'signal\s+danger_refresh_batch_completed') {
  throw 'Runtime participant must expose a structured danger refresh batch signal'
}
if ($participantText -notmatch '"threat_changed"' -or $participantText -notmatch '_on_threat_changed') {
  throw 'Runtime participant must consume hostile attack state transitions'
}
if ($participantText -notmatch 'refresh_for_events' -or $participantText -notmatch 'immediate_event_count' -or $participantText -notmatch 'coalesced_danger_event_count') {
  throw 'Runtime participant must distinguish raw events, actual assessments and coalesced work'
}
if ($participantText -match 'func\s+_on_ecology_changed[\s\S]{0,220}refresh_now') {
  throw 'Ecology signal handlers must not perform an immediate full assessment directly'
}

if ($dangerServiceText -notmatch 'func\s+refresh_for_events\s*\(') {
  throw 'Danger service must expose the event-aware cached assessment path'
}
foreach ($diagnostic in @('environment_scan_count','environment_reuse_count','assessment_count','max_samples_observed','last_reused_environment')) {
  if ($dangerServiceText -notmatch $diagnostic) { throw "Danger service is missing budget diagnostic: $diagnostic" }
}
if ($dangerServiceText -notmatch 'center\s*==\s*_cached_sample_center') {
  throw 'Environment samples may only be reused while the player remains in the same block'
}
if ([int]$dangerData.max_samples -ne 125) {
  throw "Production danger sample budget changed unexpectedly: $($dangerData.max_samples)"
}

if ($spawnerText -notmatch 'signal\s+threat_changed') {
  throw 'Creature spawner must publish aggregate threat invalidation events'
}
if ($spawnerText -notmatch 'MAX_HOSTILE_QUERY_NODES\s*:=\s*64') {
  throw 'Hostile windup query must remain bounded to 64 visited nodes'
}
foreach ($contract in @('get_nearby_hostile_windup_summary','attack_state_changed','tree_exiting','creature_died','soonest_impact_seconds','elite_windup_count')) {
  if ($spawnerText -notmatch $contract) { throw "Spawner windup and death telemetry is missing: $contract" }
}
if ($spawnerText -match 'windup_positions|attacker_positions|coordinates') {
  throw 'Windup telemetry must not expose attacker coordinates'
}
if ($spawnerText -notmatch 'func\s+clear_creature_population[\s\S]{0,420}is_in_group\("creatures"\)') {
  throw 'Drop-safe population clearing must filter actual creatures instead of deleting ItemPickup children'
}
if ($spawnerText -notmatch 'func\s+clear_creatures\s*\(') {
  throw 'Full world-lifecycle cleanup must retain its compatible clear_creatures entry point'
}
if ($spawnerText -notmatch '_is_live_hostile') {
  throw 'Danger queries must exclude defeated hostiles before their death tween exits the tree'
}

foreach ($field in @('windup_count','elite_windup_count','soonest_impact_seconds','windup_urgency_label')) {
  if ($dangerPolicyText -notmatch $field) { throw "Danger policy is missing incoming attack field: $field" }
}
if ($hudText -notmatch '_danger_warning' -or $hudText -notmatch 'get_danger_warning_text' -or $hudText -notmatch 'is_danger_warning_visible') {
  throw 'HUD must expose the aggregate incoming attack warning for acceptance tests'
}
if ($hudText -notmatch '来袭攻击') {
  throw 'Incoming attack warning must be player-readable'
}

if ($runAllText -notmatch 'multi_hostile_danger_batch_regression\.gd') {
  throw 'Full regression entry point must include the multi-hostile danger batch regression'
}
if ($workflowText -notmatch 'multi_hostile_danger_batch_regression\.gd') {
  throw 'Multi-hostile workflow is missing the danger batch regression'
}
if ($workflowText -notmatch 'multi_hostile_danger_batched_desktop_acceptance\.gd') {
  throw 'Multi-hostile workflow must run the optimized real desktop journey'
}
if ($desktopBatchedText -notmatch 'extends\s+"res://tests/qa/multi_hostile_danger_desktop_acceptance\.gd"') {
  throw 'Optimized desktop journey must preserve the original full acceptance through inheritance'
}

Write-Host 'PASS multi_hostile_danger pending=64 triggers=3 sample_budget=125 hostile_query=64 drops=preserved lifecycle=full-clear desktop=batched'
