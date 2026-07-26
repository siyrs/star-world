$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = Resolve-Path "$PSScriptRoot\..\.."

function Read-RequiredText {
  param([Parameter(Mandatory = $true)][string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) {
    throw "Missing bounded autosave contract file: $Path"
  }
  return Get-Content -Raw -Encoding UTF8 $Path
}

function Assert-Matches {
  param(
    [Parameter(Mandatory = $true)][string]$Text,
    [Parameter(Mandatory = $true)][string]$Pattern,
    [Parameter(Mandatory = $true)][string]$Message
  )
  if ($Text -notmatch $Pattern) { throw $Message }
}

function Assert-NotMatches {
  param(
    [Parameter(Mandatory = $true)][string]$Text,
    [Parameter(Mandatory = $true)][string]$Pattern,
    [Parameter(Mandatory = $true)][string]$Message
  )
  if ($Text -match $Pattern) { throw $Message }
}

$paths = [ordered]@{
  participant = Join-Path $root 'src\save\autosave_runtime_participant.gd'
  settings_policy = Join-Path $root 'src\settings\game_settings_policy.gd'
  final_hub = Join-Path $root 'src\ui\exploration_progression_service_hub.gd'
  runtime_health_hub = Join-Path $root 'src\ui\runtime_health_service_hub.gd'
  settings_panel = Join-Path $root 'src\ui\settings_panel.gd'
  runtime_test = Join-Path $root 'tests\qa\bounded_autosave_runtime_regression.gd'
  desktop_test = Join-Path $root 'tests\qa\bounded_autosave_desktop_acceptance.gd'
  failed_return_test = Join-Path $root 'tests\qa\runtime_health_failed_return_regression.gd'
  settings_test = Join-Path $root 'tests\qa\settings_retest.gd'
  workflow = Join-Path $root '.github\workflows\bounded-autosave-tests.yml'
  run_all = Join-Path $root 'tests\run_all.ps1'
  contract = Join-Path $root 'docs\BOUNDED_AUTOSAVE_RUNTIME.md'
  audit = Join-Path $root 'docs\ARCHITECTURE_AUDIT_2026-07-26_ITERATION_42.md'
  testing = Join-Path $root 'docs\TESTING.md'
  roadmap = Join-Path $root 'docs\PRODUCT_ROADMAP.md'
}

$text = @{}
foreach ($name in $paths.Keys) {
  $text[$name] = Read-RequiredText -Path $paths[$name]
}

foreach ($token in @(
  'class_name\s+AutosaveRuntimeParticipant',
  'signal\s+autosave_completed',
  'MAX_PROCESS_DELTA_SECONDS\s*:=\s*1\.0',
  'MAX_INTERVAL_MINUTES\s*:=\s*15\.0',
  'RETRY_DELAYS_SECONDS[^\n]*15\.0[^\n]*60\.0[^\n]*300\.0',
  '&"machine_runtime"',
  '&"agriculture_runtime"',
  '&"husbandry_runtime"',
  '&"ranch_runtime"',
  '&"exploration_runtime"',
  '&"exploration_journal_rewards"',
  'process_mode\s*=\s*Node\.PROCESS_MODE_ALWAYS',
  'call_deferred\("_flush_autosave"\)',
  'hub\.call\("save_current"\)',
  'func\s+_retry_delay_for_failure\s*\(',
  'func\s+_on_world_save_completed\s*\(',
  'func\s+_on_settings_applied\s*\(',
  'func\s+_on_pause_changed\s*\(',
  'snapshot\["autosave"\]\s*=\s*get_snapshot\(\)',
  'func\s+save_into\s*\('
)) {
  Assert-Matches $text.participant $token "Autosave runtime is missing bounded lifecycle behavior: $token"
}
Assert-NotMatches $text.participant 'Timer\.new\(' 'Autosave must not create a parallel Timer loop'
Assert-NotMatches $text.participant 'FileAccess|DirAccess|AtomicJsonStore' 'Autosave must delegate to the authoritative save transaction'
Assert-NotMatches $text.participant '_publish_character_message|show_message|show_save_result' 'Autosave domain must emit facts instead of controlling UI'
Assert-NotMatches $text.participant 'payload\["autosave"\]' 'Transient autosave scheduling state must not enter world.json'

foreach ($token in @(
  'class_name\s+GameSettingsPolicy',
  '"autosave_minutes"\s*:\s*5',
  'AUTOSAVE_MINUTES\s*:=\s*\[0,\s*2,\s*5,\s*10,\s*15\]',
  'func\s+normalize\s*\(',
  'var\s+normalized\s*:=\s*defaults\(\)',
  'func\s+merge\s*\(',
  'func\s+normalize_autosave_minutes\s*\(',
  'return\s+normalized',
  'is_finite'
)) {
  Assert-Matches $text.settings_policy $token "Canonical settings policy is missing autosave normalization: $token"
}
Assert-NotMatches $text.settings_policy 'extends\s+Node|FileAccess|save_settings' 'Settings policy must remain pure and persistence-free'
Assert-NotMatches $text.settings_policy 'normalized\.merge\(raw_settings' 'Unknown settings must not escape the canonical whitelist'

foreach ($token in @(
  'AutosaveRuntimeParticipantScript',
  'AUTOSAVE_RUNTIME_FEATURE\s*:=\s*&"autosave_runtime"',
  'SettingsPolicyScript\.normalize\(current_settings\)',
  'SettingsPolicyScript\.merge\(current_settings,\s*settings\)',
  'autosave_completed',
  'func\s+get_autosave_snapshot\s*\(',
  'snapshot\["autosave"\]',
  '世界已自动保存',
  '秒后重试'
)) {
  Assert-Matches $text.final_hub $token "Final production composition is missing autosave integration: $token"
}
Assert-Matches $text.final_hub 'Registered last|registered last' 'Autosave composition must document reverse-cleanup ordering'

Assert-Matches $text.runtime_health_hub 'func\s+return_to_menu\s*\(\)[\s\S]{0,700}super\.return_to_menu\(\)[\s\S]{0,300}current_world_id\.is_empty\(\)[\s\S]{0,200}detach_runtime' 'Runtime health must detach only after the authoritative return succeeds'
Assert-NotMatches $text.runtime_health_hub 'func\s+return_to_menu\s*\(\)[\s\S]{0,180}detach_runtime[\s\S]{0,180}super\.return_to_menu' 'Runtime health must not detach before a fallible final save'

foreach ($token in @(
  'game_settings_policy\.gd',
  '_autosave_interval:\s*OptionButton',
  'SettingsPolicy\.allowed_autosave_minutes\(\)',
  '"自动保存"',
  '"关闭"',
  '"每 %d 分钟"',
  '"autosave_minutes"'
)) {
  Assert-Matches $text.settings_panel $token "Settings UI is missing bounded autosave controls: $token"
}
Assert-NotMatches $text.settings_panel 'const\s+DEFAULTS\s*:=' 'Settings panel must not keep a second defaults dictionary'

foreach ($phrase in @(
  'autosave settings expose one bounded deterministic choice list',
  'manual save cancels a queued autosave',
  'failure 3 applies the bounded 300-second retry tier',
  'real autosave transaction persists the production inventory mutation',
  'production lifecycle contains seven explicit participants',
  'reverse lifecycle cleanup disables autosave'
)) {
  Assert-Matches $text.runtime_test ([regex]::Escape($phrase)) "Autosave runtime regression is missing coverage: $phrase"
}

foreach ($phrase in @(
  'real settings page exposes exactly the bounded autosave choices',
  'paused desktop time cannot schedule an automatic save',
  'real autosave persists the unsaved production inventory mutation',
  'successful automatic checkpoint is visible in the real gameplay HUD',
  'real autosave settings screenshot is saved',
  'real gameplay autosave confirmation screenshot is saved'
)) {
  Assert-Matches $text.desktop_test ([regex]::Escape($phrase)) "Autosave desktop acceptance is missing coverage: $phrase"
}

foreach ($phrase in @(
  'failed final save keeps the player in the current world',
  'failed final save keeps F3 attached to the world still in use',
  'failed final save remains visible as critical operational evidence',
  'runtime health detaches only after world ownership is actually released'
)) {
  Assert-Matches $text.failed_return_test ([regex]::Escape($phrase)) "Failed-return health regression is missing coverage: $phrase"
}

foreach ($phrase in @(
  'production settings policy normalizes autosave to an allowed interval',
  'live autosave runtime receives the normalized interval',
  'reloaded autosave runtime uses the persisted interval',
  'zero-minute setting disables autosave'
)) {
  Assert-Matches $text.settings_test ([regex]::Escape($phrase)) "Settings regression is missing autosave coverage: $phrase"
}

foreach ($token in @(
  'uses:\s*\./\.github/workflows/reusable-godot-quality-gate\.yml',
  'validate_bounded_autosave\.ps1',
  'bounded_autosave_runtime_regression\.gd',
  'settings_retest\.gd',
  'service_hub_feature_lifecycle_regression\.gd',
  'runtime_health_failed_return_regression\.gd',
  'bounded_autosave_desktop_acceptance\.gd',
  'bounded-autosave-desktop-settings\.png',
  'bounded-autosave-desktop\.json'
)) {
  Assert-Matches $text.workflow $token "Bounded autosave workflow is missing validation or visual evidence: $token"
}

foreach ($token in @(
  'validate_bounded_autosave\.ps1',
  'bounded_autosave_runtime_regression\.gd',
  'runtime_health_failed_return_regression\.gd'
)) {
  Assert-Matches $text.run_all $token "Full regression entry point is missing autosave coverage: $token"
}

foreach ($phrase in @(
  '活动时间', '手动保存', '15 / 60 / 300', '不进入世界存档', '真实桌面', 'Windows Release'
)) {
  Assert-Matches $text.contract ([regex]::Escape($phrase)) "Autosave contract is missing a boundary: $phrase"
}
foreach ($phrase in @(
  '周期性真实保存', '重复设置默认值', '领域事实', '分级退避', '第七个生命周期参与者'
)) {
  Assert-Matches $text.audit ([regex]::Escape($phrase)) "Architecture audit is missing a finding or decision: $phrase"
}
Assert-Matches $text.testing 'bounded_autosave_runtime_regression\.gd' 'Testing guide must document the autosave domain command'
Assert-Matches $text.testing 'bounded_autosave_desktop_acceptance\.gd' 'Testing guide must document the autosave desktop command'
Assert-Matches $text.testing 'runtime_health_failed_return_regression\.gd' 'Testing guide must document the failed-return regression'
Assert-Matches $text.roadmap '有界自动保存' 'Product roadmap must record the completed bounded autosave capability'
Assert-Matches $text.roadmap 'BOUNDED_AUTOSAVE_RUNTIME\.md' 'Product roadmap must link the autosave contract'

Write-Host 'PASS bounded_autosave interval=0|2|5|10|15 active_time=pause-aware manual=deduplicated retries=15|60|300 participants=7 persistence=authoritative ui=fact-driven failed_return=attached desktop=visual'
