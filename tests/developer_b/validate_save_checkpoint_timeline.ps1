$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = Resolve-Path "$PSScriptRoot\..\.."
$paths = [ordered]@{
  Policy = Join-Path $root 'src\save\save_checkpoint_timeline_policy.gd'
  Formatter = Join-Path $root 'src\save\save_checkpoint_timeline_formatter.gd'
  Report = Join-Path $root 'src\diagnostics\runtime_health_report_service.gd'
  HealthFormatter = Join-Path $root 'src\diagnostics\runtime_health_report_formatter.gd'
  Hub = Join-Path $root 'src\ui\runtime_health_service_hub.gd'
  Regression = Join-Path $root 'tests\qa\save_checkpoint_timeline_regression.gd'
  Desktop = Join-Path $root 'tests\qa\save_checkpoint_timeline_desktop_acceptance.gd'
  Workflow = Join-Path $root '.github\workflows\save-checkpoint-timeline-tests.yml'
  RunAll = Join-Path $root 'tests\run_all.ps1'
  Contract = Join-Path $root 'docs\SAVE_CHECKPOINT_TIMELINE.md'
  Audit = Join-Path $root 'docs\ARCHITECTURE_AUDIT_2026-07-26_ITERATION_43.md'
}
foreach ($entry in $paths.GetEnumerator()) {
  if (-not (Test-Path -LiteralPath $entry.Value)) {
    throw "Save checkpoint timeline contract file is missing: $($entry.Key) $($entry.Value)"
  }
}
$text = @{}
foreach ($entry in $paths.GetEnumerator()) {
  $text[$entry.Key] = Get-Content -Raw -Encoding UTF8 $entry.Value
}

foreach ($token in @(
  'class_name\s+SaveCheckpointTimelinePolicy',
  'MAX_EVENTS\s*:=\s*12',
  'REASON_MANUAL',
  'REASON_AUTOSAVE',
  'REASON_RETURN_TO_MENU',
  'REASON_SYSTEM',
  'append_bounded',
  'project_history',
  'project_reason_counts',
  'project_autosave',
  'project_timeline'
)) {
  if ($text.Policy -notmatch $token) { throw "Checkpoint policy is missing bounded contract: $token" }
}
if ($text.Policy -match 'extends\s+Node|Timer\.new\(|FileAccess|DirAccess') {
  throw 'Checkpoint policy must remain a pure bounded projection'
}
if ($text.Formatter -notmatch '保存来源' -or $text.Formatter -notmatch '最近检查点' -or $text.Formatter -notmatch '自动保存') {
  throw 'Checkpoint formatter must expose player-facing save source and countdown text'
}
if ($text.Formatter -match 'extends\s+Node|FileAccess|DirAccess|Timer\.new\(') {
  throw 'Checkpoint formatter must remain a pure presentation helper'
}

foreach ($token in @(
  'save_checkpoint_recorded',
  '_save_event_history',
  '_save_history_dropped_count',
  '_save_reason_counts',
  'record_save_result',
  'get_save_timeline_snapshot',
  'end_world',
  'TimelinePolicyScript\.append_bounded',
  'save_timeline'
)) {
  if ($text.Report -notmatch $token) { throw "Runtime health service is missing checkpoint ownership: $token" }
}
if ($text.Report -match 'func\s+serialize\s*\(') {
  throw 'Checkpoint timeline must not become a persistence domain'
}
foreach ($token in @(
  'save_current_with_reason',
  '_save_reason_context',
  '_resolve_save_reason',
  'REASON_RETURN_TO_MENU',
  'REASON_AUTOSAVE',
  'get_save_checkpoint_timeline_snapshot',
  'end_world'
)) {
  if ($text.Hub -notmatch $token) { throw "Save reason composition is missing: $token" }
}
if ($text.HealthFormatter -notmatch 'TimelineFormatter\.format_f3' -or $text.HealthFormatter -notmatch 'save_timeline') {
  throw 'F3 health formatter must render the bounded checkpoint timeline'
}

foreach ($phrase in @(
  'checkpoint policy retains exactly twelve recent events',
  'reason counters remain exact after bounded event eviction',
  'ending a world clears active identity without discarding session history',
  'checkpoint timeline remains transient and never enters world.json',
  'production context distinguishes manual, system and final return saves'
)) {
  if ($text.Regression -notmatch [regex]::Escape($phrase)) {
    throw "Checkpoint regression is missing assertion: $phrase"
  }
}
foreach ($phrase in @(
  'real pause save is classified as one manual checkpoint',
  'timeline correlates one real manual and one real automatic checkpoint',
  'latest current-world checkpoint is the successful automatic save',
  'real F3 timeline renders',
  'save checkpoint timeline screenshot is saved'
)) {
  if ($text.Desktop -notmatch [regex]::Escape($phrase)) {
    throw "Checkpoint desktop acceptance is missing assertion: $phrase"
  }
}
foreach ($token in @(
  'uses:\s*\./\.github/workflows/reusable-godot-quality-gate\.yml',
  'validate_save_checkpoint_timeline\.ps1',
  'save_checkpoint_timeline_regression\.gd',
  'save_checkpoint_timeline_desktop_acceptance\.gd',
  'save-checkpoint-timeline-desktop\.png',
  'save-checkpoint-timeline-desktop\.json'
)) {
  if ($text.Workflow -notmatch $token) { throw "Checkpoint workflow is missing gate or evidence: $token" }
}
if ($text.RunAll -notmatch 'validate_save_checkpoint_timeline\.ps1' -or $text.RunAll -notmatch 'save_checkpoint_timeline_regression\.gd') {
  throw 'Full regression entry point must permanently include checkpoint timeline coverage'
}
foreach ($phrase in @('12','manual','autosave','return_to_menu','system','F3','world.json','单一权威保存事务')) {
  if ($text.Contract -notmatch [regex]::Escape($phrase)) { throw "Checkpoint contract is missing boundary: $phrase" }
}
foreach ($phrase in @('来源不可见','最后一次结果','旧世界 ID','有界历史','真实桌面','Windows Release')) {
  if ($text.Audit -notmatch [regex]::Escape($phrase)) { throw "Architecture audit is missing finding or acceptance: $phrase" }
}

Write-Host 'PASS save_checkpoint_timeline events=12 reasons=4 counts=exact history=bounded autosave=inferred return=context world_id=authoritative ui=F3 persistence=none ci=real-desktop'
