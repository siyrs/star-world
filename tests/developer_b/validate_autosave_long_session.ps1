$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = Resolve-Path "$PSScriptRoot\..\.."
$paths = [ordered]@{
  Policy = Join-Path $root 'src\save\autosave_schedule_policy.gd'
  Participant = Join-Path $root 'src\save\autosave_runtime_participant.gd'
  Formatter = Join-Path $root 'src\save\save_checkpoint_timeline_formatter.gd'
  Regression = Join-Path $root 'tests\qa\autosave_long_session_endurance_regression.gd'
  Desktop = Join-Path $root 'tests\qa\autosave_long_session_desktop_acceptance.gd'
  Workflow = Join-Path $root '.github\workflows\autosave-long-session-tests.yml'
  RunAll = Join-Path $root 'tests\run_all.ps1'
  Contract = Join-Path $root 'docs\AUTOSAVE_LONG_SESSION_SCHEDULING.md'
  BaseContract = Join-Path $root 'docs\BOUNDED_AUTOSAVE_RUNTIME.md'
  Testing = Join-Path $root 'docs\TESTING.md'
  Audit = Join-Path $root 'docs\ARCHITECTURE_AUDIT_2026-07-29_ITERATION_50.md'
}

foreach ($entry in $paths.GetEnumerator()) {
  if (-not (Test-Path -LiteralPath $entry.Value)) {
    throw "Long-session autosave contract file is missing: $($entry.Key) $($entry.Value)"
  }
}

$text = @{}
foreach ($entry in $paths.GetEnumerator()) {
  $text[$entry.Key] = Get-Content -Raw -Encoding UTF8 $entry.Value
}

foreach ($token in @(
  'class_name\s+AutosaveSchedulePolicy',
  'extends\s+RefCounted',
  'MICROSECONDS_PER_SECOND\s*:=\s*1000000',
  'MAX_INTERVAL_MICROSECONDS\s*:=\s*900000000',
  'MAX_CARRY_MICROSECONDS\s*:=\s*1000000',
  'fractional_microseconds',
  'current_carry_microseconds',
  'discarded_overshoot_microseconds',
  'int\(round\(',
  'static\s+func\s+configure\s*\(',
  'static\s+func\s+advance\s*\(',
  'static\s+func\s+consume_pending\s*\(',
  'static\s+func\s+record_success\s*\(',
  'static\s+func\s+record_failure\s*\(',
  'static\s+func\s+record_manual_save\s*\(',
  'static\s+func\s+snapshot\s*\('
)) {
  if ($text.Policy -notmatch $token) {
    throw "Autosave schedule policy is missing fixed-point contract: $token"
  }
}
if ($text.Policy -match 'extends\s+Node|Timer\.new\(|FileAccess|DirAccess|Time\.|Input\.|call_deferred|save_current') {
  throw 'Autosave schedule policy must remain pure, constant-time and side-effect free'
}
if ($text.Policy -match '(?m)^\s*(for|while)\s+') {
  throw 'Autosave schedule policy must remain O(1) and must not catch up with loops'
}

foreach ($token in @(
  'autosave_schedule_policy\.gd',
  '_schedule_state',
  'SchedulePolicyScript\.configure',
  'SchedulePolicyScript\.advance',
  'SchedulePolicyScript\.consume_pending',
  'SchedulePolicyScript\.record_success',
  'SchedulePolicyScript\.record_failure',
  'SchedulePolicyScript\.record_manual_save',
  'call_deferred\("_flush_autosave"\)',
  'hub\.call\("save_current"\)',
  'RETRY_DELAYS_SECONDS[^\n]*15\.0[^\n]*60\.0[^\n]*300\.0',
  'MAX_PROCESS_DELTA_SECONDS\s*:=\s*1\.0'
)) {
  if ($text.Participant -notmatch $token) {
    throw "Autosave participant is missing delegated long-session behavior: $token"
  }
}
if ($text.Participant -match 'var\s+_elapsed_active_seconds|var\s+_interval_seconds|var\s+_pending_flush') {
  throw 'Autosave participant must not retain the retired parallel float schedule fields'
}
if ($text.Participant -match 'Timer\.new\(|FileAccess|DirAccess|AtomicJsonStore') {
  throw 'Autosave participant must still delegate persistence and avoid a second timer'
}

foreach ($token in @(
  '连续失败\s+%d\s+次',
  'last_retry_delay_seconds',
  'consecutive_failure_count',
  'current_session_history_count'
)) {
  if ($text.Formatter -notmatch $token) {
    throw "Checkpoint formatter is missing long-session failure visibility: $token"
  }
}
if ($text.Formatter -match 'extends\s+Node|FileAccess|DirAccess|Timer\.new\(') {
  throw 'Checkpoint formatter must remain a pure presentation helper'
}

foreach ($phrase in @(
  'eight active hours at five-minute intervals produce exactly ninety-six checkpoints',
  'mixed frame deltas finish with no cumulative checkpoint drift',
  'unexpected giant deltas retain at most one production-frame carry',
  'three real failures reach the bounded 300-second retry tier',
  'thirteen production checkpoints roll over to the exact twelve-event session budget',
  'recovery persists every mutation accumulated before and during failed attempts',
  'fixed-point scheduling and long-session diagnostics remain outside world.json'
)) {
  if ($text.Regression -notmatch [regex]::Escape($phrase)) {
    throw "Long-session autosave regression is missing assertion: $phrase"
  }
}
if ($text.Regression -notmatch 'EIGHT_HOURS_SECONDS\s*:=\s*8\.0\s*\*\s*60\.0\s*\*\s*60\.0') {
  throw 'Long-session regression must retain an explicit eight-hour simulation horizon'
}
if ($text.Regression -notmatch 'due_count\s*==\s*96') {
  throw 'Long-session regression must assert exactly ninety-six five-minute checkpoints'
}

foreach ($phrase in @(
  'real long-session journey produces eight successful automatic checkpoints before manual save',
  'real pause button interleaves one manual checkpoint without duplicate autosave',
  'three real autosave failures reach the bounded 300-second retry tier',
  'F3 exposes the active three-failure backoff without stale success text',
  'successful retry clears failure pressure and persists all delayed mutations',
  'history rolls over to twelve with one exact dropped checkpoint',
  'autosave long-session backoff screenshot is saved',
  'autosave long-session recovery screenshot is saved'
)) {
  if ($text.Desktop -notmatch [regex]::Escape($phrase)) {
    throw "Long-session desktop acceptance is missing assertion: $phrase"
  }
}

foreach ($token in @(
  'uses:\s*\./\.github/workflows/reusable-godot-quality-gate\.yml',
  'validate_autosave_long_session\.ps1',
  'autosave_long_session_endurance_regression\.gd',
  'bounded_autosave_runtime_regression\.gd',
  'save_checkpoint_timeline_regression\.gd',
  'world_scoped_save_checkpoint_session_regression\.gd',
  'runtime_soak_regression\.gd',
  'autosave_long_session_desktop_acceptance\.gd',
  'autosave-long-session-backoff\.png',
  'autosave-long-session-recovered\.png',
  'autosave-long-session-report\.json'
)) {
  if ($text.Workflow -notmatch $token) {
    throw "Long-session autosave workflow is missing gate or evidence: $token"
  }
}

if ($text.RunAll -notmatch 'validate_autosave_long_session\.ps1' -or $text.RunAll -notmatch 'autosave_long_session_endurance_regression\.gd') {
  throw 'Full regression entry point must permanently include long-session autosave coverage'
}

foreach ($phrase in @(
  '整数微秒',
  '有界帧越界 carry',
  '单 pending',
  '8 小时',
  '96 个检查点',
  '15 / 60 / 300',
  'world.json',
  'Windows Release'
)) {
  if ($text.Contract -notmatch [regex]::Escape($phrase)) {
    throw "Long-session autosave contract is missing boundary: $phrase"
  }
}
foreach ($phrase in @(
  '固定点调度与长期无漂移',
  'discarded_overshoot_seconds',
  '连续失败 N 次',
  'AutosaveSchedulePolicy'
)) {
  if ($text.BaseContract -notmatch [regex]::Escape($phrase)) {
    throw "Bounded autosave contract is missing the long-session upgrade: $phrase"
  }
}
foreach ($phrase in @(
  '长会话自动保存',
  'autosave_long_session_endurance_regression.gd',
  'autosave_long_session_desktop_acceptance.gd',
  'autosave-long-session-recovered.png'
)) {
  if ($text.Testing -notmatch [regex]::Escape($phrase)) {
    throw "Testing guide is missing long-session autosave coverage: $phrase"
  }
}
foreach ($phrase in @(
  '调度数学与 I/O 生命周期耦合',
  '每个周期丢弃不足一帧',
  '纯固定点调度策略',
  '不在同一帧追赶多个保存',
  '真实桌面双截图'
)) {
  if ($text.Audit -notmatch [regex]::Escape($phrase)) {
    throw "Iteration 50 audit is missing finding or decision: $phrase"
  }
}

Write-Host 'PASS autosave_long_session policy=fixed-point precision=usec carry=1s catchup=bounded horizon=8h checkpoints=96 failures=3 retry=300s history=12 dropped=1 persistence=none desktop=dual-evidence'
