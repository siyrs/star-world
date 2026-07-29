$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = Resolve-Path "$PSScriptRoot\..\.."
$paths = [ordered]@{
  Policy = Join-Path $root 'src\save\world_session_recovery_policy.gd'
  Service = Join-Path $root 'src\save\world_session_recovery_service.gd'
  MainMenu = Join-Path $root 'src\ui\accessibility_protected_main_menu.gd'
  GameUi = Join-Path $root 'src\ui\accessibility_machine_game_ui.gd'
  Hub = Join-Path $root 'src\ui\exploration_progression_service_hub.gd'
  Game = Join-Path $root 'src\core\batched_game.gd'
  GameScene = Join-Path $root 'scenes\game\game.tscn'
  HubScene = Join-Path $root 'scenes\ui\service_hub.tscn'
  MenuScene = Join-Path $root 'scenes\ui\main_menu.tscn'
  GameUiScene = Join-Path $root 'scenes\ui\game_ui.tscn'
  RecoveryTest = Join-Path $root 'tests\qa\world_session_recovery_regression.gd'
  QuitTest = Join-Path $root 'tests\qa\graceful_application_quit_regression.gd'
  UiTest = Join-Path $root 'tests\qa\session_recovery_ui_regression.gd'
  Desktop = Join-Path $root 'tests\qa\world_session_recovery_desktop_acceptance.gd'
  Workflow = Join-Path $root '.github\workflows\crash-safe-session-recovery-tests.yml'
  RunAll = Join-Path $root 'tests\run_all.ps1'
  Contract = Join-Path $root 'docs\CRASH_SAFE_SESSION_RECOVERY.md'
  Audit = Join-Path $root 'docs\ARCHITECTURE_AUDIT_2026-07-29_ITERATION_51.md'
  Testing = Join-Path $root 'docs\CRASH_SAFE_SESSION_RECOVERY_TESTING.md'
  Roadmap = Join-Path $root 'docs\PRODUCT_ROADMAP_ITERATION_51.md'
}

foreach ($entry in $paths.GetEnumerator()) {
  if (-not (Test-Path -LiteralPath $entry.Value)) {
    throw "Crash-safe session recovery contract file is missing: $($entry.Key) $($entry.Value)"
  }
}

foreach ($removedWrapper in @(
  'src\core\crash_safe_game.gd',
  'src\ui\crash_safe_service_hub.gd',
  'src\ui\crash_recovery_main_menu.gd',
  'src\ui\crash_recovery_game_ui.gd'
)) {
  if (Test-Path -LiteralPath (Join-Path $root $removedWrapper)) {
    throw "Crash-safe recovery must extend stable production entry points instead of keeping wrapper: $removedWrapper"
  }
}

$text = @{}
foreach ($entry in $paths.GetEnumerator()) {
  $text[$entry.Key] = Get-Content -Raw -Encoding UTF8 $entry.Value
}

foreach ($token in @(
  'class_name\s+WorldSessionRecoveryPolicy',
  'extends\s+RefCounted',
  'STATE_LOADING',
  'STATE_ACTIVE',
  'MAX_WORLD_ID_LENGTH\s*:=\s*128',
  'func\s+create_marker\s*\(',
  'func\s+normalize\s*\(',
  'func\s+mark_active\s*\(',
  'func\s+record_checkpoint\s*\(',
  'func\s+candidate\s*\('
)) {
  if ($text.Policy -notmatch $token) {
    throw "Recovery policy is missing strict state behavior: $token"
  }
}
if ($text.Policy -match 'extends\s+Node|FileAccess|DirAccess|AtomicJsonStore|save_world|load_world') {
  throw 'Recovery policy must remain pure, persistence-free and world-I/O-free'
}

foreach ($token in @(
  'class_name\s+WorldSessionRecoveryService',
  'MARKER_PATH\s*:=\s*"user://session_recovery\.json"',
  'AtomicJsonStoreScript',
  'func\s+begin_world\s*\(',
  'func\s+mark_active\s*\(',
  'func\s+end_world\s*\(',
  'func\s+dismiss_candidate\s*\(',
  'func\s+get_recovery_candidate\s*\(',
  'source\s*!=\s*"primary"',
  '_clear_marker_files\(\)',
  'world_saved',
  'world_deleted'
)) {
  if ($text.Service -notmatch $token) {
    throw "Recovery service is missing lifecycle or fail-closed behavior: $token"
  }
}
if ($text.Service -match 'Timer\.new\(|func\s+save_into\s*\(|payload\["session_recovery"\]') {
  throw 'Recovery service must not create a timer or enter the authoritative world payload'
}

foreach ($token in @(
  'class_name\s+AccessibilityProtectedMainMenu',
  'extends\s+"res://src/ui/protected_main_menu\.gd"',
  'RecoverLastSessionButton',
  'DismissSessionRecoveryButton',
  '恢复上次世界',
  '忽略并清除',
  'setup_session_recovery',
  'continue_world_requested\.emit',
  'quit_requested\.emit',
  '_rewire_quit_command',
  '_regular_primary_button\.visible\s*=\s*not\s+recovery_visible',
  'visible_regular_command_count'
)) {
  if ($text.MainMenu -notmatch $token) {
    throw "Stable accessible main menu is missing recovery or bounded compact behavior: $token"
  }
}
if ($text.MainMenu -match 'get_tree\(\)\.quit|SceneTree\.quit') {
  throw 'Main menu must emit quit intent and never own process termination'
}

foreach ($token in @(
  'class_name\s+AccessibilityMachineGameUI',
  'extends\s+"res://src/ui/machine_game_ui\.gd"',
  'signal\s+quit_to_desktop_requested',
  'SafeQuitDesktopButton',
  '保存并退出游戏',
  'show_quit_progress',
  'show_quit_result',
  'quit_to_desktop_requested\.emit'
)) {
  if ($text.GameUi -notmatch $token) {
    throw "Stable accessible gameplay UI is missing safe desktop quit behavior: $token"
  }
}

foreach ($token in @(
  'class_name\s+ExplorationProgressionServiceHub',
  'extends\s+"res://src/ui/runtime_health_service_hub\.gd"',
  'WorldSessionRecoveryServiceScript',
  'application_quit_requested',
  'func\s+prepare_application_quit\s*\(',
  'return_to_menu\(\)',
  'current_world_id\.is_empty\(\)',
  'world_session_recovery_service\.call\("end_world"',
  'world_session_recovery_service\.call\("abort_world"',
  'snapshot\["session_recovery"\]',
  'snapshot\["application_quit"\]'
)) {
  if ($text.Hub -notmatch $token) {
    throw "Stable exploration hub is missing authoritative recovery coordination: $token"
  }
}
if ($text.Hub -match 'save_service\.save_world|FileAccess|DirAccess|Timer\.new\(') {
  throw 'Crash-safe composition must reuse return_to_menu/save_current instead of creating persistence I/O'
}

foreach ($token in @(
  'class_name\s+BatchedStarWorldGame',
  'extends\s+"res://src/core/game\.gd"',
  'auto_accept_quit\s*=\s*false',
  'NOTIFICATION_WM_CLOSE_REQUEST',
  'func\s+request_application_quit\s*\(',
  'prepare_application_quit',
  'application_quit_prepared',
  'application_quit_blocked',
  'tree\.quit\(0\)',
  'BATCHED_WORLD_SCRIPT_PATH',
  'BATCHED_PLAYER_SCENE_PATH'
)) {
  if ($text.Game -notmatch $token) {
    throw "Stable batched game root is missing window-close or quit ownership: $token"
  }
}

foreach ($pair in @(
  @{ Text = $text.GameScene; Pattern = 'res://src/core/batched_game\.gd' },
  @{ Text = $text.HubScene; Pattern = 'res://src/ui/exploration_progression_service_hub\.gd' },
  @{ Text = $text.MenuScene; Pattern = 'res://src/ui/accessibility_protected_main_menu\.gd' },
  @{ Text = $text.GameUiScene; Pattern = 'res://src/ui/accessibility_machine_game_ui\.gd' }
)) {
  if ($pair.Text -notmatch $pair.Pattern) {
    throw "Production scene must retain its stable public entry point: $($pair.Pattern)"
  }
}

foreach ($phrase in @(
  'fresh application instance discovers the interrupted world session',
  'corrupt primary never promotes an older backup into a false recovery prompt',
  'dismissing recovery preserves the world and removes every marker candidate',
  'session recovery diagnostics remain completely outside world.json'
)) {
  if ($text.RecoveryTest -notmatch [regex]::Escape($phrase)) {
    throw "Recovery regression is missing assertion: $phrase"
  }
}
foreach ($phrase in @(
  'window-close request completes the authoritative final-save path',
  'failed final save blocks application exit',
  'failed quit preserves the recovery marker for the still-active world',
  'main-menu quit is an intent routed through the game composition root',
  'real WM close notification uses the same bounded quit coordinator'
)) {
  if ($text.QuitTest -notmatch [regex]::Escape($phrase)) {
    throw "Graceful quit regression is missing assertion: $phrase"
  }
}
foreach ($phrase in @(
  'recovery command deck remains inside the 1024x576 viewport',
  'recovery replaces only the duplicate generic primary CTA without changing the bounded command contract',
  'keyboard and controller focus prioritizes recovery while the card is active',
  'safe desktop exit remains inside the 1024x576 pause viewport'
)) {
  if ($text.UiTest -notmatch [regex]::Escape($phrase)) {
    throw "Compact recovery UI regression is missing assertion: $phrase"
  }
}
foreach ($phrase in @(
  'restart exposes exactly the interrupted world and checkpoint count',
  'real mouse recovery command reloads the interrupted world',
  'pause overlay exposes the safe desktop exit command',
  'clean final save removes the recovery card and every marker candidate',
  'safe quit persists the recovered world without losing checkpoint data'
)) {
  if ($text.Desktop -notmatch [regex]::Escape($phrase)) {
    throw "Recovery desktop acceptance is missing assertion: $phrase"
  }
}

foreach ($token in @(
  'uses:\s*\./\.github/workflows/reusable-godot-quality-gate\.yml',
  'validate_crash_safe_session_recovery\.ps1',
  'world_session_recovery_regression\.gd',
  'graceful_application_quit_regression\.gd',
  'session_recovery_ui_regression\.gd',
  'world_session_recovery_desktop_acceptance\.gd',
  'session-recovery-candidate\.png',
  'session-recovery-safe-quit\.png',
  'session-recovery-clean-exit\.png',
  'session-recovery-report\.json'
)) {
  if ($text.Workflow -notmatch $token) {
    throw "Crash-safe recovery workflow is missing gate or evidence: $token"
  }
}

foreach ($token in @(
  'validate_crash_safe_session_recovery\.ps1',
  'world_session_recovery_regression\.gd',
  'graceful_application_quit_regression\.gd',
  'session_recovery_ui_regression\.gd'
)) {
  if ($text.RunAll -notmatch $token) {
    throw "Full regression entry point is missing crash-safe recovery coverage: $token"
  }
}

foreach ($phrase in @(
  '异常退出',
  '权威存档',
  'session_recovery.json',
  '失败时取消退出',
  '不进入 world.json',
  '真实桌面',
  'Windows Release',
  '稳定入口'
)) {
  if ($text.Contract -notmatch [regex]::Escape($phrase)) {
    throw "Crash-safe recovery contract is missing boundary: $phrase"
  }
}
foreach ($phrase in @(
  'UI 直接终止进程',
  '窗口关闭绕过最终保存',
  '旧 backup 误报恢复',
  '单一退出协调器',
  '模拟重启',
  '稳定入口'
)) {
  if ($text.Audit -notmatch [regex]::Escape($phrase)) {
    throw "Iteration 51 audit is missing finding or decision: $phrase"
  }
}
if ($text.Testing -notmatch 'world_session_recovery_desktop_acceptance\.gd') {
  throw 'Testing guide must document the real recovery journey'
}
if ($text.Roadmap -notmatch '异常会话恢复') {
  throw 'Product roadmap must record crash-safe session recovery'
}

Write-Host 'PASS crash_safe_session_recovery marker=strict-primary-only world_state=authoritative stable_entries=4 quit=single-coordinator wm_close=final-save failure=blocked restart=real compact=1024x576 desktop=three-screen release=windows'
