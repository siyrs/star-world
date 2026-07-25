$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = Resolve-Path "$PSScriptRoot\..\.."
$paths = [ordered]@{
  service = Join-Path $root 'src\save\protected_save_service.gd'
  panel = Join-Path $root 'src\ui\protected_save_browser_panel.gd'
  menu = Join-Path $root 'src\ui\protected_main_menu.gd'
  scene = Join-Path $root 'scenes\ui\main_menu.tscn'
  service_regression = Join-Path $root 'tests\qa\protected_save_service_regression.gd'
  panel_regression = Join-Path $root 'tests\qa\protected_save_browser_regression.gd'
  desktop = Join-Path $root 'tests\qa\protected_save_deletion_desktop_acceptance.gd'
  workflow = Join-Path $root '.github\workflows\protected-save-deletion-tests.yml'
  contract = Join-Path $root 'docs\PROTECTED_SAVE_DELETION.md'
  audit = Join-Path $root 'docs\ARCHITECTURE_AUDIT_2026-07-25_ITERATION_40.md'
  roadmap = Join-Path $root 'docs\PRODUCT_ROADMAP.md'
  run_all = Join-Path $root 'tests\run_all.ps1'
}

$text = @{}
foreach ($name in $paths.Keys) {
  if (-not (Test-Path -LiteralPath $paths[$name])) {
    throw "Missing protected save deletion file: $($paths[$name])"
  }
  $text[$name] = Get-Content -Raw -Encoding UTF8 $paths[$name]
}

function Assert-Match([string]$Text, [string]$Pattern, [string]$Message) {
  if ($Text -notmatch $Pattern) { throw $Message }
}

function Assert-NoMatch([string]$Text, [string]$Pattern, [string]$Message) {
  if ($Text -match $Pattern) { throw $Message }
}

foreach ($token in @(
  'extends\s+"res://src/save/save_service\.gd"',
  'TRASH_DIR\s*:=\s*"user://world_trash"',
  'TRASH_FILE_NAME\s*:=\s*"trash\.json"',
  'MAX_TRASH_ENTRIES\s*:=\s*32',
  'deleted_unix_usec',
  'invalid_entry_count',
  'naturalnocasecmp_to',
  'func\s+trash_world\s*\(',
  'func\s+restore_trashed_world\s*\(',
  'func\s+purge_trashed_world\s*\(',
  'func\s+list_trashed_worlds\s*\(',
  'func\s+get_trash_diagnostics\s*\(',
  'DirAccess\.rename_absolute\(',
  'manifest_write_failed_rollback_failed',
  'trash_full',
  'world_exists',
  'trash_missing_or_invalid',
  '_remove_directory_recursive'
)) {
  Assert-Match $text.service $token "Protected save service lost required behavior: $token"
}
Assert-NoMatch $text.service 'delete_world\s*\(' 'Protected service must not override the explicit permanent-delete compatibility API'
Assert-Match $text.service '_trash_entry_count\s*>=\s*MAX_TRASH_ENTRIES' 'Full trash must reject new deletion before moving files'
Assert-Match $text.service '_store\.write_dictionary\(_trash_manifest_path' 'Trash must persist a bounded manifest after the atomic directory move'
Assert-Match $text.service '_remove_trash_manifest_files\(_world_directory' 'Restore must remove internal trash metadata from the active world'
Assert-Match $text.service 'deleted_unix_value\s*:=\s*Time\.get_unix_time_from_system\(\)' 'Trash must capture a persistent Unix epoch value'
Assert-Match $text.service 'deleted_unix_usec\s*:=\s*int\(deleted_unix_value\s*\*\s*1000000\.0\)' 'Rapid trash ordering must derive epoch microseconds from the captured Unix value'

foreach ($token in @(
  'extends\s+"res://src/ui/save_browser_panel\.gd"',
  'ProtectedDeletionService',
  '确认移到回收站',
  '撤销删除',
  'delete_confirmation_armed',
  'pending_delete_world_id',
  'undo_available',
  'func\s+_undo_last_delete\s*\(',
  'func\s+_reset_delete_confirmation\s*\(',
  'has_method\("trash_world"\)',
  'has_method\("restore_trashed_world"\)'
)) {
  Assert-Match $text.panel $token "Protected save browser lost confirmation or undo behavior: $token"
}
Assert-NoMatch $text.panel 'save_service\.delete_world|\.call\("delete_world"' 'Player-facing save browser must never call irreversible delete'
Assert-NoMatch $text.panel 'Timer\.new\(|Thread\.new\(|create_timer\(' 'Delete confirmation and undo must not add timers or threads'
Assert-Match $text.panel '_pending_delete_world_id\s*!=\s*_selected_world_id' 'First click must only arm the exact selected world'
Assert-Match $text.panel 'super\.refresh\(\)' 'Trash and restore must re-enter the normal authoritative world-list path'

Assert-Match $text.menu 'protected_save_browser_panel\.gd' 'Production main menu must instantiate the protected save browser'
Assert-Match $text.scene 'protected_main_menu\.gd' 'Production main-menu scene must route through protected composition'

foreach ($phrase in @(
  'trash operation atomically returns a stable trash id',
  'restore refuses an occupied id without consuming the trash entry',
  'restore preserves primary, sidecar and backup bytes exactly',
  'thirty-third deletion is rejected instead of purging older worlds',
  'rapid deletions retain the true latest undo entry',
  'freed slot accepts the previously blocked world without exceeding capacity'
)) {
  Assert-Match $text.service_regression ([regex]::Escape($phrase)) "Protected service regression is missing assertion: $phrase"
}

foreach ($phrase in @(
  'first delete click only arms confirmation and performs no deletion',
  'changing selection clears the pending destructive action',
  'second click moves one world through trash and never calls permanent delete',
  'filtering a selected world out clears confirmation and hidden deletion state',
  'trash-full rejection preserves the world and resets confirmation'
)) {
  Assert-Match $text.panel_regression ([regex]::Escape($phrase)) "Protected browser regression is missing assertion: $phrase"
}

foreach ($phrase in @(
  'first real delete click only arms the exact selected world',
  'confirmation state leaves authoritative files untouched',
  'real trash directory retains primary, sidecar and backup',
  'real undo preserves primary, sidecar and backup bytes exactly',
  'real filtering clears an armed hidden deletion without moving the world'
)) {
  Assert-Match $text.desktop ([regex]::Escape($phrase)) "Protected deletion desktop acceptance is missing assertion: $phrase"
}

foreach ($token in @(
  'uses:\s*\./\.github/workflows/reusable-godot-quality-gate\.yml',
  'validate_protected_save_deletion\.ps1',
  'protected_save_service_regression\.gd',
  'protected_save_browser_regression\.gd',
  'protected_save_deletion_desktop_acceptance\.gd',
  'protected-save-deletion-desktop\.png',
  'protected-save-deletion-desktop-confirm\.png',
  'protected-save-deletion-desktop-restored\.png',
  'protected-save-deletion-desktop\.json'
)) {
  Assert-Match $text.workflow $token "Protected deletion workflow is missing: $token"
}

foreach ($token in @('二次确认','原子','回收站','32','微秒','撤销','Primary','Sidecar','备份','Windows Release')) {
  Assert-Match $text.contract ([regex]::Escape($token)) "Protected deletion contract is missing: $token"
}
foreach ($token in @('一键物理删除','不可撤销','误删','回收站','同一秒','隐藏选择','真实桌面','Windows Release')) {
  Assert-Match $text.audit ([regex]::Escape($token)) "Architecture audit is missing protected-deletion finding: $token"
}
Assert-Match $text.roadmap '回收站最多 32' 'Roadmap must record bounded save trash capacity'
Assert-Match $text.roadmap '二次确认' 'Roadmap must record protected deletion confirmation'
Assert-Match $text.roadmap '撤销恢复' 'Roadmap must record undo restoration'
Assert-Match $text.run_all 'validate_protected_save_deletion\.ps1' 'Full suite is missing protected deletion static validation'
Assert-Match $text.run_all 'protected_save_service_regression\.gd' 'Full suite is missing protected save service regression'
Assert-Match $text.run_all 'protected_save_browser_regression\.gd' 'Full suite is missing protected save browser regression'

Write-Host 'PASS protected_save_deletion confirmation=2-click trash=atomic capacity=32 auto-purge=off undo=on rapid-order=epoch-usec conflict=reject primary-sidecar-backup=preserved permanent-delete-ui=0 desktop=real release=required'
