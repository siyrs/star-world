$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = Resolve-Path "$PSScriptRoot\..\.."
$paths = @{
  Pickup = Join-Path $root 'src\entity\item_pickup.gd'
  Coordinator = Join-Path $root 'src\entity\pickup_stack_coordinator.gd'
  Bounded = Join-Path $root 'src\entity\bounded_pickup_stack_coordinator.gd'
  Participant = Join-Path $root 'src\exploration\pickup_aware_exploration_runtime_participant.gd'
  Hub = Join-Path $root 'src\ui\exploration_progression_service_hub.gd'
  Regression = Join-Path $root 'tests\qa\pickup_stack_regression.gd'
  Desktop = Join-Path $root 'tests\qa\mixed_runtime_endurance_desktop_acceptance.gd'
  Workflow = Join-Path $root '.github\workflows\mixed-runtime-endurance-tests.yml'
  RunAll = Join-Path $root 'tests\run_all.ps1'
  Contract = Join-Path $root 'docs\BOUNDED_PICKUP_STACKS.md'
  Audit = Join-Path $root 'docs\ARCHITECTURE_AUDIT_2026-07-22_ITERATION_26.md'
}
foreach ($entry in $paths.GetEnumerator()) {
  if (-not (Test-Path -LiteralPath $entry.Value)) {
    throw "Pickup stack contract file is missing: $($entry.Key) $($entry.Value)"
  }
}
$text = @{}
foreach ($entry in $paths.GetEnumerator()) {
  $text[$entry.Key] = Get-Content -Raw -Encoding UTF8 $entry.Value
}

foreach ($constant in @(
  'MAX_PICKUP_NODES\s*:=\s*128',
  'MAX_MERGE_SCAN_NODES\s*:=\s*64',
  'MAX_PENDING_ITEM_TYPES\s*:=\s*256',
  'MAX_PENDING_MATERIALIZATIONS\s*:=\s*16',
  'MAX_ITEMS_PER_PICKUP\s*:=\s*65535'
)) {
  if ($text.Coordinator -notmatch $constant) { throw "Missing pickup hard budget: $constant" }
}
if ($text.Bounded -notmatch 'MERGE_TRIGGER_NODES\s*:=\s*8') {
  throw 'Small natural drop spreads must remain readable until the eight-node pressure trigger'
}
foreach ($method in @('can_merge','merge_items','get_pickup_snapshot','get_count_label')) {
  if ($text.Pickup -notmatch "func\s+$method\s*\(") { throw "ItemPickup is missing: $method" }
}
if ($text.Pickup -notmatch 'Label3D\.new\(\)' -or $text.Pickup -notmatch '"×%d"') {
  throw 'Merged physical pickups must render their exact stack count in the world'
}
foreach ($method in @('setup','activate','clear','shutdown','flush_pending_pickups','get_snapshot')) {
  if ($text.Coordinator -notmatch "func\s+$method\s*\(") { throw "Pickup coordinator is missing: $method" }
}
if ($text.Coordinator -notmatch 'child_entered_tree' -or $text.Coordinator -notmatch 'child_exiting_tree') {
  throw 'Pickup coordination must be event-driven by the existing spawner lifecycle'
}
if ($text.Coordinator -notmatch '_pending_pickups' -or $text.Coordinator -notmatch '_queue_pending') {
  throw 'Pickup node pressure must defer excess items instead of deleting them'
}
if ($text.Coordinator -match 'Timer\.new\(' -or $text.Coordinator -match 'func\s+_process\s*\(' -or $text.Coordinator -match 'func\s+serialize\s*\(' -or $text.Coordinator -match 'FileAccess') {
  throw 'Pickup stacking must not create another timer, frame scheduler, persistence owner, or file'
}
if ($text.Participant -notmatch 'extends\s+"res://src/exploration/exploration_runtime_participant\.gd"' -or $text.Participant -notmatch 'bounded_pickup_stack_coordinator\.gd') {
  throw 'Pickup runtime must extend the stable exploration participant and own the bounded coordinator'
}
foreach ($method in @('install','begin_world','activate','snapshot_into','clear','shutdown','get_pickup_coordinator','get_lifecycle_snapshot')) {
  if ($text.Participant -notmatch "func\s+$method\s*\(") { throw "Pickup-aware exploration participant is missing: $method" }
}
if ($text.Participant -notmatch 'snapshot\["pickups"\]' -or $text.Participant -notmatch 'hub\.set\("pickup_stack_coordinator"') {
  throw 'Exploration participant must publish the compatibility port and bounded pickup diagnostics'
}
if ($text.Hub -notmatch 'pickup_aware_exploration_runtime_participant\.gd' -or $text.Hub -notmatch 'get_pickup_coordinator') {
  throw 'Production Exploration hub must select the pickup-aware participant and retain its public port'
}
foreach ($legacyLifecycle in @('_begin_world','activate_gameplay','handle_world_start_failed','return_to_menu','_exit_tree')) {
  if ($text.Hub -match "func\s+$legacyLifecycle\s*\(") { throw "Exploration hub must remain a thin registration layer: $legacyLifecycle" }
}
foreach ($phrase in @(
  'one hundred nearby drops consolidate to the eight-node readability trigger',
  'pressure merging preserves every physical item without a hidden remainder',
  'the one-hundred-twenty-ninth pickup is deferred at the hard node budget',
  'freeing one node materializes the deferred item through the bounded flush path'
)) {
  if ($text.Regression -notmatch [regex]::Escape($phrase)) {
    throw "Pickup stack regression is missing assertion: $phrase"
  }
}
foreach ($phrase in @(
  'mixed endurance keeps physical pickup nodes inside the hard budget',
  'mixed endurance preserves every hostile drop across stacking and collection',
  'mixed endurance visual evidence uses 1024x576 resolution',
  'full mixed-session reload reaches a bounded playable state',
  'new world session resets pickup stack diagnostics and pending items'
)) {
  if ($text.Desktop -notmatch [regex]::Escape($phrase)) {
    throw "Mixed runtime desktop acceptance is missing assertion: $phrase"
  }
}
if ($text.Workflow -notmatch 'Invoke-Godot\.ps1' -or $text.Workflow -notmatch 'pickup_stack_regression\.gd') {
  throw 'Mixed endurance workflow must run real awaited pickup-domain tests'
}
if ($text.Workflow -notmatch 'mixed_runtime_endurance_desktop_acceptance\.gd' -or $text.Workflow -notmatch 'mixed-runtime-endurance-desktop\.json') {
  throw 'Mixed endurance workflow must upload visualization and machine-readable evidence'
}
if ($text.RunAll -notmatch 'validate_pickup_stacks\.ps1' -or $text.RunAll -notmatch 'pickup_stack_regression\.gd') {
  throw 'Full regression entry point must permanently include pickup stacking'
}
if ($text.Contract -notmatch '128' -or $text.Contract -notmatch '64' -or $text.Contract -notmatch '不进入存档') {
  throw 'Pickup stack contract must document node, scan, and persistence boundaries'
}
if ($text.Audit -notmatch 'Area3D' -or $text.Audit -notmatch '180' -or $text.Audit -notmatch '混合') {
  throw 'Architecture audit must record the original physical-drop accumulation problem and mixed validation'
}

Write-Host 'PASS pickup_stacks nodes=128 trigger=8 scan=64 pending_types=256 materialize=16 exact_items=1 lifecycle=exploration_runtime persistence=none'
