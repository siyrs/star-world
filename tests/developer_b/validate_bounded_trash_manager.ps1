$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = Resolve-Path "$PSScriptRoot\..\.."
$paths = [ordered]@{
  service = Join-Path $root 'src\save\protected_save_service.gd'
  manager = Join-Path $root 'src\ui\save_trash_manager_panel.gd'
  browser = Join-Path $root 'src\ui\protected_save_browser_panel.gd'
  service_regression = Join-Path $root 'tests\qa\trash_manager_service_regression.gd'
  panel_regression = Join-Path $root 'tests\qa\trash_manager_panel_regression.gd'
  desktop = Join-Path $root 'tests\qa\bounded_trash_manager_desktop_acceptance.gd'
  workflow = Join-Path $root '.github\workflows\bounded-trash-manager-tests.yml'
  contract = Join-Path $root 'docs\BOUNDED_TRASH_MANAGER.md'
  audit = Join-Path $root 'docs\ARCHITECTURE_AUDIT_2026-07-25_ITERATION_41.md'
  roadmap = Join-Path $root 'docs\PRODUCT_ROADMAP.md'
  run_all = Join-Path $root 'tests\run_all.ps1'
}

$text = @{}
foreach ($name in $paths.Keys) {
  if (-not (Test-Path -LiteralPath $paths[$name])) {
    throw "Missing bounded trash manager file: $($paths[$name])"
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
  'MAX_TRASH_ENTRIES\s*:=\s*32',
  'MAX_TRASH_SCAN_ENTRIES\s*:=\s*64',
  'func\s+list_trash_slots\s*\(',
  'func\s+purge_trash_slot\s*\(',
  'valid_entry_count',
  'invalid_entry_count',
  'overflow_entry_count',
  'latest_deleted_unix_usec',
  'manifest_missing_or_invalid',
  'unsafe_trash_id',
  'trash_slot_purged',
  '_remove_directory_tree'
)) {
  Assert-Match $text.service $token "Protected save service lost trash-manager behavior: $token"
}
# Purges route through the shared long-path-tolerant tree removal
# (BUG-SAVE-LONG-PATH-001); a private recursive deleter would bypass the
# relocation fallback on deep save roots.
Assert-NoMatch $text.service 'func\s+_remove_directory_recursive' 'Trash manager must not keep a private recursive deleter that bypasses the long-path fallback'
Assert-Match $text.service 'deleted_unix_usec\s*=\s*maxi\(deleted_unix_usec,\s*_latest_trash_deleted_usec\s*\+\s*1\)' 'Trash deletion order must remain strictly monotonic'
Assert-Match $text.service '_trash_entry_count\s*>=\s*MAX_TRASH_ENTRIES' 'Physical trash capacity must be checked before moving a world'
Assert-Match $text.service 'physical_count\s*:=\s*trash_ids\.size\(\)' 'Capacity must count physical directories, not only valid manifests'
Assert-NoMatch $text.service 'func\s+delete_world\s*\(' 'Trash manager service must not override active-world permanent deletion'

foreach ($token in @(
  'class_name\s+SaveTrashManagerPanel',
  'MAX_VISIBLE_ROWS\s*:=\s*24',
  'MAX_TRASH_ENTRIES\s*:=\s*32',
  'func\s+get_management_snapshot\s*\(',
  'func\s+show_page\s*\(',
  'func\s+_restore_trash_id\s*\(',
  'func\s+_purge_selected\s*\(',
  '确认永久清理',
  '损坏的回收站条目',
  'purge_confirmation_armed',
  'service_list_count',
  'refresh_now'
)) {
  Assert-Match $text.manager $token "Trash manager panel lost bounded UI behavior: $token"
}
Assert-Match $text.manager 'if\s+refresh_now' 'Trash manager setup must support lazy hidden binding'
Assert-Match $text.manager 'for\s+slot_index\s+in\s+MAX_VISIBLE_ROWS' 'Trash manager must create a fixed row pool'
Assert-Match $text.manager '_pending_purge_trash_id\s*!=\s*_selected_trash_id' 'First permanent clean click must only arm the exact selected slot'
Assert-NoMatch $text.manager 'Timer\.new\(|Thread\.new\(|create_timer\(' 'Trash manager must not add timers or threads'
Assert-NoMatch $text.manager 'delete_world\s*\(' 'Trash manager must never permanently delete an active world'

foreach ($token in @(
  'save_trash_manager_panel\.gd',
  '管理回收站',
  'trash_manager_visible',
  'func\s+_show_trash_manager\s*\(',
  'func\s+_hide_trash_manager\s*\(',
  'world_restored',
  'trash_slot_purged'
)) {
  Assert-Match $text.browser $token "Protected save browser lost trash-manager composition: $token"
}
Assert-NoMatch $text.browser 'save_service\.delete_world|\.call\("delete_world"' 'Player-facing protected browser must never call irreversible active-world delete'

foreach ($phrase in @(
  'restart counts valid and damaged physical slots without losing capacity',
  'manager projection exposes the damaged slot as purgeable but not restorable',
  'manager can restore an explicitly selected older valid entry',
  'selected restore preserves primary, sidecar and backup bytes exactly',
  'purging one damaged slot frees exactly one capacity unit'
)) {
  Assert-Match $text.service_regression ([regex]::Escape($phrase)) "Trash manager service regression is missing assertion: $phrase"
}

foreach ($phrase in @(
  'manager creates exactly twenty-four reusable rows',
  'page navigation performs no additional trash-directory scan',
  'damaged slot visibly disables restore',
  'first permanent-clean click only arms the exact damaged slot',
  'row restore targets an explicitly selected older valid entry',
  'trash manager never calls the active-world permanent delete API'
)) {
  Assert-Match $text.panel_regression ([regex]::Escape($phrase)) "Trash manager panel regression is missing assertion: $phrase"
}

foreach ($phrase in @(
  'hidden manager performs zero directory lists before the player opens it',
  'real full trash exposes thirty-two slots across two pages including damage',
  'full physical trash rejects the thirty-third world without moving it',
  'selected older entry restores without consuming the latest trash item',
  'first permanent-clean click arms the damaged slot without removing files',
  'capacity released by management accepts the previously blocked world',
  'restored target is immediately searchable in the active browser'
)) {
  Assert-Match $text.desktop ([regex]::Escape($phrase)) "Trash manager desktop acceptance is missing assertion: $phrase"
}

foreach ($token in @(
  'uses:\s*\./\.github/workflows/reusable-godot-quality-gate\.yml',
  'validate_bounded_trash_manager\.ps1',
  'trash_manager_service_regression\.gd',
  'trash_manager_panel_regression\.gd',
  'bounded_trash_manager_desktop_acceptance\.gd',
  'bounded-trash-manager-desktop\.png',
  'bounded-trash-manager-desktop-purge-confirm\.png',
  'bounded-trash-manager-desktop-after\.png',
  'bounded-trash-manager-desktop\.json'
)) {
  Assert-Match $text.workflow $token "Bounded trash manager workflow is missing: $token"
}

foreach ($token in @('指定恢复','损坏','32','64','24','二次确认','Primary','Sidecar','Backup','Windows Release')) {
  Assert-Match $text.contract ([regex]::Escape($token)) "Trash manager contract is missing: $token"
}
foreach ($token in @('损坏 Manifest','指定恢复','永久清理','严格单调','真实桌面','Windows Release')) {
  Assert-Match $text.audit ([regex]::Escape($token)) "Architecture audit is missing trash-manager finding: $token"
}
Assert-Match $text.audit '容量[^\r\n]{0,30}死锁' 'Architecture audit must identify the player-facing capacity deadlock'
Assert-Match $text.roadmap '固定 24 行的回收站管理页' 'Roadmap must record bounded trash manager virtualization'
Assert-Match $text.roadmap '指定恢复' 'Roadmap must record selected trash restore'
Assert-Match $text.roadmap '损坏 Manifest' 'Roadmap must record damaged trash-slot governance'
Assert-Match $text.run_all 'validate_bounded_trash_manager\.ps1' 'Full suite is missing bounded trash manager validation'
Assert-Match $text.run_all 'trash_manager_service_regression\.gd' 'Full suite is missing trash manager service regression'
Assert-Match $text.run_all 'trash_manager_panel_regression\.gd' 'Full suite is missing trash manager panel regression'

Write-Host 'PASS bounded_trash_manager slots=32 scan=64 rows=24 pages=2 selected-restore=on invalid-purge=on permanent-clean=2-click page-scan=0 active-delete-ui=0 desktop=33-world release=required'
