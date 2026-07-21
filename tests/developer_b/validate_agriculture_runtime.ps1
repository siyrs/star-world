$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = Resolve-Path "$PSScriptRoot\..\.."
$paths = @{
  Participant = Join-Path $root 'src\agriculture\agriculture_runtime_participant.gd'
  Service = Join-Path $root 'src\agriculture\fertilizable_agriculture_service.gd'
  Migration = Join-Path $root 'src\agriculture\agriculture_state_migration.gd'
  Notification = Join-Path $root 'src\agriculture\agriculture_notification_policy.gd'
  CharacterHub = Join-Path $root 'src\ui\character_progression_service_hub.gd'
  Interaction = Join-Path $root 'src\agriculture\agriculture_interaction_adapter.gd'
  Regression = Join-Path $root 'tests\qa\agriculture_runtime_lifecycle_regression.gd'
  Desktop = Join-Path $root 'tests\qa\agriculture_runtime_desktop_acceptance.gd'
  Workflow = Join-Path $root '.github\workflows\agriculture-runtime-tests.yml'
  RunAll = Join-Path $root 'tests\run_all.ps1'
}
foreach ($entry in $paths.GetEnumerator()) {
  if (-not (Test-Path -LiteralPath $entry.Value)) {
    throw "Agriculture runtime file is missing: $($entry.Key) $($entry.Value)"
  }
}
$text = @{}
foreach ($entry in $paths.GetEnumerator()) {
  $text[$entry.Key] = Get-Content -Raw -Encoding UTF8 $entry.Value
}

foreach ($method in @('get_dependencies','install','normalize_world_state','begin_world','attach_game','activate','save_into','snapshot_into','clear','shutdown','get_lifecycle_snapshot')) {
  if ($text.Participant -notmatch "func\s+$method\s*\(") {
    throw "Agriculture participant is missing lifecycle method: $method"
  }
}
if ($text.Participant -notmatch 'MAX_PENDING_MATURITY_EVENTS\s*:=\s*64' -or $text.Participant -notmatch 'call_deferred\("_flush_maturity_batch"\)') {
  throw 'Agriculture maturity feedback must remain bounded and frame-batched'
}
if ($text.Participant -notmatch 'payload\["agriculture"\]' -or $text.Participant -notmatch 'snapshot\["agriculture"\]') {
  throw 'Agriculture participant must own persistence and runtime diagnostics'
}
if ($text.Participant -notmatch 'register_extension' -or $text.Participant -notmatch 'unregister_extension') {
  throw 'Agriculture participant must own interaction registration and cleanup'
}

if ($text.Service -notmatch 'PROCESS_MODE_PAUSABLE') {
  throw 'Production agriculture must explicitly pause even under the always-processing ServiceHub'
}
foreach ($method in @('activate','deactivate','shutdown','get_runtime_snapshot')) {
  if ($text.Service -notmatch "func\s+$method\s*\(") {
    throw "Production agriculture service is missing runtime method: $method"
  }
}
if ($text.Service -notmatch 'can_transact_items' -or $text.Service -notmatch 'transact_items') {
  throw 'Mature harvest must use the shared atomic inventory transaction contract'
}
if ($text.Service -match 'func\s+_can_store_outputs\s*\(' -or $text.Service -match 'remove_item.*granted') {
  throw 'Production agriculture must not duplicate capacity planning or perform item-by-item rollback'
}

if ($text.Migration -notmatch 'MAX_CROP_RECORDS\s*:=\s*4096' -or $text.Migration -notmatch 'MAX_SOIL_RECORDS\s*:=\s*4096') {
  throw 'Agriculture migration must cap crop and soil records at 4096'
}
if ($text.Migration -notmatch 'MAX_ELAPSED_SECONDS\s*:=\s*6\.0\s*\*\s*60\.0\s*\*\s*60\.0') {
  throw 'Agriculture elapsed state must retain the six-hour hard limit'
}
if ($text.Notification -notmatch 'MAX_VISIBLE_CROP_TYPES\s*:=\s*3') {
  throw 'Maturity summaries must bound visible crop types'
}

if ($text.CharacterHub -notmatch 'agriculture_runtime_participant\.gd' -or $text.CharacterHub -notmatch 'AGRICULTURE_RUNTIME_FEATURE') {
  throw 'Character composition must install the agriculture runtime participant'
}
if ($text.CharacterHub -match 'FertilizableAgricultureService' -or $text.CharacterHub -match 'AgricultureInteractionAdapterScript') {
  throw 'Character inheritance must not directly construct agriculture runtime implementations'
}
if ($text.CharacterHub -match 'current_state\["agriculture"\]' -or $text.CharacterHub -match 'agriculture_service\.call\("deserialize"') {
  throw 'Character inheritance must not duplicate agriculture save or begin-world ownership'
}
if ($text.CharacterHub -match 'register_extension", agriculture_interaction' -or $text.CharacterHub -match 'unregister_extension", agriculture_interaction') {
  throw 'Character inheritance must not duplicate agriculture interaction lifecycle ownership'
}

foreach ($script in @('agriculture_runtime_lifecycle_regression.gd','agriculture_runtime_desktop_acceptance.gd')) {
  if ($text.Workflow -notmatch [regex]::Escape($script)) {
    throw "Agriculture runtime workflow is missing test: $script"
  }
}
if ($text.RunAll -notmatch 'validate_agriculture_runtime.ps1' -or $text.RunAll -notmatch 'agriculture_runtime_lifecycle_regression.gd') {
  throw 'Agriculture runtime tests must be wired into tests/run_all.ps1'
}

Write-Host 'PASS agriculture_runtime participant=1 crops=4096 soils=4096 offline_hours=6 maturity_batch=64 visible_types=3 pausable=1 atomic_harvest=1'
