$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = Resolve-Path "$PSScriptRoot\..\.."
$paths = [ordered]@{
  save = Join-Path $root 'src\save\save_service.gd'
  marker_test = Join-Path $root 'tests\qa\catalog_transaction_marker_recovery_regression.gd'
  long_test = Join-Path $root 'tests\qa\long_term_scale_recovery_regression.gd'
  churn_test = Join-Path $root 'tests\qa\long_term_structure_pickup_churn_regression.gd'
  desktop = Join-Path $root 'tests\qa\ultrawide_high_dpi_controller_focus_desktop_acceptance.gd'
  navigation = Join-Path $root 'src\ui\protected_main_menu.gd'
  workflow = Join-Path $root '.github\workflows\long-term-scale-recovery-tests.yml'
  contract = Join-Path $root 'docs\LONG_TERM_SCALE_RECOVERY.md'
  testing = Join-Path $root 'docs\LONG_TERM_SCALE_RECOVERY_TESTING.md'
  roadmap_iteration = Join-Path $root 'docs\PRODUCT_ROADMAP_ITERATION_58.md'
  audit = Join-Path $root 'docs\ARCHITECTURE_AUDIT_2026-08-06_ITERATION_58.md'
  roadmap = Join-Path $root 'docs\PRODUCT_ROADMAP.md'
  issues = Join-Path $root 'qa\issues-found.md'
  run_all = Join-Path $root 'tests\run_all.ps1'
}

$text = @{}
foreach ($name in $paths.Keys) {
  if (-not (Test-Path -LiteralPath $paths[$name])) {
    throw "Missing long-term scale and recovery file: $name $($paths[$name])"
  }
  $text[$name] = Get-Content -Raw -Encoding UTF8 $paths[$name]
}

function Assert-Match([string]$Text, [string]$Pattern, [string]$Message) {
  if ($Text -notmatch $Pattern) { throw $Message }
}

function Assert-NoMatch([string]$Text, [string]$Pattern, [string]$Message) {
  if ($Text -match $Pattern) { throw $Message }
}

function Get-MethodBody([string]$Text, [string]$MethodName) {
  $pattern = '(?ms)^func\s+' + [regex]::Escape($MethodName) + '\s*\(.*?(?=^func\s+|\z)'
  $match = [regex]::Match($Text, $pattern)
  if (-not $match.Success) { throw "Unable to isolate method: $MethodName" }
  return $match.Value
}

foreach ($token in @(
  'CATALOG_PENDING_FILE_NAME\s*:=\s*"catalog\.pending"',
  '_catalog_pending_marker_write_failure_count',
  '_catalog_pending_marker_clear_failure_count',
  '_catalog_pending_marker_detected_count',
  '_last_catalog_pending_marker_detected_count',
  'func\s+_mark_catalog_pending\s*\(',
  'func\s+_clear_catalog_pending\s*\(',
  'func\s+_catalog_pending_exists\s*\(',
  'pending_marker_write_failure_count',
  'pending_marker_clear_failure_count',
  'pending_marker_detected_count',
  'last_pending_marker_detected_count'
)) {
  Assert-Match $text.save $token "SaveService lost catalog transaction-marker contract: $token"
}

$saveBody = Get-MethodBody $text.save 'save_world'
$markIndex = $saveBody.IndexOf('_mark_catalog_pending')
$worldWriteIndex = $saveBody.IndexOf('_store.write_dictionary')
if ($markIndex -lt 0 -or $worldWriteIndex -lt 0 -or $markIndex -gt $worldWriteIndex) {
  throw 'Catalog transaction marker must be established before the authoritative world write'
}
Assert-Match $saveBody '_clear_catalog_pending' 'Failed authoritative world writes must clear the pending marker'

$readCatalogBody = Get-MethodBody $text.save '_read_catalog_entry'
Assert-Match $readCatalogBody '_catalog_pending_exists' 'Catalog reads must reject a sidecar while its transaction marker exists'
Assert-Match $readCatalogBody '_catalog_pending_marker_detected_count\s*\+=' 'Pending marker detections must be diagnosed'

$writeCatalogBody = Get-MethodBody $text.save '_write_catalog_value'
Assert-Match $writeCatalogBody '_clear_catalog_pending' 'Successful sidecar writes must clear the transaction marker'
Assert-NoMatch $text.save 'catalog\.pending.*world\[|payload\[.*catalog\.pending' 'Catalog transaction state must never enter world.json'

foreach ($phrase in @(
  'same-byte authoritative mutation changes metadata without changing file size',
  'restart rejects the stale same-byte sidecar and lists authoritative metadata',
  'self-healing consumes one bounded read and one bounded sidecar rebuild',
  'second listing is a pure sidecar hit with zero authoritative reads'
)) {
  Assert-Match $text.marker_test ([regex]::Escape($phrase)) "Catalog marker regression is missing assertion: $phrase"
}

foreach ($phrase in @(
  'twenty-four-hour campaign records the exact autosave attempt count',
  'three bounded failure bursts produce exactly nine failed attempts',
  'one manual save interleaves every four active hours',
  'checkpoint history remains at the exact twelve-event hard limit',
  'current-entry history never leaks another world or an earlier visit',
  'explicit session reset converges without inheriting old global evidence'
)) {
  Assert-Match $text.long_test ([regex]::Escape($phrase)) "Long-session qualification regression is missing assertion: $phrase"
}
Assert-Match $text.long_test 'const\s+HOURS\s*:=\s*24' 'Long-session qualification must cover exactly twenty-four hours'
Assert-Match $text.long_test 'const\s+WINDOW_COUNT\s*:=\s*HOURS\s*\*\s*12' 'Five-minute windows must remain derived from the twenty-four-hour target'

foreach ($phrase in @(
  'structure pressure cycle %02d releases every temporary runtime node',
  'reaches the exact 128-node shared-runtime budget',
  'expires and unregisters all nodes without residue',
  'never exceeds the hard runtime capacity'
)) {
  Assert-Match $text.churn_test ([regex]::Escape($phrase)) "Structure/pickup churn regression is missing assertion: $phrase"
}
Assert-Match $text.churn_test 'STRUCTURE_CYCLES\s*:=\s*24' 'Structure pressure must retain twenty-four complete cycles'
Assert-Match $text.churn_test 'PICKUP_CYCLES\s*:=\s*5' 'Pickup pressure must retain five full-capacity cycles'

foreach ($token in @(
  'PHYSICAL_SIZE\s*:=\s*Vector2i\(3440,\s*1440\)',
  'LOGICAL_SIZE\s*:=\s*Vector2i\(1720,\s*720\)',
  'JOY_BUTTON_DPAD_DOWN',
  'JOY_BUTTON_DPAD_UP',
  'JOY_BUTTON_A',
  'JOY_BUTTON_B',
  'has_theme_stylebox\("focus"\)',
  'ultrawide-high-dpi-controller-focus-report\.json'
)) {
  Assert-Match $text.desktop $token "Ultrawide/high-DPI/controller evidence is missing: $token"
}
foreach ($phrase in @(
  'real controller D-pad moves focus to the next visible command',
  'controller accept opens the production settings workspace',
  'controller cancel returns from settings without losing the command deck',
  'desktop evidence retains the full 3440x1440 physical surface'
)) {
  Assert-Match $text.desktop ([regex]::Escape($phrase)) "Desktop qualification is missing assertion: $phrase"
}


foreach ($token in @(
  'set_process_input\(true\)',
  'JOY_BUTTON_DPAD_DOWN',
  'JOY_BUTTON_DPAD_UP',
  'func\s+_move_controller_focus\s*\(',
  'func\s+_controller_focus_scope\s*\(',
  'func\s+_collect_controller_focusables\s*\(',
  'ensure_control_visible',
  'set_input_as_handled'
)) {
  Assert-Match $text.navigation $token "Production controller focus graph is missing: $token"
}
Assert-NoMatch $text.navigation 'Timer\.new|Thread\.new|get_nodes_in_group' 'Controller focus navigation must remain event-driven and tree-local'

foreach ($token in @(
  'uses:\s*\./\.github/workflows/reusable-godot-quality-gate\.yml',
  'validate_long_term_scale_recovery\.ps1',
  'catalog_transaction_marker_recovery_regression\.gd',
  'long_term_scale_recovery_regression\.gd',
  'long_term_structure_pickup_churn_regression\.gd',
  'bounded_multi_world_recovery_regression\.gd',
  'autosave_long_session_endurance_regression\.gd',
  'world_scoped_save_checkpoint_session_regression\.gd',
  'pickup_shared_runtime_regression\.gd',
  'structural_integrity_batched_regression\.gd',
  'connected_block_shapes_regression\.gd',
  'recent_chunk_snapshot_cache_regression\.gd',
  'ultrawide_high_dpi_controller_focus_desktop_acceptance\.gd'
)) {
  Assert-Match $text.workflow $token "Permanent long-term workflow is missing: $token"
}

foreach ($token in @('catalog.pending','24 小时','128','3440×1440','Joypad','E4-H','7,200')) {
  Assert-Match ($text.contract + $text.testing + $text.roadmap_iteration + $text.audit) ([regex]::Escape($token)) "Long-term documentation is missing boundary: $token"
}
Assert-Match $text.roadmap 'Iteration 58' 'Main product roadmap must record Iteration 58'
Assert-Match $text.issues 'Iteration 58' 'Issue ledger must record the Iteration 58 findings and corrections'

foreach ($token in @(
  'validate_long_term_scale_recovery\.ps1',
  'catalog_transaction_marker_recovery_regression\.gd',
  'long_term_scale_recovery_regression\.gd',
  'long_term_structure_pickup_churn_regression\.gd'
)) {
  Assert-Match $text.run_all $token "Full regression entry is missing: $token"
}

Assert-NoMatch ($text.marker_test + $text.long_test + $text.churn_test) 'Timer\.new|Thread\.new|save_version\s*=' 'Qualification fixtures must not add parallel timers, threads, or save schemas'

Write-Host 'PASS long_term_scale_recovery marker=cross-file worlds=restart autosave=24h failures=9 manual=6 history=12 structures=24 pickup-cycles=5 pickup-capacity=128 ultrawide=3440x1440 logical=1720x720 controller=real release=required'
