$ErrorActionPreference = 'Stop'

$root = Resolve-Path "$PSScriptRoot\..\.."
$schedulerPath = Join-Path $root 'src\machine\machine_runtime_scheduler.gd'
$participantPath = Join-Path $root 'src\machine\machine_runtime_participant.gd'
$progressPath = Join-Path $root 'src\machine\machine_progress_policy.gd'
$migrationPath = Join-Path $root 'src\machine\machine_state_migration.gd'
$completionPath = Join-Path $root 'src\machine\machine_completion_policy.gd'
$furnacePath = Join-Path $root 'src\machine\furnace_service.gd'
$gameplayHubPath = Join-Path $root 'src\ui\service_hub.gd'
$savePath = Join-Path $root 'src\save\save_service.gd'
$recipePath = Join-Path $root 'data\furnace_recipes.json'
$runAllPath = Join-Path $root 'tests\run_all.ps1'
$workflowPath = Join-Path $root '.github\workflows\machine-base-tests.yml'

foreach ($path in @($schedulerPath,$participantPath,$progressPath,$migrationPath,$completionPath,$furnacePath)) {
  if (-not (Test-Path -LiteralPath $path)) { throw "Machine Base file is missing: $path" }
}
if (-not (Test-Path -LiteralPath $workflowPath)) { throw 'Machine Base workflow is missing' }

$schedulerText = Get-Content -Raw -Encoding UTF8 $schedulerPath
$participantText = Get-Content -Raw -Encoding UTF8 $participantPath
$progressText = Get-Content -Raw -Encoding UTF8 $progressPath
$migrationText = Get-Content -Raw -Encoding UTF8 $migrationPath
$completionText = Get-Content -Raw -Encoding UTF8 $completionPath
$furnaceText = Get-Content -Raw -Encoding UTF8 $furnacePath
$gameplayHubText = Get-Content -Raw -Encoding UTF8 $gameplayHubPath
$saveText = Get-Content -Raw -Encoding UTF8 $savePath
$runAllText = Get-Content -Raw -Encoding UTF8 $runAllPath
$workflowText = Get-Content -Raw -Encoding UTF8 $workflowPath
$recipes = Get-Content -Raw -Encoding UTF8 $recipePath | ConvertFrom-Json

if (@($recipes.recipes).Count -ne 9) { throw "Expected nine production furnace recipes, found $(@($recipes.recipes).Count)" }
if ([int]$recipes.schema_version -ne 1) { throw 'Furnace recipe schema must remain version one' }

if ($schedulerText -notmatch 'class_name\s+MachineRuntimeScheduler') { throw 'Shared machine scheduler class is missing' }
if ($schedulerText -notmatch 'MAX_DOMAINS\s*:=\s*16') { throw 'Machine scheduler domain capacity must remain bounded at sixteen' }
if ($schedulerText -notmatch 'PROCESS_MODE_PAUSABLE' -or $schedulerText -notmatch 'advance_machine_runtime') {
  throw 'Machine scheduler must share one pausable runtime loop across domains'
}
foreach ($reason in @('duplicate_domain','domain_contract','domain_capacity')) {
  if ($schedulerText -notmatch $reason) { throw "Machine scheduler must expose registration rejection: $reason" }
}

foreach ($method in @('get_dependencies','install','normalize_world_state','begin_world','attach_game','activate','save_into','snapshot_into','clear','shutdown','get_lifecycle_snapshot')) {
  if ($participantText -notmatch "func\s+$method\s*\(") { throw "Machine runtime participant is missing method: $method" }
}
if ($participantText -notmatch 'payload\["machines"\]' -or $participantText -notmatch 'snapshot\["machine_runtime"\]') {
  throw 'Machine participant must own machine persistence and diagnostics'
}
if ($participantText -notmatch 'MAX_PENDING_COMPLETIONS\s*:=\s*128' -or $participantText -notmatch 'call_deferred\("_flush_completion_batch"\)') {
  throw 'Machine completion feedback must be bounded and coalesced at frame end'
}
if ($participantText -notmatch 'completion_audio_count') { throw 'Machine participant must expose completion sound budgeting' }

foreach ($method in @('normalize_elapsed','progress_ratio','remaining_seconds','queued_jobs','estimated_total_seconds')) {
  if ($progressText -notmatch "static\s+func\s+$method\s*\(") { throw "Machine progress policy is missing method: $method" }
}
if ($migrationText -notmatch 'VERSION\s*:=\s*1' -or $migrationText -notmatch 'MAX_MACHINE_COUNT\s*:=\s*4096') {
  throw 'Machine state migration must preserve schema one and a bounded machine count'
}
if ($migrationText -notmatch 'normalize_world_state' -or $migrationText -notmatch '"furnaces"') {
  throw 'Machine state migration must preserve the machines.furnaces compatibility path'
}
if ($completionText -notmatch 'MAX_VISIBLE_OUTPUT_TYPES\s*:=\s*3' -or $completionText -notmatch 'machine_count') {
  throw 'Machine completion summaries must bound visible types and preserve machine totals'
}

if ($furnaceText -notmatch 'set_external_scheduler' -or $furnaceText -notmatch 'advance_machine_runtime' -or $furnaceText -notmatch 'get_runtime_snapshot') {
  throw 'Furnace must implement the shared machine runtime contract'
}
foreach ($field in @('queued_jobs','queued_output_count','estimated_total_seconds','remaining_seconds','runtime_managed')) {
  if ($furnaceText -notmatch $field) { throw "Furnace snapshot is missing Machine Base field: $field" }
}
if ($furnaceText -notmatch 'MAX_SIMULATION_ITERATIONS\s*:=\s*512') {
  throw 'Furnace elapsed simulation must retain its iteration hard cap'
}

if ($gameplayHubText -notmatch 'machine_runtime_participant\.gd' -or $gameplayHubText -notmatch 'MACHINE_RUNTIME_FEATURE') {
  throw 'Gameplay root must install the Machine Runtime participant before higher domains'
}
if ($gameplayHubText -match '_on_item_smelted') {
  throw 'Gameplay root must not play one sound for every individual furnace completion'
}
if ($saveText -notmatch '"machines": \{"version": 1, "saved_at_unix": timestamp, "furnaces": \{\}\}') {
  throw 'New worlds must preserve the version-one machines.furnaces schema'
}

$allMachineText = $schedulerText + "`n" + $participantText + "`n" + $progressText + "`n" + $migrationText + "`n" + $completionText
if ($allMachineText -match 'Timer\.new\(') { throw 'Machine Base must not create per-machine Timer nodes' }
if ($allMachineText -match 'save_world\(' -or $allMachineText -match 'FileAccess\.open\(') {
  throw 'Machine runtime code must not perform independent world file writes'
}

foreach ($script in @('machine_base_regression\.gd','machine_base_desktop_acceptance\.gd')) {
  if ($runAllText -notmatch $script -and $workflowText -notmatch $script) { throw "Machine Base acceptance is not permanently wired: $script" }
}

Write-Host 'PASS machine_base domains=16 machines=4096 completion_batch=128 visible_types=3 furnace_recipes=9 schema=1'
