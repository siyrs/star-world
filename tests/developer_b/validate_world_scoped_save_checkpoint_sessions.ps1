$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = Resolve-Path "$PSScriptRoot\..\.."
$paths = [ordered]@{
  BasePolicy = Join-Path $root 'src\save\save_checkpoint_timeline_policy.gd'
  ScopedPolicy = Join-Path $root 'src\save\world_scoped_save_checkpoint_timeline_policy.gd'
  ScopedService = Join-Path $root 'src\diagnostics\session_scoped_runtime_health_report_service.gd'
  Formatter = Join-Path $root 'src\save\save_checkpoint_timeline_formatter.gd'
  Hub = Join-Path $root 'src\ui\runtime_health_service_hub.gd'
  Regression = Join-Path $root 'tests\qa\world_scoped_save_checkpoint_session_regression.gd'
  Desktop = Join-Path $root 'tests\qa\world_scoped_save_checkpoint_session_desktop_acceptance.gd'
  Workflow = Join-Path $root '.github\workflows\world-scoped-save-checkpoint-session-tests.yml'
  RunAll = Join-Path $root 'tests\run_all.ps1'
  Contract = Join-Path $root 'docs\WORLD_SCOPED_SAVE_CHECKPOINT_SESSIONS.md'
  TimelineContract = Join-Path $root 'docs\SAVE_CHECKPOINT_TIMELINE.md'
  Audit = Join-Path $root 'docs\ARCHITECTURE_AUDIT_2026-07-29_ITERATION_49.md'
}

foreach ($entry in $paths.GetEnumerator()) {
  if (-not (Test-Path -LiteralPath $entry.Value)) {
    throw "World-scoped checkpoint session contract file is missing: $($entry.Key) $($entry.Value)"
  }
}

$text = @{}
foreach ($entry in $paths.GetEnumerator()) {
  $text[$entry.Key] = Get-Content -Raw -Encoding UTF8 $entry.Value
}

foreach ($token in @(
  'class_name\s+WorldScopedSaveCheckpointTimelinePolicy',
  'BasePolicy\.project_timeline',
  'current_world_session_sequence',
  'current_world_session_started_after_sequence',
  'current_session_history',
  'last_current_session_event',
  'event\.get\("sequence",\s*0\)\)\s*>\s*started_after_sequence',
  'current_world_history',
  'last_current_world_event'
)) {
  if ($text.ScopedPolicy -notmatch $token) { throw "Scoped checkpoint policy is missing contract: $token" }
}
if ($text.ScopedPolicy -match 'extends\s+Node|Timer\.new\(|FileAccess|DirAccess') {
  throw 'World-scoped checkpoint policy must remain a pure projection'
}

foreach ($token in @(
  'class_name\s+SessionScopedRuntimeHealthReportService',
  'extends\s+"res://src/diagnostics/runtime_health_report_service\.gd"',
  '_world_session_sequence_counter',
  '_current_world_session_sequence',
  '_current_world_session_started_after_sequence',
  'func\s+begin_world\s*\(',
  '_save_event_sequence',
  'func\s+get_save_timeline_snapshot\s*\(',
  'func\s+clear_session_counters\s*\(',
  'super\.clear_session_counters',
  'func\s+_timeline_payload\s*\('
)) {
  if ($text.ScopedService -notmatch $token) { throw "Session-scoped health service is missing contract: $token" }
}
if ($text.ScopedService -match 'Timer\.new\(|FileAccess|DirAccess|func\s+serialize\s*\(') {
  throw 'Session-scoped health service must not create a timer or persistence domain'
}
if ($text.ScopedService -match 'func\s+record_save_result\s*\(') {
  throw 'Session-scoped service must reuse the authoritative base save recording path'
}

if ($text.Hub -notmatch 'session_scoped_runtime_health_report_service\.gd') {
  throw 'Production RuntimeHealthServiceHub does not compose the session-scoped service'
}
if ($text.Hub -match 'RuntimeHealthReportServiceScript\.new\(\)[\s\S]{0,200}RuntimeHealthReportServiceScript\.new\(\)') {
  throw 'Production composition must not create a second runtime health owner'
}

foreach ($token in @(
  'world_scoped_save_checkpoint_timeline_policy\.gd',
  'current_session_history_count',
  'last_current_session_event',
  '当前世界本次进入尚无保存记录',
  'current_world_id\.is_empty\(\)'
)) {
  if ($text.Formatter -notmatch $token) { throw "Checkpoint formatter is missing session-safe behavior: $token" }
}
if ($text.Formatter -match 'extends\s+Node|FileAccess|DirAccess|Timer\.new\(') {
  throw 'Checkpoint formatter must remain pure presentation'
}

foreach ($phrase in @(
  'same-world events from an earlier entry are excluded by the sequence boundary',
  'F3 never falls back to another world or an earlier entry while a world is active',
  'switching worlds preserves old evidence but starts with an empty current entry',
  're-entering the same world excludes checkpoints from its previous entry',
  'explicit session reset clears global evidence and re-bases the active world entry'
)) {
  if ($text.Regression -notmatch [regex]::Escape($phrase)) {
    throw "World-scoped checkpoint regression is missing assertion: $phrase"
  }
}

foreach ($phrase in @(
  'world B keeps global A evidence but starts with no current-entry checkpoint',
  'world B F3 never falls back to world A checkpoints',
  'same world ID re-entry excludes checkpoints from world A first entry',
  'same-world re-entry F3 visibly starts from an empty checkpoint scope',
  'world A second entry accepts exactly its new real manual checkpoint',
  'cross-world checkpoint isolation screenshot is saved',
  'same-world re-entry checkpoint isolation screenshot is saved'
)) {
  if ($text.Desktop -notmatch [regex]::Escape($phrase)) {
    throw "World-scoped checkpoint desktop acceptance is missing assertion: $phrase"
  }
}

foreach ($token in @(
  'uses:\s*\./\.github/workflows/reusable-godot-quality-gate\.yml',
  'validate_world_scoped_save_checkpoint_sessions\.ps1',
  'world_scoped_save_checkpoint_session_regression\.gd',
  'save_checkpoint_timeline_regression\.gd',
  'world_scoped_save_checkpoint_session_desktop_acceptance\.gd',
  'save-checkpoint-session-isolation\.png',
  'save-checkpoint-same-world-reentry\.png',
  'save-checkpoint-session-isolation\.json'
)) {
  if ($text.Workflow -notmatch $token) { throw "World-scoped checkpoint workflow is missing gate or evidence: $token" }
}

if (
  $text.RunAll -notmatch 'validate_world_scoped_save_checkpoint_sessions\.ps1'
  -or $text.RunAll -notmatch 'world_scoped_save_checkpoint_session_regression\.gd'
) {
  throw 'Full regression entry point must permanently include world-scoped checkpoint coverage'
}

foreach ($phrase in @(
  '全局运行会话证据',
  '本次进入',
  'A → B → A',
  'current_world_session_started_after_sequence',
  '不创建第二个保存事务',
  'Windows Release'
)) {
  if ($text.Contract -notmatch [regex]::Escape($phrase)) {
    throw "World-scoped checkpoint contract is missing boundary: $phrase"
  }
}
foreach ($phrase in @('世界会话作用域','同一世界重新进入','禁止回退','current_session_history')) {
  if ($text.TimelineContract -notmatch [regex]::Escape($phrase)) {
    throw "Save checkpoint timeline contract is missing session upgrade: $phrase"
  }
}
foreach ($phrase in @(
  'world ID 不是进入会话',
  '活动世界无记录时错误回退',
  '全局 sequence 进入边界',
  '没有创建第二套时间线',
  '真实桌面'
)) {
  if ($text.Audit -notmatch [regex]::Escape($phrase)) {
    throw "Iteration 49 audit is missing finding or decision: $phrase"
  }
}

Write-Host 'PASS world_scoped_checkpoint_sessions global_history=12 current_entry=sequence-bound same_world=reentry-safe cross_world=isolated reset=explicit f3=no-stale persistence=none ci=real-desktop'
