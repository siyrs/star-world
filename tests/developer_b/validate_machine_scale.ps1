$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = Resolve-Path "$PSScriptRoot\..\.."
$paths = @{
  Index = Join-Path $root 'src\machine\machine_activity_index.gd'
  Furnace = Join-Path $root 'src\machine\scalable_furnace_service.gd'
  Stonecutter = Join-Path $root 'src\machine\scalable_stonecutter_service.gd'
  Automation = Join-Path $root 'src\machine\scalable_machine_automation_service.gd'
  Completion = Join-Path $root 'src\machine\scalable_machine_completion_policy.gd'
  Participant = Join-Path $root 'src\machine\scalable_machine_runtime_participant.gd'
  Hub = Join-Path $root 'src\ui\scalable_machine_service_hub.gd'
  Scene = Join-Path $root 'scenes\ui\service_hub.tscn'
  Regression = Join-Path $root 'tests\qa\machine_scale_runtime_regression.gd'
  Desktop = Join-Path $root 'tests\qa\machine_scale_desktop_acceptance.gd'
  Workflow = Join-Path $root '.github\workflows\machine-scale-tests.yml'
  RunAll = Join-Path $root 'tests\run_all.ps1'
  Contract = Join-Path $root 'docs\MACHINE_SCALE_RUNTIME.md'
  Audit = Join-Path $root 'docs\ARCHITECTURE_AUDIT_2026-07-22_ITERATION_24.md'
}
foreach ($entry in $paths.GetEnumerator()) {
  if (-not (Test-Path -LiteralPath $entry.Value)) {
    throw "Machine scale contract file is missing: $($entry.Key) $($entry.Value)"
  }
}
$text = @{}
foreach ($entry in $paths.GetEnumerator()) {
  $text[$entry.Key] = Get-Content -Raw -Encoding UTF8 $entry.Value
}

if ($text.Index -notmatch 'MAX_TRACKED_IDS\s*:=\s*4096') {
  throw 'Machine activity index must retain the persisted-machine hard limit'
}
if ($text.Index -notmatch 'func\s+ordered_ids_view\s*\(' -or $text.Index -notmatch '_ensure_sorted\(\)') {
  throw 'Machine activity ordering must be maintained outside per-frame full scans'
}
$setActiveMatch = [regex]::Match($text.Index, 'func\s+set_active[\s\S]*?func\s+rebuild')
if (-not $setActiveMatch.Success -or $setActiveMatch.Value -match '_order\.sort\(\)') {
  throw 'Each machine activity event must not sort the complete directory'
}

foreach ($serviceName in @('Furnace','Stonecutter')) {
  $service = $text[$serviceName]
  if ($service -notmatch 'RUNTIME_STEP_SECONDS\s*:=\s*0\.1') {
    throw "$serviceName runtime must coalesce scheduler frames into a 100ms domain step"
  }
  if ($service -notmatch 'MAX_CHANGED_MACHINE_ID_SAMPLES\s*:=\s*64') {
    throw "$serviceName runtime must bound changed-machine diagnostic ids"
  }
  foreach ($token in @('_activity_index','_advance_indexed','active_machine_count','avoided_idle_evaluation_count','dropped_changed_machine_samples')) {
    if ($service -notmatch [regex]::Escape($token)) {
      throw "$serviceName runtime is missing scale token: $token"
    }
  }
  if ($service -match 'Timer\.new\(') {
    throw "$serviceName scale runtime must not create per-machine timers"
  }
}

if ($text.Automation -notmatch '_candidate_order_dirty' -or $text.Automation -notmatch 'func\s+_ensure_candidate_order') {
  throw 'Automation candidate ordering must be deferred to the cycle boundary'
}
$addCandidateMatch = [regex]::Match($text.Automation, 'func\s+_add_candidate[\s\S]*?func\s+_ensure_candidate_order')
if (-not $addCandidateMatch.Success -or $addCandidateMatch.Value -match '_candidate_order\.sort\(\)') {
  throw 'Automation must not sort the complete candidate directory for every machine event'
}

foreach ($token in @(
  'MAX_COMPLETION_EVENT_SAMPLES\s*:=\s*64',
  'MAX_TRACKED_COMPLETION_MACHINES\s*:=\s*4096',
  '_pending_completion_job_count',
  '_pending_completion_item_total',
  '_pending_dropped_completion_samples',
  'flush_pending_completion_batch'
)) {
  if ($text.Participant -notmatch $token) {
    throw "Exact completion aggregation is missing: $token"
  }
}
if ($text.Participant -match '_pending_completions\.size\(\)\s*>=\s*MAX_PENDING_COMPLETIONS') {
  throw 'Production completion totals must not be truncated by the old event-sample limit'
}
if ($text.Completion -notmatch 'build_counts' -or $text.Completion -notmatch 'MAX_VISIBLE_OUTPUT_TYPES\s*:=\s*3') {
  throw 'Large completion summaries must keep exact counts and bounded player-visible types'
}

foreach ($token in @('ScalableFurnaceScript','ScalableStonecutterScript','ScalableAutomationScript','ScalableParticipantScript')) {
  if ($text.Hub -notmatch $token) {
    throw "Production machine composition is missing: $token"
  }
}
if ($text.Scene -notmatch 'scalable_machine_service_hub\.gd') {
  throw 'Production ServiceHub scene must instantiate scalable machine composition'
}

foreach ($phrase in @(
  'furnace activity index excludes idle persisted machines',
  'stonecutter activity index excludes idle persisted machines',
  'two thousand forty-eight automation candidates sort once at the cycle boundary',
  'large completion summary preserves jobs, items and contributing machines',
  'production lifecycle installs exact completion aggregation'
)) {
  if ($text.Regression -notmatch [regex]::Escape($phrase)) {
    throw "Machine scale regression is missing assertion: $phrase"
  }
}
foreach ($phrase in @(
  'scale fixture contains five hundred twelve production machines',
  'five hundred twelve candidates sort once and feed all active machines exactly',
  'completion feedback preserves all two hundred fifty-six jobs and outputs',
  'machine scale save remains below three megabytes',
  'machine scale evidence uses 1024x576 product resolution'
)) {
  if ($text.Desktop -notmatch [regex]::Escape($phrase)) {
    throw "Machine scale desktop acceptance is missing assertion: $phrase"
  }
}
if ($text.Workflow -notmatch 'Invoke-Godot\.ps1' -or $text.Workflow -notmatch 'machine_scale_runtime_regression\.gd') {
  throw 'Machine scale workflow must run real awaited domain tests'
}
if ($text.Workflow -notmatch 'machine_scale_desktop_acceptance\.gd' -or $text.Workflow -notmatch 'machine-scale-desktop\.json') {
  throw 'Machine scale workflow must upload visual and machine-readable evidence'
}
if ($text.RunAll -notmatch 'validate_machine_scale\.ps1' -or $text.RunAll -notmatch 'machine_scale_runtime_regression\.gd') {
  throw 'Full regression entry point must permanently include machine scale coverage'
}
if ($text.Contract -notmatch '4096' -or $text.Contract -notmatch '0\.1' -or $text.Contract -notmatch '64') {
  throw 'Machine scale contract must document persistent, cadence and diagnostic budgets'
}
if ($text.Audit -notmatch 'get_machine_ids' -or $text.Audit -notmatch 'MAX_PENDING_COMPLETIONS') {
  throw 'Architecture audit must record the original full scan and completion truncation risks'
}

Write-Host 'PASS machine_scale machines=4096 runtime_step_ms=100 changed_id_samples=64 completion_samples=64 candidate_sort=cycle-boundary persistence=unchanged'
