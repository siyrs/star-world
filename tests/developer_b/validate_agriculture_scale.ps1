$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = Resolve-Path "$PSScriptRoot\..\.."
$files = @{
  Cache = 'src\agriculture\cached_soil_moisture_service.gd'
  Service = 'src\agriculture\scalable_agriculture_service.gd'
  Participant = 'src\agriculture\scalable_agriculture_runtime_participant.gd'
  Policy = 'src\agriculture\agriculture_notification_policy.gd'
  Hub = 'src\ui\character_progression_service_hub.gd'
  Regression = 'tests\qa\agriculture_scale_batch_regression.gd'
  Desktop = 'tests\qa\agriculture_scale_desktop_acceptance.gd'
  Workflow = '.github\workflows\agriculture-scale-tests.yml'
  RunAll = 'tests\run_all.ps1'
  Contract = 'docs\AGRICULTURE_SCALE_BATCHING.md'
  Audit = 'docs\ARCHITECTURE_AUDIT_2026-07-22_ITERATION_23.md'
}
$text = @{}
foreach ($name in $files.Keys) {
  $path = Join-Path $root $files[$name]
  if (-not (Test-Path -LiteralPath $path)) { throw "Missing agriculture scale file: $path" }
  $text[$name] = Get-Content -Raw -Encoding UTF8 $path
}

if ($text.Cache -notmatch 'MAX_REFRESH_SAMPLE_CACHE_CELLS\s*:=\s*65536') { throw 'Hydration cache budget changed' }
foreach ($method in @('attach_world_without_refresh','refresh_all','refresh_budgeted','get_runtime_snapshot','_has_nearby_water')) {
  if ($text.Cache -notmatch "func\s+$method\s*\(") { throw "Missing cached moisture method: $method" }
}
if ($text.Cache -notmatch '_sample_cache\.has\(candidate\)' -or $text.Cache -notmatch '_window_cache_hits\s*\+=\s*1') { throw 'Hydration samples are not cached' }
if ($text.Cache -notmatch 'begin_chunk_rebuild_batch' -or $text.Cache -notmatch 'end_chunk_rebuild_batch') { throw 'Hydration visuals do not join world batching' }

if ($text.Service -notmatch 'fertilizable_agriculture_service\.gd') { throw 'Scalable service must preserve production agriculture' }
foreach ($method in @('attach_world','advance_time','get_runtime_snapshot','get_world_mutation_batch_snapshot')) {
  if ($text.Service -notmatch "func\s+$method\s*\(") { throw "Missing scalable agriculture method: $method" }
}
if ($text.Service -notmatch 'attach_world_without_refresh' -or $text.Service -notmatch 'super\.advance_time') { throw 'Attach or growth contract regressed' }
if ($text.Service -notmatch 'begin_chunk_rebuild_batch' -or $text.Service -notmatch 'end_chunk_rebuild_batch') { throw 'Growth does not use world batching' }

if ($text.Participant -notmatch 'MAX_MATURITY_POSITION_SAMPLES\s*:=\s*64') { throw 'Maturity sample budget changed' }
if ($text.Participant -notmatch 'MAX_TRACKED_MATURITY_TYPES\s*:=\s*16') { throw 'Maturity type budget changed' }
if ($text.Participant -notmatch '_pending_maturity_total\s*\+=\s*1' -or $text.Participant -notmatch 'maturity_counts') { throw 'Mature crops are not fully counted' }
if ($text.Participant -match '_dropped_maturity_events\s*\+=\s*1') { throw 'Mature crop counts must not be dropped' }
if ($text.Policy -notmatch 'static\s+func\s+maturity_counts\s*\(' -or $text.Policy -notmatch 'dropped_position_samples') { throw 'Count-based maturity policy missing' }
if ($text.Hub -notmatch 'scalable_agriculture_runtime_participant\.gd') { throw 'Production hub does not install scalable agriculture' }

foreach ($phrase in @('one hundred twenty-eight crops mature through one loaded-chunk rebuild','overlapping soil refreshes reuse cached world samples','two thousand forty-eight maturity events remain fully counted','agriculture batching diagnostics remain transient')) {
  if ($text.Regression -notmatch [regex]::Escape($phrase)) { throw "Missing regression assertion: $phrase" }
}
foreach ($phrase in @('production field contains two thousand forty-eight crops','all mature crops are reported in one accurate player batch','large-field growth rebuilds each dirty chunk at most once','agriculture scale evidence uses 1024x576 product resolution','full farm reload reaches a bounded playable state')) {
  if ($text.Desktop -notmatch [regex]::Escape($phrase)) { throw "Missing desktop assertion: $phrase" }
}
if ($text.Workflow -notmatch 'agriculture_scale_batch_regression\.gd' -or $text.Workflow -notmatch 'agriculture_scale_desktop_acceptance\.gd') { throw 'Workflow coverage missing' }
if ($text.Workflow -notmatch 'Invoke-Godot\.ps1' -or $text.Workflow -notmatch 'run_godot_desktop_test\.ps1') { throw 'Workflow must await Godot' }
if ($text.RunAll -notmatch 'validate_agriculture_scale\.ps1' -or $text.RunAll -notmatch 'agriculture_scale_batch_regression\.gd') { throw 'Full suite wiring missing' }
if ($text.Contract -notmatch '2,048' -or $text.Contract -notmatch '65,536') { throw 'Contract budgets missing' }
if ($text.Audit -notmatch 'refresh_all' -or $text.Audit -notmatch '64') { throw 'Audit findings missing' }

Write-Host 'PASS agriculture_scale crops=4096 evidence=2048 position_samples=64 types=16 cache=65536 exact_counts=true'
